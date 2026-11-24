---
id: TASK-0277
title: Event page editor extras as Outlook
status: In Progress
assignee:
  - '@edtA'
created_date: '2026-11-24T13:25:00Z'
updated_date: '2026-11-24T15:32:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0274..0276: the Graphics pane's Emoji tab lacks Outlook's category tabs and Stock images shows a grid instead of Outlook's category tiles; inserted file links lose Outlook's file-type icon; inserted stock image (400 px) and sticker (120 px) sizes are not measured; Upload to's Change location and the email reminder's Custom time are not built; Acceptable times for a series doesn't send Outlook's weekday filter; Editor settings are kept on the device and spelling squiggles aren't wired into the event body.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Graphics pane's Emoji and Stock images tabs match Outlook's (categories, tiles) and inserted images and stickers use Outlook's sizes
- [x] #2 Inserted file links keep Outlook's file-type icon
- [x] #3 Upload to's Change location and the email reminder's Custom time work as Outlook
- [x] #4 Acceptable times for a series sends Outlook's weekday filter
- [x] #5 Editor settings are saved where Outlook saves them and the event body shows Editor's spelling marks as Outlook
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (edtA): captured on winpc (CDP network/DOM, Outlook's form in Teams): Emoji category bar (8 tabs incl. more options ▸ Activities, Symbols; each category = content-service search for its name, Smilies/Hand gestures word filters), Stock images' theme tiles (pivots/<id>/themes) searching their name, results grid, stickers 91 x 75.33 cells, empty state; inserted stock image = canvas JPEG q0.5 data URI at natural size with max-width 729px, sticker 100 x 100 PNG data URI; Share link/Upload and share = read-only OWALink entity with the Fluent item-types icon; Upload to ▸ Change location (folder browser, Create new folder); email reminder Custom (date + time pickers, saved as ReminderOffset minutes, each Save saves at once); series Acceptable times = weekday circles and DayOfWeek filters (series days first); Editor settings saved to ows/v1.0/OutlookOptions Proofing/TextPrediction/AutoCorrect (POST then PATCH); body spelling marks are the browser's red wavy line (no AugLoop critiques, no click card).
- Built natively (see commit); OWA service.svc large payloads now go in the request body (an update with pictures failed in the header).

- Verified live (OST on linuxlt as ost-test1, Teams on winpc): Graphics pane categories, Activities via more options, theme tiles, Challenge search, stickers; OST-inserted stock image (729 x 546 shown, JPEG data URI) and sticker (100 x 100 PNG data) and Upload-and-share link (pptx icon on the #FAFAFA chip) saved by OST's Send and shown so in Teams' event page; Change location listed ost-test1's folders, an empty folder's view, uploaded into Attachments; a Custom reminder (8:45 AM) saved by OST listed by Outlook as "Remind me: Wed 11/25/2026 at 8:45 AM"; S1 series Intent from OST (Thu, Tue, Wed, Fri, Sun; three times) read back by Teams' Acceptable times as S T W T F picked; Editor settings saved by OST (Capitalize 'I' and Grammar off) read by a freshly loaded Outlook frame; spelling marks under Edtor, mispelled, wrod, Anothr, tset in OST's body.
- Put back: Editor options (Capitalize 'I', Grammar on; the three option items now exist in the mailbox, a DELETE is refused 403); authoringLanguages untouched.
- Found and fixed: large Outlook action payloads in the header failed (now the body); links with an id were split by Qt's rich text on save (Teams meeting block), now kept whole.
- Commit 3d70b13b (worktree agent-afee19ffce9667321). lib tests 962 passed before the owa_action change; rerun pending (linuxlt went down 15:33 UTC).
<!-- SECTION:NOTES:END -->
