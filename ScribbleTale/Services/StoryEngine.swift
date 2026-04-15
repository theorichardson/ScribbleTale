import Foundation
import os
import MLXLLM
import MLXLMCommon

private let log = Logger(subsystem: "com.scribbletale.app", category: "StoryEngine")

@Observable
@MainActor
final class StoryEngine {
    private var modelContainer: ModelContainer?
    private(set) var isLoaded = false
    private(set) var isGenerating = false
    private(set) var loadingProgress: Double = 0
    private(set) var loadingStatus: String = ""

    private static let modelID = "mlx-community/gemma-3-1b-it-4bit"

    func loadModel() async {
        guard !isLoaded else {
            log.info("loadModel: already loaded, skipping")
            return
        }
        log.info("loadModel: starting — model=\(Self.modelID, privacy: .public)")
        loadingStatus = "Downloading model..."

        do {
            let config = ModelConfiguration(id: Self.modelID)
            log.info("loadModel: config created, calling loadContainer")
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.loadingProgress = progress.fractionCompleted
                    if progress.fractionCompleted < 1.0 {
                        let pct = Int(progress.fractionCompleted * 100)
                        self.loadingStatus = "Downloading model... \(pct)%"
                    } else {
                        self.loadingStatus = "Loading model into memory..."
                    }
                }
            }
            isLoaded = true
            loadingStatus = "Model ready"
            log.info("loadModel: SUCCESS — model loaded and ready")
        } catch {
            loadingStatus = "Model failed to load"
            log.error("loadModel: FAILED — \(error, privacy: .public)")
        }
    }

    // MARK: - Prompt 1: Story Introduction

    struct IntroductionResult {
        var setting: String
        var protagonist: String
        var opening: String
        var gap: String
    }

    func generateIntroduction(for storyType: StoryType) -> AsyncThrowingStream<String, Error> {
        log.info("generateIntroduction: storyType=\(storyType.rawValue, privacy: .public)")
        let prompt = """
        Genre: \(storyType.rawValue)

        Write a story opening. Return exactly this structure:
        SETTING: [one sentence describing where and when]
        PROTAGONIST: [one sentence: an animal or creature, who they are and what they want]
        OPENING: [2-3 simple sentences of story. End on a moment of need or mystery.]
        GAP: [one sentence describing what animal, creature, or object could resolve the tension]
        """
        return streamText(
            systemPrompt: introSystemPrompt(for: storyType),
            userPrompt: prompt,
            maxTokens: 80,
            temperature: 0.7,
            topP: 0.9
        )
    }

    static func parseIntroduction(_ text: String, storyType: StoryType) -> IntroductionResult {
        let cleaned = cleanGeneratedText(text)

        let setting = extractField("SETTING", from: cleaned)
        let protagonist = extractField("PROTAGONIST", from: cleaned)
        let opening = extractField("OPENING", from: cleaned)
        let gap = extractField("GAP", from: cleaned)

        if !opening.isEmpty {
            log.info("parseIntroduction: structured parse succeeded")
            return IntroductionResult(
                setting: setting.isEmpty ? "A mysterious land where animals roam" : setting,
                protagonist: protagonist.isEmpty ? "A brave little rabbit who dreams of adventure" : protagonist,
                opening: opening,
                gap: gap.isEmpty ? "a helpful creature or special object" : gap
            )
        }

        log.warning("parseIntroduction: structured parse failed, using raw text as opening")
        return IntroductionResult(
            setting: "A mysterious land where animals roam",
            protagonist: "A brave little rabbit who dreams of adventure",
            opening: cleaned,
            gap: "a helpful creature or special object"
        )
    }

    // MARK: - Prompt 2: Drawing Challenge

    func generateDrawingChallenge(
        gap: String,
        state: NarrativeState,
        storyType: StoryType
    ) -> AsyncThrowingStream<String, Error> {
        let beatIndex = state.currentBeatIndex
        log.info("generateDrawingChallenge: beat \(beatIndex) gap=\"\(gap, privacy: .public)\"")
        let prompt = """
        Setting: \(state.setting)
        Protagonist: \(state.protagonist)
        Story gap: \(gap)
        Beat number: \(beatIndex + 1) of \(state.beatPlan.count)

        Return exactly this structure:
        SUBJECT: [the specific animal, creature, or object to draw, 2-5 words]
        ROLE: [one sentence: how it will matter in the story]
        DRAWING_PROMPT: [what to show the child, starting with "Draw", under 15 words]
        IMAGE_GEN_PROMPT: [detailed visual description for image generation, include "children's storybook illustration, warm colors, soft edges"]
        """
        return streamText(
            systemPrompt: challengeSystemPrompt,
            userPrompt: prompt,
            maxTokens: 60,
            temperature: 0.7,
            topP: 0.9
        )
    }

    static func parseDrawingChallenge(_ text: String, fallbackRole: BeatRole) -> DrawingChallenge {
        let cleaned = cleanGeneratedText(text)

        let subject = extractField("SUBJECT", from: cleaned)
        let role = extractField("ROLE", from: cleaned)
        let drawingPrompt = extractField("DRAWING_PROMPT", from: cleaned)
        let imageGenPrompt = extractField("IMAGE_GEN_PROMPT", from: cleaned)

        if !subject.isEmpty && !drawingPrompt.isEmpty {
            log.info("parseDrawingChallenge: structured parse succeeded — subject=\"\(subject, privacy: .public)\"")
            return DrawingChallenge(
                subject: subject,
                role: role.isEmpty ? "plays an important part in the story" : role,
                drawingPrompt: cleanDrawingPrompt(drawingPrompt),
                imageGenPrompt: imageGenPrompt.isEmpty
                    ? "\(subject), children's storybook illustration, warm colors, soft edges"
                    : imageGenPrompt
            )
        }

        log.warning("parseDrawingChallenge: structured parse failed, using fallback for \(fallbackRole.rawValue, privacy: .public)")
        return DrawingChallenge.fallbacks[fallbackRole]
            ?? DrawingChallenge.fallbacks[.introduce]!
    }

    // MARK: - Prompt 3: Image Caption

    func generateImageCaption(
        subject: String,
        role: String,
        state: NarrativeState,
        storyType: StoryType
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateImageCaption: subject=\"\(subject, privacy: .public)\"")
        let prompt = """
        Setting: \(state.setting)
        Protagonist: \(state.protagonist)
        What was drawn: \(subject)
        Its role in the story: \(role)

        Write the image caption. Maximum 2 sentences.
        """
        return streamText(
            systemPrompt: captionSystemPrompt(for: storyType),
            userPrompt: prompt,
            maxTokens: 40,
            temperature: 0.6,
            topP: 0.88
        )
    }

    static func cleanCaption(_ text: String) -> String {
        let cleaned = cleanGeneratedText(text)
        let sentences = cleaned.splitSentences()
        return sentences.prefix(2).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt 4: Narrative Bridge

    struct BridgeResult {
        var narrativeBridge: String
        var newGap: String
    }

    func generateNarrativeBridge(
        subject: String,
        role: String,
        state: NarrativeState,
        storyType: StoryType,
        beatPlan: BeatPlan
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateNarrativeBridge: beat \(beatPlan.beatIndex) role=\(beatPlan.role.rawValue, privacy: .public)")
        let context = state.compressedContext()
        let isFinalBeat = beatPlan.role == .resolve || beatPlan.role == .epilogue

        var prompt = """
        Story so far: \(context)
        Object that just appeared: \(subject)
        Its role: \(role)
        Beat number: \(beatPlan.beatIndex + 1) of \(state.beatPlan.count)

        Continue the story in 2-3 sentences. The object must appear and do something meaningful.
        """

        if !isFinalBeat {
            prompt += "\nThen on a new line write:\nNEW_GAP: [one sentence: what animal, creature, or object could resolve the new tension]"
        }

        let systemPrompt = bridgeSystemPrompt(for: storyType, tonalNote: beatPlan.role.tonalNote)
        return streamText(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            maxTokens: 60,
            temperature: 0.6,
            topP: 0.88
        )
    }

    static func parseBridgeResult(_ text: String, isFinalBeat: Bool) -> BridgeResult {
        let cleaned = cleanGeneratedText(text)

        if isFinalBeat {
            let sentences = cleaned.splitSentences()
            let bridge = sentences.prefix(3).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return BridgeResult(narrativeBridge: bridge, newGap: "")
        }

        let gap = extractField("NEW_GAP", from: cleaned)
        var bridge: String
        if !gap.isEmpty, let gapRange = cleaned.range(of: "NEW_GAP:", options: .caseInsensitive) {
            bridge = String(cleaned[cleaned.startIndex..<gapRange.lowerBound])
        } else {
            bridge = cleaned
        }

        bridge = cleanNarration(bridge)
        let finalGap = gap.isEmpty ? "something unexpected appears on the path" : gap
        return BridgeResult(narrativeBridge: bridge, newGap: finalGap)
    }

    // MARK: - Output Cleaning

    static func cleanGeneratedText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        result = result.replacingOccurrences(
            of: #"\*{1,3}([^*]+)\*{1,3}"#,
            with: "$1",
            options: .regularExpression
        )

        let preamblePatterns: [String] = [
            #"^(?:okay|ok|sure|alright|great|absolutely|here)[,!.]?\s*"#,
            #"^here(?:['''\u{2018}\u{2019}]s| is| are)\s+.*?:\s*"#,
            #"^(?:the )?(?:continuation|next part|story continues|story so far).*?:\s*"#,
            #"^chapter\s+\d+\s*(?:of\s+\d+)?[:\s—–-]*"#,
            #"^["""\u{201C}\u{201D}]|["""\u{201C}\u{201D}]$"#,
        ]

        for pattern in preamblePatterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    private static let instructionMarkers = [
        "do not", "don't", "write only", "write a", "caption",
        "describe what", "image prompt", "story so far",
        "picture book", "kids aged", "children's storyteller",
        "draw a", "drawing prompt", "meta-text",
        "1-2 sentences", "short sentences", "continue the story",
        "next story event", "plain, concrete",
        "return exactly", "beat number", "new_gap",
    ]

    private static func isLeakedInstruction(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return instructionMarkers.contains { lower.contains($0) }
    }

    static func cleanNarration(_ text: String) -> String {
        let base = cleanGeneratedText(text)
        let sentences = base.splitSentences()

        let storySentences = sentences.filter { !isLeakedInstruction($0) }
        let result = storySentences.prefix(3).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.isEmpty {
            log.warning("cleanNarration: all sentences were instructions, returning first sentence as fallback")
            return sentences.first ?? base
        }

        if storySentences.count < sentences.count {
            let dropped = sentences.count - storySentences.count
            log.info("cleanNarration: dropped \(dropped) leaked instruction sentence(s)")
        }

        return result
    }

    static func cleanDrawingPrompt(_ text: String) -> String {
        var result = cleanGeneratedText(text)

        if let drawRange = result.range(of: "Draw", options: .caseInsensitive) {
            result = String(result[drawRange.lowerBound...])
        }

        if let dotRange = result.range(of: ".", options: .literal) {
            let sentence = String(result[result.startIndex..<dotRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result = sentence }
        }

        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }

        return result
    }

    // MARK: - Structured Field Extraction

    /// Extracts the value after a labeled field like "SETTING: some value".
    /// Handles both "FIELD: value" on its own line and inline among other fields.
    static func extractField(_ label: String, from text: String) -> String {
        let pattern = #"(?:^|\n)\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*:\s*(.+?)(?=\n\s*[A-Z_]+\s*:|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[valueRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    // MARK: - System Prompts

    private func introSystemPrompt(for storyType: StoryType) -> String {
        """
        You are a storyteller writing for children ages 6-10. \
        All characters must be animals or fantastical creatures — never humans or people. \
        Write in simple, vivid sentences. Maximum 3 sentences per paragraph. \
        Always end with an unresolved situation that needs an animal, creature, or object to appear. \
        Genre: \(storyType.rawValue).
        """
    }

    private var challengeSystemPrompt: String {
        """
        You are designing a drawing challenge for a child's interactive storybook. \
        The animal, creature, or object they draw will appear in the story. \
        Be specific. "a striped badger" is better than "an animal." \
        All characters must be animals or creatures — never humans. \
        Keep the drawing prompt encouraging and under 15 words.
        """
    }

    private func captionSystemPrompt(for storyType: StoryType) -> String {
        """
        You are writing a caption for an illustration in a children's storybook. \
        The caption should sound like it belongs in the book — not like a description. \
        It should feel like the story is continuing, not pausing to explain. \
        Maximum 2 sentences. Simple words. All characters are animals or creatures.
        """
    }

    private func bridgeSystemPrompt(for storyType: StoryType, tonalNote: String) -> String {
        """
        You are continuing a children's \(storyType.rawValue) storybook. \
        All characters are animals or creatures — never humans. \
        Write simply and vividly. \
        The object or creature just drawn must appear and do something meaningful. \
        \(tonalNote) \
        Maximum 3 sentences total.
        """
    }

    // MARK: - Streaming Infrastructure

    private static let controlTokenPattern = /(<end_of_turn>|<start_of_turn>|<eos>|<bos>|<pad>)/

    private func streamText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 100,
        temperature: Float = 0.6,
        topP: Float = 0.9
    ) -> AsyncThrowingStream<String, Error> {
        guard let modelContainer else {
            log.error("streamText: model not loaded, returning empty stream")
            return AsyncThrowingStream { $0.finish() }
        }

        let container = modelContainer
        let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: topP)
        let promptPreview = String(userPrompt.prefix(80))
        log.info("streamText: starting — maxTokens=\(maxTokens) temp=\(temperature) prompt=\"\(promptPreview, privacy: .public)...\"")

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                self.isGenerating = true
                defer { self.isGenerating = false }

                let session = ChatSession(
                    container,
                    instructions: systemPrompt,
                    generateParameters: params
                )

                var tokenCount = 0
                do {
                    for try await chunk in session.streamResponse(to: userPrompt) {
                        tokenCount += 1
                        if chunk.contains("<end_of_turn>") || chunk.contains("<eos>") {
                            let cleaned = chunk.replacing(Self.controlTokenPattern, with: "")
                            if !cleaned.isEmpty { continuation.yield(cleaned) }
                            break
                        }
                        let cleaned = chunk.replacing(Self.controlTokenPattern, with: "")
                        if !cleaned.isEmpty { continuation.yield(cleaned) }
                    }
                    log.info("streamText: completed — \(tokenCount) tokens")
                    continuation.finish()
                } catch {
                    log.error("streamText: error after \(tokenCount) tokens — \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - String helpers

private extension String {
    func splitSentences() -> [String] {
        var sentences: [String] = []
        enumerateSubstrings(
            in: startIndex...,
            options: [.bySentences, .localized]
        ) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences
    }
}
