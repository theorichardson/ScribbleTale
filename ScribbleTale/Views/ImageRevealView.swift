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
    @State private var generatedImage: CGImage?
    @State private var narrationText = ""
    @State private var bufferedNarration = ""
    @State private var isGeneratingImage = true
    @State private var isReady = false
    @State private var imageScale: CGFloat = 0.8
    @State private var imageOpacity: Double = 0
    @State private var imageError: String?
    @State private var canRetryImage = false
    @State private var imageRetryCount = 0

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
                TransformingDrawingPlaceholder(chapter: chapter, storyType: story.storyType)
            } else if isGeneratingImage {
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
                VStack(spacing: 12) {
                    userDrawingFallback
                    if let imageError {
                        Text(imageError)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    if canRetryImage {
                        Button {
                            retryImageGeneration()
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    coordinator.story?.storyType.color ?? .purple,
                                    in: Capsule()
                                )
                        }
                    }
                }
            }
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

        async let imageWork = generateImage(for: chapter)
        async let narrationWork = bufferNarration(for: chapter, in: story)
        _ = await imageWork
        _ = await narrationWork

        await revealBufferedNarration(for: chapter)

        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
        }
    }

    private func generateImage(for chapter: Chapter) async {
        log.info("generateImage: dispatching to ImageGenerationService (retryCount=\(self.imageRetryCount))")
        let start = ContinuousClock.now
        do {
            let image = try await coordinator.imageService.generateImage(
                from: chapter.drawing,
                prompt: chapter.imageGenerationPrompt
            )
            let elapsed = start.duration(to: .now)
            if let image {
                chapter.generatedImage = image
                generatedImage = image
                canRetryImage = false
                imageError = nil
                log.info("generateImage: SUCCESS in \(elapsed)")

                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    imageScale = 1.0
                    imageOpacity = 1.0
                }
            } else {
                log.warning("generateImage: returned nil (no image) in \(elapsed)")
                imageError = "The magic paintbrush couldn't finish in time! Here's your original art instead."
                canRetryImage = imageRetryCount < 3
            }
        } catch is CancellationError {
            log.info("generateImage: cancelled")
            return
        } catch {
            let elapsed = start.duration(to: .now)
            let isUnavailable = (error as? ImageGenerationError) == .notAvailable
            imageError = isUnavailable
                ? "Image generation isn't available yet. Make sure Apple Intelligence is enabled in Settings."
                : "Your drawing is so unique, the magic paintbrush needs a break! Here's your original art instead."
            canRetryImage = imageRetryCount < 3
            log.error("generateImage: FAILED in \(elapsed) — unavailable=\(isUnavailable) — \(error, privacy: .public)")
        }

        isGeneratingImage = false
    }

    private func retryImageGeneration() {
        guard let chapter else { return }
        imageRetryCount += 1
        log.info("retryImageGeneration: user retry #\(self.imageRetryCount)")
        imageError = nil
        canRetryImage = false
        isGeneratingImage = true
        imageScale = 0.8
        imageOpacity = 0

        Task {
            await generateImage(for: chapter)
        }
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
            print("Narration generation failed: \(error)")
        }
    }

    private func revealBufferedNarration(for chapter: Chapter) async {
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

            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.35)
                    .tint(storyType.color)
                Text("Creating your masterpiece...")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
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
