---
id: TASK-0103
title: Help (F1) as Teams' Help window, with OST's help
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T01:52:00Z'
updated_date: '2026-11-11T02:23:00Z'
labels:
  - help
dependencies: []
documentation:
  - docs/spec/feedback-and-help.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Help window (help.svc.cloud.microsoft) becomes OST's native Help window over bundled Markdown articles in docs/help (spec docs/spec/feedback-and-help.md §4).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 F1, Settings and more > Help, and the Help app open a Help window laid out as Teams' (title row, header with More Help actions: Reload app, About, Share app)
- [x] #2 Help home: Search help, Help for OST, three hero cards, Browse all help (Teams' nine categories), Featured topics, Licence | Privacy footer
- [x] #3 Search finds OST articles; categories list their articles; articles render natively with Was this information helpful? Yes/No (to the feedback forms) and Edit on GitHub
- [x] #4 docs/help holds articles for every category, bundled so Help works offline
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- docs/help: 28 articles in Teams' nine categories (index.md per category), compiled in by desktop/build.rs (OUT_DIR/help_files.rs, src/help_bundle.rs); src/help.rs parses front matter and searches (title > description > text, every word).
- HelpView.qml (Teams' Help app header and help home: Search help, Help for OST, three cards with OST screenshots cropped free of personal data, Browse all help 3x3, Featured topics, Licence | Privacy; category, article with Was this information helpful? Yes/No and Edit on GitHub, search results), HelpWindow.qml (946 x 593 child window). F1 and Settings and more ▸ Help open the window; the Help app shows HelpView in place (no longer support.microsoft.com).
- Verified with --help-test on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help (F1) is Teams' Help with OST's own help.

- docs/help holds 28 articles in Teams' nine categories, with Teams' category descriptions. They're compiled into the app, so Help works offline.
- The Help window and the Help app copy Teams' layout: Search help, Help for OST, three cards, Browse all help, Featured topics, and a Licence | Privacy footer. Categories, articles and search results each have a page.
- Each article ends with "Was this information helpful? Yes / No", which opens Give a compliment or Report a problem with the article named, and an "Edit on GitHub" link.

Tests: help:: unit tests (front matter, categories, search ranking); --help-test on linuxlt (all pages captured).
<!-- SECTION:FINAL_SUMMARY:END -->
