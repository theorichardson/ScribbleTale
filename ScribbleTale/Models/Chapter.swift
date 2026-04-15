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
        case .introduce:  "This is the beginning. Set the scene gently."
        case .complicate: "A small problem appears."
        case .escalate:   "Things get a little harder."
        case .resolve:    "The problem gets solved. A happy ending."
        case .epilogue:   "The story is over. A calm, warm closing."
        }
    }
}

struct BeatPlan: Sendable {
    let beatIndex: Int
    let role: BeatRole

    static func makeSequence(count: Int) -> [BeatPlan] {
        let roles: [BeatRole] = [.introduce, .complicate, .resolve]
        return (0..<count).map { index in
            let role = index < roles.count ? roles[index] : .resolve
            return BeatPlan(beatIndex: index, role: role)
        }
    }
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
            drawingPrompt: "Draw a curious rabbit!",
            imageGenPrompt: "a curious rabbit with bright eyes, children's storybook illustration, warm watercolor, soft edges"
        ),
        .complicate: DrawingChallenge(
            subject: "a locked gate",
            role: "blocks the path forward",
            drawingPrompt: "Draw a locked gate!",
            imageGenPrompt: "a tall wooden gate with a rusty lock, children's storybook illustration, warm watercolor, soft edges"
        ),
        .resolve: DrawingChallenge(
            subject: "a golden key",
            role: "saves the day",
            drawingPrompt: "Draw a golden key!",
            imageGenPrompt: "a glowing golden key, children's storybook illustration, warm watercolor, soft edges"
        ),
        .escalate: DrawingChallenge(
            subject: "a storm cloud",
            role: "makes everything harder",
            drawingPrompt: "Draw a big storm cloud!",
            imageGenPrompt: "a dark swirling storm cloud, children's storybook illustration, warm watercolor, soft edges"
        ),
        .epilogue: DrawingChallenge(
            subject: "a cozy den",
            role: "a safe place to rest",
            drawingPrompt: "Draw a cozy den!",
            imageGenPrompt: "a warm cozy animal den with soft blankets, children's storybook illustration, warm watercolor, soft edges"
        ),
    ]
}

// MARK: - Helpers

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
