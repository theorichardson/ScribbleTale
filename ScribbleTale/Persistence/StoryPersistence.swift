import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.scribbletale.app", category: "StoryPersistence")

@MainActor
final class StoryPersistence {
    let modelContainer: ModelContainer
    private var modelContext: ModelContext

    static let shared: StoryPersistence = {
        do {
            return try StoryPersistence()
        } catch {
            fatalError("Failed to initialize StoryPersistence: \(error)")
        }
    }()

    private init() throws {
        let schema = Schema([StorySessionModel.self, SceneModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = modelContainer.mainContext
    }

    // MARK: - Session Operations

    func createSession(from session: StorySession) {
        let blueprintData = try? JSONEncoder().encode(session.blueprint)
        let bibleData = try? JSONEncoder().encode(session.characterBible)

        let model = StorySessionModel(
            sessionID: session.id,
            category: session.storyType.rawValue,
            sceneCount: session.sceneCount,
            currentSceneIndex: session.currentSceneIndex,
            blueprintJSON: blueprintData,
            characterBibleJSON: bibleData,
            openingNarrative: session.openingNarrative,
            status: session.status.rawValue
        )

        modelContext.insert(model)
        save()
        log.info("createSession: persisted session \(session.id)")
    }

    func updateSession(_ session: StorySession) {
        guard let model = fetchSessionModel(id: session.id) else {
            log.warning("updateSession: session \(session.id) not found, creating")
            createSession(from: session)
            return
        }

        model.blueprintJSON = try? JSONEncoder().encode(session.blueprint)
        model.characterBibleJSON = try? JSONEncoder().encode(session.characterBible)
        model.openingNarrative = session.openingNarrative
        model.currentSceneIndex = session.currentSceneIndex
        model.status = session.status.rawValue
        model.updatedAt = Date()

        save()
    }

    // MARK: - Scene Operations

    func persistScene(_ record: SceneRecord, sessionID: UUID) {
        guard let sessionModel = fetchSessionModel(id: sessionID) else {
            log.error("persistScene: session \(sessionID) not found")
            return
        }

        let sceneModel = SceneModel(
            sceneIndex: record.sceneIndex,
            narrativeText: record.narrativeText,
            drawingPromptText: record.drawingPromptText,
            imageGenPrompt: record.imageGenPrompt,
            entityName: record.entityName,
            entityType: record.entityType.rawValue,
            sceneSummary: record.sceneSummary,
            continuityNotes: record.continuityNotes
        )

        sceneModel.session = sessionModel
        sessionModel.scenes.append(sceneModel)
        sessionModel.currentSceneIndex = record.sceneIndex + 1
        sessionModel.updatedAt = Date()

        save()
        log.info("persistScene: saved scene \(record.sceneIndex) for session \(sessionID)")
    }

    // MARK: - Query

    func loadScenes(sessionID: UUID) -> [SceneRecord] {
        guard let sessionModel = fetchSessionModel(id: sessionID) else { return [] }
        return sessionModel.scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .map { scene in
                SceneRecord(
                    sceneIndex: scene.sceneIndex,
                    narrativeText: scene.narrativeText,
                    drawingPromptText: scene.drawingPromptText,
                    imageGenPrompt: scene.imageGenPrompt,
                    entityName: scene.entityName,
                    entityType: SceneRecord.EntityType(rawValue: scene.entityType) ?? .object,
                    sceneSummary: scene.sceneSummary,
                    continuityNotes: scene.continuityNotes
                )
            }
    }

    // MARK: - Private

    private func fetchSessionModel(id: UUID) -> StorySessionModel? {
        let predicate = #Predicate<StorySessionModel> { $0.sessionID == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            log.error("save: failed — \(error)")
        }
    }
}
