import Foundation

@Observable
final class Story: @unchecked Sendable {
    let storyType: StoryType
    let narrativeState: NarrativeState

    static let beatCount = 5

    var chapterCount: Int { narrativeState.beatPlan.count }

    init(storyType: StoryType) {
        self.storyType = storyType
        self.narrativeState = NarrativeState(
            genre: storyType.rawValue,
            beatCount: Self.beatCount
        )
    }
}
