import SwiftUI

struct IntroductionView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var displayText = ""
    @State private var isReady = false
    @State private var showButton = false
    @State private var errorMessage: String?
    @State private var buttonLabel = "Let's draw!"
    @State private var isGeneratingStory = true
    @State private var statusMessage = "Planning your story…"

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                Spacer()

                storyContent

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer()

                if showButton {
                    letsGoButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await runBootstrapPipeline()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: coordinator.story.map { $0.storyType.gradientColors.map { $0.opacity(0.15) } } ?? [.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var storyContent: some View {
        VStack(spacing: 24) {
            if let story = coordinator.story {
                Image(systemName: story.storyType.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(story.storyType.color)
                    .symbolEffect(.pulse, isActive: isGeneratingStory)

                Text(story.storyType.rawValue)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(story.storyType.color)
            }

            if isGeneratingStory {
                VStack(spacing: 16) {
                    ThinkingTextView(text: coordinator.storyEngine.thinkingText)

                    if coordinator.storyEngine.thinkingText.isEmpty {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.purple)
                    }

                    Text(statusMessage)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            if !displayText.isEmpty {
                StreamingText(
                    text: displayText,
                    font: .system(.title2, design: .serif),
                    color: .primary
                )
                .padding(.horizontal, 8)
                .transition(.opacity)
            }
        }
    }

    private var letsGoButton: some View {
        Button {
            coordinator.goToDrawing(chapterIndex: 0)
        } label: {
            Text(buttonLabel)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    coordinator.story?.storyType.color ?? .purple,
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .shadow(color: (coordinator.story?.storyType.color ?? .purple).opacity(0.4), radius: 8, y: 4)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Bootstrap Pipeline

    private func runBootstrapPipeline() async {
        guard let story = coordinator.story else { return }
        let session = story.session
        let genre = story.storyType.rawValue

        coordinator.storyEngine.resetThinkingText()

        // Step 1: Generate blueprint
        statusMessage = "Planning your story…"
        let blueprint = await generateBlueprint(genre: genre, sceneCount: session.sceneCount)
        guard let blueprint else { return }
        session.blueprint = blueprint
        await yieldForMemoryReclaim()

        // Step 2: Extract character bible
        coordinator.storyEngine.resetThinkingText()
        statusMessage = "Getting to know the characters…"
        let bible = await generateCharacterBible(protagonist: blueprint.protagonist)
        session.characterBible = bible
        await yieldForMemoryReclaim()

        // Step 3: Generate opening narrative
        coordinator.storyEngine.resetThinkingText()
        statusMessage = "Writing the opening…"
        let opening = await generateOpeningNarrative(blueprint: blueprint, bible: bible, genre: genre)
        session.openingNarrative = opening

        await revealText(opening)
        await yieldForMemoryReclaim()

        // Step 4: Build first drawing challenge (deterministic, always the protagonist)
        statusMessage = "Preparing your first drawing…"
        let challenge = generateFirstChallenge(session: session)
        session.pendingChallenge = challenge
        buttonLabel = "Draw \(challenge.subject)!"

        // Step 5: Persist session
        coordinator.persistence.createSession(from: session)

        coordinator.storyEngine.resetThinkingText()

        withAnimation(.easeOut(duration: 0.5)) {
            isGeneratingStory = false
            isReady = true
            showButton = true
        }
    }

    private func generateBlueprint(genre: String, sceneCount: Int) async -> StoryBlueprint? {
        var raw = ""
        do {
            for try await token in coordinator.storyEngine.generateBlueprint(
                genre: genre,
                sceneCount: sceneCount
            ) {
                raw += token
            }
        } catch {
            errorMessage = "Oops! The story brain had a hiccup. Try again!"
            return nil
        }
        return StoryEngine.parseBlueprint(raw, sceneCount: sceneCount)
    }

    private func generateCharacterBible(protagonist: String) async -> CharacterBible {
        var raw = ""
        do {
            for try await token in coordinator.storyEngine.generateCharacterBible(protagonist: protagonist) {
                raw += token
            }
        } catch {
            return CharacterBible(
                name: "Fern", species: "creature",
                appearance: "small and curious",
                personality: "brave", want: "to go on an adventure"
            )
        }
        return StoryEngine.parseCharacterBible(raw, fallbackProtagonist: protagonist)
    }

    private func generateOpeningNarrative(
        blueprint: StoryBlueprint,
        bible: CharacterBible,
        genre: String
    ) async -> String {
        var raw = ""
        do {
            for try await token in coordinator.storyEngine.generateOpening(
                blueprint: blueprint,
                bible: bible,
                genre: genre
            ) {
                raw += token
            }
        } catch {
            return "Once upon a time, in \(blueprint.setting), there lived \(bible.compactDescription)"
        }
        let cleaned = StoryEngine.cleanOpening(raw)
        return cleaned.isEmpty
            ? "Once upon a time, in \(blueprint.setting), there lived \(bible.compactDescription)"
            : cleaned
    }

    private func generateFirstChallenge(session: StorySession) -> DrawingChallenge {
        guard let bible = session.characterBible else {
            return DrawingChallenge.fallbacks[.introduce]!
        }
        return DrawingChallenge(
            subject: "\(bible.name) the \(bible.species)",
            role: "the hero of our story",
            drawingPrompt: "Draw \(bible.name) the \(bible.species)!",
            imageGenPrompt: "\(bible.name) the \(bible.species), \(bible.appearance), children's storybook illustration, warm watercolor, soft edges"
        )
    }

    /// Brief yield between generation steps so the Metal allocator can reclaim
    /// KV-cache buffers from the previous ChatSession before the next one allocates.
    private func yieldForMemoryReclaim() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func revealText(_ text: String) async {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard !words.isEmpty else {
            displayText = text
            return
        }
        var revealed = ""
        for (index, word) in words.enumerated() {
            if index > 0 { revealed += " " }
            revealed += word
            displayText = revealed
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}
