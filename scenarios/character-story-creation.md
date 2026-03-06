---
id: character-story-creation
category: core-flow
priority: critical
timeout: 120
setup: App running at http://localhost:3000
---

# Character & Story Creation Flow

## Description

The player navigates to the app, creates a new character with details, creates a story scenario, sees the adventure begin with a first message generated, clicks the "Story Outline" tab, and sees the story outline contents displayed in the sidebar.

## Steps

1. Navigate to `http://localhost:3000`
2. Create a new character — fill in character details (name, class/type, any required fields)
3. Create a story scenario — provide scenario details as required by the UI
4. Observe the adventure beginning — a first message should be generated and visible on screen
5. Click the "Story Outline" tab
6. Observe the story outline contents appearing in the sidebar

## Satisfaction Criteria

- **character_created**: A character was successfully created with visible confirmation (name appears, no error messages)
- **story_scenario_created**: A story scenario was created and the app transitioned to the adventure view
- **first_message_generated**: After character and story creation, a first message is generated and displayed — this should be narrative text (scene-setting, introduction, or story prompt) that is relevant to the created character and scenario, not a blank area or loading state
- **story_outline_tab_works**: Clicking the "Story Outline" tab triggers a visible response (tab highlights, content area changes)
- **sidebar_shows_outline**: The sidebar displays story outline content (structured text, chapter/scene list, or narrative outline) — not empty or placeholder text

## Anti-Patterns

- Blank or empty content areas where text should appear
- Placeholder text like "Lorem ipsum", "TODO", or "Coming soon"
- Error pages, stack traces, or unhandled exception messages
- Tabs that do not respond to clicks (no visual change, no content swap)
- Infinite loading spinners that never resolve
- Content that is clearly not related to the created character or story
