import Foundation
import os
import MLXLLM
import MLXLMCommon

private let log = Logger(subsystem: "com.scribbletale.app", category: "MLXTextProvider")

@Observable
@MainActor
final class MLXTextProvider: TextGenerationProvider {
    private var modelContainer: ModelContainer?
    private(set) var isLoaded = false
    private(set) var loadingProgress: Double = 0
    private(set) var loadingStatus: String = ""
    private(set) var thinkingText: String = ""
    private(set) var loadedModel: StoryModel?

    private static let thinkStartTag = "<think>"
    private static let thinkEndTag = "</think>"

    func load(_ model: StoryModel) async {
        if isLoaded, loadedModel == model {
            log.info("load: \(model.displayName) already loaded, skipping")
            return
        }

        if loadedModel != nil {
            log.info("load: unloading \(self.loadedModel?.displayName ?? "unknown") before switching")
            modelContainer = nil
            isLoaded = false
            loadedModel = nil
            loadingProgress = 0
        }

        log.info("load: starting — model=\(model.modelID, privacy: .public)")
        loadingStatus = "Downloading \(model.displayName)..."

        do {
            let config = ModelConfiguration(id: model.modelID)
            log.info("load: config created, calling loadContainer")
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.loadingProgress = progress.fractionCompleted
                    if progress.fractionCompleted < 1.0 {
                        let pct = Int(progress.fractionCompleted * 100)
                        self.loadingStatus = "Downloading \(model.displayName)... \(pct)%"
                    } else {
                        self.loadingStatus = "Loading \(model.displayName) into memory..."
                    }
                }
            }
            isLoaded = true
            loadedModel = model
            loadingStatus = "\(model.displayName) ready"
            log.info("load: SUCCESS — \(model.displayName) loaded and ready")
        } catch {
            loadingStatus = "\(model.displayName) failed to load"
            log.error("load: FAILED — \(error, privacy: .public)")
        }
    }

    private static let controlTokenPattern = /(<end_of_turn>|<start_of_turn>|<eos>|<bos>|<pad>|<\|im_start\|>|<\|im_end\|>|<\|endoftext\|>)/

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float
    ) -> AsyncThrowingStream<String, Error> {
        guard let modelContainer else {
            log.error("generate: model not loaded, returning empty stream")
            return AsyncThrowingStream { $0.finish() }
        }

        let container = modelContainer
        let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: topP)
        let isThinking = loadedModel?.isThinkingModel ?? false
        let promptPreview = String(userPrompt.prefix(80))
        log.info("generate: starting — maxTokens=\(maxTokens) temp=\(temperature) thinking=\(isThinking) prompt=\"\(promptPreview, privacy: .public)...\"")

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                self.thinkingText = ""

                let session = ChatSession(
                    container,
                    instructions: systemPrompt,
                    generateParameters: params
                )

                var tokenCount = 0
                var insideThinkBlock = false
                var thinkBuffer = ""

                do {
                    for try await chunk in session.streamResponse(to: userPrompt) {
                        tokenCount += 1

                        let isEndToken = chunk.contains("<end_of_turn>") || chunk.contains("<eos>")
                            || chunk.contains("<|im_end|>") || chunk.contains("<|endoftext|>")

                        let cleaned = chunk.replacing(Self.controlTokenPattern, with: "")

                        guard !cleaned.isEmpty else {
                            if isEndToken { break }
                            continue
                        }

                        if isThinking {
                            if insideThinkBlock {
                                thinkBuffer += cleaned
                                if let endRange = thinkBuffer.range(of: Self.thinkEndTag) {
                                    let afterThink = String(thinkBuffer[endRange.upperBound...])
                                    thinkBuffer = String(thinkBuffer[thinkBuffer.startIndex..<endRange.lowerBound])
                                    self.thinkingText = thinkBuffer
                                    insideThinkBlock = false
                                    if !afterThink.isEmpty {
                                        continuation.yield(afterThink)
                                    }
                                } else {
                                    self.thinkingText = thinkBuffer
                                }
                            } else if cleaned.contains(Self.thinkStartTag) {
                                if let startRange = cleaned.range(of: Self.thinkStartTag) {
                                    let before = String(cleaned[cleaned.startIndex..<startRange.lowerBound])
                                    let after = String(cleaned[startRange.upperBound...])
                                    if !before.isEmpty {
                                        continuation.yield(before)
                                    }
                                    insideThinkBlock = true
                                    thinkBuffer = after
                                    self.thinkingText = thinkBuffer
                                }
                            } else {
                                continuation.yield(cleaned)
                            }
                        } else {
                            continuation.yield(cleaned)
                        }

                        if isEndToken { break }
                    }
                    log.info("generate: completed — \(tokenCount) tokens")
                    continuation.finish()
                } catch {
                    log.error("generate: error after \(tokenCount) tokens — \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
