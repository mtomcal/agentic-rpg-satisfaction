---
id: character-story-creation
priority: critical
---

# Character & Story Creation Flow — Judgment Criteria

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
