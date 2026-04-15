import Foundation

struct PromptTemplates {

    // MARK: - Blueprint Generation

    static func blueprintSystem(genre: String) -> String {
        "You write simple children's storybooks for ages 3-7. All characters are animals or creatures, never humans. Maximum 3 characters total including the protagonist. Genre: \(genre)."
    }

    static func blueprintUser(genre: String, sceneCount: Int) -> String {
        var prompt = """
        Genre: \(genre)

        Create a simple \(sceneCount)-scene story plan with ONE main character and at most ONE supporting character. Return exactly:
        SETTING: [one sentence, where and when]
        PROTAGONIST: [one sentence, a named animal/creature, who they are and what they want]
        THEME: [2-3 words]
        """
        for i in 1...sceneCount {
            prompt += "\nGOAL_\(i): [one sentence, what happens in scene \(i)]"
        }
        return prompt
    }

    // MARK: - Character Bible Extraction

    static var characterBibleSystem: String {
        "Extract character details from the description. All characters are animals or creatures. Keep descriptions simple for ages 3-7."
    }

    static func characterBibleUser(protagonist: String) -> String {
        """
        Protagonist: \(protagonist)

        Return exactly:
        NAME: [character's first name only]
        SPECIES: [what animal or creature, one word]
        APPEARANCE: [one key visual detail a child would draw, under 6 words]
        PERSONALITY: [2-3 words]
        WANT: [what they want, under 8 words]
        """
    }

    // MARK: - Opening Narrative

    static func openingSystem(genre: String) -> String {
        "You write children's \(genre) stories for ages 3-7. Output ONLY story narrative. Simple, vivid sentences. Animals only, no humans. Max 3 sentences."
    }

    static func openingUser(blueprint: StoryBlueprint, bible: CharacterBible) -> String {
        """
        Write 2-3 opening sentences for a children's story.

        You MUST introduce the main character by name and describe what they look like:
        - Name: \(bible.name)
        - Species: \(bible.species)
        - Appearance: \(bible.appearance)
        - Setting: \(blueprint.setting)

        The opening should tell us who \(bible.name) is, what they look like, and where they are. End with a moment of need or mystery that leads into: \(blueprint.sceneGoals.first ?? "the adventure begins").
        Output ONLY the story sentences.
        """
    }

    // MARK: - Drawing Challenge

    static var challengeSystem: String {
        "You create simple drawing prompts for young children (ages 3-7). The child will draw ONE thing — a single animal, creature, or object. No scenes, no actions, no environments. Keep it very simple."
    }

    static func challengeUser(context: String, beatRole: BeatRole) -> String {
        """
        \(context)

        Pick ONE simple thing for the child to draw — a single animal, creature, or object that fits the story. NOT a scene, NOT an action, NOT multiple things.

        Return exactly:
        SUBJECT: [the thing to draw, 2-4 words, e.g. "a golden key" or "Rosie the robin"]
        ROLE: [one sentence, why it matters in the story]
        DRAWING_PROMPT: [starts with "Draw", under 8 words, e.g. "Draw a golden key!"]
        """
    }

    // MARK: - Image Caption

    static var captionSystem: String {
        "You write short picture captions for a children's storybook. Describe what is shown in the picture. Do NOT advance the plot. Max 1 sentence. Simple words for ages 3-7."
    }

    static func captionUser(context: String) -> String {
        """
        \(context)

        Write ONE short sentence describing this picture. Do NOT continue the story or add new events.
        """
    }

    // MARK: - Narrative Bridge

    static func bridgeSystem(genre: String, tonalNote: String) -> String {
        "You continue a children's \(genre) storybook for ages 3-7. Output ONLY story narrative — no labels, no commentary. Simple words. Animals only. \(tonalNote) Max 3 sentences."
    }

    static func bridgeUser(context: String, isFinalBeat: Bool) -> String {
        var prompt = """
        \(context)

        Continue the story from exactly where it left off. Write 2-3 simple sentences.
        IMPORTANT: Output ONLY the story sentences. Do NOT repeat any context above.
        """
        if !isFinalBeat {
            prompt += "\nAfter the story sentences, on a new line write:\nNEW_GAP: [one sentence, what could appear next]"
        }
        return prompt
    }

    // MARK: - Scene Summary & Continuity (Memory Write)

    static var summarySystem: String {
        "Summarize a story scene into structured memory for the next scene. Be concise."
    }

    static func summaryUser(narrativeText: String, subject: String, entityType: String) -> String {
        """
        Scene text: \(narrativeText)
        Key entity: \(subject) (\(entityType))

        Return exactly:
        SUMMARY: [one sentence summarizing what happened]
        CONTINUITY: [one sentence about what carries forward or what to remember]
        """
    }

    // MARK: - Token Budgets per Model Tier

    struct TokenBudget {
        let blueprint: Int
        let characterBible: Int
        let opening: Int
        let challenge: Int
        let caption: Int
        let bridge: Int
        let summary: Int

        /// Returns the effective maxTokens for a thinking model.
        /// Structured extraction prompts get a small fixed overhead for the
        /// think block; narrative prompts get a proportional boost.
        func thinkingAdjusted(base: Int, isNarrative: Bool) -> Int {
            isNarrative ? base + min(base, 150) : base + 100
        }
    }

    static func budget(for tier: ModelTier) -> TokenBudget {
        switch tier {
        case .small:
            TokenBudget(
                blueprint: 150,
                characterBible: 60,
                opening: 80,
                challenge: 60,
                caption: 30,
                bridge: 80,
                summary: 60
            )
        case .medium:
            TokenBudget(
                blueprint: 200,
                characterBible: 80,
                opening: 100,
                challenge: 80,
                caption: 40,
                bridge: 100,
                summary: 80
            )
        case .large:
            TokenBudget(
                blueprint: 350,
                characterBible: 100,
                opening: 150,
                challenge: 100,
                caption: 50,
                bridge: 150,
                summary: 100
            )
        }
    }
}
