---
id: TASK-0011
title: Parse meeting/event messages instead of rendering raw JSON
status: Done
assignee:
  - '@claude'
created_date: 2026-02-06 00:06
updated_date: '2026-11-10T15:52:00Z'
labels:
  - bug
  - tui
  - api
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Meeting event messages from Teams API are rendered as raw JSON blobs like {"scopeId":"...","callId":"..."} in the messages pane. These should be parsed and displayed as human-readable meeting cards showing meeting title, time, and status. The "Play" suffix appearing on meeting titles (e.g. "ProjectX Qualification Activities and StatusPlay") should also be cleaned up or displayed as a proper action button label.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Meeting event messages display meeting title, time, and organizer instead of raw JSON
- [x] #2 No raw JSON blobs visible in any channel's message list
- [x] #3 Meeting title does not show a trailing 'Play' suffix as part of the title text
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TUI now reads messages the way the desktop does, so meeting and system messages show as readable text instead of raw markup.

- Messages go through `messages::message_view` (the desktop's reader) instead of stripping tags from raw content. System events get Teams' sentences, cards and calls their text, and nothing shows as raw JSON.
- Meeting recordings (`RichText/Media_CallRecording`) use Teams' words (docs/spec/message-types.md §17): "{name} started recording." / "Recording has started", "Recording stopped. Saving recording…", and for the saved recording "Recording · {meeting title} · {duration} · organizer {name}" (the organizer is resolved by name). The card's "Play" link no longer ends up in the title, as in "…created from OSTPlay".
- Senders keep their old fallbacks (your own name on your messages, else "Unknown"), now in `tui_message`. The unused `sender_name` / `MessagesResponse` and the `from` field were removed.

Tests:
- New `recordings_read_as_teams_words_them`, `senders_as_the_tui_shows_them` and `no_raw_json_or_card_buttons`.
- Live in tmux: OST calendar test shows "Recording · OST calendar test created from OST · 1h 12m 14s · organizer OST Test 1". The OST Test Team channels and the notes chat show no JSON and no "Play".
<!-- SECTION:FINAL_SUMMARY:END -->
