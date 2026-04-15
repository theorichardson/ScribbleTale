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
    @State private var bridgeText = ""
    @State private var isGeneratingImage = true
    @State private var isReady = false
    @State private var imageScale: CGFloat = 0.8
    @State private var imageOpacity: Double = 0
    @State private var generationError: String?
    @State private var phase: RevealPhase = .generatingImage
    @State private var snapshotChallenge: DrawingChallenge?

    private enum RevealPhase {
        case generatingImage
        case showingBridge
        case complete
    }

    private var session: StorySession? {
        coordinator.story?.session
    }

    private var challenge: DrawingChallenge? {
        snapshotChallenge ?? session?.pendingChallenge
    }

    private var drawing: PKDrawing {
        session?.drawing(for: chapterIndex) ?? PKDrawing()
    }

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                chapterProgressBar
                ScrollView {
                    VStack(spacing: 24) {
                        chapterHeader
                        imageSection
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

    private var chapterProgressBar: some View {
        HStack(spacing: 6) {
            let totalBeats = coordinator.story?.chapterCount ?? 5
            ForEach(0..<totalBeats, id: \.self) { i in
                Capsule()
                    .fill(
                        i < chapterIndex
                            ? (coordinator.story?.storyType.color ?? .purple)
                            : i == chapterIndex
                                ? (coordinator.story?.storyType.color ?? .purple).opacity(0.5)
                                : Color(.systemGray4)
                    )
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var chapterHeader: some View {
        VStack(spacing: 4) {
            if let subject = challenge?.subject {
                Text(subject)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(coordinator.story?.storyType.color ?? .purple)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var imageSection: some View {
        Group {
            if isGeneratingImage, let story = coordinator.story {
                TransformingDrawingPlaceholder(
                    drawing: drawing,
                    storyType: story.storyType
                )
            } else if isGeneratingImage {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray5))
                    .frame(height: 300)
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
            } else if let image = generatedImage {
                let themeColors = coordinator.story?.storyType.gradientColors ?? [.purple, .blue]
                let themeColor = coordinator.story?.storyType.color ?? .purple

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            RadialGradient(
                                colors: [
                                    themeColors[0].opacity(0.6),
                                    themeColors.count > 1 ? themeColors[1].opacity(0.35) : themeColor.opacity(0.35),
                                    themeColor.opacity(0.15),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 280
                            )
                        )
                        .blur(radius: 30)
                        .scaleEffect(1.15)

                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: themeColor.opacity(0.4), radius: 16, y: 6)
                }
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
    private var bridgeSection: some View {
        if !bridgeText.isEmpty && (phase == .showingBridge || phase == .complete) {
            StreamingText(
                text: bridgeText,
                font: .system(.title2, design: .serif),
                color: .primary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Scene Loop Pipeline (reads pre-generated story)

    private func generateContent() async {
        guard let session = coordinator.story?.session,
              let challenge = session.pendingChallenge,
              let parsedStory = session.parsedStory else {
            log.error("generateContent: missing session, challenge, or parsed story at scene \(self.chapterIndex)")
            return
        }

        snapshotChallenge = challenge

        let enrichedPrompt = SingleCallStoryEngine.enrichedImagePrompt(
            challenge: challenge,
            characterBible: session.characterBible
        )
        log.info("""
            generateContent: scene \(self.chapterIndex)
              subject=\(challenge.subject, privacy: .public)
              imagePrompt=\(enrichedPrompt.prefix(80), privacy: .public)
              strokes=\(self.drawing.strokes.count)
            """)

        // Step 1: Generate image (only async work remaining per scene)
        await generateImage(prompt: enrichedPrompt)

        // Step 2: Show pre-generated story continuation
        phase = .showingBridge
        let continuation = parsedStory.beats[safe: chapterIndex]?.continuation ?? ""
        await revealText(continuation) { text in bridgeText = text }

        // Step 4: Persist scene record
        let sceneRecord = SceneRecord(
            sceneIndex: chapterIndex,
            narrativeText: continuation,
            drawingPromptText: challenge.drawingPrompt,
            imageGenPrompt: enrichedPrompt,
            entityName: challenge.subject,
            entityType: inferEntityType(challenge.subject),
            sceneSummary: continuation,
            continuityNotes: ""
        )
        session.scenes.append(sceneRecord)
        coordinator.persistence.persistScene(sceneRecord, sessionID: session.id)
        session.releaseCompletedSceneAssets(keepingCurrent: chapterIndex)

        // Step 5: Set next challenge from pre-generated story
        if chapterIndex + 1 < session.sceneCount {
            session.pendingChallenge = parsedStory.challenge(at: chapterIndex + 1)
        }

        phase = .complete
        withAnimation(.easeOut(duration: 0.5)) {
            isReady = true
        }
    }

    private static let maxImageDimension: CGFloat = 768

    private func generateImage(prompt: String) async {
        do {
            let currentDrawing = drawing
            let rawImage = try await coordinator.imageService.generateImage(
                from: currentDrawing,
                prompt: prompt
            )
            let image = rawImage.flatMap { Self.downscaled($0, maxDimension: Self.maxImageDimension) } ?? rawImage
            session?.generatedImages[chapterIndex] = image
            if let image {
                session?.compressedImageData[chapterIndex] = Self.compressedJPEG(image)
            }
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

    private static func compressedJPEG(_ image: CGImage, quality: CGFloat = 0.7) -> Data? {
        let uiImage = UIImage(cgImage: image)
        return uiImage.jpegData(compressionQuality: quality)
    }

    private static func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard max(w, h) > maxDimension else { return image }

        let scale = maxDimension / max(w, h)
        let newW = Int(w * scale)
        let newH = Int(h * scale)

        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    private func inferEntityType(_ subject: String) -> SceneRecord.EntityType {
        let lower = subject.lowercased()
        let creatureWords = ["rabbit", "fox", "owl", "bear", "otter", "deer", "mouse", "cat",
                             "wolf", "badger", "bird", "dragon", "creature", "butterfly", "fish"]
        let placeWords = ["forest", "cave", "river", "mountain", "house", "den", "castle",
                          "lake", "bridge", "village", "garden", "island"]

        if creatureWords.contains(where: { lower.contains($0) }) { return .creature }
        if placeWords.contains(where: { lower.contains($0) }) { return .place }
        return .object
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
