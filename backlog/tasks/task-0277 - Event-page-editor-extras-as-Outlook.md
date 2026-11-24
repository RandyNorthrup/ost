---
id: TASK-0277
title: Event page editor extras as Outlook
status: Done
assignee:
  - '@edtA'
created_date: '2026-11-24T13:25:00Z'
updated_date: '2026-11-24T16:04:00Z'
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

- Tests after the last change (ost-build-edtA): cargo test -j 4 --features audio,video --lib 962 passed; desktop 37 passed.
- Test data deleted: E1, S1, E2 and their mails (ost-test1, OST Test 2), the four edtA files in OneDrive Attachments, the winpc file, all edtA files on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The event page's editor extras now work as Outlook's form in Teams desktop does (captured on winpc 2026-11-24).

Changes:
- Graphics pane: Emoji's category bar (Smilies, Hand gestures, People, Animals, Food, Travel and places, Objects; more options ▸ Activities, Symbols) with each category's emoji from Microsoft's content service (Outlook's Smilies/Hand gestures filters); Stock images' category tiles (the pivot's themes) that search for their name, a search's pictures in Outlook's two columns; stickers in 91 x 75.33 cells; Outlook's empty state. A stock image goes in at its own size up to 729 px and is saved as a JPEG data address at quality 50, a sticker 100 x 100 as its PNG, with alt text and max-width (event_form::graphics, graphics_themes; backend graphicsFile; vfxpicture.cpp ost_picture_to_jpeg).
- File links (Share link, Upload and share) are Outlook's read-only link entity with the Fluent file-type icon (event_form::file_type_icon); the page keeps the entity, data pictures and link ids aside of Qt's rich text and puts them back on save.
- Upload to ▸ Change location (OutlookUploadTo.qml): your OneDrive's folders, the path with Parent folders, an empty folder's view, Create new folder; the file goes to the folder shown (event_form::drive_folders, create_drive_folder, upload_and_share).
- Email reminder ▸ Custom: date and time pickers from the event's start, saved as minutes before; listed as "Wed 11/25/2026 at 9:15 AM"; each Save/Remove saves at once.
- Acceptable times on a series: weekday circles (the series' days kept) and Outlook's DayOfWeek filter in the Intent (event_form::intent_json/parse_intent); turning the switch on starts afresh; the popover flips above the row when needed.
- Microsoft Editor Settings are read from and saved to your Outlook options (Proofing, TextPrediction, AutoCorrect; POST then PATCH, the Grammar/Spelling overrides) (event_form::editor_options, set_editor_options); the body shows spelling marks (Teams' Editor, spelling only) as the browser's red wavy line once focused.
- Fixes: large Outlook action payloads (an update with pictures) go in the request body instead of the X-OWA-UrlPostData header; links with an id (the Teams meeting block) no longer come back from Qt split after their first letter.
- docs/spec/calendar.md: the captured details.

Tests:
- Live as ost-test1 (OST on linuxlt, Teams on winpc): each feature above; OST-sent link, stock image and sticker shown by Teams as Outlook's; OST's custom reminder, series weekdays and Editor settings read back by Outlook/Teams.
- cargo test --lib (962), desktop crate tests; unit tests for graphics answers, series Intent, Editor settings writes.

Notes: the Editor option items Outlook creates can't be deleted (403); their values are back as before. On a line with a file link the spelling marks sit a little lower (Qt's line is taller with the 16 px icon).
<!-- SECTION:FINAL_SUMMARY:END -->
