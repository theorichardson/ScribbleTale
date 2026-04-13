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
        defer { isGenerating = false }

        var playgroundImage: CGImage?
        var coreMLImage: CGImage?
        var playgroundError: String?
        var coreMLError: String?

        if isPlaygroundAvailable {
            do {
                playgroundImage = try await generateImagePlaygroundImage(from: drawing, prompt: prompt)
            } catch {
                playgroundError = error.localizedDescription
            }
        } else {
            playgroundError = ImageGenerationError.playgroundNotAvailable.errorDescription
        }

        if isCoreMLAvailable {
            do {
                coreMLImage = try coreMLService.generateImage(
                    prompt: prompt,
                    negativePrompt: "deformed, extra limbs, blurry, low quality"
                )
            } catch {
                coreMLError = error.localizedDescription
            }
        } else {
            coreMLError = coreMLStatusMessage ?? ImageGenerationError.coreMLNotAvailable.errorDescription
        }

        return ImageComparisonResult(
            playgroundImage: playgroundImage,
            coreMLImage: coreMLImage,
            playgroundError: playgroundError,
            coreMLError: coreMLError
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

    private func generateImagePlaygroundImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        guard let creator, let style else {
            throw ImageGenerationError.playgroundNotAvailable
        }

        let concepts: [ImagePlaygroundConcept] = [
            .drawing(drawing),
            .text(prompt)
        ]

        for try await result in creator.images(for: concepts, style: style, limit: 1) {
            return result.cgImage
        }

        return nil
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
