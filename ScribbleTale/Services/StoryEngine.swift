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

    // MARK: - Generation Methods

    func generateIntroduction(for storyType: StoryType) -> AsyncThrowingStream<String, Error> {
        log.info("generateIntroduction: storyType=\(storyType.rawValue, privacy: .public)")
        let prompt = """
        Write ONE sentence (under 15 words) to open a \(storyType.rawValue) story. \
        Describe only the setting — no characters. End with suspense.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt,
            maxTokens: 40
        )
    }

    func generateDrawingPrompt(
        for chapter: Chapter,
        storyType: StoryType,
        previousChapters: [Chapter],
        introText: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateDrawingPrompt: ch\(chapter.index) beat=\(chapter.beat.rawValue, privacy: .public) subject=\(chapter.drawingSubject.displayName, privacy: .public)")
        var contextParts: [String] = []
        if !introText.isEmpty { contextParts.append(introText) }
        contextParts += previousChapters.compactMap { $0.narration.isEmpty ? nil : $0.narration }
        let context = contextParts.joined(separator: " ")

        let prompt: String
        if context.isEmpty {
            prompt = "\(chapter.drawingSubject.drawingPromptHint) Reply with ONLY: Draw a <thing>"
        } else {
            prompt = "Story so far: \(context)\n\n\(chapter.drawingSubject.drawingPromptHint) Reply with ONLY: Draw a <thing>"
        }
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt,
            maxTokens: 20
        )
    }

    func generateNarration(
        for chapter: Chapter,
        storyType: StoryType,
        previousChapters: [Chapter],
        introText: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateNarration: ch\(chapter.index) beat=\(chapter.beat.rawValue, privacy: .public) drawingPrompt=\(chapter.drawingPrompt, privacy: .public) priorChapters=\(previousChapters.count)")
        var contextParts: [String] = []
        if !introText.isEmpty { contextParts.append(introText) }
        contextParts += previousChapters.compactMap { $0.narration.isEmpty ? nil : $0.narration }
        let context = contextParts.joined(separator: " ")

        let beatGuide: String = switch chapter.beat {
        case .character: "Name the animal hero and give them one trait."
        case .companion: "Introduce a companion animal or creature."
        case .setting: "Describe the place with one vivid detail."
        case .object: "The hero finds a special object or tool."
        case .villain: "Introduce the animal or creature causing trouble."
        case .climax: "The hero tries something brave to fix the problem."
        case .resolution: "The problem is solved and the hero has grown."
        }

        let prompt: String
        if context.isEmpty {
            prompt = "\(beatGuide) Write 1-2 sentences."
        } else {
            prompt = "Story so far: \(context)\n\n\(beatGuide) Write 1-2 sentences continuing the story."
        }
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt,
            maxTokens: 60
        )
    }

    // MARK: - Output Cleaning

    /// Strips conversational preamble and leaked instructions that small LLMs
    /// frequently emit despite being told to output only story content.
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

    /// Markers that indicate a sentence is leaked instructions, not story content.
    private static let instructionMarkers = [
        "do not", "don't", "write only", "write a", "caption",
        "describe what", "image prompt", "story so far",
        "picture book", "kids aged", "children's storyteller",
        "draw a", "drawing prompt", "meta-text",
        "1-2 sentences", "short sentences", "continue the story",
        "next story event", "plain, concrete",
    ]

    /// Returns true if a sentence looks like a leaked instruction rather than story text.
    private static func isLeakedInstruction(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return instructionMarkers.contains { lower.contains($0) }
    }

    /// Cleans narration by removing any sentences that are leaked instructions
    /// or echoed prompts rather than actual story content.
    static func cleanNarration(_ text: String, drawingPrompt: String) -> String {
        let base = cleanGeneratedText(text)
        let sentences = base.splitSentences()

        let storySentences = sentences.filter { sentence in
            !isLeakedInstruction(sentence)
        }

        let result = storySentences.prefix(2).joined(separator: " ")
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

    /// Cleans a drawing prompt, keeping only the "Draw a ..." sentence.
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

    // MARK: - Private

    private func storySystemPrompt(for storyType: StoryType) -> String {
        "You are a storyteller writing a short \(storyType.rawValue) picture book for kids. All characters are animals or creatures — never humans or people. Use simple, concrete language. Keep every response to 1-2 sentences maximum."
    }

    private static let controlTokenPattern = /(<end_of_turn>|<start_of_turn>|<eos>|<bos>|<pad>)/

    private func streamText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 100
    ) -> AsyncThrowingStream<String, Error> {
        guard let modelContainer else {
            log.error("streamText: model not loaded, returning empty stream")
            return AsyncThrowingStream { $0.finish() }
        }

        let container = modelContainer
        let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.6, topP: 0.9)
        let promptPreview = String(userPrompt.prefix(80))
        log.info("streamText: starting — maxTokens=\(maxTokens) prompt=\"\(promptPreview, privacy: .public)...\"")

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

// MARK: - String helpers for narration cleaning

private extension String {
    /// Splits text into sentences at `.` `!` `?` boundaries, keeping each
    /// sentence's trailing punctuation attached.
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

    /// Fraction of words in `self` that also appear in `other` (order-independent).
    func commonWordRatio(with other: String) -> Double {
        let a = Set(self.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map { $0.lowercased() })
        let b = Set(other.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map { $0.lowercased() })
        guard !a.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.count)
    }
}
