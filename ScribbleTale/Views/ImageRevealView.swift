import SwiftUI

struct ImageRevealView: View {
    let chapterIndex: Int

    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var generatedImage: CGImage?
    @State private var narrationText = ""
    @State private var isGeneratingImage = true
    @State private var isReady = false
    @State private var imageScale: CGFloat = 0.8
    @State private var imageOpacity: Double = 0

    private var chapter: Chapter? {
        coordinator.story?.chapters[safe: chapterIndex]
    }

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 24) {
                    chapterHeader
                    imageSection
                    narrationSection

                    if isReady {
                        continueButton
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await generateContent()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: coordinator.story.map { $0.storyType.gradientColors.map { $0.opacity(0.08) } } ?? [.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var chapterHeader: some View {
        VStack(spacing: 4) {
            Text("Chapter \(chapterIndex + 1)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(chapter?.beat.rawValue ?? "")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(coordinator.story?.storyType.color ?? .purple)
        }
    }

    private var imageSection: some View {
        Group {
            if isGeneratingImage {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray5))
                    .frame(height: 300)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Creating your masterpiece...")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
            } else if let cgImage = generatedImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    .scaleEffect(imageScale)
                    .opacity(imageOpacity)
            } else {
                userDrawingFallback
            }
        }
    }

    @ViewBuilder
    private var userDrawingFallback: some View {
        if let chapter {
            let drawingImage = chapter.drawing.image(
                from: chapter.drawing.bounds,
                scale: UIScreen.main.scale
            )
            Image(uiImage: drawingImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            (coordinator.story?.storyType.color ?? .purple).opacity(0.3),
                            lineWidth: 2
                        )
                )
                .padding(4)
        }
    }

    private var narrationSection: some View {
        StreamingText(
            text: narrationText,
            font: .system(.body, design: .serif),
            color: .primary
        )
        .padding(.horizontal, 8)
    }

    private var continueButton: some View {
        Button {
            coordinator.goToNextChapterOrComplete(currentChapterIndex: chapterIndex)
        } label: {
            Text(chapterIndex < Story.chapterCount - 1 ? "Continue the story!" : "See your story!")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    coordinator.story?.storyType.color ?? .purple,
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .shadow(color: (coordinator.story?.storyType.color ?? .purple).opacity(0.4), radius: 8, y: 4)
        }
    }

    private func generateContent() async {
        guard let story = coordinator.story,
              let chapter else { return }

        var imgPrompt = ""
        for await token in coordinator.storyEngine.generateImagePrompt(
            for: chapter,
            storyType: story.storyType,
            drawingPrompt: chapter.drawingPrompt
        ) {
            imgPrompt += token
        }
        chapter.imageGenerationPrompt = imgPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let image = try await coordinator.imageService.generateImage(
                from: chapter.drawing,
                prompt: chapter.imageGenerationPrompt
            )
            chapter.generatedImage = image
            generatedImage = image

            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                imageScale = 1.0
                imageOpacity = 1.0
            }
        } catch {
            print("Image generation failed: \(error)")
        }

        isGeneratingImage = false

        let previousChapters = Array(story.chapters.prefix(chapterIndex))
        var narration = ""
        for await token in coordinator.storyEngine.generateNarration(
            for: chapter,
            storyType: story.storyType,
            previousChapters: previousChapters
        ) {
            narration += token
            narrationText = narration
        }
        chapter.narration = narration.trimmingCharacters(in: .whitespacesAndNewlines)

        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
        }
    }
}
