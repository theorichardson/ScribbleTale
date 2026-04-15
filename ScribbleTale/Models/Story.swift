import Foundation

@Observable
final class Story: @unchecked Sendable {
    let storyType: StoryType
    let session: StorySession

    static let sceneCount = 3

    var chapterCount: Int { session.sceneCount }

    init(storyType: StoryType) {
        self.storyType = storyType
        self.session = StorySession(storyType: storyType, sceneCount: Self.sceneCount)
    }
}
