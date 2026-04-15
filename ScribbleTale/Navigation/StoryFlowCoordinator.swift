import SwiftUI
import os

private let log = Logger(subsystem: "com.scribbletale.app", category: "StoryFlowCoordinator")

@Observable
@MainActor
final class StoryFlowCoordinator {
    var path = NavigationPath()
    var story: Story?

    private(set) var storyEngine: SingleCallStoryEngine
    private(set) var imageService: ImageGenerationService
    let config = ProviderConfig.shared
    let persistence = StoryPersistence.shared

    private var mlxProvider: MLXTextProvider
    private var openAITextProvider: OpenAITextProvider
    private var playgroundProvider: PlaygroundImageProvider
    private var openAIImageProvider: OpenAIImageProvider

    enum Destination: Hashable {
        case introduction
        case drawing(chapterIndex: Int)
        case imageReveal(chapterIndex: Int)
        case storyComplete
    }

    init() {
        let config = ProviderConfig.shared
        let mlx = MLXTextProvider()
        let openAIText = OpenAITextProvider(apiKey: config.openAIKey)
        let playground = PlaygroundImageProvider()
        let openAIImage = OpenAIImageProvider(apiKey: config.openAIKey)

        self.mlxProvider = mlx
        self.openAITextProvider = openAIText
        self.playgroundProvider = playground
        self.openAIImageProvider = openAIImage

        self.storyEngine = SingleCallStoryEngine(textProvider: mlx)
        self.imageService = ImageGenerationService(
            imageProvider: playground,
            needsDepersonalization: true
        )
    }

    func selectTextModel(_ model: StoryModel) {
        log.info("selectTextModel: \(model.displayName, privacy: .public) isLocal=\(model.isLocal)")
        if model.isLocal {
            storyEngine = SingleCallStoryEngine(textProvider: mlxProvider)
        } else {
            openAITextProvider.updateAPIKey(config.openAIKey)
            storyEngine = SingleCallStoryEngine(textProvider: openAITextProvider)
        }
    }

    func refreshImageProvider() {
        log.info("refreshImageProvider: \(self.config.imageProvider.rawValue, privacy: .public)")
        switch config.imageProvider {
        case .local:
            imageService = ImageGenerationService(
                imageProvider: playgroundProvider,
                needsDepersonalization: true
            )
        case .openAI:
            openAIImageProvider.updateAPIKey(config.openAIKey)
            imageService = ImageGenerationService(
                imageProvider: openAIImageProvider,
                needsDepersonalization: false
            )
        }
    }

    func startStory(type: StoryType) {
        refreshImageProvider()
        story = Story(storyType: type)
        path.append(Destination.introduction)
    }

    func goToDrawing(chapterIndex: Int) {
        path.append(Destination.drawing(chapterIndex: chapterIndex))
    }

    func goToImageReveal(chapterIndex: Int) {
        path.append(Destination.imageReveal(chapterIndex: chapterIndex))
    }

    func goToNextChapterOrComplete(currentChapterIndex: Int) {
        let nextIndex = currentChapterIndex + 1
        let totalBeats = story?.chapterCount ?? 5
        if nextIndex < totalBeats {
            path.append(Destination.drawing(chapterIndex: nextIndex))
        } else {
            path.append(Destination.storyComplete)
        }
    }

    func returnToHome() {
        story = nil
        path = NavigationPath()
    }
}
