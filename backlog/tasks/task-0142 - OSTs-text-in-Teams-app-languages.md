---
id: TASK-0142
title: OST's text in Teams' app languages
status: To Do
assignee: []
created_date: '2026-11-15T01:31:00Z'
updated_date: '2026-11-16T04:52:00Z'
labels:
  - desktop
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams offers 109 app languages (Settings ▸ General ▸ Language and regional formats). OST's text is English only, so its App language picker offers only Teams' 16 English locales (00d238b). To match Teams, OST's UI text needs to be available in Teams' other app languages and switch with App language after Save and restart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 App language offers every language Teams lists
- [ ] #2 After Save and restart, OST's own text appears in the chosen language, with Teams' wording for that language
- [ ] #3 Right-to-left languages lay out right to left as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: Teams' full list of 109 app languages is stored, and Save and restart works for regional formats. Missing: only English is offered; no translations and no right-to-left layout. (Audit 2026-11-16)
<!-- SECTION:NOTES:END -->
