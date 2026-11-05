import Foundation
import AppKit
import Carbon.HIToolbox

// Global C callback for the Advanced Paste hotkey (⌃⌥⇧V)
private func advancedPasteHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    // Only handle our own hotkey; returning noErr for others would swallow them.
    guard hotKeyID.signature == OSType(0x41445650) else { return OSStatus(eventNotHandledErr) } // "ADVP"

    Task { @MainActor in
        NotificationCenter.default.post(name: ModuleNotifications.openPaletteScreen, object: "advancedPaste.open")
    }
    return noErr
}

// MARK: - Transforms (pure)

enum PasteTransform: CaseIterable {
    case plainText, markdown, prettyJSON, minifiedJSON, uppercase, lowercase, titleCase

    var title: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .prettyJSON: return "Pretty JSON"
        case .minifiedJSON: return "Minified JSON"
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        }
    }

    var symbol: String {
        switch self {
        case .plainText: return "text.alignleft"
        case .markdown: return "number"
        case .prettyJSON, .minifiedJSON: return "curlybraces"
        case .uppercase, .lowercase, .titleCase: return "textformat"
        }
    }
}

/// What was on the pasteboard when the palette opened.
struct PasteSource: Equatable {
    var text: String?
    var html: String?
}

// MARK: - Advanced Paste Model

@MainActor
final class AdvancedPasteModel: ObservableObject {
    // MARK: - Settings
    /// Arms the ⌃⌥⇧V shortcut.
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "advancedPaste.isEnabled")
            if isEnabled { registerHotKey() } else { unregisterHotKey() }
        }
    }

    // MARK: - Runtime State
    @Published private(set) var source = PasteSource()

    // MARK: - Private
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var previousApp: NSRunningApplication?
    private var activationObserver: Any?

    // MARK: - Init
    init() {
        installHotKeyHandler()
        trackPreviousApp()
        isEnabled = UserDefaults.standard.bool(forKey: "advancedPaste.isEnabled")
        if isEnabled { registerHotKey() }
    }

    // MARK: - Transforms

    /// The palette passes the user's own locale, so Turkish text gets `İ`/`ı` right.
    /// Whatever the locale, lowercasing never leaves a stray combining dot (`i` + U+0307) behind.
    nonisolated static func lowercased(_ text: String, locale: Locale) -> String {
        text.lowercased(with: locale).replacingOccurrences(of: "i\u{307}", with: "i")
    }

    nonisolated static func uppercased(_ text: String, locale: Locale) -> String {
        text.uppercased(with: locale)
    }

    /// First letter of each whitespace-separated word upper, the rest lower.
    nonisolated static func titleCased(_ text: String, locale: Locale) -> String {
        var result = ""
        var atWordStart = true
        for ch in text {
            let s = String(ch)
            if ch.isWhitespace {
                result += s
                atWordStart = true
            } else if atWordStart {
                result += s.uppercased(with: locale)
                atWordStart = false
            } else {
                result += lowercased(s, locale: locale)
            }
        }
        return result
    }

    /// nil when the text is not a JSON object or array.
    nonisolated static func prettyJSON(_ text: String) -> String? {
        reserialized(text, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    nonisolated static func minifiedJSON(_ text: String) -> String? {
        reserialized(text, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    nonisolated private static func reserialized(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let out = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// Headings, bold, italic, links, nested lists and paragraphs; every other tag is dropped, its text kept.
    nonisolated static func markdown(fromHTML html: String) -> String {
        func strip(_ pattern: String, _ s: String) -> String {
            s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        var input = strip("<!--[\\s\\S]*?-->", html)
        for tag in ["head", "script", "style"] { input = strip("<\(tag)[\\s\\S]*?</\(tag)\\s*>", input) }

        var out = ""
        var lists: [(ordered: Bool, next: Int)] = []
        var hrefs: [String?] = []

        func blockBreak() {
            guard !out.isEmpty else { return }
            while !out.hasSuffix("\n\n") { out += "\n" }
        }
        func text(_ raw: String) {
            var s = decodeEntities(raw).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if s.hasPrefix(" "), out.isEmpty || out.hasSuffix("\n") || out.hasSuffix(" ") { s.removeFirst() }
            out += s
        }

        let tagRegex = try! NSRegularExpression(pattern: "<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>")
        let ns = input as NSString
        var cursor = 0
        for match in tagRegex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
            let closing = ns.substring(with: match.range(at: 1)) == "/"
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            let attrs = ns.substring(with: match.range(at: 3))

            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                blockBreak()
                if !closing { out += String(repeating: "#", count: Int(String(name.last!))!) + " " }
            case "p", "div":
                blockBreak()
            case "br":
                out += "\n"
            case "strong", "b":
                out += "**"
            case "em", "i":
                out += "*"
            case "a":
                if closing {
                    if let href = hrefs.popLast() ?? nil { out += "](\(href))" }
                } else {
                    var href: String?
                    if let r = attrs.range(of: "href\\s*=\\s*(\"[^\"]*\"|'[^']*')", options: [.regularExpression, .caseInsensitive]) {
                        let value = attrs[r].drop { $0 != "\"" && $0 != "'" }.dropFirst().dropLast()
                        href = decodeEntities(String(value))
                    }
                    hrefs.append(href)
                    if href != nil { out += "[" }
                }
            case "ul", "ol":
                if closing {
                    _ = lists.popLast()
                    if lists.isEmpty { blockBreak() }
                } else {
                    if lists.isEmpty { blockBreak() } else if !out.hasSuffix("\n") { out += "\n" }
                    lists.append((name == "ol", 1))
                }
            case "li":
                guard !closing, !lists.isEmpty else { break }
                if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
                let list = lists[lists.count - 1]
                lists[lists.count - 1].next += 1
                out += String(repeating: "  ", count: lists.count - 1) + (list.ordered ? "\(list.next). " : "- ")
            default:
                break
            }
        }
        text(ns.substring(from: cursor))

        let lines = out.components(separatedBy: "\n").map { line -> String in
            var l = Substring(line)
            while l.last == " " { l.removeLast() }
            return String(l)
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = s
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'"]
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = result as NSString
            for m in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                if let code = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result = (result as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                }
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&") // last, so "&amp;lt;" stays "&lt;"
    }

    /// The result of `transform` for `source`, or nil when it does not apply (no HTML, not JSON, no text).
    nonisolated static func apply(_ transform: PasteTransform, to source: PasteSource, locale: Locale) -> String? {
        guard let text = source.text, !text.isEmpty else { return nil }
        switch transform {
        case .plainText: return text
        case .markdown:
            guard let html = source.html, !html.isEmpty else { return nil }
            let md = markdown(fromHTML: html)
            return md.isEmpty ? nil : md
        case .prettyJSON: return prettyJSON(text)
        case .minifiedJSON: return minifiedJSON(text)
        case .uppercase: return uppercased(text, locale: locale)
        case .lowercase: return lowercased(text, locale: locale)
        case .titleCase: return titleCased(text, locale: locale)
        }
    }

    // MARK: - Pasteboard

    /// Reads the current pasteboard; called when the palette screen opens.
    func refreshSource() {
        let pb = NSPasteboard.general
        source = PasteSource(text: pb.string(forType: .string), html: pb.string(forType: .html))
    }

    // MARK: - Paste into the previous app

    /// ⌘V key-down and key-up (virtual key 9). Not posted here so it can be unit-tested.
    static func pasteKeyEvents(source: CGEventSource? = nil) -> [CGEvent] {
        [true, false].compactMap { keyDown in
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)
            event?.flags = .maskCommand
            return event
        }
    }

    /// Writes `result` as plain text, closes the host (palette panel), returns focus to the app that was
    /// active before and sends it ⌘V. Needs the Accessibility permission the app already requests.
    func paste(_ result: String, closeHost: () -> Void) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result, forType: .string)
        closeHost()
        if let app = previousApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for event in Self.pasteKeyEvents() { event.post(tap: .cghidEventTap) }
        }
    }

    private func trackPreviousApp() {
        let ownID = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != ownID {
            previousApp = front
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != ownID else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    // MARK: - Global Shortcut (⌃⌥⇧V) via Carbon HotKey

    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), advancedPasteHotKeyHandler, 1, &eventType, nil, &eventHandlerRef)
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x41445650), id: 1) // "ADVP"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("[AdvancedPaste] Failed to register Carbon HotKey: %d", status) }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    // MARK: - Monitoring

    func stopMonitoring() {
        unregisterHotKey()
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer); activationObserver = nil }
    }
}
