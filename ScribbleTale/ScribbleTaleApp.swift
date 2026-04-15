import SwiftUI
import SwiftData

@main
struct ScribbleTaleApp: App {
    @State private var coordinator = StoryFlowCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .modelContainer(coordinator.persistence.modelContainer)
        }
    }
}

struct ContentView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationStack(path: $coordinator.path) {
            StoryTypeSelectionView()
                .navigationDestination(for: StoryFlowCoordinator.Destination.self) { destination in
                    switch destination {
                    case .introduction:
                        IntroductionView()
                    case .drawing(let chapterIndex):
                        DrawingView(chapterIndex: chapterIndex)
                    case .imageReveal(let chapterIndex):
                        ImageRevealView(chapterIndex: chapterIndex)
                    case .storyComplete:
                        StoryCompleteView()
                    }
                }
        }
    }
}
