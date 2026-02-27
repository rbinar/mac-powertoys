import Foundation
import Combine
import UserNotifications
import AppKit

struct WebhookTopic: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    let topicID: String
    var isActive: Bool
}

@MainActor
final class WebhookNotifierModel: NSObject, ObservableObject, URLSessionDataDelegate {
    
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                activate()
            } else {
                deactivate()
            }
        }
    }
    
    @Published var notificationSound: Bool = true
    @Published var serverURL: String = "https://ntfy.blinkbrosai.com" {
        didSet {
            if isEnabled {
                // Reconnect all active topics if server URL changes
                deactivate()
                activate()
            }
        }
    }
    
    // MARK: - Persisted State
    @Published var topics: [WebhookTopic] = [] {
        didSet {
            saveTopics()
        }
    }
    private let topicsKey = "webhookNotifier.topics"
    
    // MARK: - Runtime State
    @Published private(set) var connectionStates: [UUID: Bool] = [:]
    @Published private(set) var lastMessage: (label: String, title: String?, body: String, date: Date)? = nil
    
    // MARK: - Private State
    private var dataBuffers: [UUID: Data] = [:]
    private var streamTasks: [UUID: URLSessionDataTask] = [:]
    private var reconnectTimers: [UUID: Timer] = [:]
    private var retryCounters: [UUID: Int] = [:]
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600 * 24 // Long timeout for SSE
        config.timeoutIntervalForResource = 3600 * 24
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    override init() {
        super.init()
        loadTopics()
    }
    
    // MARK: - Topic CRUD
    func addTopic(label: String) {
        let newTopic = WebhookTopic(id: UUID(), label: label, topicID: UUID().uuidString, isActive: true)
        topics.append(newTopic)
        if isEnabled {
            subscribe(to: newTopic)
        }
    }
    
    func removeTopic(id: UUID) {
        unsubscribe(topicID: id)
        topics.removeAll { $0.id == id }
        connectionStates.removeValue(forKey: id)
    }
    
    func toggleTopic(id: UUID) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].isActive.toggle()
        
        if topics[index].isActive && isEnabled {
            subscribe(to: topics[index])
        } else {
            unsubscribe(topicID: id)
            connectionStates[id] = false
        }
    }
    
    func renameTopic(id: UUID, newLabel: String) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].label = newLabel
    }
    
    private func saveTopics() {
        do {
            let data = try JSONEncoder().encode(topics)
            UserDefaults.standard.set(data, forKey: topicsKey)
        } catch {
            NSLog("[WebhookNotifier] Failed to encode topics for saving: %@", String(describing: error))
        }
    }
    
    private func loadTopics() {
        guard let data = UserDefaults.standard.data(forKey: topicsKey) else { return }
        do {
            topics = try JSONDecoder().decode([WebhookTopic].self, from: data)
        } catch {
            NSLog("[WebhookNotifier] Failed to decode topics: %@", String(describing: error))
        }
    }
    
    // MARK: - Connection Management
    private func activate() {
        requestNotificationPermission()
        for topic in topics where topic.isActive {
            subscribe(to: topic)
        }
    }
    
    private func deactivate() {
        for topic in topics {
            unsubscribe(topicID: topic.id)
            connectionStates[topic.id] = false
        }
    }
    
    func stopMonitoring() {
        deactivate()
    }
    
    private func subscribe(to topic: WebhookTopic) {
        unsubscribe(topicID: topic.id) // Ensure no duplicate tasks
        
        guard let url = URL(string: "\(serverURL)/\(topic.topicID)/json") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3600 * 24
        
        let task = urlSession.dataTask(with: request)
        task.taskDescription = topic.id.uuidString
        streamTasks[topic.id] = task
        task.resume()
        
        // Optimistically set to true, will be updated if it fails
        connectionStates[topic.id] = true
        retryCounters[topic.id] = 0
        print("[WebhookNotifier] Subscribed to topic: \(topic.label)")
    }
    
    private func unsubscribe(topicID: UUID) {
        streamTasks[topicID]?.cancel()
        streamTasks.removeValue(forKey: topicID)
        dataBuffers.removeValue(forKey: topicID)
        
        reconnectTimers[topicID]?.invalidate()
        reconnectTimers.removeValue(forKey: topicID)
    }
    
    private func scheduleReconnect(for topicID: UUID) {
        guard isEnabled, let topic = topics.first(where: { $0.id == topicID }), topic.isActive else { return }
        
        let retryCount = retryCounters[topicID] ?? 0
        let backoffSeconds = min(pow(2.0, Double(retryCount)) * 5.0, 60.0) // 5, 10, 20, 40, 60...
        retryCounters[topicID] = retryCount + 1
        
        print("[WebhookNotifier] Scheduling reconnect for \(topic.label) in \(backoffSeconds) seconds")
        
        reconnectTimers[topicID]?.invalidate()
        reconnectTimers[topicID] = Timer.scheduledTimer(withTimeInterval: backoffSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.subscribe(to: topic)
            }
        }
    }
    
    // MARK: - URLSessionDataDelegate
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let taskDesc = dataTask.taskDescription, let topicID = UUID(uuidString: taskDesc) else { return }
        
        // Buffer incoming data to handle partial messages
        Task { @MainActor in
            var buffer = self.dataBuffers[topicID] ?? Data()
            buffer.append(data)
            
            // Process complete lines (newline-delimited JSON)
            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                
                guard !lineData.isEmpty else { continue }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: lineData, options: []) as? [String: Any],
                       let event = json["event"] as? String {
                        
                        if event == "message" {
                            let title = json["title"] as? String
                            let message = json["message"] as? String ?? "New webhook received"
                            self.handleMessage(topicID: topicID, title: title, message: message)
                        } else if event == "open" {
                            self.connectionStates[topicID] = true
                            self.retryCounters[topicID] = 0
                        }
                    }
                } catch {
                    NSLog("[WebhookNotifier] Failed to parse JSON: %@", String(describing: error))
                }
            }
            
            self.dataBuffers[topicID] = buffer
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskDesc = task.taskDescription, let topicID = UUID(uuidString: taskDesc) else { return }
        
        Task { @MainActor in
            self.connectionStates[topicID] = false
            if let error = error as NSError?, error.code != NSURLErrorCancelled {
                print("[WebhookNotifier] Stream disconnected with error: \(error.localizedDescription)")
                self.scheduleReconnect(for: topicID)
            }
        }
    }
    
    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[WebhookNotifier] Notification permission error: \(error)")
            }
        }
    }
    
    private func handleMessage(topicID: UUID, title: String?, message: String) {
        guard let topic = topics.first(where: { $0.id == topicID }) else { return }
        
        lastMessage = (label: topic.label, title: title, body: message, date: Date())
        
        let content = UNMutableNotificationContent()
        content.title = title ?? topic.label
        content.body = message
        content.threadIdentifier = topic.topicID
        
        if notificationSound {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WebhookNotifier] Failed to show notification: \(error)")
            }
        }
    }
    
    // MARK: - Testing
    func sendTestNotification(for topic: WebhookTopic) {
        guard let url = URL(string: "\(serverURL)/\(topic.topicID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "This is a test notification from Mac PowerToys".data(using: .utf8)
        request.setValue("Test Notification", forHTTPHeaderField: "Title")
        
        URLSession.shared.dataTask(with: request).resume()
    }
}
