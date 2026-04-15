import Foundation
import PencilKit
import CoreGraphics

// MARK: - Story Blueprint

struct StoryBlueprint: Codable, Sendable {
    let setting: String
    let protagonist: String
    let theme: String
    var sceneGoals: [String]
}

// MARK: - Character Bible

struct CharacterBible: Codable, Sendable {
    let name: String
    let species: String
    let appearance: String
    let personality: String
    let want: String

    var compactDescription: String {
        "\(name) the \(species), \(appearance). Wants to \(want)."
    }
}

// MARK: - Scene Record

struct SceneRecord: Codable, Sendable {
    let sceneIndex: Int
    let narrativeText: String
    let drawingPromptText: String
    let imageGenPrompt: String
    let entityName: String
    let entityType: EntityType
    let sceneSummary: String
    let continuityNotes: String

    enum EntityType: String, Codable, Sendable {
        case creature
        case object
        case place
    }
}

// MARK: - Story Session

@Observable
final class StorySession: @unchecked Sendable {
    let id: UUID
    let storyType: StoryType
    let sceneCount: Int

    var blueprint: StoryBlueprint?
    var characterBible: CharacterBible?
    var openingNarrative: String = ""
    var scenes: [SceneRecord] = []
    var status: SessionStatus = .inProgress

    // Runtime-only state (not persisted)
    var pendingChallenge: DrawingChallenge?
    var drawings: [Int: PKDrawing] = [:]
    var generatedImages: [Int: CGImage] = [:]
    var compressedImageData: [Int: Data] = [:]
    var imageCaptions: [Int: String] = [:]

    let beatPlan: [BeatPlan]

    enum SessionStatus: String, Codable, Sendable {
        case inProgress
        case completed
    }

    init(storyType: StoryType, sceneCount: Int = 5) {
        self.id = UUID()
        self.storyType = storyType
        self.sceneCount = sceneCount
        self.beatPlan = BeatPlan.makeSequence(count: sceneCount)
    }

    var currentSceneIndex: Int { scenes.count }
    var isComplete: Bool { currentSceneIndex >= sceneCount }

    var currentBeatRole: BeatRole? {
        beatPlan[safe: currentSceneIndex]?.role
    }

    var priorEntityNames: [String] {
        scenes.map(\.entityName)
    }

    var priorDrawingPrompts: [String] {
        scenes.map(\.drawingPromptText)
    }

    func drawing(for sceneIndex: Int) -> PKDrawing {
        drawings[sceneIndex] ?? PKDrawing()
    }

    func setDrawing(_ drawing: PKDrawing, for sceneIndex: Int) {
        drawings[sceneIndex] = drawing
    }

    /// Release heavy runtime assets for completed scenes to reduce memory pressure.
    /// Keeps only the current scene's drawing; older drawings and all but the
    /// most recent generated image are released.
    func releaseCompletedSceneAssets(keepingCurrent sceneIndex: Int) {
        for key in drawings.keys where key < sceneIndex {
            drawings.removeValue(forKey: key)
        }
        for key in generatedImages.keys where key < sceneIndex {
            generatedImages.removeValue(forKey: key)
        }
    }
}
