# Story-Drawing App: Prompt Architecture & Narrative Engine

**Stack:** Gemma 1B (on-device) · Apple Image Playground · Swift / iOS

---

## Core Problem

Gemma 1B is small. At ~1B parameters, it has limited working memory and weak long-range coherence. Left unconstrained, it drifts — generating plausible-sounding sentences that don't connect across turns, and drawing challenges that are vague enough to produce images that don't fit the story.

The solution is not to ask the model to "be coherent." It's to design a data structure that carries coherence externally, and craft prompts that inject only what the model needs for each specific subtask.

---

## Narrative State Object

Every prompt receives a distilled version of this object. It is your source of truth.

```swift
struct NarrativeState {
    let title: String
    let genre: String              // e.g. "fairy tale", "adventure", "mystery"
    let setting: String            // 1 sentence. e.g. "A foggy harbor town at dusk"
    let protagonist: String        // 1 sentence. e.g. "A young girl named Mira who can't sleep"
    let storyBeats: [StoryBeat]    // Ordered. Each beat is one completed turn.
    let pendingDrawingSubject: DrawingChallenge?  // Set during challenge phase
}

struct StoryBeat {
    let beatIndex: Int
    let drawingSubject: String     // What was drawn. e.g. "a brass compass"
    let imageCaption: String       // Caption generated for the image
    let narrativeBridge: String    // 1–2 sentences of story that used the object
}

struct DrawingChallenge {
    let subject: String            // e.g. "a brass compass"
    let role: String               // e.g. "the key to finding the missing ship"
    let drawingPrompt: String      // Shown to user: "Draw a brass compass — it will guide Mira to the ship."
    let imageGenPrompt: String     // Sent to Image Playground
}

```

The model never sees the full history. It sees a **compressed context string** assembled from this object.

---

## Prompt Architecture

There are four distinct prompts. Each is a separate inference call with a single, focused job.

---

### Prompt 1: Story Intro Generation

**When:** App launch / new story.

**Job:** Generate a title, setting, protagonist, and opening paragraph. Also plant a narrative gap — something unresolved that a drawing can later fill.

**Compressed context passed in:** Genre and one optional user preference (e.g. "pirates", "space").

```
SYSTEM:
You are a storyteller writing for children ages 6–10.
Write in simple, vivid sentences. Maximum 3 sentences per paragraph.
Always end with an unresolved situation that needs an object or character to appear.

USER:
Genre: [genre]
Theme hint: [optional user input, or "none"]

Write a story opening. Return exactly this structure:
TITLE: [one evocative title, max 6 words]
SETTING: [one sentence describing where and when]
PROTAGONIST: [one sentence: who they are and what they want]
OPENING: [2–3 sentences of story. End on a moment of need or mystery.]
GAP: [one sentence describing what object or character could resolve the tension — do not include this in the story text]

```

**Parse:** Extract each labeled field. Store into `NarrativeState`. The `GAP` field seeds the first drawing challenge.

---

### Prompt 2: Drawing Challenge Generation

**When:** After intro, and after each completed beat.

**Job:** Take the current narrative gap and turn it into a specific, drawable subject with a clear story role. Generate three outputs: the subject name, a user-facing drawing prompt, and an Image Playground generation prompt.

**Compressed context passed in:** Setting, protagonist, current gap, beat count.

```
SYSTEM:
You are designing a drawing challenge for a child's interactive storybook.
The object or character they draw will appear in the story.
Be specific. "a lantern" is better than "a light source."
Keep the drawing prompt encouraging and under 15 words.

USER:
Setting: [setting]
Protagonist: [protagonist]
Story gap: [gap sentence]
Beat number: [N]

Return exactly this structure:
SUBJECT: [the specific thing to draw, 2–5 words, e.g. "an old brass compass"]
ROLE: [one sentence: how it will matter in the story]
DRAWING_PROMPT: [what to show the user, e.g. "Draw a brass compass — Mira needs it to find the ship!"]
IMAGE_GEN_PROMPT: [prompt for Apple Image Playground, detailed and visual, e.g. "An antique brass compass with a cracked glass face, sitting on weathered wood, storybook illustration style"]

```

**Parse:** Populate `DrawingChallenge`. Show `DRAWING_PROMPT` to user. Send `IMAGE_GEN_PROMPT` to Image Playground after drawing is submitted.

---

### Prompt 3: Image Caption Generation

**When:** After Image Playground returns a generated image.

**Job:** Write a short, story-consistent caption that acknowledges what was drawn and its role. This is the text that appears beneath the image in the storybook view.

**Compressed context passed in:** Setting, protagonist, drawing subject, drawing role, image gen prompt used.

```
SYSTEM:
You are writing a caption for an illustration in a children's storybook.
The caption should sound like it belongs in the book — not like a description.
It should feel like the story is continuing, not pausing to explain.
Maximum 2 sentences. Simple words.

USER:
Setting: [setting]
Protagonist: [protagonist]
What was drawn: [subject]
Its role in the story: [role]

Write the image caption.

```

**No parsing needed.** Raw output is the caption. Trim whitespace, cap at 2 sentences if model overshoots.

---

### Prompt 4: Narrative Bridge Generation

**When:** After caption is shown. Continues the story using the drawn object.

**Job:** Write 2–3 sentences of story that naturally incorporate the drawn object, advance the plot, and plant a new narrative gap for the next beat.

**Compressed context passed in:** Prior beats summary (compressed), current subject and role, beat index.

```
SYSTEM:
You are continuing a children's storybook. Write simply and vividly.
The object just drawn must appear and do something meaningful.
End with a new unresolved moment — something the next drawing will resolve.
Maximum 3 sentences total.

USER:
Story so far (summary): [compressed beat history — see Context Compression below]
Object that just appeared: [subject]
Its role: [role]
Beat number: [N of planned total, e.g. "2 of 4"]

Continue the story. End on a new moment of need or mystery.
Then on a new line write:
NEW_GAP: [one sentence: what object or character could resolve this new tension]

```

**Parse:** Split on `NEW_GAP:`. First part is the narrative bridge text. Second part seeds the next `DrawingChallenge`.

---

## Context Compression

Gemma 1B has a limited context window and poor attention over long inputs. Do not pass the full story. Pass a compressed summary string assembled from `NarrativeState`.

**Format:**

```
[Title]. [Setting]. [Protagonist]. 
Beat 1: [drawingSubject] — [narrativeBridge, trimmed to 1 sentence].
Beat 2: [drawingSubject] — [narrativeBridge, trimmed to 1 sentence].

```

**Rules:**

- Maximum 3 prior beats in context at any time. Drop the oldest if over.
- Each beat summary must fit in one sentence. Truncate `narrativeBridge` at the first period.
- Total compressed context should stay under ~150 tokens.

---

## Story Arc Planning

To prevent drift across 4–6 beats, plan the arc at init time using a simple beat map. This does not require a model call — it's a deterministic template.

```swift
enum BeatRole: String {
    case introduce    // Beat 1: establish subject, low stakes
    case complicate   // Beat 2: use subject to create a problem
    case escalate     // Beat 3: highest tension
    case resolve      // Beat 4: subject is used to solve the core problem
    case epilogue     // Beat 5 (optional): quiet landing
}

struct BeatPlan {
    let beatIndex: Int
    let role: BeatRole
    let tonalNote: String  // Injected into Prompt 4 system message
}

```

**Inject** `tonalNote` **into Prompt 4's system message** depending on beat role:


| BeatRole   | tonalNote injected                                                             |
| ---------- | ------------------------------------------------------------------------------ |
| introduce  | "This is early in the story. Keep tension low. Set the scene."                 |
| complicate | "A problem is starting. The object creates as much trouble as it helps."       |
| escalate   | "This is the hardest moment. The protagonist is stuck."                        |
| resolve    | "The object solves the problem. The ending should feel earned and satisfying." |
| epilogue   | "The story is over. Write a calm, warm closing."                               |


---

## Image Playground Integration

Image Playground takes a text prompt and returns a stylized image. Prompt quality determines how well the image fits the story.

**Prompt construction rules for** `IMAGE_GEN_PROMPT`**:**

1. Always include the subject as the primary noun
2. Add one visual detail (material, age, condition): `"cracked"`, `"glowing"`, `"tiny"`
3. Add one environmental detail derived from `setting`: `"sitting on damp cobblestones"`, `"floating in starlight"`
4. Always append style anchor: `"children's storybook illustration, warm colors, soft edges"`
5. Never include character names or abstract story concepts — Image Playground responds to visual nouns

**Example:**

```
An antique brass compass with a cracked glass face, sitting on weathered dock wood, 
children's storybook illustration, warm colors, soft edges

```

**If Image Playground returns an image that doesn't match:** The caption (Prompt 3) can rescue this. Prompt 3 is written to work from the *intended* subject and role, not from image analysis. The caption narratively frames whatever image was generated as the intended object.

---

## Error Handling & Fallbacks


| Failure Mode                                             | Handling                                                                                           |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Model output missing expected label (e.g. no `SUBJECT:`) | Retry once with temperature lowered by 0.1. If retry fails, use fallback values per beat role.     |
| Caption exceeds 2 sentences                              | Truncate at second period.                                                                         |
| Image Playground returns no image                        | Show drawing with hand-written caption only. Skip image beat, don't break narrative.               |
| Story drifts (protagonist name changes)                  | Always re-inject `protagonist` string at top of every prompt. Never rely on the model to remember. |
| Beat count exceeds plan                                  | Force `resolve` tone on next Prompt 4 call regardless of beat index.                               |


**Fallback subjects by beat role** (used if Prompt 2 parsing fails):

```swift
let fallbackSubjects: [BeatRole: DrawingChallenge] = [
    .introduce:  DrawingChallenge(subject: "a map", role: "shows where to go next", ...),
    .complicate: DrawingChallenge(subject: "a locked door", role: "blocks the path forward", ...),
    .escalate:   DrawingChallenge(subject: "a storm cloud", role: "makes everything harder", ...),
    .resolve:    DrawingChallenge(subject: "a key", role: "opens what was locked", ...),
]

```

---

## Recommended Model Parameters (Gemma 1B)


| Parameter          | Prompt 1–2 | Prompt 3–4 |
| ------------------ | ---------- | ---------- |
| temperature        | 0.8        | 0.65       |
| top_p              | 0.92       | 0.88       |
| max_tokens         | 200        | 120        |
| repetition_penalty | 1.15       | 1.15       |


Lower temperature for Prompts 3–4 because coherence with prior beats matters more than creativity.

---

## Data Flow Summary

```
[App launch]
    → Prompt 1 → NarrativeState (title, setting, protagonist, gap)
    
[Beat N begins]
    → Prompt 2 → DrawingChallenge (subject, role, drawingPrompt, imageGenPrompt)
    → Show drawingPrompt to user
    → User draws
    → Send imageGenPrompt to Image Playground
    → Image Playground returns image
    → Prompt 3 → imageCaption
    → Display image + caption
    → Prompt 4 → narrativeBridge + newGap
    → Append StoryBeat to NarrativeState
    → newGap becomes input for next Prompt 2
    
[Final beat]
    → Prompt 4 with BeatRole.resolve or .epilogue tone
    → No new gap generated
    → Display complete storybook

```

---

## What to Build First

1. `NarrativeState` struct and serialization
2. Prompt 1 + parser → verify title/setting/protagonist/gap extraction is reliable
3. Prompt 2 + parser → test drawing challenge quality across 5 genres
4. Prompt 3 standalone → test caption quality with fixed subject/role inputs
5. Prompt 4 + parser → verify gap extraction and bridge coherence across 3 sequential beats
6. Wire Image Playground to `imageGenPrompt` output
7. Beat arc planner + tonal injection
8. Fallback handling

Test each prompt in isolation before wiring together. Gemma 1B output variance is high — validate parsing robustness with at least 20 samples per prompt before treating it as stable.