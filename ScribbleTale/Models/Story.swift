import Foundation

@Observable
final class Story: @unchecked Sendable {
    let storyType: StoryType
    var introText: String
    var chapters: [Chapter]

    static let chapterDefinitions: [(beat: StoryBeat, subject: DrawingSubject)] = [
        (.character,  .mainCharacter),
        (.companion,  .pet),
        (.setting,    .scene),
        (.object,     .object),
        (.villain,    .villain),
        (.climax,     .ally),
        (.resolution, .scene),
    ]

    static var chapterCount: Int { chapterDefinitions.count }

    init(storyType: StoryType) {
        self.storyType = storyType
        self.introText = ""
        self.chapters = Self.chapterDefinitions.enumerated().map { index, def in
            Chapter(index: index, beat: def.beat, drawingSubject: def.subject)
        }
    }
}
