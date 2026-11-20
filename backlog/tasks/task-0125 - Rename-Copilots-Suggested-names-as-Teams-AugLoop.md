---
id: TASK-0125
title: 'Rename: Copilot''s Suggested names as Teams (AugLoop)'
status: To Do
assignee: []
created_date: '2026-11-13T01:56:00Z'
updated_date: '2026-11-20T09:04:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Rename offers Copilot's Suggested names for some files (a .txt, not an .mp4): a folded row that, expanded, asks OneDrive's AugLoop LLM service (llmScenarioGuid f44f84d5-dd13-4369-9939-c8cb945fe62f) for 3 names (docs/spec/file-actions.md). On 2026-11-12 Teams itself answered 'Something went wrong.' for OST Test 1, so the AugLoop exchange could not be captured. Needs: when Teams offers the row, the AugLoop websocket protocol and token, and a working answer to match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rename shows the Suggested names row for the files Teams shows it for, folded and expandable
- [ ] #2 Expanding it asks Copilot as Teams does and shows its three names, the AI notice with thumbs, and Teams' error and Try again
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 captured on winpc: Teams answers now (3 names for ost-share-test.txt; Get new suggestions then gave InsufficientContent: "This file doesn't have enough content to suggest names.").
  - Socket wss://augloop.svc.cloud.microsoft/ (appName odsp, appPlatform Web, releaseAudienceGroup Production, sessionId alproxy_{guid}).
  - SyncMessage with a SignalOperation [Signal, AugLoop_OdspCopilot_ODSPCopilotInputSignal], item "main": {queryId, query = the prompt, isNewConversation, raw false, disableStreaming false, dataSources.dataSources.files [{fileName, siteId, webId, listId, uniqueId}] (braced GUIDs), llmScenarioGuid}. Then the "doc" seed, activation of AugLoop_OdspCopilot_ODSPCopilotOutputAnnotation, the token, and the "context" AugLoop_OdspCopilot_ODSPCopilotScopeContext {searchContext {domains [File], entityConstraints [{@domainType File, ...}]}, selectionContext {File [{name}]}}.
  - Answers stream as annotations: Progress messages, then chatResponse.basinWrite pieces (JSON strings) of the NDJSON; status 13 partial, 0 done.
  - Offered for (OneDrive module 5164): doc docx docm dot dotx dotm xls xlsx xlsm xlt xltx xltm ppt pptx pptm pot potx potm pdf txt rtf csv tsv json md odt ods odp jpg jpeg png bmp tiff tif.

- 2026-11-20 built: src/api/rename_suggestions.rs (OneDrive's AugLoop exchange; live via examples/rename_suggest: 3 names for ost-share-test.txt with OST's own token), FileActions Rename's Suggested names row, harness --rename-suggest-test. Pending: run the harness on linuxlt.

- 2026-11-20 verified on linuxlt (--rename-suggest-test): folded 266.67 tall, loading pills, Copilot's 3 names for ost-share-test.txt, Get new suggestions, a pill into the box; no row for a folder or .mp4.
<!-- SECTION:NOTES:END -->
