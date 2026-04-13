import SwiftUI

struct IntroductionView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var introText = ""
    @State private var isReady = false
    @State private var showButton = false
    @State private var errorMessage: String?

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
                text: introText,
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
            Text("Draw your hero!")
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

        do {
            var prompt = ""
            for try await token in coordinator.storyEngine.generateIntroduction(for: story.storyType) {
                prompt += token
                introText = prompt
            }
            story.introText = StoryEngine.cleanGeneratedText(prompt)
            introText = story.introText
        } catch {
            errorMessage = "Oops! The story brain had a hiccup. Try again!"
            print("Generation error: \(error)")
        }

        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
            showButton = true
        }

        await generateDrawingPrompts(for: story)
    }

    private func generateDrawingPrompts(for story: Story) async {
        do {
            for chapter in story.chapters {
                var drawPrompt = ""
                for try await token in coordinator.storyEngine.generateDrawingPrompt(
                    for: chapter,
                    storyType: story.storyType,
                    previousChapters: Array(story.chapters.prefix(chapter.index)),
                    introText: story.introText
                ) {
                    drawPrompt += token
                }
                chapter.drawingPrompt = StoryEngine.cleanDrawingPrompt(drawPrompt)
            }
        } catch {
            print("Drawing prompt generation error: \(error)")
        }
    }

}
