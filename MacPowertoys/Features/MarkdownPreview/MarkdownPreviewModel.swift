import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

@MainActor
final class MarkdownPreviewModel: NSObject, ObservableObject {
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
    private var isWebViewLoaded: Bool = false
    private var toolbarDelegate: ToolbarDelegate?

    private let maxRecentFiles = 5
    private let bookmarksKey = "markdownPreview.recentBookmarks"

    override init() {
        super.init()
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
            UTType.init("net.daringfireball.markdown") ?? .plainText,
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
            NSLog("[MarkdownPreview] Failed to save bookmark for %@: %@", url.path, error.localizedDescription)
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
        wv.navigationDelegate = self
        self.webView = wv
        self.isWebViewLoaded = false

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
        let delegate = ToolbarDelegate()
        delegate.model = self
        self.toolbarDelegate = delegate
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window

        // renderMarkdown() is called via WKNavigationDelegate when the page finishes loading
    }

    private func renderMarkdown() {
        guard let webView, isWebViewLoaded else { return }
        guard let data = try? JSONEncoder().encode(currentMarkdown),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        let js = "renderMarkdown(\(jsonString));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func updateTheme() {
        guard let webView else { return }
        let theme = isDarkTheme ? "dark" : "light"
        webView.evaluateJavaScript("setTheme('\(theme)');", completionHandler: nil)
    }

    // MARK: - Export PDF

    func exportPDF() async {
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

        do {
            let data = try await webView.pdf(configuration: pdfConfig)
            try data.write(to: saveURL)
            NSWorkspace.shared.activateFileViewerSelecting([saveURL])
        } catch {
            NSLog("[MarkdownPreview] PDF export failed: %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
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
        return #"""
        <!DOCTYPE html>
        <html data-theme="\#(theme)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \#(Self.cssStyles)
        </style>
        </head>
        <body>
        <div id="content"><p style="color:var(--text-secondary)">Loading markdown renderer...</p></div>
        <script>
        function escapeHtml(input) {
            return (input || '')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/\"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }

        function sanitizeUrl(url) {
            const normalized = (url || '').trim().replace(/^<|>$/g, '');
            if (/^(https?:\/\/|mailto:|#|\/)/i.test(normalized)) {
                return normalized;
            }
            return '#';
        }

        function parseInline(text) {
            const codeSpans = [];
            let output = escapeHtml(text || '').replace(/`([^`]+)`/g, function(_, code) {
                const index = codeSpans.push(code) - 1;
                return '\u0000' + index + '\u0000';
            });

            output = output.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function(_, label, url) {
                const safeUrl = sanitizeUrl(url);
                return '<a href="' + safeUrl + '" target="_blank" rel="noopener noreferrer">' + label + '</a>';
            });

            output = output
                .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
                .replace(/__([^_]+)__/g, '<strong>$1</strong>')
                .replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<em>$2</em>')
                .replace(/(^|[^_])_([^_\n]+)_(?!_)/g, '$1<em>$2</em>');

            output = output.replace(/\u0000(\d+)\u0000/g, function(_, idx) {
                return '<code>' + codeSpans[Number(idx)] + '</code>';
            });

            return output;
        }

        function markdownToHtml(source) {
            const lines = (source || '').replace(/\r\n?/g, '\n').split('\n');
            const html = [];
            let paragraphBuffer = [];
            let listType = null;
            let listItems = [];
            let quoteLines = [];
            let i = 0;

            function flushParagraph() {
                if (paragraphBuffer.length === 0) {
                    return;
                }
                const text = paragraphBuffer.join(' ').trim();
                if (text.length > 0) {
                    html.push('<p>' + parseInline(text) + '</p>');
                }
                paragraphBuffer = [];
            }

            function flushList() {
                if (!listType || listItems.length === 0) {
                    listType = null;
                    listItems = [];
                    return;
                }
                const items = listItems.map(function(item) {
                    return '<li>' + parseInline(item.trim()) + '</li>';
                }).join('');
                html.push('<' + listType + '>' + items + '</' + listType + '>');
                listType = null;
                listItems = [];
            }

            function flushQuote() {
                if (quoteLines.length === 0) {
                    return;
                }
                html.push('<blockquote>' + markdownToHtml(quoteLines.join('\n')) + '</blockquote>');
                quoteLines = [];
            }

            while (i < lines.length) {
                const line = lines[i];
                const trimmed = line.trim();

                if (/^```/.test(trimmed)) {
                    flushParagraph();
                    flushList();
                    flushQuote();

                    const langMatch = trimmed.match(/^```([A-Za-z0-9_-]+)?/);
                    const language = langMatch && langMatch[1] ? langMatch[1] : '';
                    const codeLines = [];
                    i += 1;

                    while (i < lines.length && !/^```/.test(lines[i].trim())) {
                        codeLines.push(lines[i]);
                        i += 1;
                    }

                    const classAttr = language ? ' class="language-' + language + '"' : '';
                    html.push('<pre><code' + classAttr + '>' + escapeHtml(codeLines.join('\n')) + '</code></pre>');

                    if (i < lines.length && /^```/.test(lines[i].trim())) {
                        i += 1;
                    }
                    continue;
                }

                if (trimmed.length === 0) {
                    flushParagraph();
                    flushList();
                    flushQuote();
                    i += 1;
                    continue;
                }

                const quoteMatch = line.match(/^\s*>\s?(.*)$/);
                if (quoteMatch) {
                    flushParagraph();
                    flushList();
                    quoteLines.push(quoteMatch[1]);
                    i += 1;
                    continue;
                }
                if (quoteLines.length > 0) {
                    flushQuote();
                }

                if (/^(?:-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
                    flushParagraph();
                    flushList();
                    html.push('<hr>');
                    i += 1;
                    continue;
                }

                const headingMatch = trimmed.match(/^(#{1,6})\s+(.*)$/);
                if (headingMatch) {
                    flushParagraph();
                    flushList();
                    const level = headingMatch[1].length;
                    html.push('<h' + level + '>' + parseInline(headingMatch[2].trim()) + '</h' + level + '>');
                    i += 1;
                    continue;
                }

                const unorderedMatch = line.match(/^\s*[-*+]\s+(.*)$/);
                if (unorderedMatch) {
                    flushParagraph();
                    if (listType && listType !== 'ul') {
                        flushList();
                    }
                    listType = 'ul';
                    listItems.push(unorderedMatch[1]);
                    i += 1;
                    continue;
                }

                const orderedMatch = line.match(/^\s*\d+\.\s+(.*)$/);
                if (orderedMatch) {
                    flushParagraph();
                    if (listType && listType !== 'ol') {
                        flushList();
                    }
                    listType = 'ol';
                    listItems.push(orderedMatch[1]);
                    i += 1;
                    continue;
                }

                if (listType) {
                    const continuationMatch = line.match(/^\s{2,}(.*)$/);
                    if (continuationMatch && listItems.length > 0) {
                        listItems[listItems.length - 1] += ' ' + continuationMatch[1].trim();
                        i += 1;
                        continue;
                    }
                    flushList();
                }

                paragraphBuffer.push(trimmed);
                i += 1;
            }

            flushParagraph();
            flushList();
            flushQuote();

            return html.join('\n');
        }

        function renderMarkdown(md) {
            try {
                document.getElementById('content').innerHTML = markdownToHtml(md || '');
            } catch (error) {
                document.getElementById('content').innerHTML = '<p style="color:red">Failed to render markdown preview.</p>';
                console.error('Markdown render error:', error);
            }
        }
        function setTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
        }
        </script>
        </body>
        </html>
        """#
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

// MARK: - WKNavigationDelegate

extension MarkdownPreviewModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isWebViewLoaded = true
            self.renderMarkdown()
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            NSLog("[MarkdownPreview] Web content process terminated, reloading...")
            self.isWebViewLoaded = false
            let htmlContent = self.buildHTMLTemplate()
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}

// MARK: - Toolbar Delegate

class ToolbarDelegate: NSObject, NSToolbarDelegate {
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
            await model?.exportPDF()
        }
    }

    @objc private func toggleTheme() {
        Task { @MainActor in
            model?.toolbarToggleTheme()
        }
    }
}
