import Foundation
import ImagePlayground
import PencilKit
import CoreGraphics

@Observable
@MainActor
final class ImageGenerationService {
    private(set) var isGenerating = false
    private(set) var isAvailable = false
    private var creator: ImageCreator?
    private var style: ImagePlaygroundStyle?

    func checkAvailability() async {
        do {
            let c = try await ImageCreator()
            creator = c
            style = c.availableStyles.first
            isAvailable = style != nil
        } catch {
            isAvailable = false
        }
    }

    func generateImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        guard let creator, let style else {
            throw ImageGenerationError.notAvailable
        }

        isGenerating = true
        defer { isGenerating = false }

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
