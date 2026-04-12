import SwiftUI

struct StoryTypeSelectionView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var isModelLoading = false
    @State private var modelProgress: Double = 0

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                genreGrid
                if isModelLoading {
                    loadingIndicator
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.purple.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isModelLoading = true
            await coordinator.storyEngine.loadModel()
            await coordinator.imageService.checkAvailability()
            isModelLoading = false
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("ScribbleTale")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Pick your story!")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var genreGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(StoryType.allCases) { type in
                StoryTypeCard(storyType: type) {
                    coordinator.startStory(type: type)
                }
                .disabled(isModelLoading)
                .opacity(isModelLoading ? 0.6 : 1.0)
            }
        }
    }

    private var loadingIndicator: some View {
        VStack(spacing: 8) {
            ProgressView(value: coordinator.storyEngine.loadingProgress)
                .tint(.purple)
            Text("Loading story brain...")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }
}
