import Foundation
import os

private let log = Logger(subsystem: "com.scribbletale.app", category: "StoryEngine")

@Observable
@MainActor
final class StoryEngine {
    let textProvider: any TextGenerationProvider
    private(set) var isGenerating = false

    var isLoaded: Bool { textProvider.isLoaded }
    var isLoadingModel: Bool { textProvider.isLoadingModel }
    var loadingProgress: Double { textProvider.loadingProgress }
    var loadingStatus: String { textProvider.loadingStatus }
    var loadError: String? { textProvider.loadError }
    var loadedModel: StoryModel? { textProvider.loadedModel }
    var thinkingText: String { textProvider.thinkingText }

    private var tier: ModelTier { loadedModel?.modelTier ?? .small }
    private var budget: PromptTemplates.TokenBudget { PromptTemplates.budget(for: tier) }

    init(textProvider: any TextGenerationProvider) {
        self.textProvider = textProvider
    }

    func resetThinkingText() {
        textProvider.resetThinkingText()
    }

    func loadModel(_ model: StoryModel) async {
        await textProvider.load(model)
    }

    // MARK: - Phase 1: Session Bootstrap

    func generateBlueprint(
        genre: String,
        sceneCount: Int
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateBlueprint: genre=\(genre, privacy: .public) scenes=\(sceneCount)")
        return streamText(
            systemPrompt: PromptTemplates.blueprintSystem(genre: genre),
            userPrompt: PromptTemplates.blueprintUser(genre: genre, sceneCount: sceneCount),
            maxTokens: budget.blueprint,
            temperature: 0.7,
            topP: 0.9,
            isNarrative: true
        )
    }

    static func parseBlueprint(_ text: String, sceneCount: Int) -> StoryBlueprint {
        let cleaned = cleanGeneratedText(text)
        let setting = extractField("SETTING", from: cleaned)
        let protagonist = extractField("PROTAGONIST", from: cleaned)
        let theme = extractField("THEME", from: cleaned)

        var goals: [String] = []
        for i in 1...sceneCount {
            let goal = extractField("GOAL_\(i)", from: cleaned)
            goals.append(goal.isEmpty ? "The story continues" : goal)
        }

        return StoryBlueprint(
            setting: setting.isEmpty ? "A mysterious forest where animals roam" : setting,
            protagonist: protagonist.isEmpty ? "A brave little rabbit who dreams of adventure" : protagonist,
            theme: theme.isEmpty ? "Courage and friendship" : theme,
            sceneGoals: goals
        )
    }

    func generateCharacterBible(
        protagonist: String
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateCharacterBible: protagonist=\(protagonist.prefix(60), privacy: .public)")
        return streamText(
            systemPrompt: PromptTemplates.characterBibleSystem,
            userPrompt: PromptTemplates.characterBibleUser(protagonist: protagonist),
            maxTokens: budget.characterBible,
            temperature: 0.4,
            topP: 0.9
        )
    }

    static func parseCharacterBible(_ text: String, fallbackProtagonist: String) -> CharacterBible {
        let cleaned = cleanGeneratedText(text)
        let name = extractField("NAME", from: cleaned)
        let species = extractField("SPECIES", from: cleaned)
        let appearance = extractField("APPEARANCE", from: cleaned)
        let personality = extractField("PERSONALITY", from: cleaned)
        let want = extractField("WANT", from: cleaned)

        return CharacterBible(
            name: name.isEmpty ? "Fern" : name,
            species: species.isEmpty ? deriveSpecies(from: fallbackProtagonist) : species,
            appearance: appearance.isEmpty ? deriveAppearance(from: fallbackProtagonist) : appearance,
            personality: personality.isEmpty ? "brave and curious" : personality,
            want: want.isEmpty ? "to go on an adventure" : want
        )
    }

    func generateOpening(
        blueprint: StoryBlueprint,
        bible: CharacterBible,
        genre: String
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateOpening: genre=\(genre, privacy: .public)")
        return streamText(
            systemPrompt: PromptTemplates.openingSystem(genre: genre),
            userPrompt: PromptTemplates.openingUser(blueprint: blueprint, bible: bible),
            maxTokens: budget.opening,
            temperature: 0.7,
            topP: 0.9,
            isNarrative: true
        )
    }

    static func cleanOpening(_ text: String) -> String {
        let cleaned = cleanGeneratedText(text)
        return cleanNarration(cleaned)
    }

    // MARK: - Drawing Challenge (used in bootstrap and scene loop)

    func generateDrawingChallenge(
        session: StorySession,
        sceneIndex: Int
    ) -> AsyncThrowingStream<String, Error> {
        guard let blueprint = session.blueprint,
              let bible = session.characterBible else {
            log.error("generateDrawingChallenge: missing blueprint or bible")
            return AsyncThrowingStream { $0.finish() }
        }

        let beatRole = session.beatPlan[safe: sceneIndex]?.role ?? .introduce
        let context = MemoryFeed.forChallenge(
            blueprint: blueprint,
            bible: bible,
            sceneIndex: sceneIndex,
            priorScenes: session.scenes,
            tier: tier
        )

        log.info("generateDrawingChallenge: scene \(sceneIndex) role=\(beatRole.rawValue, privacy: .public)")
        return streamText(
            systemPrompt: PromptTemplates.challengeSystem,
            userPrompt: PromptTemplates.challengeUser(context: context, beatRole: beatRole),
            maxTokens: budget.challenge,
            temperature: 0.7,
            topP: 0.9
        )
    }

    func generateDrawingChallengeWithDedup(
        session: StorySession,
        sceneIndex: Int
    ) -> AsyncThrowingStream<String, Error> {
        guard let blueprint = session.blueprint,
              let bible = session.characterBible else {
            return AsyncThrowingStream { $0.finish() }
        }

        let beatRole = session.beatPlan[safe: sceneIndex]?.role ?? .introduce
        var context = MemoryFeed.forChallenge(
            blueprint: blueprint,
            bible: bible,
            sceneIndex: sceneIndex,
            priorScenes: session.scenes,
            tier: tier
        )
        context += CoherenceGuard.antiDuplicationSuffix(priorSubjects: session.priorEntityNames)

        log.info("generateDrawingChallengeWithDedup: scene \(sceneIndex)")
        return streamText(
            systemPrompt: PromptTemplates.challengeSystem,
            userPrompt: PromptTemplates.challengeUser(context: context, beatRole: beatRole),
            maxTokens: budget.challenge,
            temperature: 0.8,
            topP: 0.9
        )
    }

    static func parseDrawingChallenge(_ text: String, fallbackRole: BeatRole) -> DrawingChallenge {
        let cleaned = cleanGeneratedText(text)
        let subject = extractField("SUBJECT", from: cleaned)
        let role = extractField("ROLE", from: cleaned)
        let drawingPrompt = extractField("DRAWING_PROMPT", from: cleaned)

        if !subject.isEmpty && !drawingPrompt.isEmpty {
            log.info("parseDrawingChallenge: parsed — subject=\"\(subject, privacy: .public)\"")
            return DrawingChallenge(
                subject: subject,
                role: role.isEmpty ? "plays an important part in the story" : role,
                drawingPrompt: cleanDrawingPrompt(drawingPrompt),
                imageGenPrompt: deriveImageGenPrompt(subject: subject)
            )
        }

        log.warning("parseDrawingChallenge: structured parse failed, using fallback for \(fallbackRole.rawValue, privacy: .public)")
        return DrawingChallenge.fallbacks[fallbackRole] ?? DrawingChallenge.fallbacks[.introduce]!
    }

    /// Validate and potentially retry or fallback a challenge for uniqueness.
    static func validateChallenge(
        _ challenge: DrawingChallenge,
        session: StorySession,
        sceneIndex: Int
    ) -> DrawingChallenge {
        if CoherenceGuard.isDuplicatePrompt(challenge.drawingPrompt, against: session.priorDrawingPrompts) {
            log.warning("validateChallenge: duplicate detected, using deterministic fallback")
            let goal = session.blueprint?.sceneGoals[safe: sceneIndex] ?? "The story continues"
            let role = session.beatPlan[safe: sceneIndex]?.role ?? .introduce
            return CoherenceGuard.deterministicFallbackChallenge(
                sceneGoal: goal,
                beatRole: role,
                sceneIndex: sceneIndex
            )
        }
        return challenge
    }

    // MARK: - Phase 2: Scene Loop

    func generateImageCaption(
        session: StorySession,
        subject: String,
        role: String
    ) -> AsyncThrowingStream<String, Error> {
        guard let bible = session.characterBible else {
            return AsyncThrowingStream { $0.finish() }
        }

        let context = MemoryFeed.forCaption(
            bible: bible,
            subject: subject,
            role: role,
            setting: session.blueprint?.setting ?? ""
        )

        log.info("generateImageCaption: subject=\"\(subject, privacy: .public)\"")
        return streamText(
            systemPrompt: PromptTemplates.captionSystem,
            userPrompt: PromptTemplates.captionUser(context: context),
            maxTokens: budget.caption,
            temperature: 0.6,
            topP: 0.88
        )
    }

    static func cleanCaption(_ text: String) -> String {
        let cleaned = cleanGeneratedText(text)
        let sentences = cleaned.splitSentences()
        let storySentences = sentences.filter { !isLeakedInstruction($0) }
        let result = storySentences.prefix(1).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? (sentences.first ?? cleaned) : result
    }

    func generateNarrativeBridge(
        session: StorySession,
        sceneIndex: Int,
        subject: String,
        role: String,
        lastNarrativeText: String
    ) -> AsyncThrowingStream<String, Error> {
        guard let blueprint = session.blueprint,
              let bible = session.characterBible else {
            return AsyncThrowingStream { $0.finish() }
        }

        let beatPlan = session.beatPlan[safe: sceneIndex]
        let isFinalBeat = beatPlan?.role == .resolve || beatPlan?.role == .epilogue
        let genre = session.storyType.rawValue
        let tonalNote = beatPlan?.role.tonalNote ?? ""

        let context = MemoryFeed.forBridgeNarrative(
            blueprint: blueprint,
            bible: bible,
            sceneIndex: sceneIndex,
            subject: subject,
            role: role,
            priorScenes: session.scenes,
            lastNarrativeText: lastNarrativeText,
            tier: tier
        )

        log.info("generateNarrativeBridge: scene \(sceneIndex) final=\(isFinalBeat)")
        return streamText(
            systemPrompt: PromptTemplates.bridgeSystem(genre: genre, tonalNote: tonalNote),
            userPrompt: PromptTemplates.bridgeUser(context: context, isFinalBeat: isFinalBeat),
            maxTokens: budget.bridge,
            temperature: 0.6,
            topP: 0.88,
            isNarrative: true
        )
    }

    struct BridgeResult {
        var narrativeBridge: String
        var newGap: String
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

    // MARK: - Scene Summary & Continuity (Memory Write)

    func generateSceneSummary(
        narrativeText: String,
        subject: String,
        entityType: String
    ) -> AsyncThrowingStream<String, Error> {
        log.info("generateSceneSummary: subject=\"\(subject, privacy: .public)\"")
        return streamText(
            systemPrompt: PromptTemplates.summarySystem,
            userPrompt: PromptTemplates.summaryUser(
                narrativeText: narrativeText,
                subject: subject,
                entityType: entityType
            ),
            maxTokens: budget.summary,
            temperature: 0.4,
            topP: 0.9
        )
    }

    struct SummaryResult {
        var sceneSummary: String
        var continuityNotes: String
    }

    static func parseSummaryResult(_ text: String, fallbackNarrative: String) -> SummaryResult {
        let cleaned = cleanGeneratedText(text)
        let summary = extractField("SUMMARY", from: cleaned)
        let continuity = extractField("CONTINUITY", from: cleaned)

        return SummaryResult(
            sceneSummary: summary.isEmpty ? firstSentence(of: fallbackNarrative) : summary,
            continuityNotes: continuity.isEmpty ? "" : continuity
        )
    }

    // MARK: - Image Prompt Construction (deterministic, no LLM needed)

    static func deriveImageGenPrompt(subject: String) -> String {
        "\(subject), storybook illustration, warm watercolor, soft edges"
    }

    static func enrichedImagePrompt(
        challenge: DrawingChallenge,
        session: StorySession
    ) -> String {
        guard let bible = session.characterBible else {
            return challenge.imageGenPrompt
        }
        return MemoryFeed.enrichImagePrompt(
            basePrompt: challenge.imageGenPrompt,
            bible: bible,
            priorScenes: session.scenes
        )
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
            #"^here(?:['''\u{2018}\u{2019}]s| is| are)\s+.*?:\s*"#,
            #"^(?:here is|here's|below is)\s+.*?:\s*"#,
            #"^(?:okay|ok|sure|alright|great|absolutely|here|certainly|of course|let me|i['']ll|i will)[,!.]?\s*"#,
            #"^[''\u{2018}\u{2019}]s\s+.*?:\s*"#,
            #"^(?:the )?(?:continuation|next part|story continues|story so far).*?:\s*"#,
            #"^chapter\s+\d+\s*(?:of\s+\d+)?[:\s—–-]*"#,
            #"^["""\u{201C}\u{201D}]|["""\u{201C}\u{201D}]$"#,
            #"^(?:now,?\s+)?(?:let me|i need to|i should|i want to)\s+.*?[.!]\s*"#,
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

    private static let contextEchoPatterns: [NSRegularExpression] = {
        let raw = [
            #"^setting\s*:"#,
            #"^character\s*:"#,
            #"^continuity\s*:"#,
            #"^scene\s*\d*\s*(?:goal)?\s*:"#,
            #"^just appeared\s*:"#,
            #"^established entit"#,
            #"^already used"#,
            #"^goal for this scene\s*:"#,
            #"^drawn\s*:"#,
            #"^key entity\s*:"#,
            #"^scene text\s*:"#,
            #"^protagonist\s*:"#,
            #"^theme\s*:"#,
            #"^the story (?:is set|takes place)"#,
            #"^the main character is"#,
            #"^remember\s*:"#,
            #"^so far\s*:"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static func isLeakedInstruction(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        if instructionMarkers.contains(where: { lower.contains($0) }) { return true }
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return contextEchoPatterns.contains { $0.firstMatch(in: trimmed, range: range) != nil }
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

        let words = result.split(separator: " ")
        if words.count > 8 {
            result = words.prefix(8).joined(separator: " ")
        }

        if !result.hasSuffix("!") {
            result += "!"
        }

        return result
    }

    // MARK: - Structured Field Extraction

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

    // MARK: - Private Helpers

    private static func firstSentence(of text: String) -> String {
        let sentences = text.splitSentences()
        return sentences.first ?? text
    }

    private static func deriveSpecies(from protagonist: String) -> String {
        let animals = ["fox", "rabbit", "owl", "bear", "otter", "deer", "mouse", "cat", "wolf", "badger"]
        let lower = protagonist.lowercased()
        return animals.first { lower.contains($0) } ?? "creature"
    }

    private static func deriveAppearance(from protagonist: String) -> String {
        let cleaned = protagonist.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count < 60 { return cleaned }
        return String(cleaned.prefix(60))
    }

    // MARK: - Streaming

    private func streamText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 100,
        temperature: Float = 0.6,
        topP: Float = 0.9,
        isNarrative: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        let provider = textProvider
        let isThinking = loadedModel?.isThinkingModel ?? false
        let effectiveMaxTokens = isThinking
            ? budget.thinkingAdjusted(base: maxTokens, isNarrative: isNarrative)
            : maxTokens
        let promptPreview = String(userPrompt.prefix(80))
        log.info("streamText: maxTokens=\(effectiveMaxTokens) temp=\(temperature) thinking=\(isThinking) prompt=\"\(promptPreview, privacy: .public)...\"")

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                self?.isGenerating = true
                defer { self?.isGenerating = false }

                var tokenCount = 0

                do {
                    for try await chunk in provider.generate(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        maxTokens: effectiveMaxTokens,
                        temperature: temperature,
                        topP: topP
                    ) {
                        tokenCount += 1
                        continuation.yield(chunk)
                    }

                    log.info("streamText: completed — \(tokenCount) chunks")
                    continuation.finish()
                } catch {
                    log.error("streamText: error after \(tokenCount) chunks — \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - String helpers

extension String {
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
