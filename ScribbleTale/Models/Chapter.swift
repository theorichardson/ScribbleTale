import Foundation
import PencilKit
import CoreGraphics

// MARK: - Beat Arc Planning

enum BeatRole: String, Codable, Sendable, CaseIterable {
    case introduce
    case complicate
    case escalate
    case resolve
    case epilogue

    var tonalNote: String {
        switch self {
        case .introduce:  "This is early in the story. Keep tension low. Set the scene."
        case .complicate: "A problem is starting. The object creates as much trouble as it helps."
        case .escalate:   "This is the hardest moment. The protagonist is stuck."
        case .resolve:    "The object solves the problem. The ending should feel earned and satisfying."
        case .epilogue:   "The story is over. Write a calm, warm closing."
        }
    }
}

struct BeatPlan: Sendable {
    let beatIndex: Int
    let role: BeatRole
}

// MARK: - Drawing Challenge

struct DrawingChallenge: Sendable {
    let subject: String
    let role: String
    let drawingPrompt: String
    let imageGenPrompt: String

    static let fallbacks: [BeatRole: DrawingChallenge] = [
        .introduce: DrawingChallenge(
            subject: "a curious rabbit",
            role: "the hero who starts the adventure",
            drawingPrompt: "Draw a curious rabbit ready for an adventure!",
            imageGenPrompt: "A curious rabbit with bright eyes standing on a grassy hill, children's storybook illustration, warm colors, soft edges"
        ),
        .complicate: DrawingChallenge(
            subject: "a locked gate",
            role: "blocks the path forward",
            drawingPrompt: "Draw a locked gate blocking the way!",
            imageGenPrompt: "A tall wooden gate with a rusty lock in a misty forest, children's storybook illustration, warm colors, soft edges"
        ),
        .escalate: DrawingChallenge(
            subject: "a storm cloud",
            role: "makes everything harder",
            drawingPrompt: "Draw a big storm cloud!",
            imageGenPrompt: "A dark swirling storm cloud with rain over a small village, children's storybook illustration, dramatic lighting, soft edges"
        ),
        .resolve: DrawingChallenge(
            subject: "a golden key",
            role: "opens what was locked",
            drawingPrompt: "Draw a golden key that can save the day!",
            imageGenPrompt: "A glowing golden key with intricate patterns, floating in warm light, children's storybook illustration, warm colors, soft edges"
        ),
        .epilogue: DrawingChallenge(
            subject: "a cozy den",
            role: "a safe place to rest after the adventure",
            drawingPrompt: "Draw a cozy den where everyone can rest!",
            imageGenPrompt: "A warm cozy animal den with soft blankets and lantern light, children's storybook illustration, warm colors, soft edges"
        ),
    ]
}

// MARK: - Story Beat (completed turn)

struct StoryBeat: Sendable {
    let beatIndex: Int
    let drawingSubject: String
    let imageCaption: String
    let narrativeBridge: String
}

// MARK: - Narrative State

@Observable
final class NarrativeState: @unchecked Sendable {
    var title: String = ""
    var genre: String = ""
    var setting: String = ""
    var protagonist: String = ""
    var openingText: String = ""

    var storyBeats: [StoryBeat] = []
    var pendingChallenge: DrawingChallenge?
    var currentGap: String = ""
    let beatPlan: [BeatPlan]

    // Per-beat runtime state indexed by beat index
    var drawings: [Int: PKDrawing] = [:]
    var generatedImages: [Int: CGImage] = [:]
    var imageCaptions: [Int: String] = [:]

    init(genre: String, beatCount: Int = 5) {
        self.genre = genre
        self.beatPlan = Self.makeBeatPlan(beatCount: beatCount)
    }

    var currentBeatIndex: Int { storyBeats.count }
    var isComplete: Bool { currentBeatIndex >= beatPlan.count }

    var currentBeatRole: BeatRole? {
        beatPlan[safe: currentBeatIndex]?.role
    }

    func drawing(for beatIndex: Int) -> PKDrawing {
        drawings[beatIndex] ?? PKDrawing()
    }

    func setDrawing(_ drawing: PKDrawing, for beatIndex: Int) {
        drawings[beatIndex] = drawing
    }

    // MARK: - Context Compression

    /// Compressed context string for LLM prompts.
    /// Max 3 prior beats, each trimmed to one sentence, targeting ~150 tokens.
    func compressedContext() -> String {
        var parts: [String] = []

        if !title.isEmpty { parts.append(title + ".") }
        if !setting.isEmpty { parts.append(setting) }
        if !protagonist.isEmpty { parts.append(protagonist) }

        let recentBeats = storyBeats.suffix(3)
        for beat in recentBeats {
            let trimmed = beat.narrativeBridge.trimmedToFirstSentence()
            parts.append("Beat \(beat.beatIndex + 1): \(beat.drawingSubject) — \(trimmed)")
        }

        var result = parts.joined(separator: " ")
        // Hard cap at ~600 characters (~150 tokens)
        if result.count > 600 {
            result = String(result.prefix(600))
        }
        return result
    }

    // MARK: - Beat Plan Factory

    static func makeBeatPlan(beatCount: Int) -> [BeatPlan] {
        let roles: [BeatRole] = [.introduce, .complicate, .escalate, .resolve, .epilogue]
        return (0..<beatCount).map { index in
            let role = index < roles.count ? roles[index] : .epilogue
            return BeatPlan(beatIndex: index, role: role)
        }
    }
}

// MARK: - Helpers

private extension String {
    func trimmedToFirstSentence() -> String {
        let terminators: [Character] = [".", "!", "?"]
        if let idx = self.firstIndex(where: { terminators.contains($0) }) {
            return String(self[...idx])
        }
        return self
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
