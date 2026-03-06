---
id: character-story-creation
category: core-flow
priority: critical
timeout: 120
setup: App running at http://localhost:3000
---

# Character & Story Creation Flow

## Description

The player navigates to the app, creates a new character with details, creates a story scenario, sees the adventure begin with content loading, clicks the "Story Outline" tab, and sees the story outline contents displayed in the sidebar.

## Steps

1. Navigate to `http://localhost:3000`
2. Create a new character — fill in character details (name, class/type, any required fields)
3. Create a story scenario — provide scenario details as required by the UI
4. Observe the adventure beginning — content should load and be visible on screen
5. Click the "Story Outline" tab
6. Observe the story outline contents appearing in the sidebar

## Satisfaction Criteria

- **character_created**: A character was successfully created with visible confirmation (name appears, no error messages)
- **story_scenario_created**: A story scenario was created and the app transitioned to the adventure view
- **adventure_content_visible**: The adventure screen shows meaningful content (narrative text, scene description, or equivalent) — not a loading spinner or blank page
- **story_outline_tab_works**: Clicking the "Story Outline" tab triggers a visible response (tab highlights, content area changes)
- **sidebar_shows_outline**: The sidebar displays story outline content (structured text, chapter/scene list, or narrative outline) — not empty or placeholder text

## Anti-Patterns

- Blank or empty content areas where text should appear
- Placeholder text like "Lorem ipsum", "TODO", or "Coming soon"
- Error pages, stack traces, or unhandled exception messages
- Tabs that do not respond to clicks (no visual change, no content swap)
- Infinite loading spinners that never resolve
- Content that is clearly not related to the created character or story
