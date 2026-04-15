import Foundation
import os

private let log = Logger(subsystem: "com.scribbletale.app", category: "CoherenceGuard")

struct CoherenceGuard {

    // MARK: - Drawing Prompt Deduplication

    static func isDuplicatePrompt(
        _ newPrompt: String,
        against priorPrompts: [String],
        threshold: Double = 0.6
    ) -> Bool {
        let newWords = normalizedWordSet(newPrompt)
        for prior in priorPrompts {
            let priorWords = normalizedWordSet(prior)
            if jaccardSimilarity(newWords, priorWords) > threshold {
                log.info("isDuplicatePrompt: similarity exceeded threshold with prior prompt")
                return true
            }
        }
        return false
    }

    static func antiDuplicationSuffix(priorSubjects: [String]) -> String {
        guard !priorSubjects.isEmpty else { return "" }
        return "\nDo NOT use any of these subjects: \(priorSubjects.joined(separator: ", ")). Pick something completely different."
    }

    /// Deterministic fallback when the model fails to produce a unique prompt after retries.
    static func deterministicFallbackChallenge(
        sceneGoal: String,
        beatRole: BeatRole,
        sceneIndex: Int
    ) -> DrawingChallenge {
        let goalWords = sceneGoal.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 }

        let subject: String
        if let keyword = goalWords.first(where: { !stopWords.contains($0) }) {
            subject = "a \(keyword)"
        } else {
            subject = fallbackSubjects[sceneIndex % fallbackSubjects.count]
        }

        return DrawingChallenge(
            subject: subject,
            role: "plays a part in this scene",
            drawingPrompt: "Draw \(subject) for the story!",
            imageGenPrompt: "\(subject), storybook illustration, warm watercolor, soft edges"
        )
    }

    // MARK: - Entity Uniqueness

    static func entityAlreadyUsed(_ name: String, in priorEntities: [String]) -> Bool {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return priorEntities.contains { prior in
            let priorNorm = prior.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return priorNorm == normalized || jaccardSimilarity(
                normalizedWordSet(priorNorm),
                normalizedWordSet(normalized)
            ) > 0.7
        }
    }

    // MARK: - Output Validation

    static func validateNonEmpty(_ fields: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in fields {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = trimmed.isEmpty ? nil : trimmed
        }
        return result
    }

    static func isEchoedPrompt(_ output: String, input: String) -> Bool {
        let outWords = normalizedWordSet(output)
        let inWords = normalizedWordSet(input)
        guard !inWords.isEmpty else { return false }
        return jaccardSimilarity(outWords, inWords) > 0.8
    }

    // MARK: - Private Helpers

    private static func normalizedWordSet(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    private static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from",
        "are", "was", "were", "has", "have", "had", "been",
        "its", "his", "her", "their", "your", "our",
        "draw", "drawing", "story", "scene", "children",
    ]

    private static let fallbackSubjects = [
        "a colorful butterfly",
        "a wise old tree",
        "a sparkling river",
        "a mysterious lantern",
        "a friendly cloud",
    ]
}
