import Foundation
import PencilKit
import CoreGraphics

@MainActor
protocol ImageGenerationProvider: AnyObject {
    var isAvailable: Bool { get }
    var isGenerating: Bool { get }
    var unavailableReason: String? { get }

    func checkAvailability() async
    func generateImage(prompt: String, drawing: PKDrawing?) async throws -> CGImage?
}
