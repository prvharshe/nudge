import Foundation
import Observation

// MARK: - Coach Keep

struct CoachKeep: Codable, Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String
    let savedAt: Date
    var label: String

    init(from message: CoachMessage, savedAt: Date = .now) {
        self.id = message.id
        self.question = message.question
        self.answer = message.answer
        self.savedAt = savedAt
        self.label = CoachKeep.label(from: message.answer)
    }

    /// First sentence of the answer, capped for chip display.
    static func label(from answer: String) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Saved advice" }

        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        let firstSentence: String
        if let range = trimmed.rangeOfCharacter(from: sentenceEnders) {
            firstSentence = String(trimmed[..<range.upperBound])
        } else {
            firstSentence = trimmed
        }

        let collapsed = firstSentence
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let maxLength = 45
        if collapsed.count <= maxLength { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

// MARK: - Store

@Observable
final class CoachKeepStore {
    static let shared = CoachKeepStore()

    private let defaultsKey = "nudge.coachKeeps"

    private(set) var keeps: [CoachKeep] = []

    private init() { load() }

    var isEmpty: Bool { keeps.isEmpty }

    func isKept(id: UUID) -> Bool {
        keeps.contains { $0.id == id }
    }

    @discardableResult
    func keep(from message: CoachMessage) -> CoachKeep? {
        guard !isKept(id: message.id) else { return nil }
        let keep = CoachKeep(from: message)
        keeps.insert(keep, at: 0)
        save()
        return keep
    }

    func unkeep(id: UUID) {
        keeps.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(keeps) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([CoachKeep].self, from: data)
        else { return }
        keeps = decoded.sorted { $0.savedAt > $1.savedAt }
    }
}
