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
    private(set) var isAvailable = false
    private var creator: ImageCreator?
    private var style: ImagePlaygroundStyle?

    private static let minStrokesForDrawingConcept = 3
    private static let maxAttempts = 4
    private static let availabilityRetries = 3
    private static let baseRetryDelay: Duration = .seconds(2)

    /// Word replacements applied to every prompt before sending to Image Playground.
    /// The API throws `conceptsRequirePersonIdentity` for any person-depicting prompt
    /// unless a `.personIdentity` photo reference is provided, which we don't have.
    ///
    /// Phrases are checked first (e.g. "young girl" → "small fox") to avoid
    /// double-adjective glitches like "young young creature".
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

    func checkAvailability() async {
        log.info("checkAvailability: starting (up to \(Self.availabilityRetries) attempts)")

        for attempt in 1...Self.availabilityRetries {
            let start = ContinuousClock.now
            do {
                let c = try await ImageCreator()
                let elapsed = start.duration(to: .now)
                let available = c.availableStyles
                log.info("checkAvailability: ImageCreator init OK in \(elapsed) — availableStyles=\(available.map { String(describing: $0) }, privacy: .public) (attempt \(attempt))")

                creator = c
                style = Self.preferredStyle(from: available)
                isAvailable = style != nil

                if isAvailable {
                    log.info("checkAvailability: ready, selectedStyle=\(String(describing: self.style!), privacy: .public)")
                    return
                } else {
                    log.warning("checkAvailability: ImageCreator init OK but no usable style found in \(available.map { String(describing: $0) }, privacy: .public)")
                }
            } catch {
                let elapsed = start.duration(to: .now)
                log.error("checkAvailability: attempt \(attempt)/\(Self.availabilityRetries) failed in \(elapsed) — \(error, privacy: .public)")
            }
            if attempt < Self.availabilityRetries {
                log.debug("checkAvailability: sleeping 2s before retry")
                try? await Task.sleep(for: .seconds(2))
            }
        }

        isAvailable = false
        log.error("checkAvailability: all \(Self.availabilityRetries) attempts exhausted — isAvailable=false")
    }

    private static func preferredStyle(from available: [ImagePlaygroundStyle]) -> ImagePlaygroundStyle? {
        let order: [ImagePlaygroundStyle] = [.sketch, .illustration]
        for candidate in order where available.contains(candidate) {
            return candidate
        }
        return available.first
    }

    @discardableResult
    private func ensureCreator() async throws -> (ImageCreator, ImagePlaygroundStyle) {
        if let creator, let style {
            log.debug("ensureCreator: reusing existing creator, style=\(String(describing: style), privacy: .public)")
            return (creator, style)
        }

        log.info("ensureCreator: creating fresh ImageCreator")
        let start = ContinuousClock.now
        let fresh = try await ImageCreator()
        let elapsed = start.duration(to: .now)

        creator = fresh
        let available = fresh.availableStyles
        style = Self.preferredStyle(from: available)
        log.info("ensureCreator: created in \(elapsed), availableStyles=\(available.map { String(describing: $0) }, privacy: .public), selectedStyle=\(String(describing: self.style), privacy: .public)")

        guard let resolvedStyle = style else {
            log.error("ensureCreator: no usable style — throwing notAvailable")
            throw ImageGenerationError.notAvailable
        }
        isAvailable = true
        return (fresh, resolvedStyle)
    }

    func generateImage(from drawing: PKDrawing, prompt: String) async throws -> CGImage? {
        let sanitizedPrompt = Self.depersonalizePrompt(prompt)
        let strokeCount = drawing.strokes.count
        let bounds = drawing.bounds
        log.info("""
            generateImage: START
              originalPrompt=\(prompt, privacy: .public)
              sanitizedPrompt=\(sanitizedPrompt, privacy: .public)
              strokes=\(strokeCount), bounds=\(String(describing: bounds), privacy: .public)
              isAvailable=\(self.isAvailable), hasCreator=\(self.creator != nil), hasStyle=\(self.style != nil)
            """)

        if !isAvailable || creator == nil || style == nil {
            log.warning("generateImage: service not ready, attempting ensureCreator")
            do {
                try await ensureCreator()
            } catch {
                log.error("generateImage: ensureCreator failed — \(error, privacy: .public)")
                throw ImageGenerationError.notAvailable
            }
        }

        isGenerating = true
        defer { isGenerating = false }

        let drawingUsable = strokeCount >= Self.minStrokesForDrawingConcept
            && !bounds.isEmpty
            && bounds.width >= 20
            && bounds.height >= 20
        log.info("generateImage: drawingUsable=\(drawingUsable) (strokes=\(strokeCount), w=\(bounds.width, format: .fixed(precision: 1)), h=\(bounds.height, format: .fixed(precision: 1)))")

        var conceptSets: [([ImagePlaygroundConcept], String)] = []
        if drawingUsable {
            conceptSets.append(([.drawing(drawing), .text(sanitizedPrompt)], "drawing+text"))
        }
        conceptSets.append(([.text(sanitizedPrompt)], "text-only"))
        log.info("generateImage: will try \(conceptSets.count) concept set(s): \(conceptSets.map(\.1), privacy: .public)")

        let overallStart = ContinuousClock.now
        var lastError: Error?
        for (concepts, label) in conceptSets {
            log.info("generateImage: trying concept set '\(label, privacy: .public)'")
            let setStart = ContinuousClock.now

            do {
                if let result = try await attemptGeneration(concepts: concepts, label: label) {
                    let totalElapsed = overallStart.duration(to: .now)
                    log.info("generateImage: SUCCESS via '\(label, privacy: .public)' — total elapsed \(totalElapsed)")
                    return result
                } else {
                    let setElapsed = setStart.duration(to: .now)
                    lastError = ImageGenerationError.generationFailed
                    log.warning("generateImage: '\(label, privacy: .public)' returned no results in \(setElapsed)")
                }
            } catch where Self.isPersonIdentityError(error) {
                let setElapsed = setStart.duration(to: .now)
                log.warning("generateImage: '\(label, privacy: .public)' hit conceptsRequirePersonIdentity after \(setElapsed) — will try scene-only fallback")
                lastError = error
            } catch {
                let setElapsed = setStart.duration(to: .now)
                lastError = error
                log.error("generateImage: '\(label, privacy: .public)' threw after \(setElapsed) — \(error, privacy: .public)")
            }
        }

        // Last-resort fallback: strip all character references and describe only the scene/setting
        if Self.isPersonIdentityError(lastError) {
            let sceneFallback = Self.sceneOnlyFallback(from: sanitizedPrompt)
            log.info("generateImage: trying scene-only fallback prompt=\(sceneFallback, privacy: .public)")
            let fallbackStart = ContinuousClock.now
            do {
                if let result = try await attemptGeneration(
                    concepts: [.text(sceneFallback)],
                    label: "scene-fallback"
                ) {
                    let totalElapsed = overallStart.duration(to: .now)
                    log.info("generateImage: SUCCESS via scene-fallback — total elapsed \(totalElapsed)")
                    return result
                }
            } catch {
                let elapsed = fallbackStart.duration(to: .now)
                log.error("generateImage: scene-fallback also failed in \(elapsed) — \(error, privacy: .public)")
                lastError = error
            }
        }

        let totalElapsed = overallStart.duration(to: .now)
        log.error("generateImage: FAILED all concept sets in \(totalElapsed) — last error: \(String(describing: lastError), privacy: .public)")
        throw lastError ?? ImageGenerationError.generationFailed
    }

    /// Rewrites a prompt to describe only the environment/scene, removing any subject references
    /// that could trigger the person identity requirement.
    private static func sceneOnlyFallback(from prompt: String) -> String {
        "A whimsical storybook scene with rolling hills, colorful trees, and a magical sky. Inspired by: \(prompt)"
    }

    private static func isPersonIdentityError(_ error: (any Error)?) -> Bool {
        guard let error else { return false }
        return String(describing: error).contains("conceptsRequirePersonIdentity")
    }

    private func attemptGeneration(concepts: [ImagePlaygroundConcept], label: String) async throws -> CGImage? {
        var lastError: Error?
        var attemptsUsed = 0
        var backgroundRetries = 0

        while attemptsUsed < Self.maxAttempts {
            log.debug("attemptGeneration[\(label, privacy: .public)]: attempt \(attemptsUsed + 1)/\(Self.maxAttempts)")

            let activeCreator: ImageCreator
            let activeStyle: ImagePlaygroundStyle
            do {
                (activeCreator, activeStyle) = try await ensureCreator()
            } catch {
                log.error("attemptGeneration[\(label, privacy: .public)]: ensureCreator failed — \(error, privacy: .public)")
                lastError = error
                attemptsUsed += 1
                if attemptsUsed < Self.maxAttempts {
                    try await Task.sleep(for: Self.baseRetryDelay)
                }
                continue
            }

            let attemptStart = ContinuousClock.now
            do {
                log.info("attemptGeneration[\(label, privacy: .public)]: calling images(for:style:limit:) with style=\(String(describing: activeStyle), privacy: .public)")
                for try await result in activeCreator.images(for: concepts, style: activeStyle, limit: 1) {
                    let elapsed = attemptStart.duration(to: .now)
                    log.info("attemptGeneration[\(label, privacy: .public)]: received image in \(elapsed)")
                    return result.cgImage
                }
                let elapsed = attemptStart.duration(to: .now)
                log.warning("attemptGeneration[\(label, privacy: .public)]: stream completed with no images in \(elapsed)")
                return nil
            } catch is CancellationError {
                log.info("attemptGeneration[\(label, privacy: .public)]: cancelled")
                throw CancellationError()
            } catch where Self.isPersonIdentityError(error) {
                log.warning("attemptGeneration[\(label, privacy: .public)]: conceptsRequirePersonIdentity — not retrying, bubbling up for fallback")
                throw error
            } catch let error as ImageCreator.Error where error == .backgroundCreationForbidden {
                backgroundRetries += 1
                log.warning("attemptGeneration[\(label, privacy: .public)]: backgroundCreationForbidden (bgRetry \(backgroundRetries))")
                lastError = error
                if backgroundRetries >= 3 {
                    attemptsUsed += 1
                    backgroundRetries = 0
                    log.warning("attemptGeneration[\(label, privacy: .public)]: 3 background retries exhausted, counting as attempt \(attemptsUsed)")
                }
                try await Task.sleep(for: .seconds(3))
                continue
            } catch {
                let elapsed = attemptStart.duration(to: .now)
                log.error("attemptGeneration[\(label, privacy: .public)]: attempt \(attemptsUsed + 1)/\(Self.maxAttempts) failed in \(elapsed) — \(error, privacy: .public)")
                lastError = error
                attemptsUsed += 1
                creator = nil
                style = nil
            }

            if attemptsUsed < Self.maxAttempts {
                let backoff = Self.baseRetryDelay * Int(pow(2.0, Double(attemptsUsed - 1)))
                log.debug("attemptGeneration[\(label, privacy: .public)]: sleeping \(backoff) before retry")
                try await Task.sleep(for: backoff)
            }
        }

        log.error("attemptGeneration[\(label, privacy: .public)]: exhausted \(Self.maxAttempts) attempts")
        if let lastError { throw lastError }
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
