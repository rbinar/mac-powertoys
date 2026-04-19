import Foundation
import AppKit

@MainActor
final class TestDataGeneratorModel: ObservableObject {
    @Published var generatedData: String = ""
    
    private let loremWords = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim", "ad", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "ut", "aliquip", "ex", "ea", "commodo", "consequat", "duis", "aute", "irure", "dolor", "in", "reprehenderit", "in", "voluptate", "velit", "esse", "cillum", "dolore", "eu", "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat", "cupidatat", "non", "proident", "sunt", "in", "culpa", "qui", "officia", "deserunt", "mollit", "anim", "id", "est", "laborum"]
    private let firstNames = ["James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda", "David", "Elizabeth", "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen"]
    private let lastNames = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin"]

    func generateUUID() {
        let uuid = UUID().uuidString
        copyToClipboard(uuid)
    }
    
    func generateLoremIpsum(length: LoremLength) {
        let lengthCount: Int
        switch length {
        case .short: lengthCount = 10
        case .medium: lengthCount = 30
        case .long: lengthCount = 80
        }
        
        var words: [String] = []
        for _ in 0..<lengthCount {
            words.append(loremWords.randomElement()!)
        }
        
        let text = capitalizeFirstLetter(words.joined(separator: " ")) + "."
        copyToClipboard(text)
    }
    
    func generateName() {
        let name = "\(firstNames.randomElement()!) \(lastNames.randomElement()!)"
        copyToClipboard(name)
    }
    
    func generateDate() {
        let randomTimeInterval = TimeInterval.random(in: 0...Date().timeIntervalSince1970)
        let randomDate = Date(timeIntervalSince1970: randomTimeInterval)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: randomDate)
        copyToClipboard(dateString)
    }
    
    private func copyToClipboard(_ string: String) {
        generatedData = string
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func capitalizeFirstLetter(_ text: String) -> String {
        guard let firstCharacter = text.first else {
            return text
        }
        return firstCharacter.uppercased() + text.dropFirst()
    }
    
    enum LoremLength {
        case short, medium, long
    }
}
