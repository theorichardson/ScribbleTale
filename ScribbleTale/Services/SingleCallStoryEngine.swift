import Foundation
import os

private let log = Logger(subsystem: "com.scribbletale.app", category: "SingleCallStoryEngine")

// MARK: - Parsed Story

struct ParsedStory: Sendable {
    let characterName: String
    let characterSpecies: String
    let characterAppearance: String
    let introduction: String
    let beats: [Beat]

    struct Beat: Sendable {
        let drawingPrompt: String
        let continuation: String
    }

    var characterBible: CharacterBible {
        CharacterBible(
            name: characterName,
            species: characterSpecies,
            appearance: characterAppearance,
            personality: "brave and curious",
            want: "to go on an adventure"
        )
    }

    func challenge(at index: Int) -> DrawingChallenge {
        guard index < beats.count else {
            return DrawingChallenge.fallbacks[.introduce]!
        }
        let beat = beats[index]
        let subject = Self.deriveSubject(from: beat.drawingPrompt)
        return DrawingChallenge(
            subject: subject,
            role: "part of the story",
            drawingPrompt: beat.drawingPrompt,
            imageGenPrompt: "\(subject), storybook illustration, warm watercolor, soft edges"
        )
    }

    private static func deriveSubject(from drawingPrompt: String) -> String {
        var subject = drawingPrompt
        if let range = subject.range(of: "Draw ", options: .caseInsensitive) {
            subject = String(subject[range.upperBound...])
        }
        subject = subject.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        )
        return subject.isEmpty ? drawingPrompt : subject
    }
}

// MARK: - Engine

@Observable
@MainActor
final class SingleCallStoryEngine {
    let textProvider: any TextGenerationProvider
    private(set) var isGenerating = false

    var isLoaded: Bool { textProvider.isLoaded }
    var isLoadingModel: Bool { textProvider.isLoadingModel }
    var loadingProgress: Double { textProvider.loadingProgress }
    var loadingStatus: String { textProvider.loadingStatus }
    var loadError: String? { textProvider.loadError }
    var loadedModel: StoryModel? { textProvider.loadedModel }
    var thinkingText: String { textProvider.thinkingText }

    init(textProvider: any TextGenerationProvider) {
        self.textProvider = textProvider
    }

    func resetThinkingText() {
        textProvider.resetThinkingText()
    }

    func loadModel(_ model: StoryModel) async {
        await textProvider.load(model)
    }

    // MARK: - Single-Call Generation

    func generateFullStory(
        genre: String,
        sceneCount: Int
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateFullStory: genre=\(genre, privacy: .public) scenes=\(sceneCount)")

        let provider = textProvider
        let isThinking = loadedModel?.isThinkingModel ?? false
        let maxTokens = isThinking
            ? SingleCallPrompt.maxTokens + 200
            : SingleCallPrompt.maxTokens

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                self?.isGenerating = true
                defer { self?.isGenerating = false }

                var tokenCount = 0
                do {
                    for try await chunk in provider.generate(
                        systemPrompt: SingleCallPrompt.system(genre: genre),
                        userPrompt: SingleCallPrompt.user(genre: genre, sceneCount: sceneCount),
                        maxTokens: maxTokens,
                        temperature: SingleCallPrompt.temperature,
                        topP: SingleCallPrompt.topP
                    ) {
                        tokenCount += 1
                        continuation.yield(chunk)
                    }
                    log.info("generateFullStory: completed — \(tokenCount) chunks")
                    continuation.finish()
                } catch {
                    log.error("generateFullStory: error after \(tokenCount) chunks — \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Parsing

    static func parseFullStory(_ text: String, sceneCount: Int) -> ParsedStory? {
        let cleaned = cleanMarkdown(text)

        let name = extractField("NAME", from: cleaned)
        let species = extractField("SPECIES", from: cleaned)
        let appearance = extractField("APPEARANCE", from: cleaned)

        let intro = extractSection("INTRO", from: cleaned)

        var beats: [ParsedStory.Beat] = []
        for i in 1...sceneCount {
            let rawPrompt = extractSection("DRAW_\(i)", from: cleaned)
            let continuation: String
            if i < sceneCount {
                continuation = extractSection("STORY_\(i)", from: cleaned)
            } else {
                continuation = extractSection("CONCLUSION", from: cleaned)
            }

            guard !rawPrompt.isEmpty else {
                log.warning("parseFullStory: missing DRAW_\(i)")
                continue
            }

            beats.append(ParsedStory.Beat(
                drawingPrompt: cleanDrawingPrompt(rawPrompt),
                continuation: cleanNarration(continuation)
            ))
        }

        guard !name.isEmpty, !intro.isEmpty, beats.count == sceneCount else {
            log.error("""
                parseFullStory: failed — \
                name=\"\(name, privacy: .public)\" \
                intro=\(intro.count)chars \
                beats=\(beats.count)/\(sceneCount)
                """)
            return nil
        }

        log.info("parseFullStory: success — \(name, privacy: .public) the \(species, privacy: .public), \(beats.count) beats")
        return ParsedStory(
            characterName: name,
            characterSpecies: species.isEmpty ? "creature" : species,
            characterAppearance: appearance.isEmpty ? "small and curious" : appearance,
            introduction: cleanNarration(intro),
            beats: beats
        )
    }

    // MARK: - Image Prompt Enrichment

    static func enrichedImagePrompt(
        challenge: DrawingChallenge,
        characterBible: CharacterBible?
    ) -> String {
        var enriched = challenge.imageGenPrompt

        if let bible = characterBible,
           !enriched.lowercased().contains(bible.species.lowercased()) {
            enriched += ". \(bible.name) the \(bible.species) (\(bible.appearance)) is present"
        }

        if !enriched.lowercased().contains("storybook") {
            enriched += ", storybook illustration, warm watercolor, soft edges"
        }

        enriched += ". Single clear depiction, no duplicates."
        return enriched
    }

    // MARK: - Parsing Helpers

    private static func extractField(_ label: String, from text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"(?:^|\n)\s*"# + escaped + #"\s*:\s*(.+?)(?=\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func extractSection(_ name: String, from text: String) -> String {
        let delimiter = "---\(name)---"
        guard let startRange = text.range(of: delimiter, options: .caseInsensitive) else {
            return ""
        }
        let afterDelimiter = text[startRange.upperBound...]
        if let nextDelimiter = afterDelimiter.range(
            of: #"---[A-Z_0-9]+---"#,
            options: .regularExpression
        ) {
            return String(afterDelimiter[afterDelimiter.startIndex..<nextDelimiter.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(afterDelimiter).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanMarkdown(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\*{1,3}([^*]+)\*{1,3}"#,
            with: "$1",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanDrawingPrompt(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let dotRange = result.range(of: ".", options: .literal) {
            let sentence = String(result[result.startIndex..<dotRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result = sentence }
        }

        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }

        let words = result.split(separator: " ")
        if words.count > 8 {
            result = words.prefix(8).joined(separator: " ")
        }

        if !result.hasSuffix("!") { result += "!" }
        return result
    }

    private static func cleanNarration(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        result = result.replacingOccurrences(
            of: #"^["""\u{201C}\u{201D}]|["""\u{201C}\u{201D}]$"#,
            with: "",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
