import SwiftUI

struct ImageRevealView: View {
    let chapterIndex: Int

    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var playgroundImage: CGImage?
    @State private var coreMLImage: CGImage?
    @State private var narrationText = ""
    @State private var isGeneratingImage = true
    @State private var isReady = false
    @State private var imageScale: CGFloat = 0.8
    @State private var imageOpacity: Double = 0
    @State private var playgroundError: String?
    @State private var coreMLError: String?
    @State private var generationStatus = "Preparing image prompts..."

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
                            Text("Generating comparison images...")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(generationStatus)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    comparisonCard(
                        title: "Apple Image Playground",
                        image: playgroundImage,
                        error: playgroundError
                    )
                    comparisonCard(
                        title: "Core ML Stable Diffusion",
                        image: coreMLImage,
                        error: coreMLError
                    )
                }
            }
        }
    }

    private func comparisonCard(title: String, image: CGImage?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)

            Group {
                if let image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        .scaleEffect(imageScale)
                        .opacity(imageOpacity)
                } else {
                    userDrawingFallback
                        .overlay(alignment: .bottom) {
                            if let error {
                                Text(error)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(8)
                                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                                    .padding(8)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var userDrawingFallback: some View {
        if let chapter {
            let drawingImage = chapter.drawing.image(from: chapter.drawing.bounds, scale: UIScreen.main.scale)
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

        generationStatus = "Building image prompt..."
        do {
            var imgPrompt = ""
            for try await token in coordinator.storyEngine.generateImagePrompt(
                for: chapter,
                storyType: story.storyType,
                drawingPrompt: chapter.drawingPrompt
            ) {
                imgPrompt += token
            }
            chapter.imageGenerationPrompt = imgPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Image prompt generation failed: \(error)")
        }

        generationStatus = "Running Image Playground, then Core ML..."
        let result = await coordinator.imageService.generateComparisonImages(
            from: chapter.drawing,
            prompt: chapter.imageGenerationPrompt
        )
        chapter.playgroundGeneratedImage = result.playgroundImage
        chapter.coreMLGeneratedImage = result.coreMLImage
        chapter.generatedImage = result.coreMLImage ?? result.playgroundImage
        playgroundImage = result.playgroundImage
        coreMLImage = result.coreMLImage
        playgroundError = result.playgroundError
        coreMLError = result.coreMLError

        if chapter.generatedImage != nil {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                imageScale = 1.0
                imageOpacity = 1.0
            }
        }

        isGeneratingImage = false

        do {
            let previousChapters = Array(story.chapters.prefix(chapterIndex))
            var narration = ""
            for try await token in coordinator.storyEngine.generateNarration(
                for: chapter,
                storyType: story.storyType,
                previousChapters: previousChapters
            ) {
                narration += token
                narrationText = narration
            }
            chapter.narration = narration.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Narration generation failed: \(error)")
        }

        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
        }
    }
}
