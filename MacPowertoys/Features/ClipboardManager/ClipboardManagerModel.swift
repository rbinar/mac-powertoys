import SwiftUI
import AppKit
import Carbon

enum ClipboardItemType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    var textContent: String?
    var imageFileName: String?
    let createdAt: Date
    var isPinned: Bool
    
    // Helper to get the image URL (with path traversal protection)
    var imageURL: URL? {
        guard let fileName = imageFileName else { return nil }
        let sanitizedName = (fileName as NSString).lastPathComponent
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let historyDir = appSupport.appendingPathComponent("ClipboardHistory", isDirectory: true)
        return historyDir.appendingPathComponent(sanitizedName)
    }
}

@MainActor
final class ClipboardManagerModel: ObservableObject {
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "clipboardManager.isEnabled")
            if isEnabled {
                startMonitoring()
            } else {
                stopPollingTimer()
            }
        }
    }
    
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var maxHistoryCount: Int = 25 {
        didSet {
            UserDefaults.standard.set(maxHistoryCount, forKey: "clipboardManager.maxHistoryCount")
            enforceLimit()
        }
    }
    @Published var searchText: String = ""
    
    private var pollTimer: Timer?
    private var lastChangeCount: Int = 0
    private var isInternalCopy: Bool = false
    
    private let itemsKey = "clipboardManager.items"
    private let historyDir: URL
    
    // Global HotKey
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    init() {
        // Setup directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyDir = appSupport.appendingPathComponent("ClipboardHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        
        // Load settings
        self.isEnabled = UserDefaults.standard.bool(forKey: "clipboardManager.isEnabled")
        if UserDefaults.standard.object(forKey: "clipboardManager.maxHistoryCount") != nil {
            self.maxHistoryCount = UserDefaults.standard.integer(forKey: "clipboardManager.maxHistoryCount")
        }
        
        loadItems()
        setupGlobalHotKey()
        
        if isEnabled {
            startMonitoring()
        }
    }
    
    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardItems
        }
        return clipboardItems.filter { item in
            if item.type == .text, let text = item.textContent {
                return text.localizedCaseInsensitiveContains(searchText)
            }
            return false
        }
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }
    
    private func stopPollingTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        
        if isInternalCopy {
            isInternalCopy = false
            return
        }
        
        // Check for text first
        if let text = pb.string(forType: .string) {
            // Avoid duplicates of the most recent item
            if let first = clipboardItems.first, first.type == .text, first.textContent == text {
                return
            }
            
            let item = ClipboardItem(
                id: UUID(),
                type: .text,
                textContent: text,
                createdAt: Date(),
                isPinned: false
            )
            addItem(item)
            return
        }
        
        // Check for image
        if let imgData = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: imgData) {
            
            let fileName = "\(UUID().uuidString).png"
            let fileURL = historyDir.appendingPathComponent(fileName)
            
            // Convert to PNG and save
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                
                do {
                    try pngData.write(to: fileURL)
                    let item = ClipboardItem(
                        id: UUID(),
                        type: .image,
                        imageFileName: fileName,
                        createdAt: Date(),
                        isPinned: false
                    )
                    addItem(item)
                } catch {
                    NSLog("[ClipboardManager] Failed to save clipboard image: %@", String(describing: error))
                }
            }
        }
    }
    
    private func addItem(_ item: ClipboardItem) {
        clipboardItems.insert(item, at: 0)
        enforceLimit()
        saveItems()
    }
    
    private func enforceLimit() {
        let unpinnedCount = clipboardItems.filter { !$0.isPinned }.count
        if unpinnedCount > maxHistoryCount {
            // Find the oldest unpinned items to remove
            let itemsToRemove = clipboardItems.filter { !$0.isPinned }.suffix(unpinnedCount - maxHistoryCount)
            for item in itemsToRemove {
                deleteItem(item, saveAfter: false)
            }
            saveItems()
        }
    }
    
    // MARK: - Actions
    
    func copyItemToPasteboard(_ item: ClipboardItem) {
        isInternalCopy = true
        let pb = NSPasteboard.general
        pb.clearContents()
        
        if item.type == .text, let text = item.textContent {
            pb.setString(text, forType: .string)
        } else if item.type == .image, let url = item.imageURL, let image = NSImage(contentsOf: url) {
            pb.writeObjects([image])
        }
        
        lastChangeCount = pb.changeCount
    }
    
    func deleteItem(_ item: ClipboardItem, saveAfter: Bool = true) {
        if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
            clipboardItems.remove(at: index)
            
            // Delete image file if it exists
            if let url = item.imageURL {
                try? FileManager.default.removeItem(at: url)
            }
            
            if saveAfter {
                saveItems()
            }
        }
    }
    
    func togglePin(_ item: ClipboardItem) {
        if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
            clipboardItems[index].isPinned.toggle()
            saveItems()
        }
    }
    
    func clearHistory() {
        let itemsToRemove = clipboardItems.filter { !$0.isPinned }
        for item in itemsToRemove {
            deleteItem(item, saveAfter: false)
        }
        saveItems()
    }
    
    // MARK: - Persistence
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(clipboardItems)
            UserDefaults.standard.set(data, forKey: itemsKey)
        } catch {
            NSLog("[ClipboardManager] Failed to encode clipboard items: %@", String(describing: error))
        }
    }
    
    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: itemsKey) else { return }
        do {
            self.clipboardItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            NSLog("[ClipboardManager] Failed to decode clipboard items: %@", String(describing: error))
        }
    }
    
    // MARK: - Global HotKey (⌃⌥V)
    
    private func setupGlobalHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = UTGetOSTypeFromString("CBMG" as CFString)
        hotKeyID.id = 2 // Unique ID for this hotkey
        
        // kVK_ANSI_V is 0x09
        let keyCode = UInt32(0x09)
        let modifiers = UInt32(controlKey | optionKey)
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            
            let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
                Task { @MainActor in
                    NotificationCenter.default.post(name: NSNotification.Name("ShowClipboardManager"), object: nil)
                }
                return noErr
            }
            
            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandlerRef)
        }
    }
    
    func stopMonitoring() {
        stopPollingTimer()
        removeGlobalHotKey()
    }
    
    private func removeGlobalHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
