# StoryGame Data Flow Design

## TL;DR: How data flows to keep the story coherent

- A session starts with a **single blueprint + character bible** generated once and stored in `story_sessions`; this becomes the canonical memory for the full 5-scene arc.
- For each scene, the server generates narrative using accumulated context: **blueprint scene goal + story-so-far summaries + latest continuity notes + character bible**.
- Before accepting a new scene, the server checks prior scene prompts and enforces **drawing prompt uniqueness across the session** (retry generation if needed).
- Each finished scene writes back durable memory to SQLite (`scene_summary`, `continuity_notes`, `entity_name/type`), so the next scene is conditioned on what already happened.
- Child drawings are uploaded and linked to the current scene (`child_drawing_url`), then image generation uses that drawing plus continuity context to preserve **visual and narrative consistency**.
- If the model still repeats a prompt after retries, the server creates a deterministic scene-specific fallback prompt so the child always gets a fresh drawing mission.
- Illustration prompts include the current entity, scene summary, continuity notes, character appearance hints, and prior established entity anchors from earlier generated scenes, so characters/objects/places stay recognizable across chapters.
- Image prompts explicitly include a **no-duplicate-entity rule** (single clear depiction of the named focus entity) to reduce repeated copies in one illustration.
- The loop repeats for 5 scenes, then completion composes a recap from stored scenes; coherence is maintained by this repeated **generate -> persist -> condition next step** cycle.

## Goal of the system

Create a kid-friendly interactive story where each chapter feels like part of one continuous world, even though text and images are generated incrementally.

The architecture accomplishes this by treating each scene as both:

- a user-visible chapter, and
- a memory write for future chapters.

## System components

- **iOS app (**`StoryGame`**)**: SwiftUI screens orchestrated by `StorySessionViewModel` state machine.
- **API server (**`server/src`**)**: Express routes that coordinate generation, persistence, and file handling.
- **Persistence layer**: SQLite (`story_sessions`, `scenes`) + `uploads` directory for drawing and generated art assets.
- **AI services**:
  - Blueprint generator (`blueprintService`)
  - Narrative generator (`narrativeService`)
  - Image generation (`imageService`)

## End-to-end flow

### 1) Session bootstrap establishes narrative memory

1. User chooses a category in app.
2. App calls `POST /api/sessions`.
3. Server generates:
  - Story blueprint (5-scene arc, scene goals, entity-to-draw suggestions)
  - Character bible (traits/appearance memory)
4. Server persists both in `story_sessions`.
5. Server generates scene 0 narrative and prompt.
6. Server inserts scene 0 in `scenes`.
7. App receives `session + firstScene + first narrative/prompt` and transitions to narrative view.

Why this matters for coherence:

- The blueprint prevents scene-by-scene drift by anchoring all scenes to one initial plan.
- Character bible gives a stable source of truth for names/traits/appearance.

### 2) Scene loop writes memory before moving forward

For each scene index `n`:

1. App presents narrative and drawing prompt.
2. Child draws in `PencilKit`; app captures image.
3. App uploads drawing via `POST /sessions/:id/scenes/:n/drawing`.
4. Server stores `child_drawing_url` on that scene row.
5. App requests image generation via `POST /generate-image`.
6. Server loads scene + session continuity context and generates polished art.
7. Server stores `generated_image_url`; app reveals result.
8. User taps next; app calls `POST /advance`.

### 3) Advance endpoint creates next coherent scene

When advancing from scene `n` to `n+1`, server:

1. Reads session-level memory:
  - `story_blueprint_json`
  - `character_bible_json`
2. Reads scene-level memory:
  - `getStorySoFar(sessionId)` (scene summaries/notes in order)
  - `getLatestContinuityNotes(sessionId)`
3. Generates next scene narrative with all of that context.
4. Validates the proposed `drawingPromptText` against prior scene prompts in the same session.
5. If duplicate, retries generation with explicit anti-duplication instruction and prior prompts provided as disallowed context.
6. If still duplicate after retries, synthesizes a scene-specific fallback drawing prompt that is guaranteed unique.
7. Writes new scene row (`n+1`) including:
  - `narrative_text`
  - `drawing_prompt_text`
  - `entity_name/type`
  - `scene_summary`
  - `continuity_notes`
8. Updates session progress (`current_scene_index`).

If `n+1` would exceed scene count (5), it marks session completed and returns recap.

Coherence effect:

- Each advance call reconditions generation on all prior scene memory, so plot progression and references remain aligned with earlier chapters.

## How story coherence is maintained

### Narrative coherence

- **Blueprint constraints**: each scene has a predetermined role in the arc.
- **Story-so-far feed**: previous scene summaries are injected into next narrative generation.
- **Continuity notes propagation**: each scene emits continuity hints for the next.
- **Character bible persistence**: character details survive across all scenes.
- **Prompt de-duplication guardrail**: server compares normalized prompt text against earlier scenes and blocks repeats.

### Illustration coherence

- **Composition grounding**: image generation starts from the child drawing input.
- **Contextual prompting**: prompt includes scene summary and continuity notes.
- **Character appearance hints**: prompt includes character bible appearance data when available.
- **Entity continuity anchors**: backend collects previously generated scene entities (name/type/context) and feeds them back into each new image prompt.
- **No-duplication rule**: prompt tells the model not to produce duplicate copies of named entities and to keep one clear primary depiction of the scene focus.
- **Entity continuity**: scene stores explicit `entityName`/`entityType` used by generation.

### Cross-modal coherence (text <-> image)

- The narrative generator decides scene entity + context.
- Those values are stored in the scene row.
- The image generator reads those same stored values.
- Result: illustrations are generated from the same semantic context that produced the narrative.

## Data model and why it supports coherence

### `story_sessions`

- `id`, `category`, `target_age_band`
- `current_scene_index`
- `story_blueprint_json` (global arc plan)
- `character_bible_json` (global character memory)
- `status`, timestamps

Role: long-lived, session-wide memory.

### `scenes`

- `session_id`, `scene_index`
- `narrative_text`, `drawing_prompt_text`
- `entity_type`, `entity_name`
- `scene_summary`, `continuity_notes`
- `child_drawing_url`, `generated_image_url`
- `created_at`

Role: per-chapter payload plus forward-looking memory.

## API contracts in the coherence loop

- `POST /api/sessions`: create session, seed memory, return first scene.
- `POST /api/sessions/:id/scenes/:idx/drawing`: persist child drawing artifact.
- `POST /api/sessions/:id/scenes/:idx/generate-image`: generate and persist polished scene image using stored continuity and established entity anchors from prior generated scenes.
- `POST /api/sessions/:id/scenes/:idx/advance`: generate next scene using accumulated memory, enforce unique drawing prompt, and update progression.
- `GET /api/sessions/:id`: reconstruct all persisted state for resume/debug.

## State machine alignment in iOS app

Client states map to lifecycle stages:

- `categorySelection` -> no session yet
- `sceneNarrativeVisible` / `drawingPromptVisible` / `drawingInProgress` -> current scene creation
- `imageGenerationInProgress` / `imageReveal` -> illustration production + display
- `storyComplete` -> final recap and gallery from persisted scenes

This explicit state progression keeps API calls ordered and ensures each scene is persisted before the next one is generated.

## Known caveat

There is a moderation module in the backend, but it is not currently wired into narrative/image route handlers. Coherence logic is active; safety currently relies mostly on prompt constraints and model behavior.

## One-line design principle

The app maintains coherence by treating every scene as a checkpoint: generate content from prior memory, persist new memory, then use that updated memory to generate the next chapter and illustration.