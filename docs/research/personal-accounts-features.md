# Personal Microsoft accounts in Teams desktop: feature inventory

Research for adding personal Microsoft account (MSA: outlook.com, hotmail.com,
live.com) support to OST. Compiled 2026-11-25 from Microsoft Support, Microsoft
Learn and Microsoft Q&A. Each item has a source. Nothing here was checked
against a live client at first; the items in
[Verify on real Teams](#verify-on-real-teams-checked-2026-11-27) were then
checked on real Teams on 2026-11-27.

## Naming and doc state

- **Name.** Microsoft now calls the product "Microsoft Teams for personal use".
  "Teams Free", "Teams (free)" and "Teams for home" are older names for the same
  thing. Support articles moved from `/teams/free/...` to `/teams/personal/...`,
  and some (Communities, some settings) are still under `/teams/free/`.
  [Intro](https://support.microsoft.com/topic/bba89850-d946-43f8-a9ea-e742cdc0128c)
- **Docs are uneven.** Many personal articles give mobile steps only, or show a
  Desktop tab with no desktop text. Older `/teams/free/` pages contradict newer
  ones (examples: who can be found by email by default, whether Communities can
  be created on desktop). Where pages disagree, this file goes by the newest
  page and flags the conflict.
- **Web client.** Teams on the web for personal accounts is at
  `teams.live.com` (`teams.live.com/gather`, `aka.ms/teamspersonal`).
  [Intro](https://support.microsoft.com/topic/bba89850-d946-43f8-a9ea-e742cdc0128c)
- **OST context.** The MSA tenant id is `9188040d-6c67-4c5b-b112-36a304b66dad`
  (docs/GUIDs.md, docs/terminology/msa.md), and `src/auth/skype.rs` already
  names the consumer authz endpoint
  `https://teams.live.com/api/auth/v1.0/authz/consumer`.

## 1. Account model in the desktop app

| Item | Description | Source |
|---|---|---|
| One app for both | Since June 2024, one desktop app (Windows, macOS) runs personal and work or school accounts. Earlier, Windows 11 shipped a separate "Teams (free)" chat app. | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Add a personal account | Select the profile picture, then "Add personal account" (in the multi-account article: "Add another account"). Sign-in takes an email or phone number, then a password or a one-time code. | [Sign in/out](https://support.microsoft.com/en-us/teams/personal/get-started/sign-in-sign-up-sign-out-and-add-a-new-account-in-microsoft-teams-personal), [Add account](https://support.microsoft.com/en-us/teams/personal/get-started/add-another-account-within-microsoft-teams-personal) |
| Sign up in the app | The desktop app has a "Get started" flow that creates a Microsoft account. Newer builds ask "For my small business" or "With friends and family". | [Sign in/out](https://support.microsoft.com/en-us/teams/personal/get-started/sign-in-sign-up-sign-out-and-add-a-new-account-in-microsoft-teams-personal) |
| Onboarding survey | A survey appears the first time Teams for personal use opens, and after some updates. | [Sign in/out](https://support.microsoft.com/en-us/teams/personal/get-started/sign-in-sign-up-sign-out-and-add-a-new-account-in-microsoft-teams-personal) |
| Switch accounts | Select the profile picture, then the other account. | [Manage accounts and orgs](https://support.microsoft.com/en-US/teams/notifications-settings/manage-accounts-and-organizations-in-microsoft-teams) |
| One personal account only | You can't sign in with two personal accounts in the same app profile; you can have one personal account plus work or school accounts. This comes from a Microsoft Q&A answer (January 2026), not from official docs. | [Q&A](https://learn.microsoft.com/en-us/answers/a/12482998) |
| Side by side | Personal and work accounts can run at once, each with its own window and taskbar icon (press coverage of the 2024 launch). | [Windows Central](https://www.windowscentral.com/microsoft-teams-now-supports-workschool-and-personal-accoutns-same-time) |
| Other-account badge | Pending notifications in background accounts show as a badge count. A drop-down next to Settings and more ("Activity in your account and other orgs") lists each account with counts and types (@mentions, calls, chats). Selecting an item opens it in the right account. | [Add account](https://support.microsoft.com/en-us/teams/personal/get-started/add-another-account-within-microsoft-teams-personal) |
| Open in new window | Selecting another account's activity opens it in a new window, and the main window keeps its account. | [Manage accounts and orgs](https://support.microsoft.com/en-US/teams/notifications-settings/manage-accounts-and-organizations-in-microsoft-teams) |
| Pin accounts | Up to three accounts can be pinned to the sidebar. A pinned account shows only its own activity, with Switch and Unpin actions. | [Manage accounts and orgs](https://support.microsoft.com/en-US/teams/notifications-settings/manage-accounts-and-organizations-in-microsoft-teams), [Learn preview](https://learn.microsoft.com/en-us/microsoftteams/activity-in-other-accounts-orgs) |
| Per-account notifications | Settings > Accounts and orgs has a notification toggle for each account and org. | [Manage accounts and orgs](https://support.microsoft.com/en-US/teams/notifications-settings/manage-accounts-and-organizations-in-microsoft-teams) |
| Sign out | Profile picture > Sign out. Signing out of the personal account leaves work accounts signed in. | [Sign in/out](https://support.microsoft.com/en-us/teams/personal/get-started/sign-in-sign-up-sign-out-and-add-a-new-account-in-microsoft-teams-personal) |
| Profile menu contents | The Profile button shows the account, status and availability, a status message, "Add another account" and "Sign out". The More (Settings and more) button holds profile settings, status and Settings. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Sign in on your phone | Settings and more (…) > "Sign in on your phone" shows a QR code for the mobile app. | [Sign in/out](https://support.microsoft.com/en-us/teams/personal/get-started/sign-in-sign-up-sign-out-and-add-a-new-account-in-microsoft-teams-personal) |
| Outlook add-in | The Teams Meeting add-in for Outlook doesn't work with personal accounts (there's a dedicated support article; community answers agree). | [Intro article list](https://support.microsoft.com/topic/bba89850-d946-43f8-a9ea-e742cdc0128c), [Q&A](https://learn.microsoft.com/answers/a/8273705) |
| Regional end | Teams for personal use ends on web and desktop in China on July 28, 2026. | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Platforms | The system requirements page covers Android, iOS, Windows, Mac and web. Linux isn't mentioned. | [System requirements](https://support.microsoft.com/en-us/teams/personal/get-started/system-requirements-for-microsoft-teams-personal) |

## 2. App shell for a personal account

| Item | Description | Source |
|---|---|---|
| Left rail | Chat, Meet, People, Communities, Calendar, Activity. There's no Teams/channels app, no Files/OneDrive app, no Calls app and no Apps store entry. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Meet app | Create a meeting link, Schedule a meeting, Join with a meeting ID, a "Meeting links" list and a "Scheduled meetings" list. Since September 2025 it also shows recent calls. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal), [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| People app | All contacts (Chat, Call, Block, Delete, Invite), Copy, Active now, and Settings (contact sync, blocked users). | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Calendar app | Join with an ID, Meet now, New meeting. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Activity app | Filter, Search, Settings. Covers chats and communities. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Missed-activity emails | There's a setting for missed-activity emails, documented in its own article. | [Intro article list](https://support.microsoft.com/topic/bba89850-d946-43f8-a9ea-e742cdc0128c) |
| Settings pages (desktop) | General; Appearance (theme, emoji skin tone, chat density); Chats; Notifications and activity; Accounts and orgs; Privacy; Accessibility (sign language mode); Devices (speaker, mic, camera, video effects); People; Files and links (browser choice); Plans and upgrades; Teams Insider. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Missing settings pages | Compared with work Teams, there are no Calls (voicemail, forwarding, call queues), Captions and transcripts (as its own page), Recognition, Rooms or "Files" (default app) pages. This is from comparing the two lists; it needs a live check. | Derived from the row above and docs/parity/shell-settings.md |
| Plans and upgrades | A Settings page for the subscription upsell. No doc describes what's on it. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Teams Insider | Opt-in preview program for personal Teams (insider.teams.com). | [Intro](https://support.microsoft.com/topic/bba89850-d946-43f8-a9ea-e742cdc0128c) |
| Window layout | Resizable Teams window layout (April 2025). Comfy and Compact chat density (August 2025). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Custom notification sounds | Windows only (August 2024). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Download destination | You can choose where downloads go (June 2025). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Status | Availability plus a status message, set from the profile menu. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Profile card | Profile cards can show LinkedIn connections (August 2024). Email and phone visibility on the card is controlled under Privacy. | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal), [Privacy](https://support.microsoft.com/office/manage-privacy-settings-in-microsoft-teams-free-20847062-fcdc-42db-977a-386f964d8834) |

## 3. Chat

### 3.1 Starting chats and contacts

| Item | Description | Source |
|---|---|---|
| New chat | The To: field takes a name, email address or phone number. | [Create a chat](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal) |
| Chat with yourself | Supported, for notes and drafts. | [Create a chat](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal) |
| Group from 1:1 | "Create a group chat" from the chat header; the original 1:1 chat is kept. A group can be named. | [Create a chat](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal) |
| Group chat link | Group chats have "Get link to chat" and Leave. Mobile also offers a "join via link" toggle and a QR code. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal), [Create a chat](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal) |
| Chat requests | Chats from people you haven't talked to before go to "Chat requests". For a 1:1 request: Preview messages, Accept (they then see your profile and presence) or Block. For a group request: Preview, OK (join) or Delete chat, optionally blocking the person who started it. | [Joining a chat](https://support.microsoft.com/en-us/teams/personal/chat/joining-a-chat-in-microsoft-teams-personal) |
| Report a suspicious chat request | Added July 2025. | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Invite to Teams | Searching an email or phone number of someone not on Teams sends them an invite link (by email or text). "Invite to Teams" copies a shareable link to the clipboard. The help article gives mobile steps; the desktop steps are blank. | [Invite contacts](https://support.microsoft.com/en-us/teams/free/chat-calling/invite-contacts-to-microsoft-teams-free) |
| Contact sync | People settings > Sync contacts > Manage: from Outlook.com or from Skype, for the same Microsoft account. Takes up to 24 hours. Google contact sync was removed. Users report that Outlook sync doesn't work in new Teams. | [Sync contacts](https://support.microsoft.com/en-US/teams/free/settings/sync-your-contacts-in-microsoft-teams-free), [Q&A](https://learn.microsoft.com/answers/a/12327652) |
| Block a contact | From People or from a chat. Blocked users are managed in People settings. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Group chat size | Not documented for personal accounts. Secondary sources say 250. | [Learn limits](https://learn.microsoft.com/microsoftteams/limits-specifications-teams) |

### 3.2 Chat list and messages

| Item | Description | Source |
|---|---|---|
| Chat list | Sections are Favorites and Chats. Filters are Unread, Unmuted (or Muted) and Meeting chats. Sort by Recent or by Sections. | [New chat experience](https://support.microsoft.com/en-us/teams/personal/chat/new-chat-experience-teams-personal) |
| Per-chat menu | Open in new window, Schedule a meeting, Screen sharing, Mark as unread, Favorite, Mute, Report a concern, Delete. Group chats add Get link and Leave. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Chat header | Files and Photos tabs, plus Video call, Audio call and Screen sharing buttons. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Photos tab | A gallery of shared photos with an image viewer (zoom, download). Jump to a photo's place in the chat was added in October 2024. | [View photos](https://support.microsoft.com/en-us/teams/personal/chat/view-all-photos-in-your-chat-in-microsoft-teams-personal), [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Attachments | "Upload from my computer" or "Attach cloud files". Shared files get an "Anyone with this link" OneDrive link, and participants keep access after you leave the chat. | [Send a file](https://support.microsoft.com/en-us/teams/personal/chat/send-a-picture-link-or-file-in-microsoft-teams-personal) |
| Link previews | A pasted link shows its metadata as a preview card. | [Send a file](https://support.microsoft.com/en-us/teams/personal/chat/send-a-picture-link-or-file-in-microsoft-teams-personal) |
| Emoji and GIF, reactions | Emoji and GIF have their own article. Multiple reactions per message arrived in 2025. | [Create a chat (article list)](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal), [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Mentions | @mentions, and @Everyone in group chats (May 2025). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Read receipts | On by default. "Seen" or "Sent" shows on the message; desktop has More options > "Read by". The toggle is in Settings > Chats, and a message only counts as read if everyone in the chat has receipts on. | [Read receipts](https://support.microsoft.com/en-us/teams/personal/chat/use-read-receipts-for-messages-in-microsoft-teams-personal) |
| Pin messages | Pin messages in chat (January 2026). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Search in chat | Search for messages within a chat (June 2025), plus global search. | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Spellcheck | Built into the compose box, in multiple languages (2025). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Translate | Message translation has its own article. | [Create a chat (article list)](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal) |
| Loop components | Desktop and web. Types: Table, Voting table, Code, Bulleted list, Numbered list, Kanban, Checklist, Q&A, Retrospective, Task list, Progress tracker. Saved to OneDrive; in chat they appear as a link that opens in the browser, not inline. | [Loop](https://support.microsoft.com/en-us/teams/personal/chat/send-a-loop-component-in-microsoft-teams-personal) |
| Chat apps | Celebrate, Weather, Stocks, Wikipedia Search (May 2025) and NewsBytes (February 2025), added through "Actions and apps" (+). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Commands | Slash commands have their own article. | [Create a chat (article list)](https://support.microsoft.com/en-us/teams/personal/chat/create-a-new-chat-in-microsoft-teams-personal) |
| Report a concern | Right-click a message, or open the chat menu, then pick a category. A group-chat report sends Microsoft the last ten messages and the group picture. | [Report a concern](https://support.microsoft.com/en-us/teams/personal/privacy-safety/report-a-concern-in-microsoft-teams-personal) |

### 3.3 Retired chat features (don't build)

The "no longer available" page lists Location sharing, Safe, mini Teams, Google
Calendar sync, Tasks, SMS and Link your phone, Play Together, Polls (in
communities, group chats and meeting chats), Public communities, Community Bot,
Designer and custom community banners.
[Discontinued features](https://support.microsoft.com/en-us/teams/free/troubleshoot/features-that-are-no-longer-available-in-microsoft-teams-free)

### 3.4 Chat with work or school accounts (federation)

| Item | Description | Source |
|---|---|---|
| Who can start | A personal user searches for a work email; the chat starts once the work user accepts. The work user can see the personal user's email. SMS isn't supported. | [Chat with work](https://support.microsoft.com/en-us/teams/personal/chat/can-i-chat-with-people-who-use-microsoft-teams-work-or-school-in-microsoft-teams-personal) |
| Tenant policy | The tenant setting "People in my organization can communicate with unmanaged Teams accounts" (`AllowTeamsConsumer`) controls this. A sub-option (`AllowTeamsConsumerInbound`) lets personal users start chats; when it's off, personal users can't find org users by email. The feature doesn't exist in GCC, GCC High or DoD. | [Learn external access](https://learn.microsoft.com/en-us/microsoftteams/trusted-organizations-external-meetings-chat) |
| Native chat | Chats between personal and commercial-tenant users are native (formatting, mentions, emoji), not text-only. | [Learn native chat](https://learn.microsoft.com/en-us/microsoftteams/native-chat-for-external-users) |
| Limits when the personal user starts the chat | Org members can view but not send photos and files. No audio or video calls and no screen sharing on either side. In meetings, org members join as anonymous guests. | [Why features are missing](https://support.microsoft.com/en-us/teams/personal/chat/why-are-some-features-not-available-in-chat-in-microsoft-teams-personal) |
| Limits when the org user starts the chat | No files either way (photos are allowed). No calls or screen sharing. Personal users can't remove org members. Personal users join meetings as anonymous guests. | [Why features are missing](https://support.microsoft.com/en-us/teams/personal/chat/why-are-some-features-not-available-in-chat-in-microsoft-teams-personal) |
| Org policies apply | The org's retention applies, the org can remove personal users, and people can show as "Unknown" or "Anonymous". | [Why features are missing](https://support.microsoft.com/en-us/teams/personal/chat/why-are-some-features-not-available-in-chat-in-microsoft-teams-personal) |
| Doc conflict | The Learn intro says chat only with unmanaged accounts, but the same page's section says "chats and meetings". | [Learn external access](https://learn.microsoft.com/en-us/microsoftteams/trusted-organizations-external-meetings-chat) |

### 3.5 Skype retirement

| Item | Description | Source |
|---|---|---|
| Retired | Skype (free and paid) retired on May 5, 2025; Skype for Business wasn't affected. Skype users sign in to Teams with the same credentials. | [Skype retiring](https://support.microsoft.com/en-us/skype/skype-is-retiring-in-may-2025-what-you-need-to-know-2a7d2501-427f-485e-8be0-2068a9f90472) |
| Migrated data | Contacts and chats moved over automatically. Chat and call history is kept only for users who were active from December 2024 to February 2025 and used Teams before December 1, 2025. Not migrated: Skype-to-work chats, Skype for Business history, chats with yourself, private conversations, Copilot and bot content. Skype invite links redirect to the matching Teams chat. | [Skype retiring](https://support.microsoft.com/en-us/skype/skype-is-retiring-in-may-2025-what-you-need-to-know-2a7d2501-427f-485e-8be0-2068a9f90472) |
| Skype interop ended | Skype consumer interop with work Teams is unsupported since May 5, 2025. | [Learn Skype interop](https://learn.microsoft.com/en-us/microsoftteams/teams-skype-interop) |
| Export deadline | The Skype data export ran until June 15, 2026, after which inactive users' data was deleted. Dates conflict across pages (January 2026, April 1, 2026, June 2026). | [Skype retiring](https://support.microsoft.com/en-us/skype/skype-is-retiring-in-may-2025-what-you-need-to-know-2a7d2501-427f-485e-8be0-2068a9f90472) |

## 4. Communities (being retired)

**Status: Communities for personal use end in December 2026** (no exact day
given). New communities can't be created during the wind-down, and there's no
migration to group chats. Users can export at `teams.live.com/dataexport`.
Public communities, Polls and Community Bot were already retired (announced
August 2025).
[Deprecation](https://support.microsoft.com/en-us/teams/free/communities/communities-deprecation),
[What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal)

For reference only, in case Teams still shows Communities when OST ships:

| Item | Description | Source |
|---|---|---|
| Structure | A community has owners and members, channels for topics, events and a calendar, a Files tab, pinned posts, owner badges and "New" badges on posts. | [What are Communities](https://support.microsoft.com/en-us/teams/free/communities/what-are-communities-and-channels-in-microsoft-teams-free), [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Joining | By owner invite, a member's join link, or a join request (with a note, February 2025). Work accounts can't join. Up to 1,000 members. Private by default. | [What are Communities](https://support.microsoft.com/en-us/teams/free/communities/what-are-communities-and-channels-in-microsoft-teams-free) |
| Roles | Only owners can add or remove members, schedule events, delete others' messages, promote or demote, change name, picture, description and guidelines, or delete the community. Members can share invite links. | [Owner/member](https://support.microsoft.com/en-us/teams/free/communities/learn-more-about-community-owner-and-member-capabilities-in-microsoft-teams-personal) |
| Events | Owners create events with a title, time, recurrence, location, an optional online meeting and a description. Meeting options open in the browser. | [Events](https://support.microsoft.com/en-us/teams/free/communities/learn-about-community-calendars-and-events-in-microsoft-teams-personal) |
| Minors | Not available to minors. | [What are Communities](https://support.microsoft.com/en-us/teams/free/communities/what-are-communities-and-channels-in-microsoft-teams-free) |

## 5. Calendar and meetings

| Item | Description | Source |
|---|---|---|
| Free limits | Group meetings and calls last up to 60 minutes with up to 100 participants. 1:1 calls can last up to 30 hours. | [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05), [Create a meeting](https://support.microsoft.com/en-us/teams/personal/meetings-calls/create-a-meeting-in-microsoft-teams-personal) |
| Subscriber limits | Microsoft 365 Personal or Family raise this to 30 hours and 300 participants. A Q&A thread says "Family Classic" doesn't. | [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05), [Q&A](https://learn.microsoft.com/en-us/answers/questions/5824030/i-recently-bought-a-new-microsoft-surface-laptop-t) |
| Create a meeting link | Meet > "Create a meeting link" with a title. The link is listed under "Meeting links" with Join and Share link. | [Create a meeting](https://support.microsoft.com/en-us/teams/personal/meetings-calls/create-a-meeting-in-microsoft-teams-personal) |
| Meet now | From Calendar, a chat header, or a group chat (March 2025). | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal), [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Schedule | Meet > Schedule a meeting, or Calendar > New meeting. Fields: title, participants (name, email or phone), start and end or all-day, repeat, location, description. Advanced options cover who can bypass the lobby and who can present. SMS invites can't be recurring. | [Schedule](https://support.microsoft.com/en-us/teams/personal/meetings-calls/schedule-a-meeting-in-microsoft-teams-personal) |
| Outlook.com calendar | Meetings are tied to the account's Outlook calendar. Meetings created in Outlook can't have attendees changed in Teams; that has to be done in Outlook.com. Accounts that use a non-Microsoft email address may keep meetings only in Teams (Q&A). | [Schedule](https://support.microsoft.com/en-us/teams/personal/meetings-calls/schedule-a-meeting-in-microsoft-teams-personal), [Q&A](https://learn.microsoft.com/answers/a/8273705) |
| Email invites need a visible email | Meeting invites only arrive by email if your email is visible on your profile. | [Privacy](https://support.microsoft.com/office/manage-privacy-settings-in-microsoft-teams-free-20847062-fcdc-42db-977a-386f964d8834) |
| Join | By link, by meeting ID and passcode (Meet > "Join with meeting ID"), from Scheduled meetings, from the chat, or from Calendar. Guests can join in the browser without an account (Edge, Chrome, Firefox, Safari). | [Join](https://support.microsoft.com/en-us/teams/personal/meetings-calls/join-a-meeting-in-microsoft-teams-personal) |
| Link format | `https://teams.live.com/meet/<numeric id>?p=<passcode>`. Only a vendor doc states this; work Teams now uses `teams.microsoft.com/meet/<id>?p=<hash>`. | [Vexa docs](https://docs.vexa.ai/platforms/microsoft-teams), [MC772556](https://mc.merill.net/message/MC772556) |
| Roles | Organizer, Presenter, Attendee. Attendees can't share their screen. | [Roles and options](https://support.microsoft.com/en-us/teams/personal/meetings-calls/meeting-roles-and-options-in-microsoft-teams-personal) |
| Meeting options | Free: Bypass lobby, Share screen. Subscription only: Allow chat, Allow unmute, Allow camera, Allow reactions. | [Roles and options](https://support.microsoft.com/en-us/teams/personal/meetings-calls/meeting-roles-and-options-in-microsoft-teams-personal) |
| In-meeting (free) | Camera and mic, noise suppression, device switching, hold, turn off incoming video, backgrounds, blur, uploaded images, filters (desktop only), raise hand, reactions, share screen, photo or video with system sound, Pin for me, Spotlight, views, meeting chat, live captions (with profanity filter), RTT, sign language view, meeting info, meeting timer (January 2026), PowerPoint Live viewing (June 2025), give and take control, pop-out shared content, compact minimized window. | [During a meeting](https://support.microsoft.com/en-us/teams/personal/meetings-calls/what-can-i-do-during-a-meeting-in-microsoft-teams-personal), [Backgrounds](https://support.microsoft.com/en-us/teams/personal/meetings-calls/add-a-background-or-video-filter-to-your-microsoft-teams-personal-meeting), [Captions](https://support.microsoft.com/en-us/teams/personal/meetings-calls/live-captions-in-microsoft-teams-personal), [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Recording | Microsoft 365 Personal, Family or Premium only; minors can't record. The recording lands in the meeting chat and expires after 30 days, with Download available. Everyone is notified. One recorder at a time, at most four video streams captured, and recording stops if the recorder leaves. You pick a spoken language for playback captions. | [Recordings](https://support.microsoft.com/en-us/teams/personal/meetings-calls/manage-meeting-and-call-recordings-in-microsoft-teams-personal) |
| Not available on any personal plan | Breakout rooms, avatars, Whiteboard, immersive spaces. | [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05) |
| Subscription only | Advanced background options and screen-sharing control. | [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05) |
| Joining work meetings | A personal account can join a work meeting signed in, or as a guest in the browser. It gets chat, participant list, screen share, raise hand and reactions, but no Excel Live or Word Live, no recording files and no Whiteboard. | [Join a work meeting](https://support.microsoft.com/en-us/teams/personal/meetings-calls/join-a-teams-for-work-or-school-meeting-in-microsoft-teams-personal) |
| Work users in personal meetings | They join with a work account, a personal account or as a guest, depending on their org's policy. Microsoft's privacy statement applies, not the org's terms. | [Invite work users](https://support.microsoft.com/en-us/teams/personal/meetings-calls/invite-users-work-school-account-user-meeting-in-microsoft-teams-personal) |
| Undocumented | Together mode, transcripts, translated captions, polls in meetings (polls are retired), music mode (it has an article but no details), video clips. | — |

## 6. Calls

| Item | Description | Source |
|---|---|---|
| 1:1 and group calls | Video or audio call buttons in the chat header. Group calls ask for confirmation first. Calls from a chat allow up to 20 participants; above that, use a meeting. | [Make a call](https://support.microsoft.com/en-us/teams/personal/meetings-calls/make-a-call-in-microsoft-teams-personal) |
| Who can call you | Privacy setting: Everyone or My contacts (default: My contacts). | [Privacy](https://support.microsoft.com/office/manage-privacy-settings-in-microsoft-teams-free-20847062-fcdc-42db-977a-386f964d8834) |
| In-call | Video, mic, speaker, chat, people, share a photo or screen (with computer sound), views, background effects, audio settings, captions, hold, turn off incoming video. | [Make a call](https://support.microsoft.com/en-us/teams/personal/meetings-calls/make-a-call-in-microsoft-teams-personal) |
| Call recording | Same rules as meeting recording (subscription only). | [Recordings](https://support.microsoft.com/en-us/teams/personal/meetings-calls/manage-meeting-and-call-recordings-in-microsoft-teams-personal) |
| PSTN | No calling plans in Teams for personal use. The only phone-number calling is the **Skype Dial Pad**: outbound calls to landlines and mobiles paid with Skype Credit, under Settings and more > Skype Dial Pad, shown only to accounts with Skype Credit. New credit can't be bought and auto top-up is gone. Skype Number, SMS, forwarding, voicemail and caller ID are discontinued (caller ID ended February 15, 2026). Skype Credit and paid subscriptions ended May 1, 2026, so the Dial Pad may now be gone. | [Dial Pad](https://support.microsoft.com/en-us/teams/personal/meetings-calls/make-a-call-with-skype-dial-pad-in-microsoft-teams-personal), [Skype retiring](https://support.microsoft.com/en-us/skype/skype-is-retiring-in-may-2025-what-you-need-to-know-2a7d2501-427f-485e-8be0-2068a9f90472) |
| Ringtone | New default call ringtone (August 2025). | [What's new](https://support.microsoft.com/en-us/teams/personal/get-started/what-s-new-in-microsoft-teams-personal) |
| Calls with work users | Not possible in personal-to-work chats (see 3.4). | [Why features are missing](https://support.microsoft.com/en-us/teams/personal/chat/why-are-some-features-not-available-in-chat-in-microsoft-teams-personal) |

## 7. Files and storage

| Item | Description | Source |
|---|---|---|
| Where files go | Files attached in chats or communities are uploaded to "Microsoft Teams Chat Files" in your personal OneDrive. | [Data storage](https://support.microsoft.com/en-US/teams/free/troubleshoot/where-is-my-microsoft-teams-free-data-stored) |
| Photos and videos | Photos and videos sent through Gallery or Media aren't stored in OneDrive and have no storage limit. | [Data storage](https://support.microsoft.com/en-US/teams/free/troubleshoot/where-is-my-microsoft-teams-free-data-stored) |
| Quota | 5 GB free (shared with OneDrive and Outlook.com), 1 TB with Personal, 1 TB per person with Family. When full, you can't attach files. Single files up to 250 GB. | [Data storage](https://support.microsoft.com/en-US/teams/free/troubleshoot/where-is-my-microsoft-teams-free-data-stored), [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05), [Storage FAQ](https://support.microsoft.com/en-us/onedrive/microsoft-storage-faqs) |
| Link permission | Shared files get an "Anyone with the link can view and edit" link. Change it in OneDrive. | [Data storage](https://support.microsoft.com/en-US/teams/free/troubleshoot/where-is-my-microsoft-teams-free-data-stored) |
| OneDrive browsing | Profile > Files > OneDrive is documented for iOS and Android only. There's no OneDrive app in the desktop rail; desktop uses "Attach cloud files" in compose. | [OneDrive files](https://support.microsoft.com/en-US/teams/free/settings/access-your-onedrive-files-in-microsoft-teams-free) |
| Files tab in chat | The chat header has a Files tab. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |
| Data export | `teams.live.com/dataexport` exports chat history and media. | [Deprecation](https://support.microsoft.com/en-us/teams/free/communities/communities-deprecation) |

## 8. Subscription tiers

| Feature | Free | M365 Personal | M365 Family | Source |
|---|---|---|---|---|
| Meeting length / participants | 60 min / 100 | 30 h / 300 | 30 h / 300 | [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05) |
| Recording | No | Yes | Yes | same |
| Advanced backgrounds | No | Yes | Yes | same |
| Screen-sharing control | No | Yes | Yes | same |
| Meeting options (chat, unmute, camera, reactions) | No | Yes | Yes | [Roles and options](https://support.microsoft.com/en-us/teams/personal/meetings-calls/meeting-roles-and-options-in-microsoft-teams-personal) |
| Storage | 5 GB | 1 TB | 6 TB (1 TB each) | [Subscriptions](https://support.microsoft.com/en-us/office/do-i-need-a-subscription-to-use-teams-472099be-81c0-46a0-ae29-59ab4536dd05) |
| Copilot | No | Yes | Yes | [Intro](https://support.microsoft.com/topic/bba89850-d946-43f8-a9ea-e742cdc0128c) |

- **Premium and Basic.** Microsoft 365 Premium is named alongside Personal and
  Family for recording and Copilot. Microsoft 365 Basic isn't covered by any
  Teams doc. [Recordings](https://support.microsoft.com/en-us/teams/personal/meetings-calls/manage-meeting-and-call-recordings-in-microsoft-teams-personal)
- **Copilot features.** Copilot Chat, and Rewrite in compose (November 2025).
  Settings > Privacy > "Use AI features" (on by default) applies to the account
  everywhere. The AI credits doc doesn't list Teams.
  [AI features](https://support.microsoft.com/en-us/teams/personal/premium-copilot/use-ai-features-microsoft-teams-for-personal-use),
  [AI credits](https://support.microsoft.com/en-us/microsoft-365-copilot/ai-credits-and-limits-for-microsoft-365-subscriptions)
- **Skype minutes.** The 60 Skype minutes in Personal and Family ended in March 2026.
  [Skype retiring](https://support.microsoft.com/en-us/skype/skype-is-retiring-in-may-2025-what-you-need-to-know-2a7d2501-427f-485e-8be0-2068a9f90472)
- **Teams Essentials.** This is a paid small-business product (around $4 per
  user per month, 30 h / 300 participants, 10 GB), not a personal tier. The
  sign-up flow's "For my small business" path leads there.
  [Practical365](https://practical365.com/teams-essentials-teams-free/),
  [Skype retiring](https://support.microsoft.com/en-us/skype/skype-is-retiring-in-may-2025-what-you-need-to-know-2a7d2501-427f-485e-8be0-2068a9f90472)

## 9. Privacy, safety and age

| Item | Description | Source |
|---|---|---|
| Find me by | Settings > Privacy > Manage contact information toggles email, phone and profile name. All are on by default per the newer page; an older page said off. With them off, you only show in search for people you've chatted with before. | [Privacy](https://support.microsoft.com/office/manage-privacy-settings-in-microsoft-teams-free-20847062-fcdc-42db-977a-386f964d8834) |
| Who can call you | Everyone or My contacts (default: My contacts). | same |
| Who can add you to groups | Everyone or My contacts (default: Everyone). | same |
| Profile card details | Hide or show email and phone. Email must be shown to receive meeting invites. | same |
| AI toggle | "Use AI features" (see section 8). | [AI features](https://support.microsoft.com/en-us/teams/personal/premium-copilot/use-ai-features-microsoft-teams-for-personal-use) |
| Community Standards | The standards cover all chats, meetings and communities. Breaking them can restrict features or remove the account. | [Standards](https://support.microsoft.com/en-US/teams/free/get-started/learn-more-about-microsoft-teams-free-standards) |
| Age verification | In some regions users may be asked to verify their age. Verified minors get a restricted experience (no recording, no communities), and verification can take 24 hours to apply. The page is marked "coming soon". | [Age verification](https://support.microsoft.com/en-gb/teams/free/settings/age-verification-microsoft-teams-free) (from a search snippet; the page didn't load) |
| Parental controls | The Standards page mentions parental transparency and control but doesn't describe it. Family Safety isn't documented for Teams. | [Standards](https://support.microsoft.com/en-US/teams/free/get-started/learn-more-about-microsoft-teams-free-standards) |
| Delete account | Mobile Settings lists "Delete account" and data export. An older page said profile deletion isn't supported in the app. | [Get to know](https://support.microsoft.com/en-us/teams/personal/get-started/getting-to-know-microsoft-teams-personal) |

## Differences from work or school Teams (summary)

- **Missing in personal Teams:** Teams and channels, the Files/OneDrive rail
  app, the Apps store (only a few chat apps), the Calls app with PSTN,
  voicemail and forwarding, breakout rooms, Whiteboard, avatars, Excel Live and
  Word Live, polls, tasks, transcripts (undocumented), and the Outlook add-in.
- **Only in personal Teams:** Meet and People as default rail apps (work Teams
  has optional Meet and People apps too, with different contents), chat requests,
  Invite to Teams links, "Who can call you" and "Who can add you to groups",
  Communities (until December 2026), the Skype Dial Pad (legacy), Plans and
  upgrades, meeting limits with in-meeting upsells, and recordings stored for
  30 days in the chat instead of OneDrive or SharePoint.
- **Shared:** the shell, chat compose, the meeting stage, devices, appearance,
  accessibility and the multi-account switcher.

## Verify on real Teams (checked 2026-11-27)

Checked on 2026-11-27 (TASK-0287) on Teams desktop `26304.1207.5384.858` on
testpc2 (Windows 11), signed in as OST Test 2, with the personal account OST
Personal 2 added through the profile menu (Add another account > email >
"Use your password instead" > password > "Use this account everywhere on your
device": **Microsoft apps only**). Where the desktop couldn't show something,
teams.live.com (web client `1415/26101516645`) was used and is named.
Screenshots are kept outside the repo (coordinator PC,
`~/.local/share/ost-remaining/personal/`, files `ac2-*`). Status: **Verified**,
**Corrected** or **Partly verified** (with the reason).

1. **Left rail. Corrected.** Personal: Chat, Meet, People, **Copilot**,
   Communities, Calendar, Activity; at the bottom Upgrade (diamond) and
   "Activity in other accounts and orgs" (with a count badge). No Teams,
   Calls, OneDrive or Apps. **Communities still shows** (27 November 2026)
   with the banner "Communities is retiring soon. Use a group chat to stay
   connected." (Learn more, Start chat) and a "Communities is retiring
   soon" dialog (Learn more, Ok). "Create your own" and the templates no
   longer create a community: they open "Create a group chat" ("Communities
   is retiring soon. Create a group chat to connect, share and
   collaborate.", Learn more, Create).
2. **Profile menu and switcher. Verified, with details.** Each account has
   **its own window** (titles `<view> | Personal | <email> | Microsoft Teams`
   and `<view> | <org name> | <email> | Microsoft Teams`) and its own taskbar
   button (the personal one has the Teams personal icon). Once a second
   account exists the work window title gains the org name. Teams also keeps
   a hidden page per account in the background. Work profile menu: header
   with the org name ("Secure Coast Netw…") and Sign out, the account card
   (photo, name, email, View account), Available, Pause notifications, Set
   work location, Set status message, then the other account (avatar, "OST
   Personal 2", email) and "Add another account". Personal profile menu:
   header "Personal" and Sign out, the card (name, email, "My Microsoft
   account"), Available, Set status message (no Pause notifications or work
   location), "Switch to account ost-test2@…" and "Add another account".
   Choosing the other account opens or focuses its window. The
   other-account badge is the "Activity in other accounts and orgs" button
   at the bottom of the rail; its flyout lists each other account (avatar
   with count, name, email, a Switch button and a pin button) and the kind
   of activity ("Unread chat messages"). Clicking the pin filled its icon
   while the flyout was open, but no pinned entry appeared in the rail and
   the pin showed as unpinned when the flyout was opened again later.
3. **Second personal account. Verified.** Teams lets you go through the
   sign-in, then shows "Multiple personal accounts aren't supported in Teams
   yet. To use another personal account, open Teams on the web." with "Open
   Teams on the web" and Cancel.
4. **Settings. Verified.** Pages: General, Appearance, Chats, Notifications
   and activity, Accounts and orgs, Privacy, Accessibility, Devices, People,
   Files and links, Plans and upgrades, Teams Insider, About Teams.
   - General: Auto-start Teams, Open application in background, open chats
     and meetings in the main or a new window.
   - Appearance: Theme ("This will apply to all your Teams apps", Follow
     operating system theme), Always use dark theme for calls and meetings,
     a None…Dark radio row, Show app names, Auto collapse app bar.
   - Chats: Show message previews, Show time stamps, Filters, Comfy or
     Compact, Read receipts.
   - Notifications and activity: Mute all notifications (except calls and
     meetings), Windows Do not disturb, Sound (with Preview sound), Display
     (Test notification, previews, during calls, flash taskbar); Chat (Chat
     message notifications "Show in banner", @Mentions and Likes and
     reactions "Show in Activity and banner"); Meetings (Meeting start
     notifications, Show meeting join bar, Meeting chat notifications "Mute
     until I join or send a message", Meet now start notifications off).
   - Accounts and orgs: each account (name, email, Manage account link)
     under "Personal" and the org name.
   - Privacy: **Manage contact information** opens "Manage how people can
     find you" with one switch for the profile name (on) and one for the
     email (**off** on both new accounts, although onboarding posted
     `scd/searchability` with `searchable: true`); Manage who can add you to
     groups (Anyone); Manage who can call you (Your contacts); Turn off my
     camera and mic when my screen locks; Extended diagnostics data; Manage
     profile; Optional connected experiences; Experiences that analyze your
     content.
   - Accessibility: Sign language mode, Muted notification, single pointer
     controls.
   - Devices: speaker, microphone, Automatically adjust mic sensitivity,
     Sync device buttons, Noise suppression, Video.
   - People: Manage (contact sync).
   - Files and links: download location with Change, Always ask where to
     save, Always open web links in (browser list).
   - Plans and upgrades: "Microsoft 365 plan" (30 hours for each meeting
     and call, up to 300 participants, 1 TB storage (2 TB shared),
     productivity apps with Copilot, record calls and meetings, more), an
     Upgrade button, "Already have a subscription?", and "Your free
     benefits": 1 hour for each meeting and call, up to 100 participants,
     5 GB OneDrive.
   - Teams Insider: Join, Learn more, Terms and Conditions.
5. **Meet app. Verified.** Left list: Meeting links, Schedule a meeting,
   Calls. Meeting links page: "Create a meeting link", "Join with a meeting
   ID", "Quickly create, save, and share links with anyone." Create a
   meeting link asks "Give your meeting a title", then "Create and copy
   link" (toast "Link copied to clipboard"); the list item shows the title
   and "Created just now" with More options, Edit meeting name, Join and
   Share link.
6. **Calendar. Verified: two-way with Outlook.com.** The Calendar app has
   Join with an ID, Meet now and New meeting over a work-week grid. An
   event created in Outlook.com (outlook.live.com) appeared in the Teams
   calendar, and a meeting saved from Teams' New meeting form appeared in
   Outlook.com. Teams reads the calendar through the middle tier
   (`teams.live.com/api/mt/v2.0/me/calendars/default/calendarView`); the
   Graph token of Teams free can't read calendars. The New meeting form
   says "With your current Teams plan, you get up to 60 minutes per meeting
   with up to 100 participants." and "For non-Teams contacts, they will
   receive an email invite to the meeting with a join link.", and has
   Title, Invite attendees, start and end date and time, All day, Time
   zone, recurrence, Location, Meeting options and a details editor. Save
   opens "Share meeting invite" ("Send the meeting link, date, and time to
   invite others.", an invitation preview "<name> invited you to a Teams
   Meeting:" with title, date, time and a Meetup-Join link, and Copy).
7. **Meeting link. Verified (format), partly verified (opening).** Link:
   `https://teams.live.com/meet/9364181390928?p=wZiZR41JQZUcjwfkBW`, a
   13-digit id and an 18-character passcode. Join from Meet opens the
   pre-join screen in a separate "Meeting with …" window with Computer
   audio, Phone audio and Don't use audio. Opening the link in a browser
   that is signed in to teams.live.com goes to the pre-join screen of the
   web client. How a pasted `teams.live.com/meet/…` link opens in the
   desktop app was not tried.
8. **60-minute limit. Partly verified.** The authz response carries
   `maxMeetingDurationMinutes: 60` and `maxMeetingParticipants: 100`, and
   the New meeting form and Plans and upgrades state the 60-minute limit.
   A personal meeting (started 09:58 from a meeting link) showed **no
   warning and did not end** at 50, 55, 59 or 60 minutes and was still
   running at 1:04; by then only the organizer was left, because the
   second participant (OST Personal 1 on the web) dropped out after about
   35 minutes when its headless browser stalled. So the warning and the
   end of a meeting with two or more people present were not observed. The
   20-participant limit for calls from a chat can't be tested with two
   accounts.
9. **Chat request UI. Partly verified.** Checked the request a work user
   gets from a personal user (desktop, OST Test 2): the chat sits at the top
   of the list in bold; opening it shows "OST Personal 2
   (ost-personal2-0238@outlook.com) wants to chat with you", a box "This
   person is from outside your organization" (spam and phishing warning,
   "Note: This person is not sharing their email in Teams. To be safe,
   preview their messages."), Block and Accept, and "By selecting Accept,
   you agree to receive future communications and share some account
   information such as your name and status with OST Personal 2
   (External)." The sender sees a normal chat with the note "When you start
   this chat, your email address will be visible to the recipient to help
   build trust on Teams." A personal-to-personal request was not seen: with
   email discovery on, Teams still answered NotFound for both personal
   accounts' emails during the session (Invite was offered instead).
10. **Chat with ost-test accounts. Verified (started by the personal
    user).** Work side: header "OST Personal 2" with an **External** badge,
    "Calling isn't available in this chat." on the call button, a banner
    "OST Personal 2 is outside your org. Some Teams features aren't
    available in this chat.", "Replying to external participants." over
    the compose box, and **no Attach button** (only formatting, emoji, Loop
    and Actions and apps); the window title says "(External unfamiliar)".
    Personal side: header with the work user's name and email, Chat, Files
    and Photos tabs, video and audio call buttons disabled ("Calling isn't
    available in this chat."), the banner "OST Test 2 is part of an
    external organization. It's possible they have message-related policies
    that will apply to the chat.", and Attach files (Attach cloud files,
    Upload from this device) and Attach media available. A file uploaded
    from the personal side showed "Anyone with the link can edit"; the send
    itself did not complete in the headless web client, so delivery to the
    work side wasn't seen. **Work user starting the chat:** typing a
    personal email that Teams can't resolve offers it with an External tag,
    and sending invites it as a B2B guest of the work tenant ("Your
    invitation is on its way... it may take a couple of minutes.", a group
    chat titled "<email> and OST Test 2" with only an emoji button).
11. **Skype Dial Pad. Verified: gone.** Settings and more holds Upgrade, Pin
    window on top, Settings, Zoom, Help, Feedback, Keyboard shortcuts, Get
    the mobile app (New), Teams Insider (New) and What's new.
12. **Invites. Verified (desktop and web), partly (group chat link).**
    People > Invite to Teams copies a link ("Link copied to clipboard"). In
    a new chat, an email Teams can't find is offered with "Invite";
    choosing it copies an invite link ("Invite link copied"), from
    `POST mt/beta/join/template` →
    `https://teams.live.com/l/invite/<id>?v=g1` with the text "Let's chat
    on Microsoft Teams! …". Teams sends no email or SMS itself. The group
    chat QR code and join-link toggle were not checked.
13. **Captions, transcripts, Together mode (free account). Verified.** In a
    personal meeting, More > Language and speech offers Show live captions
    and Turn on RTT for this call; there is no transcript option. View
    offers Gallery, Speaker, Large gallery, Focus on content, Gallery size,
    Show videos first and More options (Show gallery at top, Turn off other
    videos, Hide me): **no Together mode**. The toolbar has Record (marked
    as a premium feature), Chat, People, Raise, React, View, More, Camera,
    Mic, Share, Leave; More has Meeting info, Timer, Video effects and
    settings, Audio settings, Language and speech, Settings. Subscribed
    accounts were not tested (no Microsoft 365 subscription).
14. **Files tab and OneDrive. Verified.** Chats have Chat, Files and Photos
    tabs. There is no OneDrive app; the compose Attach menu offers "Attach
    cloud files" and "Upload from this device". Uploads go to "Microsoft
    Teams Chat Files" in the user's OneDrive through Graph.
15. **Copilot. Corrected.** Free accounts have a Copilot rail app that is an
    upsell: "Chat with Copilot in Teams", "Collaborate with an AI companion
    to brainstorm, draft messages, and more with a Microsoft 365
    subscription.", View all benefits, Explore plans now, "Already have a
    subscription? Start using Copilot".
16. **Missed-activity email and notification settings. Verified.** The
    desktop Notifications and activity page has no missed-activity email
    setting (its contents are under item 4).

## Open questions

- **Protocols.** Answered by the 2026-11-27 capture: see
  docs/research/personal-accounts-protocol.md §7 (calendar through the middle
  tier, files through Graph, presence through UPS, chat through the consumer
  chat service).
- **Test accounts.** Answered: two dedicated personal accounts exist (OST
  Personal 1 and 2, in creds.md); sign-in may ask for a code sent to the
  recovery mailbox.
- **Subscription testing.** Recording, the 30 h / 300 limits and Copilot need
  Microsoft 365 Personal or Family. Is buying a trial acceptable?
- **Communities.** They end in December 2026. Skip them, or build read-only
  support for the remaining weeks?
- **Personal-to-work chat.** It depends on `AllowTeamsConsumer` and
  `AllowTeamsConsumerInbound`. The test tenant has both on (read 2026-11-27,
  Global external access policy too), and personal-to-work chat worked.
- **Group limits.** Group chat size (250?) and group call size (20 from a chat)
  aren't documented for personal accounts.
- **Age verification.** Whether the region-gated age checks and minor
  restrictions ever affect a desktop client in the US or EU.
- **Linux clients.** The Microsoft docs never mention Linux, so treat
  teams.live.com on the web as the reference client for behavior the desktop
  docs leave out.
