---
id: TASK-0239
title: SharePoint tab configuration pages draw in OST's app host
status: To Do
assignee: []
created_date: '2026-11-20T18:48:00Z'
updated_date: '2026-11-20T23:11:00Z'
labels:
  - desktop
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In TASK-0191's live check SharePoint's Recommended and Pages lists failed to draw inside OST's embedded browser when configuring a SharePoint tab; Document libraries worked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SharePoint's tab configuration page shows its Recommended, Pages and Document libraries lists in OST as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 found: in Add a tab the picker filled SharePoint's configurationUrl with an empty context, so the dialog framed `https://_layouts/15/TeamsTabConfiguration.aspx` (Chromium's error page). Fix: the picker keeps the template (`https://{teamSiteDomain}{teamSitePath}/…`, tabs::https_template) and TabConfigDialog fills it from the tab's context in both add and Settings mode (homeTemplate), as Settings already did.
- Live (linuxlt, ost-test1, OST Test Team > OST layout test, QTWEBENGINE_REMOTE_DEBUGGING + CDP clicks): Add a tab ▸ SharePoint now frames https://scnetsolutions.sharepoint.com/sites/OSTTestTeam/_layouts/15/TeamsTabConfiguration.aspx; Recommended (Documents, Home, News, Videos), Pages (News, Videos, Home), Lists and Document libraries all draw; picking Documents saved a "Documents" tab (tab::1b6c75f3…, no post). Settings on that tab: Pages, Lists, Document libraries draw; Recommended drew after switching tabs but was empty on first open (no exception logged; still checking Teams' behaviour on winpc). The "appendChild … not of type Node" error from TASK-0191 did not show again.

- Teams on winpc (Settings on the same "Documents" tab): Recommended draws at once. OST's difference was the host's settings.getSettings answer: it returned the configuration page's own address as contentUrl, so SharePoint (opened for an existing tab) had no tab to start from. Fix: TabConfigDialog passes the tab's settings (entityId, contentUrl, websiteUrl, name) and app_host.js answers getSettings with them, as Teams does.
- Live again (linuxlt, ost-test1): Settings on "Documents" now shows Recommended (Documents, Home, News) on first open, like Teams; picking Documents saved through settings.save → the tab's address rewritten (name kept); then the test tab was removed (--tab-settings-remove), channel tabs back to Conversation, Shared, Notes.
<!-- SECTION:NOTES:END -->
