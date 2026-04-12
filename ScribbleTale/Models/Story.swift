import Foundation

@Observable
final class Story: @unchecked Sendable {
    let storyType: StoryType
    var introText: String
    var chapters: [Chapter]

    static let chapterCount = 5
    static let beats: [StoryBeat] = [.character, .setting, .challenge, .climax, .resolution]

    init(storyType: StoryType) {
        self.storyType = storyType
        self.introText = ""
        self.chapters = Self.beats.enumerated().map { index, beat in
            Chapter(index: index, beat: beat)
        }
    }
}
