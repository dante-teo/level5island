import Foundation

struct CachedResponse: Sendable {
    let answer: String
    let cachedAt: Date
}

struct InterventionCache {
    private let ttl: TimeInterval = 30
    private var responses: [String: CachedResponse] = [:]

    mutating func record(sessionId: String, question: String, answer: String) {
        let key = Self.cacheKey(sessionId: sessionId, question: question)
        responses[key] = CachedResponse(answer: answer, cachedAt: Date())
    }

    mutating func lookup(sessionId: String, question: String) -> String? {
        prune()
        let key = Self.cacheKey(sessionId: sessionId, question: question)
        guard let cached = responses[key] else { return nil }
        guard -cached.cachedAt.timeIntervalSinceNow < ttl else {
            responses.removeValue(forKey: key)
            return nil
        }
        return cached.answer
    }

    mutating func prune() {
        let now = Date()
        responses = responses.filter { -$0.value.cachedAt.timeIntervalSince(now) < ttl }
    }

    static func cacheKey(sessionId: String, question: String) -> String {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(sessionId)||\(normalized)"
    }
}
