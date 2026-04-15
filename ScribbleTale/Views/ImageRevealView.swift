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
    @State private var captionText = ""
    @State private var bridgeText = ""
    @State private var isGeneratingImage = true
    @State private var isReady = false
    @State private var imageScale: CGFloat = 0.8
    @State private var imageOpacity: Double = 0
    @State private var generationError: String?
    @State private var generationStatus = "Bringing your drawing to life..."
    @State private var phase: RevealPhase = .generatingImage

    private enum RevealPhase {
        case generatingImage
        case showingCaption
        case showingBridge
        case complete
    }

    private var state: NarrativeState? {
        coordinator.story?.narrativeState
    }

    private var challenge: DrawingChallenge? {
        state?.pendingChallenge
    }

    private var drawing: PKDrawing {
        state?.drawing(for: chapterIndex) ?? PKDrawing()
    }

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        chapterHeader
                        imageSection
                        captionSection
                        bridgeSection
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
            Text("Beat \(chapterIndex + 1) of \(coordinator.story?.chapterCount ?? 5)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            if let subject = challenge?.subject {
                Text(subject)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(coordinator.story?.storyType.color ?? .purple)
            }
        }
    }

    private var imageSection: some View {
        Group {
            if isGeneratingImage, let story = coordinator.story {
                VStack(spacing: 16) {
                    TransformingDrawingPlaceholder(
                        drawing: drawing,
                        storyType: story.storyType
                    )

                    Text(generationStatus)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
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
                        }
                    }
            } else if let image = generatedImage {
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
                        if let error = generationError {
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
    }

    @ViewBuilder
    private var userDrawingFallback: some View {
        Image(uiImage: drawing.renderedImage(scale: UIScreen.main.scale))
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

    @ViewBuilder
    private var captionSection: some View {
        if !captionText.isEmpty && phase != .generatingImage {
            StreamingText(
                text: captionText,
                font: .system(.body, design: .serif),
                color: .secondary
            )
            .padding(.horizontal, 8)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var bridgeSection: some View {
        if !bridgeText.isEmpty && (phase == .showingBridge || phase == .complete) {
            StreamingText(
                text: bridgeText,
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
            let totalBeats = coordinator.story?.chapterCount ?? 5
            Text(chapterIndex < totalBeats - 1 ? "Continue the story" : "See your story")
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

    // MARK: - Content generation pipeline

    private func generateContent() async {
        guard let story = coordinator.story,
              let state = coordinator.story?.narrativeState,
              let challenge = state.pendingChallenge else {
            log.error("generateContent: no story, state, or challenge at beat \(self.chapterIndex)")
            return
        }

        let imagePrompt = challenge.imageGenPrompt
        log.info("""
            generateContent: beat \(self.chapterIndex)
              subject=\(challenge.subject, privacy: .public)
              imagePrompt=\(imagePrompt, privacy: .public)
              strokes=\(self.drawing.strokes.count)
            """)

        // Step 1: Image generation + caption generation in parallel
        generationStatus = "Bringing your drawing to life..."
        async let imageWork = generateImage(prompt: imagePrompt)
        async let captionWork = bufferCaption(
            subject: challenge.subject,
            role: challenge.role,
            state: state,
            storyType: story.storyType
        )
        _ = await imageWork
        let caption = await captionWork

        // Step 2: Show caption
        phase = .showingCaption
        await revealText(caption) { text in captionText = text }
        state.imageCaptions[chapterIndex] = caption

        // Step 3: Narrative bridge
        phase = .showingBridge
        let beatPlan = state.beatPlan[chapterIndex]
        let isFinalBeat = beatPlan.role == .resolve || beatPlan.role == .epilogue
        let bridge = await generateBridge(
            subject: challenge.subject,
            role: challenge.role,
            state: state,
            storyType: story.storyType,
            beatPlan: beatPlan
        )
        await revealText(bridge) { text in bridgeText = text }

        // Step 4: Record completed beat
        let completedBeat = StoryBeat(
            beatIndex: chapterIndex,
            drawingSubject: challenge.subject,
            imageCaption: caption,
            narrativeBridge: bridge
        )
        state.storyBeats.append(completedBeat)

        // Step 5: Generate next challenge if not final
        if !isFinalBeat && chapterIndex + 1 < state.beatPlan.count {
            await generateNextChallenge(state: state, storyType: story.storyType)
        }

        phase = .complete
        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
        }
    }

    private func generateImage(prompt: String) async {
        do {
            let currentDrawing = drawing
            let image = try await coordinator.imageService.generateImage(
                from: currentDrawing,
                prompt: prompt
            )
            state?.generatedImages[chapterIndex] = image
            generatedImage = image

            if image != nil {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    imageScale = 1.0
                    imageOpacity = 1.0
                }
            }
        } catch {
            log.error("generateImage: failed — \(error, privacy: .public)")
            generationError = error.localizedDescription
        }

        isGeneratingImage = false
    }

    private func bufferCaption(
        subject: String,
        role: String,
        state: NarrativeState,
        storyType: StoryType
    ) async -> String {
        do {
            var raw = ""
            for try await token in coordinator.storyEngine.generateImageCaption(
                subject: subject,
                role: role,
                state: state,
                storyType: storyType
            ) {
                raw += token
            }
            log.info("bufferCaption: raw = \"\(raw, privacy: .public)\"")
            return StoryEngine.cleanCaption(raw)
        } catch {
            log.error("bufferCaption: failed — \(error, privacy: .public)")
            return ""
        }
    }

    private func generateBridge(
        subject: String,
        role: String,
        state: NarrativeState,
        storyType: StoryType,
        beatPlan: BeatPlan
    ) async -> String {
        let isFinalBeat = beatPlan.role == .resolve || beatPlan.role == .epilogue
        do {
            var raw = ""
            for try await token in coordinator.storyEngine.generateNarrativeBridge(
                subject: subject,
                role: role,
                state: state,
                storyType: storyType,
                beatPlan: beatPlan
            ) {
                raw += token
            }
            log.info("generateBridge: raw = \"\(raw, privacy: .public)\"")
            let result = StoryEngine.parseBridgeResult(raw, isFinalBeat: isFinalBeat)
            if !result.newGap.isEmpty {
                state.currentGap = result.newGap
            }
            return result.narrativeBridge
        } catch {
            log.error("generateBridge: failed — \(error, privacy: .public)")
            return ""
        }
    }

    private func generateNextChallenge(state: NarrativeState, storyType: StoryType) async {
        do {
            var raw = ""
            for try await token in coordinator.storyEngine.generateDrawingChallenge(
                gap: state.currentGap,
                state: state,
                storyType: storyType
            ) {
                raw += token
            }
            let nextRole = state.currentBeatRole ?? .complicate
            let challenge = StoryEngine.parseDrawingChallenge(raw, fallbackRole: nextRole)
            state.pendingChallenge = challenge
            log.info("generateNextChallenge: subject=\"\(challenge.subject, privacy: .public)\"")
        } catch {
            log.error("generateNextChallenge: failed — \(error, privacy: .public)")
            let nextRole = state.currentBeatRole ?? .complicate
            state.pendingChallenge = DrawingChallenge.fallbacks[nextRole]
        }
    }

    private func revealText(_ text: String, update: @escaping (String) -> Void) async {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard !words.isEmpty else { return }

        var revealed = ""
        for (index, word) in words.enumerated() {
            if index > 0 { revealed += " " }
            revealed += word
            update(revealed)
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}

// MARK: - Transforming placeholder (drawing → generated image)

private struct TransformingDrawingPlaceholder: View {
    let drawing: PKDrawing
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
        let image = snapshotImage ?? drawing.renderedImage(scale: UIScreen.main.scale)

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
                snapshotImage = drawing.renderedImage(scale: UIScreen.main.scale)
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
