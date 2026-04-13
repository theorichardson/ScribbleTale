import Foundation
import ImagePlayground
import PencilKit
import CoreGraphics

struct ImageComparisonResult {
    let playgroundImage: CGImage?
    let coreMLImage: CGImage?
    let playgroundError: String?
    let coreMLError: String?
}

@Observable
@MainActor
final class ImageGenerationService {
    private(set) var isGenerating = false
    private(set) var isPlaygroundAvailable = false
    private(set) var isCoreMLAvailable = false
    private(set) var coreMLStatusMessage: String?
    private(set) var coreMLStep = 0
    private(set) var coreMLTotalSteps = 0
    var isAvailable: Bool { isPlaygroundAvailable || isCoreMLAvailable }

    private var creator: ImageCreator?
    private var style: ImagePlaygroundStyle?
    private let coreMLService = CoreMLStableDiffusionService()

    func checkAvailability() async {
        await checkImagePlaygroundAvailability()
        coreMLService.checkAvailability()
        isCoreMLAvailable = coreMLService.isAvailable
        coreMLStatusMessage = coreMLService.unavailabilityReason
    }

    func generateComparisonImages(from drawing: PKDrawing, prompt: String) async -> ImageComparisonResult {
        isGenerating = true
        coreMLStep = 0
        coreMLTotalSteps = 0
        defer { isGenerating = false }

        async let playgroundResult = runPlayground(from: drawing, prompt: prompt)
        async let coreMLResult = runCoreML(prompt: prompt)

        let (pg, cml) = await (playgroundResult, coreMLResult)

        return ImageComparisonResult(
            playgroundImage: pg.image,
            coreMLImage: cml.image,
            playgroundError: pg.error,
            coreMLError: cml.error
        )
    }

    func generateImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        let result = await generateComparisonImages(from: drawing, prompt: prompt)
        if let coreMLImage = result.coreMLImage {
            return coreMLImage
        }
        if let playgroundImage = result.playgroundImage {
            return playgroundImage
        }
        throw ImageGenerationError.generationFailed
    }

    // MARK: - Image Playground

    private func checkImagePlaygroundAvailability() async {
        do {
            let c = try await ImageCreator()
            creator = c
            style = c.availableStyles.first
            isPlaygroundAvailable = style != nil
        } catch {
            isPlaygroundAvailable = false
        }
    }

    private func runPlayground(from drawing: PKDrawing, prompt: String) async -> (image: CGImage?, error: String?) {
        guard isPlaygroundAvailable, let creator, let style else {
            return (nil, isPlaygroundAvailable
                ? ImageGenerationError.generationFailed.errorDescription
                : ImageGenerationError.playgroundNotAvailable.errorDescription)
        }

        do {
            let concepts: [ImagePlaygroundConcept] = [
                .drawing(drawing),
                .text(prompt)
            ]
            for try await result in creator.images(for: concepts, style: style, limit: 1) {
                return (result.cgImage, nil)
            }
            return (nil, ImageGenerationError.generationFailed.errorDescription)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - Core ML Stable Diffusion

    private func runCoreML(prompt: String) async -> (image: CGImage?, error: String?) {
        guard isCoreMLAvailable else {
            return (nil, coreMLStatusMessage ?? ImageGenerationError.coreMLNotAvailable.errorDescription)
        }

        let service = coreMLService
        do {
            let image = try await Task.detached(priority: .userInitiated) {
                try service.generateImage(
                    prompt: prompt,
                    negativePrompt: "deformed, extra limbs, blurry, low quality"
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.coreMLStep = progress.step
                        self?.coreMLTotalSteps = progress.totalSteps
                    }
                }
            }.value
            return (image, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}

enum ImageGenerationError: LocalizedError {
    case playgroundNotAvailable
    case coreMLNotAvailable
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .playgroundNotAvailable:
            "Image Playground is not available on this device. Apple Intelligence is required."
        case .coreMLNotAvailable:
            "Core ML Stable Diffusion resources are missing."
        case .generationFailed:
            "Failed to generate image. Please try again."
        }
    }
}
