import SwiftUI

struct StoryCompleteView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var showContent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                if let story = coordinator.story {
                    storyRecap(story)
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

    private func storyRecap(_ story: Story) -> some View {
        VStack(spacing: 28) {
            if !story.introText.isEmpty {
                Text(story.introText)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            ForEach(story.chapters) { chapter in
                chapterCard(chapter, storyType: story.storyType)
            }
        }
    }

    private func chapterCard(_ chapter: Chapter, storyType: StoryType) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Chapter \(chapter.index + 1)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(storyType.color, in: Capsule())
                Text(chapter.beat.rawValue)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let cgImage = chapter.generatedImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            } else if chapter.hasDrawing {
                let img = chapter.drawing.image(
                    from: chapter.drawing.bounds,
                    scale: UIScreen.main.scale
                )
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if !chapter.narration.isEmpty {
                Text(chapter.narration)
                    .font(.system(.body, design: .serif))
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
                Text("New Story")
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
