import Foundation
import ImagePlayground
import os
import PencilKit
import CoreGraphics

private let log = Logger(subsystem: "com.scribbletale.app", category: "PlaygroundImageProvider")

@Observable
@MainActor
final class PlaygroundImageProvider: ImageGenerationProvider {
    private(set) var isGenerating = false
    private(set) var isAvailable = false
    private(set) var unavailableReason: String?

    private static let minStrokesForDrawingConcept = 3

    func checkAvailability() async {
        log.info("checkAvailability: starting")
        do {
            let creator = try await ImageCreator()
            let available = creator.availableStyles
            log.info("checkAvailability: ImageCreator OK — availableStyles=\(available.map { String(describing: $0) }, privacy: .public)")
            isAvailable = !available.isEmpty
        } catch {
            log.error("checkAvailability: ImageCreator failed — \(error, privacy: .public)")
            isAvailable = false
        }
        log.info("checkAvailability: done — playground=\(self.isAvailable)")
    }

    func generateImage(prompt: String, drawing: PKDrawing?) async throws -> CGImage? {
        log.info("generateImage: starting — prompt=\(prompt, privacy: .public)")
        isGenerating = true
        defer {
            isGenerating = false
            log.info("generateImage: finished")
        }

        guard isAvailable else {
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

        let drawingUsable: Bool
        if let drawing {
            let strokeCount = drawing.strokes.count
            let bounds = drawing.bounds
            drawingUsable = strokeCount >= Self.minStrokesForDrawingConcept
                && !bounds.isEmpty
                && bounds.width >= 20
                && bounds.height >= 20
        } else {
            drawingUsable = false
        }

        log.info("generateImage: prompt=\(prompt, privacy: .public), style=\(String(describing: style), privacy: .public), drawingUsable=\(drawingUsable)")

        do {
            if let image = try await attemptGeneration(
                creator: creator, style: style, prompt: prompt,
                drawing: drawing ?? PKDrawing(), drawingUsable: drawingUsable
            ) {
                return image
            }
        } catch {
            log.info("generateImage: first attempt failed (\(error, privacy: .public)), will retry with ultra-safe prompt")
        }

        let safePrompt = Self.ultraSafePrompt(from: prompt)
        log.info("generateImage: retrying with ultra-safe prompt — \(safePrompt, privacy: .public)")
        do {
            return try await attemptGeneration(
                creator: creator, style: style, prompt: safePrompt,
                drawing: PKDrawing(), drawingUsable: false
            )
        } catch let error as ImageGenerationError where error == .unsupportedLanguage {
            log.error("generateImage: ultra-safe prompt also rejected as unsupportedLanguage — disabling provider")
            unavailableReason = error.localizedDescription
            isAvailable = false
            throw error
        }
    }

    // MARK: - Private

    private static func preferredStyle(from available: [ImagePlaygroundStyle]) -> ImagePlaygroundStyle? {
        let order: [ImagePlaygroundStyle] = [.sketch, .illustration, .animation]
        for candidate in order where available.contains(candidate) {
            return candidate
        }
        return available.first
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
            } catch let error as ImageCreator.Error where error == .unsupportedLanguage {
                log.warning("generateImage: '\(label, privacy: .public)' failed — unsupportedLanguage (prompt or concept combination rejected by Image Playground, trying next fallback)")
                lastError = ImageGenerationError.unsupportedLanguage
                continue
            } catch {
                log.warning("generateImage: '\(label, privacy: .public)' failed — \(error, privacy: .public)")
                lastError = error
                continue
            }
        }

        if let lastError { throw lastError }
        return nil
    }

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
}
