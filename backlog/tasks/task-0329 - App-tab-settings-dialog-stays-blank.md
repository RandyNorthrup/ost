---
id: TASK-0329
title: App tab settings dialog stays blank
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T15:37:00Z'
labels:
  - bug
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The settings dialog of an app tab in a channel or chat stays blank.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 App tab settings open with the app's configuration page as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce: Settings on the channel Notes (OneNote) tab and on a tab Teams offers Settings for
2. Fix the empty dialog
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: the wiki capture forced Settings (tabAction "updateTab", via --tab-settings-test=Notes) on OST Test Team > General's Notes tab (OneNote 0d820ecd). Neither Teams nor OST offers Settings there: Teams shows it only when the app's galleryTabs[0].canUpdateConfiguration is true (docs/spec/channel-tabs.md), OneNote's isn't, so the tab has no config_url and the dialog's page Loader never started -> an empty dialog. No tab in OST Test Team's channels offers Settings today (logged every channel's tabs).
- Real Settings path checked live: added a SharePoint tab ("Documents" library) to OST test channel with the add-tab harness, opened its Settings from the tab: SharePoint's TeamsTabConfiguration page rendered in the dialog (OST Test Team / Any SharePoint site, Recommended, Pages, Lists, Document libraries; Save off until valid), as Teams; the test tab was removed again (--tab-cleanup).
- Fix: TabConfigDialog.startUpdate refuses a tab without a configuration page (no empty dialog can open), and --tab-settings-test logs "TABSETTINGS not offered" and quits when the tab's menu has no Settings.
<!-- SECTION:NOTES:END -->
