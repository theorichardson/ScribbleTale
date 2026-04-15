import Foundation
import SwiftData

@Model
final class SceneModel {
    var sceneIndex: Int
    var narrativeText: String
    var drawingPromptText: String
    var imageGenPrompt: String
    var entityName: String
    var entityType: String
    var sceneSummary: String
    var continuityNotes: String
    var childDrawingData: Data?
    var generatedImageData: Data?
    var createdAt: Date

    var session: StorySessionModel?

    init(
        sceneIndex: Int,
        narrativeText: String,
        drawingPromptText: String,
        imageGenPrompt: String,
        entityName: String,
        entityType: String,
        sceneSummary: String,
        continuityNotes: String
    ) {
        self.sceneIndex = sceneIndex
        self.narrativeText = narrativeText
        self.drawingPromptText = drawingPromptText
        self.imageGenPrompt = imageGenPrompt
        self.entityName = entityName
        self.entityType = entityType
        self.sceneSummary = sceneSummary
        self.continuityNotes = continuityNotes
        self.createdAt = Date()
    }
}
