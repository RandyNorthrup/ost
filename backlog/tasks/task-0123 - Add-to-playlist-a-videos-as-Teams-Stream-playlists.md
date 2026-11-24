---
id: TASK-0123
title: 'Add to playlist (a video''s) as Teams: Stream playlists'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T19:58:00Z'
updated_date: '2026-11-20T15:35:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A video's Add to playlist opens OneDrive's file picker (FilePicker.aspx scenario StreamPlaylist.AddToPlaylist) listing your Stream playlists (personal lists, SP.PersonalListsProxy.GetPersonalListsProxy templateTypeId 3a867b4a-7429-0e1a-b02e-bf4b240ff1ce) under My lists, Recent lists and Favorites. OST Test 1 has no playlist, so the add request couldn't be captured; a test playlist must be made first (Stream on the web). docs/spec/file-actions.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A video's Add to playlist lists your playlists as Teams' picker does
- [x] #2 Picking a playlist adds the video to it as Teams does, verified with a test playlist
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 captured on winpc with "OST TEST 123 clip.mp4" (uploaded) and a playlist made from Teams' own New playlist:
  - Add to playlist opens OneDrive's FilePicker.aspx (scenario StreamPlaylist.AddToPlaylist): "Add to playlist" (20/600), places My lists / Recent lists / Favorites, Quick access, More places...; list Type / Name / Modified (Recent: Accessed), 59-tall rows with the playlist icon; tray New playlist, Done (primary, disabled until a pick), Cancel. Empty: "This folder is empty".
  - Lists: GET {personal}/_api/SP.PersonalListsProxy.GetPersonalListsProxy and {my host}/_api/SP.PersonalListsProxy.GetPersonalListsProxy?templateTypeId='3a867b4a-7429-0e1a-b02e-bf4b240ff1ce'; Recent: {my host}/_api/sp.RecentListProxy.GetRecentListsProxy(?templateTypeId=...); Favorites: sp.FavoriteItemCollection.GetFavoriteItems?top=500.
  - New playlist: GetListDesign / ApplyListDesign() {listDesignId: 3a867b4a-..., store:1, runtimeParameters: {Playlist_listName, Playlist_description, Playlist_color:0, Playlist_addNavLink:false, Playlist_icon:12}} (list at {personal}/Lists/{name}).
  - Add: POST {personal}/_api/web/GetList(@a1)/AddValidateUpdateItemUsingPath() with formValues Thumbnail (v2.0 drive item thumbnails/0/c90x150/content?prefer=noredirect,closestavailablesize&cb={eTag}), Title (name without extension), Owner (person JSON), Duration (HH:MM:SS), VideoIdentifiers ({UniqueId, Id, WebAbsoluteUrl, ListFullUrl, WebDavUrl}), ContentType Item. Notice "Added to the playlist" with View.
  - Teams' picker frame is 720 tall in a 632 frame, so its tray is cut off at 1280x680 (a Teams bug); measured with the frame shortened, then put back.

- 2026-11-20 built: src/api/playlists.rs, PlaylistPicker.qml, FileActions Add to playlist; harness --playlist-test. Test data left: OST TEST 123 clip.mp4 (My files) and the list OST TEST 123 playlist (My lists) — delete both when done.

- 2026-11-20 verified (--playlist-test): My lists shows OST TEST 123 playlist (GetPersonalListsProxy answer: value[] of listTitle/listId/listUrl/siteUrl/lastModifiedDate), Recent/Favorites empty, New playlist form; Done added the clip (checked with Graph: Title, Duration 00:00:06, VideoIdentifiers). Test playlist and clip deleted afterwards.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Add to playlist as Teams (Stream playlists).

- The item menu's Add to playlist opens OneDrive's playlist picker as Teams does: My lists, Recent lists, Favorites, Quick access, More places…, New playlist / Done / Cancel; lists from GetPersonalListsProxy / GetRecentListsProxy, New playlist via Microsoft Lists' form, the add via AddValidateUpdateItemUsingPath with thumbnail, title, owner, duration and the video ids; "Added to the playlist" with View.
- Live: My lists showed the test playlist; Done added the clip (Graph shows the item with title, 00:00:06 and ids). Test playlist and clip deleted.
- Not seen in Teams: what Quick access and More places list (OST shows OneDrive's empty message).
- src/api/playlists.rs, PlaylistPicker.qml, --playlist-test. 815 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
