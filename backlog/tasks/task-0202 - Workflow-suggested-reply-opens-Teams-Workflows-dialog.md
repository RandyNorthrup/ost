---
id: TASK-0202
title: Workflow suggested reply opens Teams' Workflows dialog
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-21T03:15:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0170: when the tenant turns workflow suggestions on, Teams opens its Workflows dialog (an embedded page); OST opens the Workflows page in the browser instead. Needs a TeamsJS host (TASK-0053).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The workflow suggestion opens the Workflows dialog in OST, as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (16a17d0): a general TeamsJS dialog host (TaskModuleDialog, dialog.url / tasks.startTask, Teams' size and result/cancel answers). The channel and chat Workflows dialogs run in it; the suggestion opens app 25b07509… "Workflows" 800 × 600 with suggestedAction/{page} and subEntityId as Teams launches it.

Left: the suggestion's page stays blank ("Initial app state does not contain valid QSP", "User ID or Tenant ID is empty"): Teams adds parameters not yet traced. Workflow suggestions are off in this tenant, so Teams' own result can't be seen.

- 2026-11-20 (chat agent), from Teams' code (chat-app 142420 launch; the Workflows page's own JS, saved on linuxlt in ~/loop-scratch/wf):
  - Teams adds nothing to the suggestion's address (theme / locale / ringId filled only). "Initial app state does not contain valid QSP" and "User ID or Tenant ID is empty" are warnings Teams' own launch logs too (the page falls back to app.initialize / getContext).
  - The page waits on its token: `getAuthToken("https://apihub.azure.com")`, first through nested app auth (client a0a3c1d3-7b82-4010-bdb0-e7048fb8f1fe, scope https://apihub.azure.com/.default), else authentication.getAuthToken. It reads page.subPageId (the prefilled inputs), chat.id, locale and user.id.
  - Teams' launch input carries `isMicrosoftOwned: true` and its own validDomains (automations.teams.cloud.microsoft, flow.microsoft.com, preview.flow.microsoft.com, *.consent.azure-apihub.net, *.consent.azure-apim.net, make.powerautomate.com, make.preview.powerautomate.com, make.preprod.powerautomate.com, make.gov.powerautomate.us, make.high.powerautomate.us, make.powerautomate.appsplatform.us); its NAA broker trusts those origins. OST's broker only trusted the catalog definition's domains, so the page never got its token (the blank page).
- Built: TaskModuleDialog/WebApp take the launch's validDomains and isMicrosoftOwned; app_host.js passes them with nestedAppAuth.execute; the backend's "naa" broker trusts a Microsoft-owned launch's domains; openWorkflowDialog passes Teams' list and chatId.

- 2026-11-20 (chatB): checked live on linuxlt (ost-test1, `--task-dialog-test=findmeetingtime --open-chat=<OST group test>`): the Workflows dialog opens (800 x 600, Teams' header, framed, initialize, appLoaded, success) but the form doesn't draw: the Workflows page now throws its own React error "useAutomationConnections must be used within AutomationConnectionsProvider" (after the NAA token path; the earlier blank-on-token cause is gone). Teams' own result can't be seen: workflow suggestions aren't offered in this tenant and there is no tenant setting that turns them on (Teams gates them in ECS); a task-module deep link posted as plain text to ost-test1's notes (OST TEST 202, deleted) isn't linkified, so it couldn't be opened inside Teams either. Open: find what Teams' host provides that this page's AutomationConnectionsProvider needs (likely a host capability or getContext field the page checks before mounting the provider).

- 2026-11-20 merged: the dialog opens with Teams' size and header; the Workflows page now throws 'useAutomationConnections must be used within AutomationConnectionsProvider'. Open: what Teams' host gives that page.

- 2026-11-20 (chatC): found the cause of "useAutomationConnections must be used within AutomationConnectionsProvider". It is the Workflows page's own bug, so it happens in any host, Teams included. Nothing in Teams' host affects it.
  - The page is build 2026102302, the build live at automations.teams.cloud.microsoft today. Its router mounts `/suggestedAction/:suggestedActionId` as `<StrictMode><SuggestedActionWorkflow/></StrictMode>`, with no AutomationConnectionsProvider.
  - The provider (AutomationConnectionsContextProvider-BKI2RLoN.js) is only rendered by the simple editor, settings and agent-operation pages.
  - The Find meeting time and Remind me containers (suggested-action-wrapper-BeVD_89v.js `ye`/`Ce`) call useSaveCopilotActionFromTemplateByMutation (`Er`). `Er` calls useAutomationConnections (`Ht`), which throws when there is no provider.
  - The Create a Planner task container (`Fe`) doesn't call it.
  - Scratch copies of the bundles: chatC/wf/ (index, sa.js, a/*).
- Checked live on linuxlt as ost-test1 with the current build: `--task-dialog-test=createaplanner --open-chat=<OST group test>`.
  - The Workflows dialog draws Teams' form: "New workflow", "Create a Planner task", Action details, Title prefilled "OST test" from the launch's subEntityId, Due date, Back and Create (disabled until a date is set).
  - Host events: framed, initialize, appLoaded, success. Nothing was submitted.
  - So OST's host gives the page what it needs: context, subPageId, the apihub token over NAA, and chat.id. findmeetingtime and remindme stop on the page's own error, as they would inside Teams.
- AC1 met as far as Teams itself can go. If Microsoft fixes the route, the other two forms will draw with no OST change.

- 2026-11-20 merged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Workflow suggested reply opens Teams' Workflows dialog in OST. OST now passes Teams' trusted launch domains so the page gets its token; the dialog opens at Teams' size and header and the Create a Planner task form draws prefilled (verified live, nothing submitted). The Find meeting time and Remind me forms throw "useAutomationConnections must be used within AutomationConnectionsProvider", a bug in the Workflows page (build 2026102302) that fails the same way in Teams.
<!-- SECTION:FINAL_SUMMARY:END -->
