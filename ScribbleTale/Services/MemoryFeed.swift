import Foundation

enum ModelTier: Sendable {
    case small   // 1B models: tight budgets
    case medium  // 4B models: moderate budgets
    case large   // cloud models: generous budgets

    var maxPriorScenes: Int {
        switch self {
        case .small:  2
        case .medium: 3
        case .large:  4
        }
    }

    var maxContextCharacters: Int {
        switch self {
        case .small:  500
        case .medium: 800
        case .large:  1500
        }
    }
}

struct MemoryFeed {

    // MARK: - Scene Generation Context

    static func forSceneGeneration(
        blueprint: StoryBlueprint,
        bible: CharacterBible,
        sceneIndex: Int,
        priorScenes: [SceneRecord],
        tier: ModelTier
    ) -> String {
        var parts: [String] = []

        if sceneIndex < blueprint.sceneGoals.count {
            parts.append("In this scene, \(blueprint.sceneGoals[sceneIndex].lowercased())")
        }

        parts.append("The main character is \(bible.compactDescription)")

        let window = Array(priorScenes.suffix(tier.maxPriorScenes))
        if !window.isEmpty {
            let recaps = window.map { "In scene \($0.sceneIndex + 1), \($0.sceneSummary.lowercased())" }
            parts.append(recaps.joined(separator: " "))
        }

        if let latest = priorScenes.last, !latest.continuityNotes.isEmpty {
            parts.append(latest.continuityNotes)
        }

        let entities = priorScenes.map(\.entityName)
        if !entities.isEmpty {
            parts.append("Characters so far: \(entities.joined(separator: ", ")).")
        }

        return truncate(parts.joined(separator: " "), to: tier.maxContextCharacters)
    }

    // MARK: - Bridge Narrative Context

    static func forBridgeNarrative(
        blueprint: StoryBlueprint,
        bible: CharacterBible,
        sceneIndex: Int,
        subject: String,
        role: String,
        priorScenes: [SceneRecord],
        lastNarrativeText: String,
        tier: ModelTier
    ) -> String {
        var parts: [String] = []

        parts.append("The story takes place in \(blueprint.setting).")
        parts.append("The main character is \(bible.compactDescription)")

        if !lastNarrativeText.isEmpty {
            parts.append("The story so far ends with: \"\(lastNarrativeText)\"")
        }

        if sceneIndex < blueprint.sceneGoals.count {
            parts.append("This scene's goal: \(blueprint.sceneGoals[sceneIndex])")
        }

        parts.append("\(subject) just appeared and \(role).")

        return truncate(parts.joined(separator: " "), to: tier.maxContextCharacters)
    }

    // MARK: - Caption Context

    static func forCaption(
        bible: CharacterBible,
        subject: String,
        role: String,
        setting: String
    ) -> String {
        "The picture shows \(subject) in \(setting). \(bible.name) the \(bible.species) is nearby."
    }

    // MARK: - Challenge Context

    static func forChallenge(
        blueprint: StoryBlueprint,
        bible: CharacterBible,
        sceneIndex: Int,
        priorScenes: [SceneRecord],
        tier: ModelTier
    ) -> String {
        var parts: [String] = []

        if sceneIndex < blueprint.sceneGoals.count {
            parts.append("In this scene, \(blueprint.sceneGoals[sceneIndex].lowercased())")
        }

        parts.append("The main character is \(bible.name) the \(bible.species).")

        let entities = priorScenes.map(\.entityName)
        if !entities.isEmpty {
            parts.append("Do NOT repeat these subjects: \(entities.joined(separator: ", ")).")
        }

        if let latest = priorScenes.last, !latest.continuityNotes.isEmpty {
            parts.append(latest.continuityNotes)
        }

        return truncate(parts.joined(separator: " "), to: tier.maxContextCharacters)
    }

    // MARK: - Image Prompt Enrichment

    static func enrichImagePrompt(
        basePrompt: String,
        bible: CharacterBible,
        priorScenes: [SceneRecord]
    ) -> String {
        var enriched = basePrompt

        if !enriched.lowercased().contains(bible.species.lowercased()) {
            enriched += ". \(bible.name) the \(bible.species) (\(bible.appearance)) is present"
        }

        let styleTag = "storybook illustration, warm watercolor, soft edges"
        if !enriched.lowercased().contains("storybook") {
            enriched += ", \(styleTag)"
        }

        enriched += ". Single clear depiction of the named focus entity, no duplicates."

        return enriched
    }

    // MARK: - Private

    private static func truncate(_ text: String, to maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars))
    }
}
