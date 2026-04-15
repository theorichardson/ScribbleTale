import Foundation

enum StoryModel: String, CaseIterable, Identifiable {
    case gemma3_1B
    case gemma3_4B
    case qwen3_4B_thinking
    case openAI_gpt4oMini

    var id: String { rawValue }

    var isLocal: Bool {
        switch self {
        case .openAI_gpt4oMini: return false
        default: return true
        }
    }

    var modelID: String {
        switch self {
        case .gemma3_1B:         return "mlx-community/gemma-3-1b-it-4bit"
        case .gemma3_4B:         return "mlx-community/gemma-3-4b-it-4bit"
        case .qwen3_4B_thinking: return "mlx-community/Qwen3-4B-Thinking-2507-4bit"
        case .openAI_gpt4oMini:  return "gpt-4o-mini"
        }
    }

    var displayName: String {
        switch self {
        case .gemma3_1B:         return "Gemma 3 1B"
        case .gemma3_4B:         return "Gemma 3 4B"
        case .qwen3_4B_thinking: return "Qwen 3 4B"
        case .openAI_gpt4oMini:  return "GPT-4o mini"
        }
    }

    var subtitle: String {
        switch self {
        case .gemma3_1B:         return "Fast & lightweight"
        case .gemma3_4B:         return "Better quality"
        case .qwen3_4B_thinking: return "Thinking model"
        case .openAI_gpt4oMini:  return "OpenAI cloud"
        }
    }

    var downloadSize: String {
        switch self {
        case .gemma3_1B:         return "~0.8 GB"
        case .gemma3_4B:         return "~2.5 GB"
        case .qwen3_4B_thinking: return "~2.3 GB"
        case .openAI_gpt4oMini:  return "Cloud"
        }
    }

    var icon: String {
        switch self {
        case .gemma3_1B:         return "hare"
        case .gemma3_4B:         return "sparkles"
        case .qwen3_4B_thinking: return "brain.head.profile"
        case .openAI_gpt4oMini:  return "cloud"
        }
    }

    var isThinkingModel: Bool {
        self == .qwen3_4B_thinking
    }
}
