---
id: TASK-0275
title: 'Event form: Outlook''s remaining switches and editor tools natively'
status: Done
assignee: []
created_date: '2026-11-24T10:07:00Z'
updated_date: '2026-11-24T13:24:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0271: on OST's event page (Outlook's form) these controls are drawn as Teams draws them but don't do what Outlook does yet: Response options' Allow forwarding (missing), Location settings' Rebook declined rooms, the Copilot reschedule switch and Acceptable times, Reminder's Add email reminder and Categories' New category (greyed), and the body toolbar's Attach, emoji, Editor, Loop and accessibility checker (they open Outlook's hosted page). Facilitator's Turn on and Options also go through Outlook's hosted page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Allow forwarding is in Response options and saved as Outlook saves it
- [x] #2 Rebook declined rooms, the Copilot reschedule switch and Acceptable times are saved as Outlook saves them
- [x] #3 Add email reminder and New category work as in Teams
- [x] #4 Attach, emoji, Editor, Loop and the accessibility checker work natively in the body
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (frmY): captured every control on winpc (CDP network log + DOM): Response options, Rebook declined rooms and the Copilot reschedule switch only mark the form changed and go with Send (UpdateCalendarEvent SetItemFields: HideAttendees, DoNotForwardMeeting, CalendarIsResponseRequested, IsRoomRequested, CopilotManagedEventType/Intent/CopilotAutoReschedulingCount/IsDefaultPreferences); email reminders (InboxReminders) and New category (UpdateMasterCategoryList + Categories) save at once; Attach (CreateAttachmentFromLocalFile / DeleteAttachment, OneDrive Share link, Upload and share to OneDrive ▸ Attachments), Graphics pane (emoji, Hubble stock images and stickers), Editor settings dialog, Loop (Attachments/<subject>.loop, embedded link + DocLinks), Accessibility checker pane, Facilitator (facilitator/options POST) and Options (Teams' Meeting options dialog). Details in docs/spec/calendar.md.
- The earlier immediate Graph PATCH of Request responses / Hide attendee list was not Outlook's behaviour: they now go with Send too.
- Built natively: event_form.rs (GetCalendarEvent read, form_updates, InboxReminders, master category, attachments, share/upload links, Hubble pictures, findmeetingtimes); OutlookEmailReminder, OutlookNewCategory, OutlookAcceptableTimes, OutlookFormPane (Graphics / Accessibility checker), OutlookEditorSettings; body attachment chips and the Loop card; Facilitator Turn on/off and Options in MeetingForm.
- Found and fixed: meeting options Apply failed 400 ("An item with the same key has already been added. Key: MeetingsOptions_MeetingSpokenLanguage"): the reply lists MeetingSpokenLanguage twice; post_body now sends each option once (also the in-call dialog).
- Verified live as ost-test1 on linuxlt: Y1 Send with Request responses on, Allow forwarding on, Hide attendee list off, Rebook off (Teams had set the opposite) read back from GetCalendarEvent; T1 Copilot reschedule on with Morning + Custom 10-11 AM: managed 1 and the Intent read back; T1 email reminder (30 min, "frmY OST reminder") added beside Teams' and read back; New category "frmY cat2" created and on T1; a local file attached (chip) and removed; Upload and share and OneDrive Share link put the file's org link in the body; Graphics: emoji, a stock image and stickers listed and inserted; Accessibility checker found the image without alt text; Editor settings dialog (not saved, ost-test1's Editor languages untouched); Loop: Attachments/OST TEST frmY Y1.loop made, Send saved Outlook's embedded link; Facilitator on then off; Options dialog with 29 options, a change applied and put back.

- Commit d74e188d. Tests: lib 957 passed (event_form tests: Intent, Send's updates in Outlook's order, GetCalendarEvent read, suggestions; meeting options once each), desktop 37. Test data deleted: frmY events and mails in all three accounts, OneDrive Attachments test files and Loop files, the two test categories, the winpc and linuxlt test files.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Outlook's event form controls that only looked right now do what Outlook does, natively (captured on winpc 2026-11-24).

Changes:
- Response options: Allow forwarding added; Request responses, Allow forwarding, Hide attendee list, Location settings' Rebook declined rooms and the Copilot reschedule switch (with Acceptable times and Outlook's "Why can't I use this feature?" reasons) mark the form changed and go with Send as Outlook's SetItemFields; the page reads them with GetCalendarEvent (event_form.rs).
- Reminder ▸ Add email reminder: Outlook's Email reminder dialog, saved at once (InboxReminders). Categories ▸ New category: Create new category (25 colours, None), UpdateMasterCategoryList and the event's categories.
- Body toolbar: Attach (Browse this computer → Outlook's CreateAttachmentFromLocalFile, file chips with Preview / Download / Remove attachment; OneDrive Share link; Upload and share to OneDrive ▸ Attachments), the Graphics pane (emoji, stock images, stickers), Editor (Microsoft Editor Settings), Insert Loop component (a Loop component made in Attachments, Outlook's embedded link and DocLinks on Send; an existing one shows as its card) and the Accessibility checker pane (alt text, table headers, contrast).
- Teams meeting row: Facilitator Turn on / Turn off and Options (Teams' Meeting options dialog). Meeting options Apply now sends each option once (it failed with a repeated MeetingSpokenLanguage).
- Harness --cal-page-steps; spec in docs/spec/calendar.md.

Tests:
- Live as ost-test1 (linuxlt) against test events with OST Test 2/3: each control saved and read back from Outlook (see notes).
- cargo test --lib (957), desktop (37).

Follow-ups: none required; text-width-driven positions follow Selawik as noted in TASK-0271.
<!-- SECTION:FINAL_SUMMARY:END -->
