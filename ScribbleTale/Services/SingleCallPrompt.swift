import Foundation

struct SingleCallPrompt {

    static func system(genre: String) -> String {
        """
        You write children's \(genre) storybooks for ages 3-7. \
        All characters are animals or creatures, never humans. \
        Simple words, vivid scenes, 2-3 sentences per section. \
        Maximum 3 characters total including the protagonist.
        """
    }

    static func user(genre: String, sceneCount: Int) -> String {
        var prompt = """
        Write a complete \(sceneCount)-scene children's \(genre) story. \
        Use the EXACT format below, including all --- delimiters on their own line.

        NAME: [character's first name]
        SPECIES: [one word — what animal or creature]
        APPEARANCE: [one visual detail a child would draw, under 6 words]

        ---INTRO---
        [2-3 sentences. Introduce the character by name, describe them, set the scene.]

        """

        for i in 1...sceneCount {
            prompt += "---DRAW_\(i)---\n"
            prompt += "[starts with \"Draw\", under 8 words, ONE simple thing — a single animal, creature, or object]\n\n"

            if i < sceneCount {
                prompt += "---STORY_\(i)---\n"
                prompt += "[2-3 sentences continuing the story after the child draws]\n\n"
            }
        }

        prompt += "---CONCLUSION---\n"
        prompt += "[2-3 sentences wrapping up the story with a happy, warm ending]"

        return prompt
    }

    static let maxTokens = 600
    static let temperature: Float = 0.7
    static let topP: Float = 0.9
}
