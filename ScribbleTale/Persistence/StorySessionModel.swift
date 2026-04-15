import Foundation
import SwiftData

@Model
final class StorySessionModel {
    @Attribute(.unique) var sessionID: UUID
    var category: String
    var sceneCount: Int
    var currentSceneIndex: Int
    var blueprintJSON: Data?
    var characterBibleJSON: Data?
    var openingNarrative: String
    var status: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SceneModel.session)
    var scenes: [SceneModel]

    init(
        sessionID: UUID,
        category: String,
        sceneCount: Int,
        currentSceneIndex: Int = 0,
        blueprintJSON: Data? = nil,
        characterBibleJSON: Data? = nil,
        openingNarrative: String = "",
        status: String = "inProgress"
    ) {
        self.sessionID = sessionID
        self.category = category
        self.sceneCount = sceneCount
        self.currentSceneIndex = currentSceneIndex
        self.blueprintJSON = blueprintJSON
        self.characterBibleJSON = characterBibleJSON
        self.openingNarrative = openingNarrative
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
        self.scenes = []
    }
}
