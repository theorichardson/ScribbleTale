import Foundation
import MLXLLM
import MLXLMCommon

@Observable
@MainActor
final class StoryEngine {
    private var modelContainer: ModelContainer?
    private(set) var isLoaded = false
    private(set) var isGenerating = false
    private(set) var loadingProgress: Double = 0

    private static let modelID = "mlx-community/gemma-3-1b-it-4bit"

    func loadModel() async {
        guard !isLoaded else { return }
        do {
            let config = ModelConfiguration(id: Self.modelID)
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.loadingProgress = progress.fractionCompleted
                }
            }
            isLoaded = true
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    // MARK: - Generation Methods

    func generateIntroduction(for storyType: StoryType) -> AsyncThrowingStream<String, Error> {
        let prompt = """
        Write a short, exciting, cinematic introduction (3-4 sentences) for a \
        \(storyType.rawValue) story for kids aged 6-10. Make it vivid and full of wonder. \
        Use simple language. Set the scene and make the reader feel like they're about to \
        go on an amazing adventure. Only output the story introduction.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt
        )
    }

    func generateDrawingPrompt(
        for chapter: Chapter,
        storyType: StoryType,
        previousChapters: [Chapter]
    ) -> AsyncThrowingStream<String, Error> {
        let context = previousChapters
            .compactMap { $0.narration.isEmpty ? nil : $0.narration }
            .joined(separator: " ")

        let prompt = """
        Generate a short, fun drawing prompt for a child (5-10 words max). \
        This is chapter \(chapter.index + 1) of 5, the "\(chapter.beat.rawValue)" beat \
        of a \(storyType.rawValue) story.\
        \(context.isEmpty ? "" : " Story so far: \(context)") \
        The prompt should start with "Draw" and tell the child what to draw. \
        Only output the prompt, nothing else.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt
        )
    }

    func generateImagePrompt(
        for chapter: Chapter,
        storyType: StoryType,
        drawingPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = """
        Based on a child's drawing for the prompt "\(drawingPrompt)" in a \
        \(storyType.rawValue) story, write a detailed image generation prompt \
        (1-2 sentences) describing the scene vividly. Include style cues: colorful, \
        whimsical, children's book illustration style. Only output the image prompt.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt
        )
    }

    func generateNarration(
        for chapter: Chapter,
        storyType: StoryType,
        previousChapters: [Chapter]
    ) -> AsyncThrowingStream<String, Error> {
        let context = previousChapters
            .compactMap { $0.narration.isEmpty ? nil : $0.narration }
            .joined(separator: " ")

        let beatGuide: String = switch chapter.beat {
        case .character: "Introduce the main character with personality and charm."
        case .setting: "Describe the world they're entering with vivid detail."
        case .challenge: "Present an exciting challenge or obstacle."
        case .climax: "Build to the most thrilling moment of the story."
        case .resolution: "Wrap up the story with a satisfying, happy ending."
        }

        let prompt = """
        Write the next part of this \(storyType.rawValue) story for kids (3-4 sentences). \
        This is the \(chapter.beat.rawValue) chapter (chapter \(chapter.index + 1) of 5). \
        \(beatGuide) \
        \(context.isEmpty ? "" : "Story so far: \(context) ") \
        The child drew something for the prompt: "\(chapter.drawingPrompt)". \
        Continue the story naturally. Only output the story text.
        """
        return streamText(
            systemPrompt: storySystemPrompt(for: storyType),
            userPrompt: prompt
        )
    }

    // MARK: - Private

    private func storySystemPrompt(for storyType: StoryType) -> String {
        """
        You are a creative children's storyteller specializing in \(storyType.rawValue) stories. \
        Your audience is kids aged 6-10. Use simple, vivid language. Be fun, warm, and encouraging. \
        Keep responses concise. Never include meta-text, instructions, or markdown formatting.
        """
    }

    private func streamText(
        systemPrompt: String,
        userPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        guard let modelContainer else {
            return AsyncThrowingStream { $0.finish() }
        }

        let container = modelContainer
        let params = GenerateParameters(maxTokens: 256, temperature: 0.7, topP: 0.9)

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                self.isGenerating = true
                defer { self.isGenerating = false }

                let session = ChatSession(
                    container,
                    instructions: systemPrompt,
                    generateParameters: params
                )

                do {
                    for try await chunk in session.streamResponse(to: userPrompt) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
