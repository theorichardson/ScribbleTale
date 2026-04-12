import SwiftUI

enum StoryType: String, CaseIterable, Identifiable, Codable, Sendable {
    case fantasy = "Fantasy"
    case adventure = "Adventure"
    case celebrity = "Celebrity"
    case friendship = "Friendship"
    case mystery = "Mystery"
    case space = "Space"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fantasy: "wand.and.stars"
        case .adventure: "figure.hiking"
        case .celebrity: "star.fill"
        case .friendship: "heart.fill"
        case .mystery: "magnifyingglass"
        case .space: "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .fantasy: .purple
        case .adventure: .orange
        case .celebrity: .pink
        case .friendship: .red
        case .mystery: .indigo
        case .space: .cyan
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .fantasy: [.purple, .blue]
        case .adventure: [.orange, .yellow]
        case .celebrity: [.pink, .purple]
        case .friendship: [.red, .pink]
        case .mystery: [.indigo, .gray]
        case .space: [.cyan, .blue]
        }
    }

    var tagline: String {
        switch self {
        case .fantasy: "Magic & wonder"
        case .adventure: "Daring quests"
        case .celebrity: "Fame & spotlight"
        case .friendship: "Bonds that last"
        case .mystery: "Clues & secrets"
        case .space: "Beyond the stars"
        }
    }
}
