import Foundation
import ImagePlayground
import os
import PencilKit
import CoreGraphics

private let log = Logger(subsystem: "com.scribbletale.app", category: "ImageGeneration")

@Observable
@MainActor
final class ImageGenerationService {
    private(set) var isGenerating = false
    private(set) var isPlaygroundAvailable = false
    var isAvailable: Bool { isPlaygroundAvailable }

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

    // MARK: - Availability

    func checkAvailability() async {
        log.info("checkAvailability: starting")

        do {
            let creator = try await ImageCreator()
            let available = creator.availableStyles
            log.info("checkAvailability: ImageCreator OK — availableStyles=\(available.map { String(describing: $0) }, privacy: .public)")
            isPlaygroundAvailable = !available.isEmpty
        } catch {
            log.error("checkAvailability: ImageCreator failed — \(error, privacy: .public)")
            isPlaygroundAvailable = false
        }

        log.info("checkAvailability: done — playground=\(self.isPlaygroundAvailable)")
    }

    private static func preferredStyle(from available: [ImagePlaygroundStyle]) -> ImagePlaygroundStyle? {
        let order: [ImagePlaygroundStyle] = [.sketch, .illustration, .animation]
        for candidate in order where available.contains(candidate) {
            return candidate
        }
        return available.first
    }

    // MARK: - Generation

    func generateImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        log.info("generateImage: starting — prompt=\(prompt, privacy: .public)")
        isGenerating = true
        defer {
            isGenerating = false
            log.info("generateImage: finished")
        }

        guard isPlaygroundAvailable else {
            log.error("generateImage: Image Playground not available")
            throw ImageGenerationError.playgroundNotAvailable
        }

        let creator: ImageCreator
        do {
            creator = try await ImageCreator()
        } catch {
            log.error("generateImage: ImageCreator init failed — \(error, privacy: .public)")
            throw ImageGenerationError.generationFailed
        }

        guard let style = Self.preferredStyle(from: creator.availableStyles) else {
            log.error("generateImage: no available styles")
            throw ImageGenerationError.playgroundNotAvailable
        }

        let sanitizedPrompt = Self.depersonalizePrompt(prompt)
        let strokeCount = drawing.strokes.count
        let bounds = drawing.bounds
        let drawingUsable = strokeCount >= Self.minStrokesForDrawingConcept
            && !bounds.isEmpty
            && bounds.width >= 20
            && bounds.height >= 20

        if sanitizedPrompt != prompt {
            log.info("generateImage: depersonalized \"\(prompt, privacy: .public)\" → \"\(sanitizedPrompt, privacy: .public)\"")
        }
        log.info("generateImage: finalPrompt=\(sanitizedPrompt, privacy: .public), style=\(String(describing: style), privacy: .public), drawingUsable=\(drawingUsable) (strokes=\(strokeCount))")

        if let image = try await attemptGeneration(
            creator: creator, style: style, prompt: sanitizedPrompt,
            drawing: drawing, drawingUsable: drawingUsable
        ) {
            return image
        }

        let safePrompt = Self.ultraSafePrompt(from: sanitizedPrompt)
        log.info("generateImage: retrying with ultra-safe prompt — \(safePrompt, privacy: .public)")
        return try await attemptGeneration(
            creator: creator, style: style, prompt: safePrompt,
            drawing: drawing, drawingUsable: drawingUsable
        )
    }

    /// Strips everything except nouns/adjectives that are clearly non-human,
    /// producing a prompt Image Playground should always accept.
    private static func ultraSafePrompt(from prompt: String) -> String {
        var result = prompt
        let personAdjacentPatterns: [String] = [
            #"\b\d+-\d+\b"#,
            #"\byear.?old\b"#,
            #"\baudience\b"#,
            #"\bstory\b"#,
            #"\btale\b"#,
        ]
        for pattern in personAdjacentPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: ""
            )
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        if result.count < 5 {
            result = "a colorful creature in a magical forest"
        }
        return result
    }

    private func attemptGeneration(
        creator: ImageCreator, style: ImagePlaygroundStyle, prompt: String,
        drawing: PKDrawing, drawingUsable: Bool
    ) async throws -> CGImage? {
        let conceptSets: [([ImagePlaygroundConcept], String)]
        if drawingUsable {
            conceptSets = [
                ([.drawing(drawing), .text(prompt)], "drawing+text"),
                ([.text(prompt)], "text-only"),
            ]
        } else {
            conceptSets = [([.text(prompt)], "text-only")]
        }

        var lastError: Error?
        for (concepts, label) in conceptSets {
            do {
                for try await result in creator.images(for: concepts, style: style, limit: 1) {
                    log.info("generateImage: SUCCESS via '\(label, privacy: .public)'")
                    return result.cgImage
                }
                log.warning("generateImage: '\(label, privacy: .public)' stream completed with no images")
            } catch {
                log.warning("generateImage: '\(label, privacy: .public)' failed — \(error, privacy: .public)")
                lastError = error
                continue
            }
        }

        if let lastError { throw lastError }
        return nil
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
