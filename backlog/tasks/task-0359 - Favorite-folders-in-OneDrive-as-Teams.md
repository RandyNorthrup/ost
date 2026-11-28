---
id: TASK-0359
title: Favorite folders in OneDrive as Teams
status: Done
assignee:
  - '@t372'
created_date: '2026-11-27T17:48:00Z'
updated_date: '2026-11-28T02:56:00Z'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' OneDrive menus offer Add to favorites for folders as well as files; OST offers it for files only (docs/spec/file-actions.md lists folder favorites under 'Not yet in OST'). Found by the 2026-11-27 recheck of the work page's left-out list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A folder's ··· and right-click menus in OneDrive (and Files) offer Add to favorites / Remove from favorites as Teams does, using the same OneDrive service calls, and favorited folders appear where Teams lists them, verified side by side with Teams desktop
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read OneDrive's favorite command rules and calls (canFavoriteItem, favoriteItems, getFavoritedItems).
2. Offer Add to / Remove from favorites for folders in the menus, the selection bar and the row star; favorite with followedListItems/oneDrive.add by SharePoint ids.
3. List Favorites from GetFavoriteItems, as Teams.
4. Live: favorite a folder from OST, see it in Teams' Favorites and menus, remove it.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- OneDrive (bundle 2026-11-13): canFavoriteItem allows folders (not shortcuts or .url); favoriteItems posts favorites/followedListItems/oneDrive.add with {siteId, webId, listId, listItemUniqueId}; Favorites lists sp.FavoriteItemCollection.GetFavoriteItems?top=500.
- OST: menus, selection bar, row star (kept visible at rest for a favorite, as Teams) offer it for folders; set_favorite uses oneDrive.add/remove for files and folders; Favorites (view and pickers) read GetFavoriteItems; favorite_ids carry Graph and SharePoint ids.
- Live 2026-11-27 (ost-test1): favorited "OST drive test" from OST on linuxlt; Teams on testpc1 then showed Remove from favorites in its menu, the filled star on the row and the folder under Copy to ▸ Favorites ("Location: My Files"); OST's Favorites view lists it. Teams offers no favorites for a shortcut (checked), nor does OST.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Folders can be favorited in OneDrive and Files as in Teams desktop.

- Menus (··· and right-click), the selection bar and the row star follow OneDrive's canFavoriteItem / canUnfavoriteItem: any file or folder except a shortcut or a .url link; a favorite keeps its filled star at rest, as Teams.
- api::drive::set_favorite posts OneDrive's favorites/followedListItems/oneDrive.add (or .remove) with the item's SharePoint ids (site and address as fallback), for files and folders.
- Favorites (the view and the Move/Copy pickers) read sp.FavoriteItemCollection.GetFavoriteItems?top=500 as Teams does; favorite_ids carry Graph and SharePoint ids.
- Spec: docs/spec/file-actions.md "Favorites".

Live (ost-test1, 2026-11-27): favorited "OST drive test" from OST on linuxlt; Teams on testpc1 showed Remove from favorites, the filled star and the folder under Copy to ▸ Favorites; OST's Favorites listed it; removed again.

Tests: drive::tests::favorites_send_onedrive_ids_else_the_address, favorites_read_both_reply_shapes.
<!-- SECTION:FINAL_SUMMARY:END -->
