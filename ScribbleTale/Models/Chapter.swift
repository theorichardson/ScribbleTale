import Foundation
import PencilKit
import CoreGraphics

enum StoryBeat: String, Codable, Sendable {
    case character = "Character"
    case companion = "Companion"
    case setting = "Setting"
    case object = "Object"
    case villain = "Villain"
    case climax = "Climax"
    case resolution = "Resolution"
}

enum DrawingSubject: String, Codable, Sendable {
    case mainCharacter
    case ally
    case villain
    case pet
    case object
    case scene

    var displayName: String {
        switch self {
        case .mainCharacter: "Your Hero"
        case .ally: "A Friend"
        case .villain: "The Troublemaker"
        case .pet: "A Companion"
        case .object: "A Special Item"
        case .scene: "A Place"
        }
    }

    var icon: String {
        switch self {
        case .mainCharacter: "hare.fill"
        case .ally: "bird.fill"
        case .villain: "theatermasks.fill"
        case .pet: "pawprint.fill"
        case .object: "sparkle"
        case .scene: "mountain.2.fill"
        }
    }

    /// Context given to the LLM when generating the child's drawing prompt.
    /// All characters MUST be animals or creatures — Image Playground cannot
    /// generate people without a source photo.
    var drawingPromptHint: String {
        switch self {
        case .mainCharacter:
            "Ask the child to draw an animal or creature who is the hero of the story."
        case .ally:
            "Ask the child to draw a friendly animal or creature who helps the hero."
        case .villain:
            "Ask the child to draw a sneaky or scary animal, monster, or creature who causes trouble."
        case .pet:
            "Ask the child to draw a small animal companion or pet that joins the adventure."
        case .object:
            "Ask the child to draw a special object, tool, or magical item."
        case .scene:
            "Ask the child to draw a place or setting where the story happens."
        }
    }

    /// Context passed into the image generation pipeline so it knows what kind of subject the drawing depicts.
    /// IMPORTANT: Avoid "person", "human", "boy", "girl", "man", "woman" — Image Playground
    /// rejects prompts depicting people without a personIdentity photo reference.
    var pipelineContext: String {
        switch self {
        case .mainCharacter:
            "The child drew the story's main creature or fantastical hero."
        case .ally:
            "The child drew a friendly creature or magical companion."
        case .villain:
            "The child drew a mischievous monster, beast, or shadowy villain."
        case .pet:
            "The child drew an animal companion or pet creature."
        case .object:
            "The child drew a special object, tool, or magical item."
        case .scene:
            "The child drew a location, landscape, or place."
        }
    }
}

@Observable
final class Chapter: Identifiable, @unchecked Sendable {
    let id = UUID()
    let index: Int
    let beat: StoryBeat
    let drawingSubject: DrawingSubject
    var drawingPrompt: String
    var imageGenerationPrompt: String
    var drawing: PKDrawing
    var generatedImage: CGImage?
    var narration: String

    init(
        index: Int,
        beat: StoryBeat,
        drawingSubject: DrawingSubject,
        drawingPrompt: String = "",
        imageGenerationPrompt: String = "",
        narration: String = ""
    ) {
        self.index = index
        self.beat = beat
        self.drawingSubject = drawingSubject
        self.drawingPrompt = drawingPrompt
        self.imageGenerationPrompt = imageGenerationPrompt
        self.drawing = PKDrawing()
        self.narration = narration
    }

    var hasDrawing: Bool {
        !drawing.strokes.isEmpty
    }
}
