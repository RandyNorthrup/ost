# Teams' "Share this file"

Opened from Share in a search file card's ··· (Grid view). Measured on winpc 2026-11-11
(Teams 26288), 1280 x 720 CSS px; layout notes are in `desktop/qml/ShareFileDialog.qml`.

## What it does

- **Add recipients** is Teams' forward-dialog people picker. It calls Substrate's
  `POST /search/api/v1/suggestions?scenario=peoplepicker.newChat` with People, Chat,
  Channel and Team requests (`api::search::recipients_body`) on every keystroke. It lists the
  results in the reply's `LayoutHints.BestMatchSuggestions` order. Teams also lists
  Microsoft 365 groups (with their address); OST leaves those out.
- **A person's second line** is Teams' `description`. It is the sign-in name before "@" in
  capitals (`OST-TEST2`), written `(ALIAS) Job title` when there is a job title. A guest
  shows their e-mail instead. A channel's second line is its team.
- **Access check:** picking a person runs SharePoint's `CheckPermissions`
  (`{"recipients":[{"email":"i:0#.f|membership|<upn>"}]}`, reply `hasAccess`). Anyone who
  can't open the file puts "The recipient can't access this item" and Give access under the
  card head. Teams keeps the bar after a link is chosen; the link only reaches them when the
  message is posted.
- **The link line and Give access** open OneDrive's Link settings on its own (no Back). An
  extra choice, "People currently in this chat", sits third, with no line under it. Apply
  sets the card's link line:
  - "People with existing access can use the link" (the starting choice)
  - "Anyone with the link can edit / view"
  - "People in <org> with the link can …"
  - "Specific people with the link can …" (this chat, and people you choose)
- **Share** first makes the chosen link with `ShareLink`. For this chat the body is
  `{"linkKind":6,"role":2,"restrictShareMembership":true,"scope":2,…}`; SharePoint reuses
  the file's existing chat link if there is one. Share then posts one message to the picked
  chat or channel, or to the person's 1:1 or group chat. The message is the note
  (`<p>…</p>`) plus a `properties.files` entry carrying the link's `shareUrl` / `shareId`
  (`api::files::shared_record`, the record Teams sent). Nobody is added to the link: the
  chat service ("p2p") opens it to the chat. With existing access, the record carries the
  file's own address.
- **··· ▸ Share outside Teams** closes this dialog and opens OneDrive's share dialog
  (`docs/spec/onedrive-share.md`).

## Not yet in OST

- The message box's Format button (Teams' formatting bar); Emoji works.
- Teams lists you ("OST Test 1 (You)") among the people. The suggestions service doesn't
  return you to OST, so OST doesn't.
