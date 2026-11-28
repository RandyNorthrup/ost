---
id: TASK-0379
title: 'OneDrive Copilot pane: knowledge agent tools (code mode) as Teams'
status: To Do
assignee: []
created_date: '2026-11-28T02:13:00Z'
labels:
  - desktop
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-0372 AC#4. With your OneDrive's page context saying isKnowledgeAgentEnabled (ost-test1: true), Teams' OneDrive app sets up OneDrive's knowledge agent in the Copilot pane (Summarize and Ask a question): it answers the page's request-tool-registration with registerRemoteTools (tool schemas its knowledge agent runtime, loaded from the page context's kaToolsUrls, defines), sends updateKnowledgeAgentState {scenario, kaToolsUrls, kaToolsDevMode, webUrl, webTitle, listTitle, sharePointIds, eligibleCodeModePrimitives, currentPivot}, and then runs Copilot's execute_plan tool calls: JavaScript Copilot writes, run in a sandbox against about a hundred code-mode primitives (files.read, email.send, automation.*, …) with codeModePrimitiveProgress and completeToolInvocation (captured on winpc 2026-11-26; docs/spec/onedrive-rows.md "The knowledge agent"). OST hosts chat.aspx but none of that runtime, so it leaves the state out (announcing it without the tools would make Copilot plan calls nobody runs).

Built so far: the Copilot pane (OdspCopilotPane.qml) with Summarize and Ask a question, the messenger, tokens; OST answers request-tool-registration as unsupported.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ask a question and Summarize register OneDrive's knowledge agent tools and send its state as Teams does, when the page context enables it
- [ ] #2 Copilot's execute_plan calls run in a sandbox against the same primitives with Teams' progress and completion messages, checked side by side with Teams desktop
<!-- AC:END -->
