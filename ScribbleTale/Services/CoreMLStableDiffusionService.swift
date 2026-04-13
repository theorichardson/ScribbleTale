import Foundation
import CoreGraphics
import CoreML
import StableDiffusion

@MainActor
final class CoreMLStableDiffusionService {
    private(set) var isAvailable = false
    private(set) var unavailabilityReason: String?

    private var resourcesURL: URL?

    func checkAvailability() {
        guard let url = resolveResourcesURL() else {
            isAvailable = false
            unavailabilityReason = """
            Core ML model resources were not found.
            Add a folder named StableDiffusionResources (or StableDiffusion) with converted models.
            """
            resourcesURL = nil
            return
        }

        isAvailable = true
        unavailabilityReason = nil
        resourcesURL = url
    }

    func generateImage(prompt: String, negativePrompt: String = "") throws -> CGImage? {
        guard let resourcesURL else {
            throw ImageGenerationError.coreMLNotAvailable
        }

        var modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .cpuAndNeuralEngine

        let pipeline = try StableDiffusionPipeline(
            resourcesAt: resourcesURL,
            controlNet: [],
            configuration: modelConfig,
            disableSafety: false,
            reduceMemory: true
        )
        try pipeline.loadResources()
        defer { pipeline.unloadResources() }

        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.imageCount = 1
        config.stepCount = 20
        config.guidanceScale = 7.5
        config.schedulerType = .dpmSolverMultistepScheduler
        config.seed = UInt32.random(in: 0...UInt32.max)

        return try pipeline.generateImages(configuration: config).first ?? nil
    }

    private func resolveResourcesURL() -> URL? {
        let fm = FileManager.default
        let bundleURL = Bundle.main.resourceURL
        let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        let candidates = [
            bundleURL?.appendingPathComponent("StableDiffusionResources", isDirectory: true),
            bundleURL?.appendingPathComponent("StableDiffusion", isDirectory: true),
            appSupportURL?.appendingPathComponent("StableDiffusionResources", isDirectory: true),
            appSupportURL?.appendingPathComponent("StableDiffusion", isDirectory: true)
        ]

        for case let url? in candidates where hasRequiredResources(at: url) {
            return url
        }

        return nil
    }

    private func hasRequiredResources(at baseURL: URL) -> Bool {
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
            && hasUnet
            && fm.fileExists(atPath: decoderPath)
            && fm.fileExists(atPath: vocabPath)
            && fm.fileExists(atPath: mergesPath)
    }
}
