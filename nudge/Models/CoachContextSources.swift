import Foundation

/// Retrieval counts the coach used for a reply (from SSE `meta.generating`).
struct CoachContextSources: Codable, Equatable, Sendable {
    var recentEntries: Int
    var semanticHits: Int
    var profile: Int
    var keeps: Int

    static let empty = CoachContextSources(
        recentEntries: 0,
        semanticHits: 0,
        profile: 0,
        keeps: 0
    )

    var checkInCount: Int { recentEntries + semanticHits }

    var isEmpty: Bool {
        checkInCount == 0 && profile == 0 && keeps == 0
    }
}

enum CoachStreamEvent: Sendable {
    case retrieving
    case generating(CoachContextSources)
    case token(String)
    case done
}
