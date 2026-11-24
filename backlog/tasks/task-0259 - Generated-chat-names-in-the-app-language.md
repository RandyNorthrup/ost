---
id: TASK-0259
title: Generated chat names in the app language
status: Done
assignee:
  - '@calX'
created_date: '2026-11-23T17:40:00Z'
updated_date: '2026-11-23T19:36:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0254: OST now names unnamed group chats from their members as Teams does, but always joins them in English ("A and B", ", +N"). Teams formats the list in the app's language.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Unnamed group chat names use Teams' list wording for the current app language (and, +N), matching Teams in at least English and one other language
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (calX) What Teams does: worker module 99234 `JR(names, count, locale)`: when every chosen name fits, `new Intl.ListFormat(locale).format(names)` (default conjunction, long style) if the result is at most 26 long; 98382 `q` calls it with the localization service's app locale (`ae.locale`; without one the plain ", " join `Yx`). The ", +N" suffix is a literal template (`, +${count}`), not translated; the long title joins with ", ".
- Teams' engine (WebView2 on winpc, read over CDP): en-us "A and B" / "A, B, and C", de-de "A und B" / "A, B und C", fr-fr "A et B", es-es "A y B", ja-jp "A、B、C", zh-tw "A、B和C", ar-sa "A وB وC", he-il "A, B ו-C", sr-latn-rs "A, B i C", en-gb "A, B and C".
- Built: i18n::list_and(items, locale) on ICU4X icu_list (CLDR list patterns, the data Intl.ListFormat uses); generated_title passes the app locale; Hebrew's newer-CLDR non-breaking hyphen is written "-" as Teams' engine does. app_details::list_format (Works in) stays en-us.

- Verified live on linuxlt (ost-calX, spatest = ost-test1, --open-chat-named): English 'OST and OST Test 3' (as Teams on winpc), German app language 'OST und OST Test 3' (Teams' Intl.ListFormat de-de). Tests: lib 935 passed, desktop 36 passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Generated group chat names now join their names in the app language, as Teams does with Intl.ListFormat.

Changes:
- src/i18n.rs: list_and(items, locale), a CLDR conjunction list (ICU4X icu_list, the data behind Intl.ListFormat); en-us when no translated catalogue is in use. Hebrew's newer-CLDR non-breaking hyphen is written "-" as Teams' WebView2 does.
- src/api/chat.rs: generated_title formats the fitting names with the app locale; ", +N" stays untranslated, as in Teams.
- src/api/app_details.rs: list_format uses the same formatter (en-us).
- Cargo: icu_list, icu_locale_core (Unicode-3.0; THIRD-PARTY-NOTICES updated).

Tests: unit tests for de/fr names and the list wording of en-us, en-gb, de-de, es-es, ja-jp, zh-tw, ar-sa, he-il, sr-latn-rs (the values read from Teams' engine over CDP); lib tests 935 passed.
Live (linuxlt, ost-test1): English "OST and OST Test 3" (Teams on winpc shows the same); app language German (LC_ALL=de_DE): "OST und OST Test 3", which is Teams' Intl.ListFormat("de-de") wording.
<!-- SECTION:FINAL_SUMMARY:END -->
