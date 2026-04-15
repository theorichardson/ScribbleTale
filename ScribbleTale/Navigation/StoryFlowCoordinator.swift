import SwiftUI

@Observable
@MainActor
final class StoryFlowCoordinator {
    var path = NavigationPath()
    var story: Story?

    let storyEngine = StoryEngine()
    let imageService = ImageGenerationService()

    enum Destination: Hashable {
        case introduction
        case drawing(chapterIndex: Int)
        case imageReveal(chapterIndex: Int)
        case storyComplete
    }

    func startStory(type: StoryType) {
        story = Story(storyType: type)
        path.append(Destination.introduction)
    }

    func goToDrawing(chapterIndex: Int) {
        path.append(Destination.drawing(chapterIndex: chapterIndex))
    }

    func goToImageReveal(chapterIndex: Int) {
        path.append(Destination.imageReveal(chapterIndex: chapterIndex))
    }

    func goToNextChapterOrComplete(currentChapterIndex: Int) {
        let nextIndex = currentChapterIndex + 1
        let totalBeats = story?.chapterCount ?? 5
        if nextIndex < totalBeats {
            path.append(Destination.drawing(chapterIndex: nextIndex))
        } else {
            path.append(Destination.storyComplete)
        }
    }

    func returnToHome() {
        story = nil
        path = NavigationPath()
    }
}
