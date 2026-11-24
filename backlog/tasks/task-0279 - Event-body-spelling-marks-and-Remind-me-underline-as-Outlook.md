---
id: TASK-0279
title: Event body spelling marks and Remind me underline as Outlook
status: Done
assignee:
  - '@splC'
created_date: '2026-11-24T16:04:00Z'
updated_date: '2026-11-24T17:44:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0277: on a line holding a file link, OST's spelling marks sit slightly lower than Outlook's (the 16 px icon makes Qt's line taller); the event page's Remind me dropdown lacks Outlook's underline.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spelling marks sit where Outlook's do on every line, including lines with file links
- [x] #2 The Remind me dropdown matches Outlook's, underline included
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (splC): measured on winpc (event "splC spell test" with an Outlook Upload-and-share link, Aptos 12pt body): lines 20 tall, baseline 15.33 down, mark rows 16.0–19.33 on every line incl. the link line; the link line is 20.53 tall (icon middle + 2 px bottom padding grows it below only), icon 2.53–18.53. Chromium (text_decoration_offset/info.cc) places the spelling-error wave from the baseline: gap max(1, ceil(t/2)) device px + t + 1 (2.33 CSS at 150 %).
- Remind me: label + dropdown share one 0.67 #F0F0F0 bottom edge (wrapper .oja3y), 39.67 down, 1 px past the dropdown; unchanged on hover/focus/open; Fabric ChevronDown 12 px at width-20; cursor pointer; list "1 hour/day/week before".
- Found: Outlook-saved link entities (styled delimiters, two inner spans) were not recognised by keepBodyParts, so they showed as an 18 px picture (line +2) and would have been saved through Qt; fixed.
- Verified live (OST on linuxlt, ost-test1): marks 1 px under the glyphs on all four lines, link line now 22 like the others, bodyHtml() === bodyAtLoad with the entity intact; reminder underline 30→251 at 39.67 #F0F0F0, chevron, "1 day before".
- Tests (ost-build-splC): lib 967 passed, desktop 38 passed. Commit 871bd0c8 (worktree agent-ac339dfecee5ff14b).
- Test data deleted: the event (Teams Delete), splC-link.txt in OneDrive Attachments (recycle bin), C:\Users\Randy\splC-link.txt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The event page body's spelling marks now sit where Outlook's do on every line, including lines with a file link. The email reminder's Remind me dropdown now matches Outlook's, including its underline. Measured in Teams on winpc on 2026-11-24.

Changes:
- Spelling marks are placed from the word's baseline, as Chromium places its spelling-error decoration: a gap of max(1, ceil(thickness / 2)) device pixels, then the wave's centre thickness + 1 below that (2.33 px at 150 %). Before, they were placed from the line's bottom. The new RichText.spellingMarkLines (richtext.cpp ost_rich_line_ascents and rich_text.rs spelling_mark_centre, with a unit test) gives the position.
- File links: the icon is centred on the line without making it taller, so the text stays where it is, as in Outlook. Outlook's own saved link entity (delimiters carrying the font, two inner spans) is now recognised. Before, it showed as an 18 px picture that made its line 2 px taller, and Qt rewrote it on save. Now it is shown as a chip and saved back unchanged.
- Email reminder: "Remind me:" and its dropdown share one 0.67 #F0F0F0 underline, 39.67 down and 1 px past the dropdown, the same when hovered, focused or open. The chevron is Fabric's thin ChevronDown, 20 px from the end. The dropdown shows a pointer cursor. The list now reads "1 hour before", "1 day before" and "1 week before" (it used to say "1 hours", "1 days" and "1 weeks").
- docs/spec/calendar.md records the measurements.

Tests:
- Live as ost-test1 (OST on linuxlt, Outlook in Teams on winpc), on an event with an Outlook Upload and share link: the marks sit 1 px under the glyphs on all four lines, the link line is the same height as the others, and bodyHtml() matches the body as loaded. The reminder underline, chevron and wording are as in Outlook.
- cargo test --lib: 967 passed. Desktop crate: 38 passed.

Notes: Aptos is not installed on linuxlt, so OST shows the body in Noto Sans (lines 22 px instead of 20). In Outlook, a link line also grows 0.53 px at the bottom; OST does not reproduce that growth.
<!-- SECTION:FINAL_SUMMARY:END -->
