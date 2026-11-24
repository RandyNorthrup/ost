---
id: TASK-0191
title: Configurable app tab settings as Teams
status: Done
assignee: []
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T18:59:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' tab menu has Settings for configurable app tabs; OST can't change them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings on a configurable app tab opens the app's configuration and saves it as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 research: Settings (updateTab) shows for an ExtensionTab when the app's galleryTabs[0].canUpdateConfiguration (FileViewTab always; WebsiteTab never with enableDeprecateWebsiteTab), after Rename, needs isAllowedToUpdateTabs. Test tab: SharePoint (2a527703) "OST TEST 191 SharePoint" in OST Test Team > OST test channel (tab::c0579819-47ae-4df5-a4ac-e4217b7fc0cb). Dialog: the config dialog (600 x 602.3, header "<app> settings dialog", the configurationUrl framed 550.7 x 412 at 24.7,93.9), footer Save only (no Back). Save: settings.save → setSettings {contentUrl, suggestedDisplayName, websiteUrl, entityId} → `PUT chatsvc threads/{channel}/properties?name=tab::{id}` with url/websiteUrl/entityId replaced, name and dateAdded kept (suggestedDisplayName ignored), then beforeUnload/load to the content frame.

- 2026-11-20 built (worktree agent-a1c49f721b8083768): tabs.rs AppFlags (canUpdateConfiguration) → "Settings" (updateTab) after Rename; Tab.config_url; TabConfigDialog.startUpdate (600 x 602.3, Save only, the tab's entity, hostTeamThread) saving via saveTab without suggestedDisplayName, then the tab re-framed (Conversation.tabRevision); --tab-settings-test. Live so far: OST menu lists Settings for "OST TEST 191 SharePoint"; dialog drawn; config page first failed to load (no team site in context) → fixed by passing the team thread; re-test pending.

- 2026-11-20 live (linuxlt, ost-test1, --tab-settings-test on "OST TEST 191 SharePoint" in OST Test Team > OST test channel): the menu now matches Teams exactly (Open tab in new window, Expand, Reload, Open in browser, Copy link, | Rename, Settings, About this tab, Move left, Move right, | Remove; a chat-tabs load racing the channel's had dropped the moves — fixed in backend chat_tabs_load); Settings opened SharePoint's TeamsTabConfiguration page (frameContext settings, the team site from the team thread) in the 600 x 602.3 dialog with only Save; picked Document libraries > Documents; Save went settings.save → setSettings → save.success and the tab property was rewritten (entityId sharepointtab_0.2464… → sharepointtab_0.0091…, name kept), the tab re-framed. Open: SharePoint's Recommended and Pages lists throw "appendChild … not of type Node" inside sp-pages-assembly in QtWebEngine (Document libraries works).

- 2026-11-20 merged as 2c746e0. SharePoint's Recommended/Pages lists not drawing moved to TASK-0239.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings on configurable app tabs as Teams: the tab menu shows Settings after Rename when the app allows reconfiguring; it reopens the configuration page in update mode (TabConfigDialog.startUpdate) and Save rewrites the tab's address keeping its name. Also fixed a race that dropped Move left / Move right. Verified live with an OST TEST 191 SharePoint tab (since removed). Follow-up TASK-0239.
<!-- SECTION:FINAL_SUMMARY:END -->
