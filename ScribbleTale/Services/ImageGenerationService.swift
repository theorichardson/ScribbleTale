import Foundation
import ImagePlayground
import os
import PencilKit
import CoreGraphics

private let log = Logger(subsystem: "com.scribbletale.app", category: "ImageGeneration")

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

    private static let minStrokesForDrawingConcept = 3

    // MARK: - Prompt depersonalization

    /// Image Playground throws `conceptsRequirePersonIdentity` for any prompt
    /// depicting people unless a `.personIdentity` photo reference is provided.
    /// Phrases are checked first to avoid double-adjective glitches.
    private static let phraseReplacements: [(pattern: String, replacement: String)] = [
        (#"\byoung boy\b"#, "small fox"),
        (#"\byoung girl\b"#, "small fox"),
        (#"\blittle boy\b"#, "tiny otter"),
        (#"\blittle girl\b"#, "tiny otter"),
        (#"\bsmall child\b"#, "small rabbit"),
        (#"\byoung child\b"#, "young rabbit"),
        (#"\blittle kid\b"#, "tiny squirrel"),
        (#"\byoung man\b"#, "young lion"),
        (#"\byoung woman\b"#, "young fox"),
        (#"\bold man\b"#, "wise owl"),
        (#"\bold woman\b"#, "wise owl"),
        (#"\bbrave hero\b"#, "brave lion"),
        (#"\bevil villain\b"#, "shadowy dragon"),
        (#"\bevil witch\b"#, "dark raven"),
    ]

    private static let wordReplacements: [(pattern: String, replacement: String)] = [
        (#"\bpeople\b"#, "creatures"),
        (#"\bperson\b"#, "creature"),
        (#"\bhuman\b"#, "creature"),
        (#"\bhumans\b"#, "creatures"),
        (#"\bman\b"#, "bear"),
        (#"\bwoman\b"#, "fox"),
        (#"\bboy\b"#, "otter"),
        (#"\bgirl\b"#, "fox"),
        (#"\bchild\b"#, "rabbit"),
        (#"\bchildren\b"#, "rabbits"),
        (#"\bkid\b"#, "squirrel"),
        (#"\bkids\b"#, "squirrels"),
        (#"\bking\b"#, "lion king"),
        (#"\bqueen\b"#, "swan queen"),
        (#"\bprince\b"#, "young stag"),
        (#"\bprincess\b"#, "young swan"),
        (#"\bknight\b"#, "armored bear"),
        (#"\bwarrior\b"#, "fierce wolf"),
        (#"\bhero\b"#, "brave lion"),
        (#"\bheroine\b"#, "brave fox"),
        (#"\bvillain\b"#, "shadowy dragon"),
        (#"\bwitch\b"#, "dark raven"),
        (#"\bwizard\b"#, "wise owl"),
        (#"\bpirate\b"#, "seafaring cat"),
        (#"\bcaptain\b"#, "great eagle"),
        (#"\bfriend\b"#, "companion"),
        (#"\bcharacter\b"#, "creature"),
    ]

    static func depersonalizePrompt(_ prompt: String) -> String {
        var result = prompt
        for (pattern, replacement) in phraseReplacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        for (pattern, replacement) in wordReplacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return result
    }

    // MARK: - Availability

    func checkAvailability() async {
        log.info("checkAvailability: starting")

        do {
            let c = try await ImageCreator()
            let available = c.availableStyles
            log.info("checkAvailability: ImageCreator OK — availableStyles=\(available.map { String(describing: $0) }, privacy: .public)")
            creator = c
            style = Self.preferredStyle(from: available)
            isPlaygroundAvailable = style != nil
        } catch {
            log.error("checkAvailability: ImageCreator failed — \(error, privacy: .public)")
            isPlaygroundAvailable = false
        }

        coreMLService.checkAvailability()
        isCoreMLAvailable = coreMLService.isAvailable
        coreMLStatusMessage = coreMLService.unavailabilityReason
        log.info("checkAvailability: done — playground=\(self.isPlaygroundAvailable), coreML=\(self.isCoreMLAvailable)")
    }

    private static func preferredStyle(from available: [ImagePlaygroundStyle]) -> ImagePlaygroundStyle? {
        let order: [ImagePlaygroundStyle] = [.sketch, .illustration]
        for candidate in order where available.contains(candidate) {
            return candidate
        }
        return available.first
    }

    // MARK: - Generation

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

    private func runPlayground(from drawing: PKDrawing, prompt: String) async -> (image: CGImage?, error: String?) {
        guard isPlaygroundAvailable, let creator, let style else {
            return (nil, ImageGenerationError.playgroundNotAvailable.errorDescription)
        }

        let sanitizedPrompt = Self.depersonalizePrompt(prompt)
        let strokeCount = drawing.strokes.count
        let bounds = drawing.bounds
        let drawingUsable = strokeCount >= Self.minStrokesForDrawingConcept
            && !bounds.isEmpty
            && bounds.width >= 20
            && bounds.height >= 20

        log.info("runPlayground: prompt=\(sanitizedPrompt, privacy: .public), drawingUsable=\(drawingUsable) (strokes=\(strokeCount))")

        let conceptSets: [([ImagePlaygroundConcept], String)]
        if drawingUsable {
            conceptSets = [
                ([.drawing(drawing), .text(sanitizedPrompt)], "drawing+text"),
                ([.text(sanitizedPrompt)], "text-only"),
            ]
        } else {
            conceptSets = [([.text(sanitizedPrompt)], "text-only")]
        }

        for (concepts, label) in conceptSets {
            do {
                for try await result in creator.images(for: concepts, style: style, limit: 1) {
                    log.info("runPlayground: SUCCESS via '\(label, privacy: .public)'")
                    return (result.cgImage, nil)
                }
                log.warning("runPlayground: '\(label, privacy: .public)' stream completed with no images")
            } catch where String(describing: error).contains("conceptsRequirePersonIdentity") {
                log.warning("runPlayground: '\(label, privacy: .public)' hit personIdentity — trying next concept set")
                continue
            } catch {
                log.error("runPlayground: '\(label, privacy: .public)' failed — \(error, privacy: .public)")
                return (nil, error.localizedDescription)
            }
        }

        return (nil, ImageGenerationError.generationFailed.errorDescription)
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
            log.error("runCoreML: failed — \(error, privacy: .public)")
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
