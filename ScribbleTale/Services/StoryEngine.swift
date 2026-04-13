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
        Write a ONE-sentence hook (under 15 words) for a \(storyType.rawValue) story. \
        Set the scene with a concrete place and a hint of what's about to happen. \
        End on a cliffhanger or unfinished moment — the sentence should feel like the story \
        is about to begin but the hero hasn't appeared yet. \
        The reader will draw the main character next, so leave room for that. \
        Do NOT name or describe any character. Focus only on the setting and a sense of suspense. \
        Only output the single sentence, nothing else.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt
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

        let prompt = """
        \(chapter.drawingSubject.drawingPromptHint) \
        This is part of a \(storyType.rawValue) story.\
        \(context.isEmpty ? "" : " Story so far: \(context)") \
        Reply with ONLY a "Draw a …" sentence (5-10 words). ONE simple subject to draw. \
        Do NOT include any preamble, label, explanation, or extra sentences. \
        Your entire reply must be just: Draw a <thing>
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt,
            maxTokens: 30
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
        case .character: "Introduce the main character — give them a name and one clear personality trait."
        case .companion: "Introduce the character's companion or pet — describe how they met or what makes this companion special."
        case .setting: "Describe where the character is — a specific, real-feeling place with one memorable detail."
        case .object: "Introduce a special object, tool, or item that the character discovers or receives."
        case .villain: "Introduce the antagonist or obstacle — who or what is causing trouble and why."
        case .climax: "The character and their allies try something brave or clever to overcome the challenge."
        case .resolution: "The problem is solved and the character learns or grows from the experience."
        }

        let prompt = """
        Continue this \(storyType.rawValue) story (1-2 short sentences only). \
        Chapter \(chapter.index + 1) of \(Story.chapterCount) — \(chapter.beat.rawValue). \(beatGuide) \
        \(context.isEmpty ? "" : "Story so far: \(context) ") \
        The child's drawing prompt was: "\(chapter.drawingPrompt)". \
        Do NOT describe what the drawing looks like or write an image caption. \
        Write ONLY the next story event — what happens, what someone says, or what changes. \
        Stay consistent with the story so far. Use plain, concrete language. \
        Only output the story text, nothing else.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt
        )
    }

    // MARK: - Output Cleaning

    /// Strips conversational preamble that small LLMs frequently emit despite
    /// instructions to output only the requested content.
    static func cleanGeneratedText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Unwrap markdown bold/italic — keep the text inside
        result = result.replacingOccurrences(
            of: #"\*{1,3}([^*]+)\*{1,3}"#,
            with: "$1",
            options: .regularExpression
        )

        let preamblePatterns: [String] = [
            #"^(?:okay|ok|sure|alright|great|absolutely)[,!.]?\s*"#,
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

    /// Cleans narration output, dropping a leading sentence if it echoes
    /// the drawing prompt rather than advancing the story.
    static func cleanNarration(_ text: String, drawingPrompt: String) -> String {
        let base = cleanGeneratedText(text)

        let sentences = base.splitSentences()
        guard sentences.count > 1 else { return base }

        let first = sentences[0].lowercased()
        let prompt = drawingPrompt.lowercased()
        let similarity = first.commonWordRatio(with: prompt)
        if similarity > 0.4 {
            return sentences.dropFirst().joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return base
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
        """
        You are a children's storyteller writing a \(storyType.rawValue) story for kids aged 6-10. \
        Write like a real picture book — grounded, clear, and easy to follow. \
        Every sentence must connect logically to what came before. \
        Use concrete details (names, places, colors, actions) instead of vague or abstract language. \
        Do NOT be random, silly, or nonsensical. Avoid made-up words, bizarre events, or surreal logic. \
        The story should feel like something a child could imagine happening — unique but believable within the genre. \
        Keep responses very short — no more than two sentences. \
        Never include meta-text, instructions, or markdown formatting.
        """
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
