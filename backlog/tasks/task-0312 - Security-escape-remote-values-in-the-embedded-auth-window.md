---
id: TASK-0312
title: 'Security: escape remote values in the embedded auth window'
status: To Do
assignee: []
created_date: '2026-11-25T19:49:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The embedded auth window inserts remotely supplied values into an inline script without escaping them for HTML/JavaScript.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every value placed into injected scripts or HTML is serialized safely (JSON with <, >, &, U+2028/2029 escaped, or passed through WebChannel/messages instead of string building)
- [ ] #2 A test shows a value containing </script>, quotes and newlines can't break out
<!-- AC:END -->
