import Foundation
import AppKit
import WebKit
import Combine

@MainActor
final class MarkdownPreviewModel: ObservableObject {
    @Published var recentFiles: [URL] = []
    @Published var isDarkTheme: Bool = true {
        didSet {
            UserDefaults.standard.set(isDarkTheme, forKey: "markdownPreview.isDarkTheme")
            updateTheme()
        }
    }

    private var currentFileURL: URL?
    private var currentMarkdown: String = ""
    private var previewWindow: NSWindow?
    private var webView: WKWebView?
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var activeSecurityScope: URL?

    private let maxRecentFiles = 5
    private let bookmarksKey = "markdownPreview.recentBookmarks"

    init() {
        isDarkTheme = UserDefaults.standard.object(forKey: "markdownPreview.isDarkTheme") as? Bool ?? true
        loadRecentFiles()
    }

    func stopMonitoring() {
        stopFileWatcher()
        stopSecurityScope()
        previewWindow?.close()
        previewWindow = nil
        webView = nil
    }

    // MARK: - File Operations

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .plainText
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a Markdown file to preview"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }

    func openRecentFile(_ url: URL) {
        guard let bookmarkData = loadBookmark(for: url) else {
            recentFiles.removeAll { $0 == url }
            saveRecentFiles()
            return
        }
        var isStale = false
        do {
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                recentFiles.removeAll { $0 == url }
                saveRecentFiles()
                return
            }
            stopSecurityScope()
            activeSecurityScope = resolvedURL
            if isStale {
                saveBookmark(for: resolvedURL)
            }
            loadFile(resolvedURL)
        } catch {
            recentFiles.removeAll { $0 == url }
            saveRecentFiles()
        }
    }

    func pasteFromClipboard() {
        guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Clipboard Empty"
            alert.informativeText = "No text found in clipboard."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        currentFileURL = nil
        currentMarkdown = content
        stopFileWatcher()
        showPreviewWindow()
        renderMarkdown()
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        saveRecentFiles()
    }

    private func loadFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            currentFileURL = url
            currentMarkdown = content
            addToRecentFiles(url)
            showPreviewWindow()
            renderMarkdown()
            startFileWatcher(for: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Open File"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Recent Files Persistence

    private func addToRecentFiles(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        saveBookmark(for: url)
        saveRecentFiles()
    }

    private func saveRecentFiles() {
        let paths = recentFiles.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "markdownPreview.recentFiles")
    }

    private func loadRecentFiles() {
        guard let paths = UserDefaults.standard.stringArray(forKey: "markdownPreview.recentFiles") else { return }
        recentFiles = paths.compactMap { URL(fileURLWithPath: $0) }
            .filter { loadBookmark(for: $0) != nil }
    }

    // MARK: - Security-Scoped Bookmarks

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.path] = data
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        } catch {
            // Bookmark creation failed, file will not be accessible from recent files
        }
    }

    private func loadBookmark(for url: URL) -> Data? {
        let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data]
        return bookmarks?[url.path]
    }

    private func stopSecurityScope() {
        activeSecurityScope?.stopAccessingSecurityScopedResource()
        activeSecurityScope = nil
    }

    // MARK: - File Watcher

    private func startFileWatcher(for url: URL) {
        stopFileWatcher()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.reloadCurrentFile()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileWatcherSource = source
    }

    private func stopFileWatcher() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    private func reloadCurrentFile() {
        guard let url = currentFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        currentMarkdown = content
        renderMarkdown()
    }

    // MARK: - Preview Window

    private func showPreviewWindow() {
        if let window = previewWindow {
            window.title = currentFileURL?.lastPathComponent ?? "Markdown Preview"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv

        let htmlContent = buildHTMLTemplate()
        wv.loadHTMLString(htmlContent, baseURL: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = currentFileURL?.lastPathComponent ?? "Markdown Preview"
        window.center()
        window.contentView = wv
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)

        let toolbar = NSToolbar(identifier: "MarkdownPreviewToolbar")
        toolbar.delegate = ToolbarDelegate.shared
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        ToolbarDelegate.shared.model = self

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window

        // Render after a short delay to let WKWebView load the template
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.renderMarkdown()
        }
    }

    private func renderMarkdown() {
        guard let webView else { return }
        let escaped = currentMarkdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let js = "renderMarkdown(`\(escaped)`);"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func updateTheme() {
        guard let webView else { return }
        let theme = isDarkTheme ? "dark" : "light"
        webView.evaluateJavaScript("setTheme('\(theme)');", completionHandler: nil)
    }

    // MARK: - Export PDF

    func exportPDF() {
        guard let webView else {
            let alert = NSAlert()
            alert.messageText = "No Preview Open"
            alert.informativeText = "Open a Markdown file first before exporting."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = (currentFileURL?.deletingPathExtension().lastPathComponent ?? "document") + ".pdf"
        savePanel.message = "Export Markdown as PDF"

        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }

        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = .zero // Full page

        webView.createPDF(configuration: pdfConfig) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: saveURL)
                        NSWorkspace.shared.activateFileViewerSelecting([saveURL])
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "PDF Generation Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Toolbar Actions

    func toolbarOpenFile() {
        openFile()
    }

    func toolbarToggleTheme() {
        isDarkTheme.toggle()
    }

    // MARK: - HTML Template

    private func buildHTMLTemplate() -> String {
        let theme = isDarkTheme ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html data-theme="\(theme)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(Self.cssStyles)
        </style>
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        </head>
        <body>
        <div id="content"><p style="color:var(--text-secondary)">Loading markdown renderer...</p></div>
        <script>
        function renderMarkdown(md) {
            if (typeof marked === 'undefined') {
                document.getElementById('content').innerHTML = '<p style="color:red">Failed to load markdown renderer. Check your internet connection.</p>';
                return;
            }
            marked.setOptions({ gfm: true, breaks: true });
            document.getElementById('content').innerHTML = marked.parse(md || '');
        }
        function setTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
        }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Embedded CSS

    private static let cssStyles = """
    :root {
        --bg: #ffffff;
        --text: #24292f;
        --text-secondary: #57606a;
        --border: #d0d7de;
        --code-bg: #f6f8fa;
        --blockquote-border: #d0d7de;
        --blockquote-text: #57606a;
        --link: #0969da;
        --table-border: #d0d7de;
        --table-row-bg: #f6f8fa;
    }
    [data-theme="dark"] {
        --bg: #0d1117;
        --text: #e6edf3;
        --text-secondary: #8b949e;
        --border: #30363d;
        --code-bg: #161b22;
        --blockquote-border: #30363d;
        --blockquote-text: #8b949e;
        --link: #58a6ff;
        --table-border: #30363d;
        --table-row-bg: #161b22;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
        font-size: 16px;
        line-height: 1.6;
        color: var(--text);
        background-color: var(--bg);
        padding: 32px;
        max-width: 900px;
        margin: 0 auto;
        -webkit-font-smoothing: antialiased;
    }
    #content > *:first-child { margin-top: 0; }
    h1, h2, h3, h4, h5, h6 {
        margin-top: 24px;
        margin-bottom: 16px;
        font-weight: 600;
        line-height: 1.25;
    }
    h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    p { margin-top: 0; margin-bottom: 16px; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 600; }
    img { max-width: 100%; height: auto; border-radius: 6px; }
    code {
        font-family: 'SF Mono', SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
        font-size: 85%;
        background-color: var(--code-bg);
        padding: 0.2em 0.4em;
        border-radius: 6px;
    }
    pre {
        margin-top: 0;
        margin-bottom: 16px;
        padding: 16px;
        overflow: auto;
        font-size: 85%;
        line-height: 1.45;
        background-color: var(--code-bg);
        border-radius: 6px;
    }
    pre code {
        padding: 0;
        background-color: transparent;
        border-radius: 0;
        font-size: 100%;
    }
    blockquote {
        margin: 0 0 16px 0;
        padding: 0 1em;
        color: var(--blockquote-text);
        border-left: 0.25em solid var(--blockquote-border);
    }
    ul, ol {
        margin-top: 0;
        margin-bottom: 16px;
        padding-left: 2em;
    }
    li + li { margin-top: 0.25em; }
    table {
        border-spacing: 0;
        border-collapse: collapse;
        margin-top: 0;
        margin-bottom: 16px;
        width: auto;
        overflow: auto;
        display: block;
    }
    table th, table td {
        padding: 6px 13px;
        border: 1px solid var(--table-border);
    }
    table th {
        font-weight: 600;
        background-color: var(--code-bg);
    }
    table tr:nth-child(2n) { background-color: var(--table-row-bg); }
    hr {
        height: 0.25em;
        padding: 0;
        margin: 24px 0;
        background-color: var(--border);
        border: 0;
        border-radius: 2px;
    }
    input[type="checkbox"] {
        margin-right: 0.5em;
    }
    /* PDF print styles */
    @media print {
        body { padding: 20px; background: white; color: black; }
        pre { border: 1px solid #ddd; }
    }
    """

}

// MARK: - Toolbar Delegate

class ToolbarDelegate: NSObject, NSToolbarDelegate {
    static let shared = ToolbarDelegate()
    weak var model: MarkdownPreviewModel?

    private static let openItem = NSToolbarItem.Identifier("openFile")
    private static let exportPDFItem = NSToolbarItem.Identifier("exportPDF")
    private static let toggleThemeItem = NSToolbarItem.Identifier("toggleTheme")

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.openItem, Self.exportPDFItem, .flexibleSpace, Self.toggleThemeItem]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.openItem, Self.exportPDFItem, .flexibleSpace, Self.toggleThemeItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case Self.openItem:
            item.label = "Open"
            item.toolTip = "Open Markdown File"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")
            item.target = self
            item.action = #selector(openFile)
        case Self.exportPDFItem:
            item.label = "Export PDF"
            item.toolTip = "Export as PDF"
            item.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Export PDF")
            item.target = self
            item.action = #selector(exportPDF)
        case Self.toggleThemeItem:
            item.label = "Theme"
            item.toolTip = "Toggle Light/Dark Theme"
            item.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Toggle Theme")
            item.target = self
            item.action = #selector(toggleTheme)
        default:
            return nil
        }

        return item
    }

    @objc private func openFile() {
        Task { @MainActor in
            model?.toolbarOpenFile()
        }
    }

    @objc private func exportPDF() {
        Task { @MainActor in
            model?.exportPDF()
        }
    }

    @objc private func toggleTheme() {
        Task { @MainActor in
            model?.toolbarToggleTheme()
        }
    }
}
