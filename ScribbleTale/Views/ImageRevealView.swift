import os
import SwiftUI
import PencilKit

private let log = Logger(subsystem: "com.scribbletale.app", category: "ImageReveal")

private extension PKDrawing {
    func renderedImage(scale: CGFloat) -> UIImage {
        let b = bounds
        guard !b.isNull, !b.isEmpty else {
            return UIImage()
        }
        let padded = b.insetBy(dx: -20, dy: -20)
        let raw = image(from: padded, scale: scale)

        let renderer = UIGraphicsImageRenderer(size: raw.size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: raw.size))
            raw.draw(at: .zero)
        }
    }
}

struct ImageRevealView: View {
    let chapterIndex: Int

    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var playgroundImage: CGImage?
    @State private var coreMLImage: CGImage?
    @State private var narrationText = ""
    @State private var bufferedNarration = ""
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

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        chapterHeader
                        imageSection
                        narrationSection
                    }
                    .padding(24)
                }

                if isReady {
                    continueButton
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: coordinator.story.map { $0.storyType.gradientColors.map { $0.opacity(0.08) } } ?? [.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
            Text("Chapter \(chapterIndex + 1) of \(Story.chapterCount)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            if let subject = chapter?.drawingSubject {
                Label(subject.displayName, systemImage: subject.icon)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(chapter?.beat.rawValue ?? "")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(coordinator.story?.storyType.color ?? .purple)
        }
    }

    private var imageSection: some View {
        Group {
            if isGeneratingImage, let chapter, let story = coordinator.story {
                VStack(spacing: 16) {
                    TransformingDrawingPlaceholder(chapter: chapter, storyType: story.storyType)

                    Text(generationStatus)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    coreMLProgressView
                }
            } else if isGeneratingImage {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray5))
                    .frame(height: 300)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(generationStatus)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                            coreMLProgressView
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

    @ViewBuilder
    private var coreMLProgressView: some View {
        let step = coordinator.imageService.coreMLStep
        let total = coordinator.imageService.coreMLTotalSteps
        if total > 0 {
            VStack(spacing: 4) {
                ProgressView(value: Double(step), total: Double(total))
                    .tint(coordinator.story?.storyType.color ?? .purple)
                    .frame(width: 200)
                Text("Core ML step \(step)/\(total)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
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
            Image(uiImage: chapter.drawing.renderedImage(scale: UIScreen.main.scale))
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

    @ViewBuilder
    private var narrationSection: some View {
        if !isGeneratingImage && !narrationText.isEmpty {
            StreamingText(
                text: narrationText,
                font: .system(.title2, design: .serif),
                color: .primary
            )
            .padding(.horizontal, 8)
            .transition(.opacity)
        }
    }

    private var continueButton: some View {
        Button {
            coordinator.goToNextChapterOrComplete(currentChapterIndex: chapterIndex)
        } label: {
            Text(chapterIndex < Story.chapterCount - 1 ? "Continue the story" : "See your story")
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

    // MARK: - Content generation

    private func generateContent() async {
        guard let story = coordinator.story,
              let chapter else {
            log.error("generateContent: no story or chapter at index \(self.chapterIndex)")
            return
        }

        log.info("""
            generateContent: START chapter \(self.chapterIndex)
              beat=\(chapter.beat.rawValue, privacy: .public), subject=\(chapter.drawingSubject.displayName, privacy: .public)
              drawingPrompt=\(chapter.drawingPrompt, privacy: .public)
              strokes=\(chapter.drawing.strokes.count)
            """)

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
            chapter.imageGenerationPrompt = StoryEngine.cleanImagePrompt(imgPrompt)
            log.info("generateContent: LLM image prompt = \"\(chapter.imageGenerationPrompt, privacy: .public)\"")
        } catch {
            log.error("generateContent: LLM image prompt generation failed — \(error, privacy: .public)")
        }

        if chapter.imageGenerationPrompt.isEmpty {
            chapter.imageGenerationPrompt =
                "\(chapter.drawingSubject.pipelineContext) Picture-book scene: \(chapter.drawingPrompt)."
            log.warning("generateContent: LLM prompt was empty, using fallback: \"\(chapter.imageGenerationPrompt, privacy: .public)\"")
        }

        generationStatus = "Running Image Playground + Core ML..."
        async let imageWork = generateImages(for: chapter)
        async let narrationWork = bufferNarration(for: chapter, in: story)
        _ = await imageWork
        _ = await narrationWork

        await revealBufferedNarration()

        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
        }
    }

    private func generateImages(for chapter: Chapter) async {
        log.info("generateImages: dispatching comparison")
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
    }

    private func bufferNarration(for chapter: Chapter, in story: Story) async {
        do {
            let previousChapters = Array(story.chapters.prefix(chapterIndex))
            var narration = ""
            for try await token in coordinator.storyEngine.generateNarration(
                for: chapter,
                storyType: story.storyType,
                previousChapters: previousChapters
            ) {
                narration += token
            }
            let cleaned = StoryEngine.cleanNarration(
                narration,
                imagePrompt: chapter.imageGenerationPrompt
            )
            bufferedNarration = cleaned
            chapter.narration = cleaned
        } catch {
            log.error("bufferNarration: failed — \(error, privacy: .public)")
        }
    }

    private func revealBufferedNarration() async {
        let words = bufferedNarration.split(
            separator: " ",
            omittingEmptySubsequences: false
        )
        guard !words.isEmpty else { return }

        var revealed = ""
        for (index, word) in words.enumerated() {
            if index > 0 { revealed += " " }
            revealed += word
            narrationText = revealed
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}

// MARK: - Transforming placeholder (drawing → generated image)

private struct TransformingDrawingPlaceholder: View {
    let chapter: Chapter
    let storyType: StoryType

    @State private var snapshotImage: UIImage?

    private var ringColors: [Color] {
        let g = storyType.gradientColors
        if g.count >= 2 {
            return [g[0], g[1], storyType.color, g[0].opacity(0.85), g[1]]
        }
        return [storyType.color, .white.opacity(0.85), storyType.color.opacity(0.7), storyType.color]
    }

    var body: some View {
        let image = snapshotImage ?? chapter.drawing.renderedImage(scale: UIScreen.main.scale)

        VStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let spinDegrees = t.truncatingRemainder(dividingBy: 2.75) / 2.75 * 360
                let shimmerPhase = t.truncatingRemainder(dividingBy: 1.9) / 1.9
                let pulse = (sin(t * 2.85) + 1) / 2
                let angle = Angle.degrees(spinDegrees)

                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: ringColors),
                                center: .center,
                                angle: angle
                            ),
                            lineWidth: 10 + pulse * 6
                        )
                        .blur(radius: 10 + pulse * 6)
                        .opacity(0.45 + pulse * 0.35)
                        .scaleEffect(1.04 + pulse * 0.02)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)

                        shimmerBand(progress: shimmerPhase)

                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        storyType.gradientColors[0].opacity(0.06 + pulse * 0.08),
                                        storyType.gradientColors.count > 1
                                            ? storyType.gradientColors[1].opacity(0.05 + pulse * 0.06)
                                            : storyType.color.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.plusLighter)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(colors: ringColors),
                                    center: .center,
                                    angle: angle
                                ),
                                lineWidth: 2.5 + pulse * 0.8
                            )
                    }
                    .shadow(color: ringColors[0].opacity(0.55 + pulse * 0.25), radius: 10 + pulse * 8)
                    .shadow(color: (storyType.gradientColors.count > 1 ? storyType.gradientColors[1] : storyType.color).opacity(0.35 + pulse * 0.2), radius: 6 + pulse * 5)
                }
                .compositingGroup()
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if snapshotImage == nil {
                snapshotImage = chapter.drawing.renderedImage(scale: UIScreen.main.scale)
            }
        }
    }

    private func shimmerBand(progress: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bandWidth = max(w, h) * 0.65
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.42),
                    Color.white.opacity(0.12),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: bandWidth, height: h * 1.4)
            .rotationEffect(.degrees(-22))
            .offset(x: CGFloat(progress) * (w + bandWidth) - bandWidth * 0.5, y: 0)
            .frame(width: w, height: h)
        }
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}
