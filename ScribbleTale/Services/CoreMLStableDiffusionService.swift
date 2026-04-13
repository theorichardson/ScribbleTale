import Foundation
import CoreGraphics
import CoreML
import StableDiffusion

final class CoreMLStableDiffusionService: Sendable {
    private let state = CoreMLState()

    struct GenerationProgress: Sendable {
        let step: Int
        let totalSteps: Int
    }

    var isAvailable: Bool { state.isAvailable }
    var unavailabilityReason: String? { state.unavailabilityReason }

    func checkAvailability() {
        let discovery = resolveResourcesURL()
        guard let url = discovery.resourcesURL else {
            state.isAvailable = false
            state.unavailabilityReason = buildUnavailableMessage(searchedPaths: discovery.searchedPaths)
            state.discoveredResourcesURL = nil
            state.preparedResourcesURL = nil
            return
        }

        state.isAvailable = true
        state.unavailabilityReason = nil
        state.discoveredResourcesURL = url
    }

    func warmUp() throws {
        guard let discoveredURL = state.discoveredResourcesURL else {
            throw ImageGenerationError.coreMLNotAvailable
        }
        let resourcesURL = try prepareRuntimeResourcesIfNeeded(from: discoveredURL)

        if state.pipeline == nil {
            let modelConfig = MLModelConfiguration()
            modelConfig.computeUnits = .cpuAndNeuralEngine

            let pipeline = try StableDiffusionPipeline(
                resourcesAt: resourcesURL,
                controlNet: [],
                configuration: modelConfig,
                disableSafety: false,
                reduceMemory: true
            )
            try pipeline.loadResources()
            state.pipeline = pipeline
        }
    }

    nonisolated func generateImage(
        prompt: String,
        negativePrompt: String = "",
        onProgress: @Sendable (GenerationProgress) -> Void = { _ in }
    ) throws -> CGImage? {
        guard let discoveredURL = state.discoveredResourcesURL else {
            throw ImageGenerationError.coreMLNotAvailable
        }

        let pipeline: StableDiffusionPipeline
        if let cached = state.pipeline {
            pipeline = cached
        } else {
            let resourcesURL = try prepareRuntimeResourcesIfNeeded(from: discoveredURL)
            let modelConfig = MLModelConfiguration()
            modelConfig.computeUnits = .cpuAndNeuralEngine

            let newPipeline = try StableDiffusionPipeline(
                resourcesAt: resourcesURL,
                controlNet: [],
                configuration: modelConfig,
                disableSafety: false,
                reduceMemory: true
            )
            try newPipeline.loadResources()
            state.pipeline = newPipeline
            pipeline = newPipeline
        }

        let stepCount = 20
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.imageCount = 1
        config.stepCount = stepCount
        config.guidanceScale = 7.5
        config.schedulerType = .dpmSolverMultistepScheduler
        config.seed = UInt32.random(in: 0...UInt32.max)

        return try pipeline.generateImages(configuration: config) { progress in
            onProgress(GenerationProgress(step: progress.step, totalSteps: stepCount))
            return true
        }.first ?? nil
    }

    // MARK: - Resource Discovery

    private func resolveResourcesURL() -> (resourcesURL: URL?, searchedPaths: [String]) {
        let fm = FileManager.default
        let bundleURL = Bundle.main.resourceURL
        let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""

        let roots = [
            bundleURL,
            appSupportURL,
            appSupportURL?.appendingPathComponent(bundleIdentifier, isDirectory: true)
        ]

        let folderNames = [
            "StableDiffusionResources",
            "StableDiffusion",
            "Resources/StableDiffusionResources",
            "Resources/StableDiffusion",
            "StableDiffusionResources/Resources",
            "StableDiffusion/Resources",
            "Resources"
        ]

        var candidates: [URL] = []
        var searchedPaths: [String] = []
        for case let root? in roots {
            candidates.append(root)
            searchedPaths.append(root.path)

            for folderName in folderNames {
                let candidate = root.appendingPathComponent(folderName, isDirectory: true)
                candidates.append(candidate)
                searchedPaths.append(candidate.path)
            }
        }

        for url in candidates where hasRequiredResources(at: url) {
            return (url, searchedPaths)
        }

        return (nil, searchedPaths)
    }

    private func hasRequiredResources(at baseURL: URL) -> Bool {
        let fm = FileManager.default
        let textEncoderPath = modelURL(modelName: "TextEncoder", in: baseURL)?.path
        let decoderPath = modelURL(modelName: "VAEDecoder", in: baseURL)?.path
        let vocabPath = baseURL.appendingPathComponent("vocab.json").path
        let mergesPath = baseURL.appendingPathComponent("merges.txt").path

        let hasSingleUnet = modelURL(modelName: "Unet", in: baseURL) != nil
        let hasChunkedUnet = modelURL(modelName: "UnetChunk1", in: baseURL) != nil
            && modelURL(modelName: "UnetChunk2", in: baseURL) != nil

        return textEncoderPath.map { fm.fileExists(atPath: $0) } ?? false
            && (hasSingleUnet || hasChunkedUnet)
            && (decoderPath.map { fm.fileExists(atPath: $0) } ?? false)
            && fm.fileExists(atPath: vocabPath)
            && fm.fileExists(atPath: mergesPath)
    }

    private func modelURL(modelName: String, in baseURL: URL) -> URL? {
        let fm = FileManager.default
        let compiledURL = baseURL.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true)
        if fm.fileExists(atPath: compiledURL.path) {
            return compiledURL
        }

        let packageURL = baseURL.appendingPathComponent("\(modelName).mlpackage", isDirectory: true)
        if fm.fileExists(atPath: packageURL.path) {
            return packageURL
        }

        return nil
    }

    // MARK: - Runtime Compilation

    private func prepareRuntimeResourcesIfNeeded(from sourceURL: URL) throws -> URL {
        if let preparedURL = state.preparedResourcesURL {
            return preparedURL
        }

        let requiredModels = requiredModelURLs(in: sourceURL)
        let packageModels = requiredModels.filter { $0.value.pathExtension == "mlpackage" }
        if packageModels.isEmpty {
            state.preparedResourcesURL = sourceURL
            return sourceURL
        }

        let compiledResourcesURL = try compilePackagesIfNeeded(
            sourceURL: sourceURL,
            requiredModels: requiredModels
        )
        state.preparedResourcesURL = compiledResourcesURL
        return compiledResourcesURL
    }

    private func requiredModelURLs(in sourceURL: URL) -> [String: URL] {
        var models: [String: URL] = [:]
        if let textEncoder = modelURL(modelName: "TextEncoder", in: sourceURL) {
            models["TextEncoder"] = textEncoder
        }
        if let decoder = modelURL(modelName: "VAEDecoder", in: sourceURL) {
            models["VAEDecoder"] = decoder
        }

        if let unet = modelURL(modelName: "Unet", in: sourceURL) {
            models["Unet"] = unet
        } else {
            if let unetChunk1 = modelURL(modelName: "UnetChunk1", in: sourceURL) {
                models["UnetChunk1"] = unetChunk1
            }
            if let unetChunk2 = modelURL(modelName: "UnetChunk2", in: sourceURL) {
                models["UnetChunk2"] = unetChunk2
            }
        }
        return models
    }

    private func compilePackagesIfNeeded(sourceURL: URL, requiredModels: [String: URL]) throws -> URL {
        let packageModels = requiredModels.filter { $0.value.pathExtension == "mlpackage" }
        let compiledModels = requiredModels.filter { $0.value.pathExtension == "mlmodelc" }

        if !packageModels.isEmpty && !compiledModels.isEmpty {
            throw CoreMLResourceError.mixedModelFormats
        }

        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CoreMLResourceError.appSupportUnavailable
        }

        let runtimeURL = appSupport
            .appendingPathComponent("StableDiffusionCompiledResources", isDirectory: true)
            .appendingPathComponent(safePathComponent(from: sourceURL.path), isDirectory: true)

        if hasRequiredCompiledResources(at: runtimeURL) {
            return runtimeURL
        }

        if fm.fileExists(atPath: runtimeURL.path) {
            try fm.removeItem(at: runtimeURL)
        }
        try fm.createDirectory(at: runtimeURL, withIntermediateDirectories: true)

        try copyTokenizerResources(from: sourceURL, to: runtimeURL)

        for (modelName, packageURL) in packageModels {
            let compiledTempURL = try MLModel.compileModel(at: packageURL)
            let finalCompiledURL = runtimeURL.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true)
            if fm.fileExists(atPath: finalCompiledURL.path) {
                try fm.removeItem(at: finalCompiledURL)
            }
            try fm.copyItem(at: compiledTempURL, to: finalCompiledURL)
        }

        return runtimeURL
    }

    private func copyTokenizerResources(from sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        for fileName in ["vocab.json", "merges.txt"] {
            let source = sourceURL.appendingPathComponent(fileName)
            let destination = destinationURL.appendingPathComponent(fileName)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }
    }

    private func hasRequiredCompiledResources(at baseURL: URL) -> Bool {
        let fm = FileManager.default
        let textEncoderPath = baseURL.appendingPathComponent("TextEncoder.mlmodelc").path
        let decoderPath = baseURL.appendingPathComponent("VAEDecoder.mlmodelc").path
        let vocabPath = baseURL.appendingPathComponent("vocab.json").path
        let mergesPath = baseURL.appendingPathComponent("merges.txt").path
        let unetPath = baseURL.appendingPathComponent("Unet.mlmodelc").path
        let unetChunk1Path = baseURL.appendingPathComponent("UnetChunk1.mlmodelc").path
        let unetChunk2Path = baseURL.appendingPathComponent("UnetChunk2.mlmodelc").path

        let hasUnet = fm.fileExists(atPath: unetPath)
            || (fm.fileExists(atPath: unetChunk1Path) && fm.fileExists(atPath: unetChunk2Path))

        return fm.fileExists(atPath: textEncoderPath)
            && fm.fileExists(atPath: decoderPath)
            && hasUnet
            && fm.fileExists(atPath: vocabPath)
            && fm.fileExists(atPath: mergesPath)
    }

    private func safePathComponent(from path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }

    private func buildUnavailableMessage(searchedPaths: [String]) -> String {
        let pathList = searchedPaths
            .prefix(4)
            .map { "• \($0)" }
            .joined(separator: "\n")
        return """
        Core ML model resources were not found.
        Add a folder named StableDiffusionResources (or StableDiffusion) containing model files.
        Checked paths:
        \(pathList)
        """
    }
}

private final class CoreMLState: @unchecked Sendable {
    var isAvailable = false
    var unavailabilityReason: String?
    var discoveredResourcesURL: URL?
    var preparedResourcesURL: URL?
    var pipeline: StableDiffusionPipeline?
}

private enum CoreMLResourceError: LocalizedError {
    case mixedModelFormats
    case appSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .mixedModelFormats:
            "Detected a mix of .mlmodelc and .mlpackage files. Use one format for all required models."
        case .appSupportUnavailable:
            "Application Support directory is unavailable for compiling model packages."
        }
    }
}
