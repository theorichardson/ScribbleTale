import Foundation
import PencilKit
import CoreGraphics

enum StoryBeat: String, Codable, Sendable {
    case character = "Character"
    case setting = "Setting"
    case challenge = "Challenge"
    case climax = "Climax"
    case resolution = "Resolution"
}

@Observable
final class Chapter: Identifiable, @unchecked Sendable {
    let id = UUID()
    let index: Int
    let beat: StoryBeat
    var drawingPrompt: String
    var imageGenerationPrompt: String
    var drawing: PKDrawing
    var generatedImage: CGImage?
    var playgroundGeneratedImage: CGImage?
    var coreMLGeneratedImage: CGImage?
    var narration: String

    init(
        index: Int,
        beat: StoryBeat,
        drawingPrompt: String = "",
        imageGenerationPrompt: String = "",
        narration: String = ""
    ) {
        self.index = index
        self.beat = beat
        self.drawingPrompt = drawingPrompt
        self.imageGenerationPrompt = imageGenerationPrompt
        self.drawing = PKDrawing()
        self.narration = narration
    }

    var hasDrawing: Bool {
        !drawing.strokes.isEmpty
    }
}
