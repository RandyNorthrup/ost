---
id: TASK-0077
title: 'Store: Devices tab, See all filter and Manage your apps as Teams'
status: Done
assignee: []
created_date: '2026-11-09T15:00:00Z'
updated_date: '2026-11-20T18:59:00Z'
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
- [x] #1 The Devices tab lists Teams' device collections and devices, measured on winpc
- [x] #2 See all pages offer Teams' collection filter
- [x] #3 Manage your apps in the Store header opens Teams' Manage apps
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10 research:
  - Devices is a header dropdown (Featured, Headsets, Web cameras, Speakerphones, Desk phones & Teams displays, Monitors, Teams Rooms, Room systems accessories, each with an icon). Each opens a commerce page: title and blurb, a filter button, product tiles (image, name, maker, price), and a "USA" region picker with a cart.
  - The catalog comes from a OneCDN source (Marketplace config catalogOneCdnBaseUrl https://res.cdn.office.net/devicescatalog, deviceStoreCatalogCDNHost https://devicescatalog.teams.cdn.office.net; images from devicescatalogimages.teams.cdn.office.net). The file path wasn't found yet: Teams served it from cache, so no request was seen.
  - Manage your apps: header (back, gear icon, "Manage your apps", "Apps" tab); toolbar "+ Get more apps", "Upload an app", Sort, "Find by name"; rows with an expand caret, 32 px icon, name (14 bold), publisher (12 grey) and a ··· menu. Its data API isn't captured yet (also cached).

- 2026-11-20 research (winpc + bundles):
  - Devices catalog: ECS marketplace enableCatalogOneCdn (on): pointer `res.cdn.office.net/devicescatalog/5mttl/pointer` (a date like 2026/11/20), then `…/1httl/<date>/US_en-us/AllDevices` (510 devices: deviceId, deviceName, manufacturerName, shortDescription, thumbnailImage.blobURI, price, collections[], isFeatured, availabilityStatus, certifiedDate…); details `…/<deviceId>`. Off: `devicescatalog.teams.cdn.office.net/catalogdata/US_en-us/AllDevices`.
  - Collections (ECS storeDevicesCollections): featured=24 (isFeatured), headsets 9, webcameras 5, speakerphones 8, deskphones 7, monitors 11, teamsrooms 6, roomsystemsaccessories 10; titles/descriptions from Teams strings; icons Star, Headset, Video, Speaker, DeviceMeetingRoom, Desktop, SurfaceHub, DeviceMeetingRoomRemote. Default sort Availability then entityId as string; 24 per page.
  - Page: back, title 30/36, description 16/22, gray region bar with globe "USA" and cart pill; tiles 239x312 (image 207x160, name 12/16 w600, maker 12/16, price 14/20 bold, short description 2 lines). Its filter offers only an empty "App features" group (Teams quirk).
  - Cart is local (IndexedDB) per market; Checkout opens the fulfiller (UC).
  - App See all filter: popover tree, Availability (Ready to add), Pricing (Free to add / Subscription plans available), Certification (Microsoft 365 certified / Publisher attested), Supported Channel (Shared / Private), App features (Bot, Connector, Agent, Meeting, Messaging, Personal, Tab), only options the page's apps have; selected ones OR'd, shown as brand pills left of the round filter button; features from the definitions (worker KDr).
  - Header right: "Your agents and apps" (library icon) and "Manage your apps" (gear).
  - Manage your apps: GraphQL installedAppsForUser: personal entitlements Installed/AdminPreInstalled/InstalledAndFavorited (+PreConsented) plus apps installed in your teams (`GET {mt}/beta/chats/{team thread}/apps/entitlements`), sorted Recently used (apps usage MRU, updates first) or A-Z / Z-A; rows expand to "Recently used" (i) with Personal app and each team, each with Remove (trash); ··· = View details, Copy link; Upload an app = dialog "Submit an app to your org".

- 2026-11-20 built: api::devices (catalog/collections/details), api::manage_apps (list, uninstall, submit), store_content features for the See all filter, StoreView Devices menu/pages/band/filters/header buttons, DeviceDetailsDialog, DeviceCartDialog (local cart, checkout hosts the Client Store app with TeamsJS marketplace.*), ManageAppsView, "Your agents and apps" page; harnesses --store-devices-test, --store-filter-test, --manage-apps-test; docs/spec/store.md §5–7. Live verification pending.

- 2026-11-20 live (linuxlt, ost-test1; commit 11fdeab on the worktree branch):
  - AC1: --store-devices-test: Devices menu with Teams' 8 collections and icons; Headsets "Keep focused …", 147 devices, first 100 ADAPT 165T USB C II $66.38, 1000, 1004, 1021, 1022, 1026 (= winpc); Featured 24 (1018, 1023, 323, 359 = winpc); band (USA, cart), tiles, filter (App features only), details (3 highlights, 8 specs), Add to cart → View Cart, the cart (Subtotal US $66.38, Checkout), emptied; layouts match winpc within a pixel or two.
  - AC2: --store-filter-test on Popular on Teams: the tree offers exactly Teams' options (Availability: Ready to add; Pricing both; Certification both; Supported Channel both; App features Bot, Connector, Agent, Meeting, Messaging, Personal, Tab); Bot + Free kept 3231/3312, pills shown.
  - AC3: --manage-apps-test: the gear opens Manage your apps (header, toolbar, rows with icons and ···, expand, Sort menu, A-Z, Upload an app dialog). 24 apps vs Teams' 27: Teams also lists SharePoint Pages, Forms and Lists, which neither the personal, shared nor team entitlements return here (source not found yet); MRU order follows the usage service, which differed from Teams' cached order.
  - Not pressed: Checkout (would order), Upload an app ▸ Submit (would submit to the admin), Remove (real apps).

- 2026-11-20 merged as 2c746e0; 817 lib + 29 desktop tests pass on linuxlt. The 3 missing SharePoint rows and the Recently used order moved to TASK-0237.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Store Devices, See all filter and Manage your apps as Teams.

- api::devices reads Microsoft's public device catalog (OneCDN pointer, AllDevices, details); the Devices menu has Teams' 8 collections, pages with the USA region bar and cart, a details dialog and a local cart whose Checkout hosts the fulfiller in TeamsJS.
- See all pages get Teams' filter tree (Availability, Pricing, Certification, Supported Channel, App features), only options present, OR'd, shown as pills.
- The header has Your agents and apps and the Manage your apps gear: ManageAppsView with personal, shared and team apps, sorting, expandable rows, View details / Copy link, Remove and Upload an app.

Verified live against winpc: Headsets (147 devices, same order and prices), Featured (24), details and cart; filter options and Bot + Free (3231/3312); Manage your apps layout. Follow-up TASK-0237 for 3 missing SharePoint rows and the MRU order.
Tests: 817 lib, 29 desktop on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
