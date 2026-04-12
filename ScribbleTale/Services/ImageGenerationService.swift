import Foundation
import ImagePlayground
import PencilKit
import CoreGraphics

@Observable
@MainActor
final class ImageGenerationService {
    private(set) var isGenerating = false
    private(set) var isAvailable = false

    func checkAvailability() async {
        isAvailable = ImageCreator.isAvailable
    }

    func generateImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        guard isAvailable else {
            throw ImageGenerationError.notAvailable
        }

        isGenerating = true
        defer { isGenerating = false }

        let creator = ImageCreator()
        let concepts: [ImagePlaygroundConcept] = [
            .drawing(drawing),
            .text(prompt)
        ]

        let styles = ImageCreator.availableStyles
        let style = styles.first ?? .animation

        for try await result in creator.images(for: concepts, style: style) {
            return result.cgImage
        }

        return nil
    }
}

enum ImageGenerationError: LocalizedError {
    case notAvailable
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Image generation is not available on this device. Apple Intelligence is required."
        case .generationFailed:
            "Failed to generate image. Please try again."
        }
    }
}
