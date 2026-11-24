# Feedback and Help (OST's GitHub in Microsoft's place)

Teams sends feedback to Microsoft and opens help on Microsoft's sites. OST
keeps the same entry points, layouts and wording, but sends feedback to the
OST project's GitHub and opens OST's own help. Only the destination changes,
and the text is changed to say so truthfully. Everything below was measured
on winpc against Teams desktop on 2026-11-10. Nothing was submitted.

The destination repo is one setting (`OST_FEEDBACK_REPO`, default
`RandyNorthrup/ost`). An upstream port can point it at its own repo.

## 1. Where feedback and help are reached

| Teams | OST |
|---|---|
| **Settings and more (···)** in the title bar: Unlock Teams Premium, Pin window on top, Settings, Cast, Downloads, the zoom row, **Help (F1)**, **Feedback ▸**, Keyboard shortcuts, Get the mobile app | The same menu gets **Help (F1)** and **Feedback ▸** in Teams' places, with the same icons and keys |
| **Feedback ▸** (229 × 365 menu; submenu 245 × 100): **Report a problem** (Ctrl+Alt+Shift+R), **Give a compliment**, **Suggest a feature** | The same three items and the same shortcut |
| Child windows' ··· (Help window, captions pop-out, post window): Report a problem | Report a problem in OST's child-window menu |
| **"Send feedback 👍 👎"** footers (Find in chat pane, the search results page) | The same footer. 👍 opens Give a compliment, 👎 and "Send feedback" open Report a problem, each with the context filled in (for example "Find in chat: 'OST test', 33 results"). *What Teams' thumbs do wasn't verified, because a click would send a rating to Microsoft.* |
| The **Help** app in the rail's ··· and the Apps flyout | It opens OST's Help window (section 4) instead of support.microsoft.com |

## 2. Report a problem / Give a compliment

Teams opens a child window (786 × 673, title row "Report a problem" or "Give
a compliment") holding Microsoft's form (OCV, admin.microsoft.com/centrohost).
OST builds the same form natively; only the text that names Microsoft changes.

| Teams (measured) | OST |
|---|---|
| H1 "Submit feedback to Microsoft" (20/600, 24 px in, 24 px down) | "Submit feedback to OST" |
| "What did you dislike?" (Report) / "What did you like?" (Compliment), 14 px with a red `*` (#D13438) | Same |
| A textarea, 669.3 × 112, placeholder "Do not include any private or sensitive information." Its underline is brand when focused, and it can be resized | Same |
| "Add more details", then 12 px #616161 "Drag and drop files here or paste an image from your clipboard". **Capture screenshot** (173.7 × 31.3, 20 px icon) and **Attach file** (116.1 × 31.3) | Same. Capture screenshot grabs OST's main window, and the files show as thumbnails with an ×. Dropping files and pasting images also work |
| "Share relevant content samples and additional log files? **Learn more** \*" with **Yes, share** / **No, don't share** (32 px radios, 14 px #616161 labels) | Same. "Learn more" opens the help article "What feedback shares". Yes adds the support log's recent lines (`collect_support_files`), with names and addresses masked |
| "May we contact you about your feedback? \*" with **Yes, you may contact me** / **No, don't contact me** | Same. Yes adds "The reporter is happy to answer questions on this issue." |
| Footer (10 px): "Signed in as {email}. **Learn more** about how this data is used and your rights. By pressing Submit, your feedback will be used to improve Microsoft products and services. **Privacy statement.**" | "Signed in as {email}. **Learn more** about how this data is used and your rights. By pressing Submit, your feedback opens as a **public** issue on GitHub ({repo}) and will be used to improve OST. **Privacy statement.**" The links go to the help article and PRIVACY.md. The address is never put in the issue |
| **Submit** (96 × 31.3, brand; #F0F0F0 / #BDBDBD until the required answers are given) and **Cancel** (96 × 31.3, outline) | Same |

**What Submit does.** It opens GitHub's new-issue page with the matching issue
form (`.github/ISSUE_TEMPLATE/report-a-problem.yml` or
`give-a-compliment.yml`). The form's fields are filled from the URL: the
title (the first line of the text), the text, OST's version, the OS, Qt and
build, the area it came from, the log lines (if shared), and the contact
answer.

GitHub can't take attachments in a URL. So OST copies the first screenshot to
the clipboard and opens the folder holding the other files. Then it shows
Teams' thank-you state, with one line added: "Finish on GitHub: paste your
screenshot (Ctrl+V) and select Create." The reporter submits it on GitHub
themselves; OST never posts anything on its own.

## 3. Suggest a feature

Teams opens the browser on Microsoft's public feedback portal: the
"Microsoft Teams" forum on feedbackportal.microsoft.com (most votes, filters,
Send feedback). OST opens the browser on the repo's **Discussions ▸ Ideas**
category, which works the same way: public ideas with upvotes and official
replies.

## 4. Help (F1)

Teams opens a child window, "Help" (946 × 593). It has the 32 px title row,
then a 61 px header with the Help app icon (32 px, round, 20 px in), "Help"
(18/700, 72 px in), and **More Help actions** ··· (Reload app, About, Share
app). The body is help.svc.cloud.microsoft:

| Teams (measured) | OST |
|---|---|
| A back button (34 px) and Home (42 px) at 97 / 131, then **Search help** (660 × 40, radius 6, 16 px, a search button inside) | Same; the search covers OST's help articles |
| H1 "Help for Microsoft Teams" (22/700, 91.5 px in, 95 px down) | "Help for OST" |
| Three hero cards (229 × 145 picture, title 18/700, a 14 px brand link) | Three OST cards ("Change your background", "Set up notifications", "What's new in OST") with OST's own screenshots |
| "Browse all help" (18/700): a 3 × 3 grid of a 64 px icon, a 14/600 brand link and a 14 px description. The nine are Get started, Chat, Meetings, Teams & channels, Notifications & settings, Calls & devices, Files, Apps & services, Troubleshoot | The same nine categories with the same descriptions where they hold for OST. Each opens a list of OST articles |
| "Featured topics" (18/700): six links in a 3 × 2 grid | Six OST articles (Change your status, Record a meeting, Share your screen, Delete a chat, Manage notifications, Report a problem) |
| Footer: Terms \| Privacy & Cookies \| Consumer Health Privacy (12 px) | Licence \| Privacy (the repo's LICENSE and PRIVACY.md) |
| Category and article pages (support.microsoft.com) | Articles are Markdown in `docs/help/`, bundled into the app (they work offline) and shown natively. Each has "Was this information helpful? Yes / No" leading to the feedback forms, and "Edit on GitHub" |

The Help app in the rail and the Apps flyout opens the same Help content in
place.

## 5. Calls

Teams sometimes asks for call quality after a call ("How was the call
quality?"). OST asks the same, as an opt-in in Settings > Privacy (the
Surveys card's "Ask me about call quality after calls", off by default,
kept on this device; usable while Surveys is on, as Teams asks only then).

What Teams does (its CQF bundle, read 2026-11-18; the survey measured on
winpc 2026-11-11): it samples calls (`samplingRatesForCQF` on desktop: 1:1,
group, meeting and screen share from chat 0.1; PSTN and interop 0) and
skips the test call and calls under 5 s (8 s for a meeting). The live
style is ThumbsCombined: "How was the call quality?" with Had issues
(rating 1) and Good (rating 5). Good is sent at once and "Thanks for the
feedback!" shows for 3 s. Had issues shows "What could've been better?"
with the categories Audio (8 call items and the 2 reliability ones),
Video (8) and Screenshare (8), both the categories and their items
shuffled, the reasons as checkboxes in two columns, "Privacy statement",
Dismiss and Send feedback. An unanswered survey goes after 60 s.

Measured live in Teams desktop 2026-11-18 (its sampling forced over CDP for a solo Meet now): one page on #F5F5F5 — "How was the call quality?" (28/700, line 40, #424242), the two thumbs (61.33 squares, 0.67 #D1D1D1, radius 4, transparent; 50 px emoticons 5.67 in; 10.14 apart) with "Had issues" / "Good" (14/20 #252423) under them, then, 24 under, a 580-wide group: "What could've been better?" (14/20 #242424) with the category tabs beside it (radios 28.67 tall, padding 5 12, a 16 px Call / Share screen / Video glyph, 12/600 #424242, the selected one underlined 2 px #5B5FC7), the reasons in two 282-wide columns 16 apart (rows 32, 52 when wrapped; a 16 px box, 0.67 #616161, radius 2; labels 14/20 #616161), the privacy line (10/14 #424242: "By pressing \"Send Feedback\" to Microsoft, your feedback will be used to improve Microsoft products and services. Your IT admin will be able to collect this data. Privacy statement"), and Dismiss / Send feedback at the right (15 apart). OST says instead that Send feedback opens Report a problem for a public GitHub issue and nothing is sent before.

OST (`calling::quality_survey`, `CallQualitySurvey.qml`): the same pages,
sampling and shuffles. Good sends nothing anywhere. Send feedback opens
Report a problem (area "Call quality") with the reasons as its text and the
call's technical details in its details: the kind of call, its length,
the reasons' ids and the Call health values at the end (network, audio,
video and sharing: round trip, loss, jitter, bit rates, codecs,
resolutions); never anyone's name. The reporter submits it on GitHub.

## 6. The repo (needs the owner's go-ahead)

- **Issues on RandyNorthrup/ost:** currently **disabled**. Enable them.
- **Discussions:** currently **disabled**. Enable them with the categories
  **Ideas** (Suggest a feature, upvotes), **Q&A** (help) and
  **Announcements** (What's new).
- **Labels:** add `feedback`, `report-a-problem`, `compliment` and
  `feature-request` (`bug`, `enhancement` and `documentation` already
  exist).
- **Files to add:**
  - `.github/ISSUE_TEMPLATE/report-a-problem.yml`,
    `.github/ISSUE_TEMPLATE/give-a-compliment.yml` and
    `.github/ISSUE_TEMPLATE/config.yml` (it links to Discussions ▸ Ideas
    and Q&A, and to Help).
  - `SUPPORT.md`, `PRIVACY.md` and `docs/help/` (the articles).

## 7. Order of work (each one PR-sized)

1. Repo setup (section 6), once approved: templates, SUPPORT and PRIVACY,
   labels, Discussions.
2. The Feedback ▸ menu, and the Report a problem and Give a compliment
   window and flow (section 2), with Ctrl+Alt+Shift+R and the child-window
   menu item.
3. Suggest a feature (section 3).
4. The "Send feedback 👍 👎" footers (the find pane, then the search page).
5. Help (F1): the window, home, search, categories, articles, and the first
   set of OST help articles (section 4); the Help app opens it.
6. The call-quality survey, opt-in (section 5).
