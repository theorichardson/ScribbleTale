import SwiftUI
import PencilKit

private extension PKDrawing {
    func renderedImage(scale: CGFloat) -> UIImage {
        let b = bounds
        guard !b.isNull, !b.isEmpty else { return UIImage() }
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

struct StoryCompleteView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var showContent = false

    private var session: StorySession? {
        coordinator.story?.session
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                if let session {
                    storyRecap(session)
                }
                homeButton
            }
            .padding(24)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
        .background(
            LinearGradient(
                colors: coordinator.story.map { $0.storyType.gradientColors.map { $0.opacity(0.08) } } ?? [.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                showContent = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolEffect(.bounce, options: .repeating)

            Text("The End!")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(coordinator.story?.storyType.color ?? .purple)

            Text("What an amazing story you created!")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func storyRecap(_ session: StorySession) -> some View {
        let storyType = coordinator.story?.storyType ?? .fantasy

        return VStack(spacing: 28) {
            if !session.openingNarrative.isEmpty {
                Text(session.openingNarrative)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            ForEach(Array(session.scenes.enumerated()), id: \.offset) { _, scene in
                sceneCard(scene, session: session, storyType: storyType)
            }
        }
    }

    private func sceneCard(_ scene: SceneRecord, session: StorySession, storyType: StoryType) -> some View {
        let beatPlan = session.beatPlan[safe: scene.sceneIndex]

        return VStack(spacing: 16) {
            HStack {
                Text("Beat \(scene.sceneIndex + 1)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(storyType.color, in: Capsule())
                if let role = beatPlan?.role {
                    Text(role.rawValue.capitalized)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(scene.entityName)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            if let cgImage = session.generatedImages[scene.sceneIndex] {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            } else if let data = session.compressedImageData[scene.sceneIndex],
                      let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            } else {
                let drawing = session.drawing(for: scene.sceneIndex)
                if !drawing.strokes.isEmpty {
                    Image(uiImage: drawing.renderedImage(scale: UIScreen.main.scale))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            if let caption = session.imageCaptions[scene.sceneIndex], !caption.isEmpty {
                Text(caption)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !scene.narrativeText.isEmpty {
                Text(scene.narrativeText)
                    .font(.system(.title3, design: .serif))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var homeButton: some View {
        Button {
            coordinator.returnToHome()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                Text("New story")
            }
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
        .padding(.bottom, 32)
    }
}
