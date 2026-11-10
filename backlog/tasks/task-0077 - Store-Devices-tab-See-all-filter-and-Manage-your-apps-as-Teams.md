---
id: TASK-0077
title: 'Store: Devices tab, See all filter and Manage your apps as Teams'
status: To Do
assignee: []
created_date: '2026-11-09T15:00:00Z'
updated_date: '2026-11-10T17:36:00Z'
labels:
  - desktop
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0076 rebuilt the Store (Home feed, Featured/Categories menus, pages, search) from Teams' data. Teams' Store also has a Devices tab (a device store with its own collections: Featured, Headsets, Web cameras, Speakerphones, Desk phones & Teams displays, Monitors, Teams Rooms), a filter button on See all pages, and the header's Manage your apps.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Devices tab lists Teams' device collections and devices, measured on winpc
- [ ] #2 See all pages offer Teams' collection filter
- [ ] #3 Manage your apps in the Store header opens Teams' Manage apps
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10 research:
  - Devices is a header dropdown (Featured, Headsets, Web cameras, Speakerphones, Desk phones & Teams displays, Monitors, Teams Rooms, Room systems accessories, each with an icon). Each opens a commerce page: title and blurb, a filter button, product tiles (image, name, maker, price), and a "USA" region picker with a cart.
  - The catalog comes from a OneCDN source (Marketplace config catalogOneCdnBaseUrl https://res.cdn.office.net/devicescatalog, deviceStoreCatalogCDNHost https://devicescatalog.teams.cdn.office.net; images from devicescatalogimages.teams.cdn.office.net). The file path wasn't found yet: Teams served it from cache, so no request was seen.
  - Manage your apps: header (back, gear icon, "Manage your apps", "Apps" tab); toolbar "+ Get more apps", "Upload an app", Sort, "Find by name"; rows with an expand caret, 32 px icon, name (14 bold), publisher (12 grey) and a ··· menu. Its data API isn't captured yet (also cached).
<!-- SECTION:NOTES:END -->
