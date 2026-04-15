import Foundation
import os
import MLX
import MLXLLM
import MLXLMCommon

private let log = Logger(subsystem: "com.scribbletale.app", category: "MLXTextProvider")

@Observable
@MainActor
final class MLXTextProvider: TextGenerationProvider {
    private var modelContainer: ModelContainer?
    private(set) var isLoaded = false
    private(set) var isLoadingModel = false
    private(set) var loadingProgress: Double = 0
    private(set) var loadingStatus: String = ""
    private(set) var loadError: String?
    private(set) var thinkingText: String = ""
    private(set) var loadedModel: StoryModel?
    private var loadStartTime: CFAbsoluteTime = 0
    private var downloadPhaseLogged = false

    private static let thinkStartTag = "<think>"
    private static let thinkEndTag = "</think>"
    private static let thinkBufferCap = 3000
    private static let thinkUpdateInterval = 8
    private static let gpuCacheLimit = 32 * 1024 * 1024 // 32 MB

    func resetThinkingText() {
        thinkingText = ""
    }

    func load(_ model: StoryModel) async {
        if isLoaded, loadedModel == model {
            log.info("load: \(model.displayName, privacy: .public) already loaded, skipping")
            return
        }

        if loadedModel != nil {
            log.info("load: unloading \(self.loadedModel?.displayName ?? "unknown", privacy: .public) before switching")
            modelContainer = nil
            isLoaded = false
            loadedModel = nil
            GPU.set(cacheLimit: 0)
            GPU.clearCache()
            log.info("load: GPU cache flushed after unload")
        }

        GPU.set(cacheLimit: Self.gpuCacheLimit)
        log.info("load: GPU cacheLimit set to \(Self.gpuCacheLimit / 1024 / 1024) MB")

        let available = os_proc_available_memory()
        log.info("load: available process memory = \(available / 1024 / 1024) MB")
        if available < 1_500_000_000 {
            log.warning("load: low memory warning — only \(available / 1024 / 1024) MB available before loading \(model.displayName, privacy: .public)")
        }

        isLoadingModel = true
        loadError = nil
        loadingProgress = 0
        loadingStatus = "Preparing \(model.displayName)..."
        log.info("load: starting — model=\(model.modelID, privacy: .public)")

        loadStartTime = CFAbsoluteTimeGetCurrent()
        downloadPhaseLogged = false

        do {
            let config = ModelConfiguration(id: model.modelID)
            log.info("load: config created, calling loadContainer for \(model.modelID, privacy: .public)")
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.handleLoadProgress(progress, model: model)
                }
            }

            let totalDuration = CFAbsoluteTimeGetCurrent() - loadStartTime
            isLoaded = true
            loadedModel = model
            loadingStatus = "\(model.displayName) ready"
            log.info("load: SUCCESS — \(model.displayName, privacy: .public) loaded in \(String(format: "%.1f", totalDuration))s")
        } catch {
            let errorDesc = String(describing: error)
            loadError = "Failed to load \(model.displayName): \(errorDesc.prefix(120))"
            loadingStatus = "\(model.displayName) failed to load"
            log.error("load: FAILED — model=\(model.modelID, privacy: .public) error=\(errorDesc, privacy: .public)")
        }

        isLoadingModel = false
    }

    private func handleLoadProgress(_ progress: Progress, model: StoryModel) {
        loadingProgress = progress.fractionCompleted
        if progress.fractionCompleted < 1.0 {
            let pct = Int(progress.fractionCompleted * 100)
            loadingStatus = "Downloading \(model.displayName)... \(pct)%"
            if pct % 10 == 0 {
                log.info("load: download progress \(pct)%")
            }
        } else {
            if !downloadPhaseLogged {
                downloadPhaseLogged = true
                let elapsed = CFAbsoluteTimeGetCurrent() - loadStartTime
                log.info("load: download complete in \(String(format: "%.1f", elapsed))s, loading into memory...")
            }
            loadingStatus = "Loading \(model.displayName) into memory..."
        }
    }

    private static let controlTokenPattern = /(<end_of_turn>|<start_of_turn>|<eos>|<bos>|<pad>|<\|im_start\|>|<\|im_end\|>|<\|endoftext\|>)/

    private static func cappedThinkText(_ buffer: String) -> String {
        if buffer.count > thinkBufferCap {
            return "…" + buffer.suffix(thinkBufferCap)
        }
        return buffer
    }

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
                var thinkTokensSinceUpdate = 0

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
                                    self.thinkingText = Self.cappedThinkText(thinkBuffer)
                                    insideThinkBlock = false
                                    thinkTokensSinceUpdate = 0
                                    if !afterThink.isEmpty {
                                        continuation.yield(afterThink)
                                    }
                                } else {
                                    thinkTokensSinceUpdate += 1
                                    if thinkTokensSinceUpdate >= Self.thinkUpdateInterval {
                                        if thinkBuffer.count > Self.thinkBufferCap {
                                            thinkBuffer = String(thinkBuffer.suffix(Self.thinkBufferCap))
                                        }
                                        self.thinkingText = Self.cappedThinkText(thinkBuffer)
                                        thinkTokensSinceUpdate = 0
                                    }
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
                                    thinkTokensSinceUpdate = 0
                                }
                            } else {
                                continuation.yield(cleaned)
                            }
                        } else {
                            continuation.yield(cleaned)
                        }

                        if isEndToken { break }
                    }

                    if insideThinkBlock && !thinkBuffer.isEmpty {
                        self.thinkingText = Self.cappedThinkText(thinkBuffer)
                    }

                    GPU.clearCache()
                    log.info("generate: completed — \(tokenCount) tokens")
                    continuation.finish()
                } catch {
                    GPU.clearCache()
                    log.error("generate: error after \(tokenCount) tokens — \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
