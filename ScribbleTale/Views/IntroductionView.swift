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

    // MARK: - Bootstrap Pipeline (single LLM call)

    private func runBootstrapPipeline() async {
        guard let story = coordinator.story else { return }
        let session = story.session
        let genre = story.storyType.rawValue

        coordinator.storyEngine.resetThinkingText()
        statusMessage = "Writing your story…"

        var raw = ""
        do {
            for try await token in coordinator.storyEngine.generateFullStory(
                genre: genre,
                sceneCount: session.sceneCount
            ) {
                raw += token
            }
        } catch {
            errorMessage = "Oops! The story brain had a hiccup. Try again!"
            return
        }

        guard let parsed = SingleCallStoryEngine.parseFullStory(raw, sceneCount: session.sceneCount) else {
            errorMessage = "The story got a bit jumbled. Try again!"
            return
        }

        session.parsedStory = parsed
        session.characterBible = parsed.characterBible
        session.openingNarrative = parsed.introduction
        session.blueprint = StoryBlueprint(
            setting: "a magical world",
            protagonist: "\(parsed.characterName) the \(parsed.characterSpecies)",
            theme: story.storyType.tagline,
            sceneGoals: parsed.beats.map { _ in "The story continues" }
        )

        let challenge = parsed.challenge(at: 0)
        session.pendingChallenge = challenge

        await revealText(parsed.introduction)

        buttonLabel = "Let's draw!"
        coordinator.persistence.createSession(from: session)
        coordinator.storyEngine.resetThinkingText()

        withAnimation(.easeOut(duration: 0.5)) {
            isGeneratingStory = false
            isReady = true
            showButton = true
        }
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
