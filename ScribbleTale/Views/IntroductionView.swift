import SwiftUI

struct IntroductionView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var displayText = ""
    @State private var isReady = false
    @State private var showButton = false
    @State private var errorMessage: String?
    @State private var buttonLabel = "Let's draw!"

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
            await generateIntro()
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
                    .symbolEffect(.pulse, isActive: !isReady)

                Text(story.storyType.rawValue)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(story.storyType.color)
            }

            StreamingText(
                text: displayText,
                font: .system(.title2, design: .serif),
                color: .primary
            )
            .padding(.horizontal, 8)
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

    private func generateIntro() async {
        guard let story = coordinator.story else { return }
        let state = story.narrativeState

        // Step 1: Generate and stream the introduction
        var raw = ""
        do {
            for try await token in coordinator.storyEngine.generateIntroduction(for: story.storyType) {
                raw += token
                displayText = raw
            }
        } catch {
            errorMessage = "Oops! The story brain had a hiccup. Try again!"
            print("Generation error: \(error)")
            return
        }

        // Step 2: Parse structured fields into NarrativeState
        let result = StoryEngine.parseIntroduction(raw, storyType: story.storyType)
        state.setting = result.setting
        state.protagonist = result.protagonist
        state.openingText = result.opening
        state.currentGap = result.gap

        displayText = result.opening

        // Step 3: Generate the first drawing challenge from the GAP
        do {
            var challengeRaw = ""
            for try await token in coordinator.storyEngine.generateDrawingChallenge(
                gap: state.currentGap,
                state: state,
                storyType: story.storyType
            ) {
                challengeRaw += token
            }
            let fallbackRole = state.currentBeatRole ?? .introduce
            let challenge = StoryEngine.parseDrawingChallenge(challengeRaw, fallbackRole: fallbackRole)
            state.pendingChallenge = challenge
            buttonLabel = "Draw \(challenge.subject)!"
        } catch {
            print("Drawing challenge generation error: \(error)")
            let fallbackRole = state.currentBeatRole ?? .introduce
            state.pendingChallenge = DrawingChallenge.fallbacks[fallbackRole]
            buttonLabel = "Let's draw!"
        }

        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
            showButton = true
        }
    }
}
