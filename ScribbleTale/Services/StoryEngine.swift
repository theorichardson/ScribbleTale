import Foundation
import MLXLLM
import MLXLMCommon

@Observable
@MainActor
final class StoryEngine {
    private var llm: LLMModel?
    private(set) var isLoaded = false
    private(set) var isGenerating = false
    private(set) var loadingProgress: Double = 0

    private static let modelID = "mlx-community/gemma-3-1b-it-4bit"

    func loadModel() async {
        guard !isLoaded else { return }
        do {
            let modelConfig = ModelConfiguration(id: Self.modelID)
            llm = try await LLMModelFactory.shared.create(configuration: modelConfig) { progress in
                Task { @MainActor in
                    self.loadingProgress = progress.fractionCompleted
                }
            }
            isLoaded = true
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    func generateIntroduction(for storyType: StoryType) -> AsyncStream<String> {
        let prompt = """
        You are a children's storyteller. Write a short, exciting, cinematic introduction \
        (3-4 sentences) for a \(storyType.rawValue) story for kids aged 6-10. \
        Make it vivid and full of wonder. Use simple language. \
        Set the scene and make the reader feel like they're about to go on an amazing adventure. \
        Do not include any instructions or meta-text, just the story introduction.
        """
        return streamGeneration(systemPrompt: storySystemPrompt(for: storyType), userPrompt: prompt)
    }

    func generateDrawingPrompt(for chapter: Chapter, storyType: StoryType, previousChapters: [Chapter]) -> AsyncStream<String> {
        let context = previousChapters.isEmpty ? "" : """
        \nSo far in the story: \(previousChapters.compactMap { $0.narration.isEmpty ? nil : $0.narration }.joined(separator: " "))
        """

        let prompt = """
        Generate a short, fun drawing prompt for a child (5-10 words max). \
        This is chapter \(chapter.index + 1) of 5, the "\(chapter.beat.rawValue)" chapter \
        of a \(storyType.rawValue) story.\(context)
        The prompt should start with "Draw" and tell the child what to draw. \
        Only output the prompt, nothing else.
        """
        return streamGeneration(systemPrompt: storySystemPrompt(for: storyType), userPrompt: prompt)
    }

    func generateImagePrompt(for chapter: Chapter, storyType: StoryType, drawingPrompt: String) -> AsyncStream<String> {
        let prompt = """
        Based on a child's drawing for the prompt "\(drawingPrompt)" in a \(storyType.rawValue) story, \
        write a detailed image generation prompt (1-2 sentences) that describes the scene vividly. \
        Include style cues: colorful, whimsical, children's book illustration style. \
        Only output the image prompt, nothing else.
        """
        return streamGeneration(systemPrompt: storySystemPrompt(for: storyType), userPrompt: prompt)
    }

    func generateNarration(for chapter: Chapter, storyType: StoryType, previousChapters: [Chapter]) -> AsyncStream<String> {
        let context = previousChapters.compactMap { $0.narration.isEmpty ? nil : $0.narration }.joined(separator: " ")
        let beatGuide: String
        switch chapter.beat {
        case .character:
            beatGuide = "Introduce the main character with personality and charm."
        case .setting:
            beatGuide = "Describe the world they're entering with vivid detail."
        case .challenge:
            beatGuide = "Present an exciting challenge or obstacle."
        case .climax:
            beatGuide = "Build to the most thrilling moment of the story."
        case .resolution:
            beatGuide = "Wrap up the story with a satisfying, happy ending."
        }

        let prompt = """
        Write the next part of this \(storyType.rawValue) story for kids (3-4 sentences). \
        This is the \(chapter.beat.rawValue) chapter (chapter \(chapter.index + 1) of 5). \
        \(beatGuide) \
        \(context.isEmpty ? "" : "Story so far: \(context) ") \
        The child drew something for the prompt: "\(chapter.drawingPrompt)". \
        Continue the story naturally. Only output the story text, nothing else.
        """
        return streamGeneration(systemPrompt: storySystemPrompt(for: storyType), userPrompt: prompt)
    }

    private func storySystemPrompt(for storyType: StoryType) -> String {
        """
        You are a creative children's storyteller specializing in \(storyType.rawValue) stories. \
        Your audience is kids aged 6-10. Use simple, vivid language. Be fun, warm, and encouraging. \
        Keep responses concise. Never include meta-text, instructions, or markdown.
        """
    }

    private static let controlTokenPattern = /(<end_of_turn>|<start_of_turn>|<eos>|<bos>|<pad>)/

    private func streamGeneration(systemPrompt: String, userPrompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let llm else {
                    continuation.finish()
                    return
                }
                isGenerating = true
                defer { isGenerating = false }

                do {
                    let messages: [[String: String]] = [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": userPrompt]
                    ]
                    var hitStop = false
                    let result = try await llm.generate(
                        messages: messages,
                        maxTokens: 256
                    ) { token in
                        guard !hitStop else { return }
                        if token.contains("<end_of_turn>") || token.contains("<eos>") {
                            let cleaned = token.replacing(Self.controlTokenPattern, with: "")
                            if !cleaned.isEmpty { continuation.yield(cleaned) }
                            hitStop = true
                            return
                        }
                        let cleaned = token.replacing(Self.controlTokenPattern, with: "")
                        if !cleaned.isEmpty { continuation.yield(cleaned) }
                    }
                    _ = result
                    continuation.finish()
                } catch {
                    print("Generation error: \(error)")
                    continuation.finish()
                }
            }
        }
    }
}
