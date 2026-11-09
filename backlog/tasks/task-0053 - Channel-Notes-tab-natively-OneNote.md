---
id: TASK-0053
title: Channel Notes tab natively (OneNote)
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-09T15:28:00Z'
labels:
  - notes
  - tabs
dependencies: []
references:
  - docs/spec/notes-tab.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Notes is OneNote's channel notes page, which Teams embeds (docs/spec/notes-tab.md; contentUrl is microsoft365.com/launch/onenote/officeunihost/teams). OST shows a notice instead. Per the 2026-11-07 scope decision (embed what Teams embeds), host it as Teams does: in OST's web view with a TeamsJS host (initialize, getContext, authentication.getAuthToken served from OST's tokens). Loaded without a host, the page stays blank (checked 2026-11-09).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provisioning as Teams (team notebook + channel-named section, the wait screen)
- [ ] #2 Page list, add page, page title/date, page content view and editing through the OneNote API
- [ ] #3 Reload / Expand / Open in new window / App permissions act on the native view as Teams' do
<!-- AC:END -->
