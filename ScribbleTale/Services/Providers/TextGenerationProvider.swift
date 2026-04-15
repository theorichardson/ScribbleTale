import Foundation

@MainActor
protocol TextGenerationProvider: AnyObject {
    var isLoaded: Bool { get }
    var loadingProgress: Double { get }
    var loadingStatus: String { get }
    var thinkingText: String { get }
    var loadedModel: StoryModel? { get }

    func load(_ model: StoryModel) async
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float
    ) -> AsyncThrowingStream<String, Error>
}
