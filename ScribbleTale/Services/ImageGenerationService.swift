import Foundation
import os
import PencilKit
import CoreGraphics

private let log = Logger(subsystem: "com.scribbletale.app", category: "ImageGeneration")

@Observable
@MainActor
final class ImageGenerationService {
    let imageProvider: any ImageGenerationProvider
    private let needsDepersonalization: Bool

    var isGenerating: Bool { imageProvider.isGenerating }
    var isAvailable: Bool { imageProvider.isAvailable }
    var isPlaygroundAvailable: Bool { imageProvider.isAvailable }

    init(imageProvider: any ImageGenerationProvider, needsDepersonalization: Bool = true) {
        self.imageProvider = imageProvider
        self.needsDepersonalization = needsDepersonalization
    }

    func checkAvailability() async {
        await imageProvider.checkAvailability()
    }

    func generateImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        let finalPrompt = needsDepersonalization ? Self.depersonalizePrompt(prompt) : prompt
        if finalPrompt != prompt {
            log.info("generateImage: depersonalized prompt for provider")
        }
        return try await imageProvider.generateImage(prompt: finalPrompt, drawing: drawing)
    }

    // MARK: - Prompt depersonalization (Image Playground policy)

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
        (#"\byear.old\b"#, ""),
        (#"\bfamily members?\b"#, "woodland creatures"),
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
        (#"\bbaby\b"#, "tiny bunny"),
        (#"\btoddler\b"#, "small bunny"),
        (#"\bteenager\b"#, "young fox"),
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
        (#"\bmother\b"#, "kind fox"),
        (#"\bfather\b"#, "strong bear"),
        (#"\bparent\b"#, "elder owl"),
        (#"\bparents\b"#, "elder owls"),
        (#"\bsister\b"#, "little fox"),
        (#"\bbrother\b"#, "little bear"),
        (#"\bfamily\b"#, "woodland clan"),
        (#"\baudience\b"#, "gathering"),
        (#"\belderly\b"#, "ancient"),
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
}

enum ImageGenerationError: LocalizedError {
    case playgroundNotAvailable
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .playgroundNotAvailable:
            "Image Playground is not available on this device. Apple Intelligence is required."
        case .generationFailed:
            "Failed to generate image. Please try again."
        }
    }
}
