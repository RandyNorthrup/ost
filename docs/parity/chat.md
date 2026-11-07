# Teams (new Teams 2.x, Windows desktop) parity inventory: CHAT & MESSAGING

Scope: 1:1 chats, group chats, meeting chats, the self-chat "(You)", the chat list, chat header, composer, message actions, receipts, search and keyboard shortcuts. The research cut-off is 2026-11-06.

Conventions:
- `[doc]` means Microsoft documents the behaviour (the source sits right under it).
- `[verify]` means the behaviour is commonly seen in the shipping client but the cited page doesn't spell it out. Check it on winpc (real Teams desktop) before building it pixel-exact.
- `[admin]` means a tenant messaging policy can switch it off. A clone must hide the UI when the policy says so.
- `[new]` means it rolled out in 2025–2026 (Message Center ID given).
- Where web, Mac or mobile behave differently, the item says so.

---

## 1. Chat list: views and layout

- [ ] Combined vs Separate view: choose it from **More list options** (…) at the top of the list > **Customize view** > **Combined** / **Separate**. Combined puts chats, teams and channels in one list under Chat. Separate gives the classic split into a Chat app and a Teams app, each with its own Favorites. `[doc]`
  Source: https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] Default sections in Combined view are **Favorites**, then **Chats**, then **Teams and channels**. Favorites holds the items that used to be pinned. **Chats** is sorted by recency and shows up to 25 chats at a time, with a "see more" control. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Quick navigation bar ("Teams and channels") in Combined view on Windows, Mac and Web. Clicking it scrolls to the Teams and channels section. It turns **bold** when that section has unread items, even when those items are off-screen, and shows "@" when a channel has an unread @mention. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Unread state: the chat or channel name is shown in **bold**. Collapsed sections still go bold and show "@" for new mentions. Channels show activity icons, not numeric counts (changed to match chats). `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] "Needs attention" purple indicators on chat conversations. `[new]` `[verify]` the exact glyph.
  Source: https://support.microsoft.com/en-us/topic/d7092a6d-c896-424c-b362-a472d5f105de (What's new in Teams)
- [ ] Message previews in the list: **off by default** on Windows, Mac and Web, and on by default on mobile. Turn them on in **Settings and more (…) > Settings > Chats and channels > Show message previews for chats and team names for channels**. **Show time stamps** is a separate toggle. Time stamps can be shown without previews, but previews can't be shown without time stamps. The time stamp is the day sent, or the time if the message was sent today. With multiple accounts, every account must use the same preview setting. Screen readers only read previews when they are on. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/preview-messages-in-microsoft-teams
- [ ] Message density: **Settings > Chats and channels > Chat > Message density** = **Comfy** (default) or **Compact**. Compact tightens message spacing, compacts the chat list and hides previews by default. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/change-the-spacing-of-your-chat-messages-in-microsoft-teams
- [ ] Channel list options: on the section label choose **More options (…) > List options > Channels only** for a flat list, which can be sorted **Most recent**. In the flat list, channels named "General" show their team's name. **See all channels** appears per team, **See all your teams** appears at the bottom, and a team's … menu has **Hide all channels**. Teams with no shown channels are left out of the list. Hidden teams that still have a shown channel appear collapsed at the bottom. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Draggable pane divider between the list and the conversation. Ctrl+Alt+Enter moves focus to the divider. Ctrl+Shift+Enter returns the pane to its default width. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] First-run "Get started" / "Do it later" screen for the new chat and channels experience. It reminds up to 3 times, then forces the change about a week later. This only matters if the clone mirrors the onboarding. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf

## 2. Chat list: filters

- [ ] Filter pills at the top of the list: **Unread**, **Chats**, **Channels**, **Meeting chats**. The text search filter and some extra filters sit behind a **More filters** arrow. Ctrl+Shift+F opens the filter. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Muted** filter. TechCommunity lists the filters as Unread, Chat, Channels, Meetings, Muted. `[doc]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/introducing-the-new-microsoft-teams-chat-and-channels-experience/4275674
- [ ] **Unread** can be combined with one of Channels, Chats or Meeting chats. Clicking the selected pill again clears it. Ctrl+Alt+Z clears all filters. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] A filter persists when you leave the list and come back. New items arrive live into the filtered list, so with Unread on, new unread items appear as they come in. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Filter keyboard shortcuts: Ctrl+Alt+U (all unread chats), Ctrl+Alt+C (chat conversations), Ctrl+Alt+A (channel conversations), Ctrl+Alt+B (meeting chats), Ctrl+Alt+Z (clear all filters). `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] `[new]` The **Meeting chats** filter is being *replaced* by a **Meeting chats system section**. See section 3. Rollout moved to early to late January 2027 (MC1269864, updated 2026-11-05). `[doc]`
  Source: https://mc.merill.net/message/MC1269864

## 3. Chat list: sections, Favorites and sorting

- [ ] **Favorites** section is on by default and takes the old pinned chats. Add to it by dragging, or with **More options > Move to > Favorites**. Remove with **More options > Remove from section**. Order is manual (drag). `[doc]`
  Source: https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066
- [ ] Custom sections: **New items** (down-arrow next to New message) > **New section**. A section can hold 1:1, group and meeting chats, channels, bots and AI agents. Items go in by drag-and-drop or by **Move to** / **Show in** in their context menu. Limits: **50 sections, 50 items each**. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf ; https://techcommunity.microsoft.com/blog/microsoftteamsblog/introducing-the-new-microsoft-teams-chat-and-channels-experience/4275674
- [ ] Sections can be **renamed, deleted, collapsed and reordered**. Reorder by dragging the section header on desktop. On mobile it's **… > Customize list view > Reorder**. A collapsed section still goes bold and shows "@". `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Per-section **Sort** menu (right-click the section header): **Custom** (manual drag; the default for Favorites and custom sections), **By recency** / **Most recent** (the default for Chats and the flat Channels list), and **Unread only** (shows only unread items, with a **See read items** link). In the team hierarchy, channels sort A–Z within each team. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Keyboard reorder: Ctrl+Alt+Shift+Up / Down moves the selected chat or channel up or down in the list. Alt+Q collapses all folders. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] `[new]` **Muted chats** system section (MC1269864). On by default. Muted chats that aren't in Favorites or a custom section move into it automatically. It sits at the bottom of the list. Unread items stay bold but do not add to the chat badge. Toggle it in **Settings > Chats and channels**. It can be dragged to reorder. No admin control. `[doc]`
  Source: https://mc.merill.net/message/MC1269864 ; https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066
- [ ] `[new]` **Meeting chats** system section (MC1269864). Off by default. When on, meeting chats that aren't in Favorites or custom sections move into it, below the main chat list. Unread items stay bold and still count toward the badge. Toggle it in Settings > Chats and channels. `[doc]`
  Source: https://mc.merill.net/message/MC1269864

## 4. Chat list: Quick views (Mentions, Followed threads, Tag mentions, Saved, Drafts, Reminders)

- [ ] **Quick views** header above the list. The section is collapsible and its header goes **bold** when any view has unread items. Hidden views are reached with the **eye icon** (**See more**) next to the header. Views can be dragged to reorder. Each view's context menu offers **Always**, **When unread** and **Hide**. `[doc]` `[new]` MC1234574 (GA late Mar–Jun 2026).
  Source: https://mc.merill.net/message/MC1234574 ; https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] Default visibility: **Mentions**, **Followed threads** and **Tag mentions** only appear when they contain at least one item. **Saved** can be set to always show or hidden. Older behaviour showed every view even when empty. `[doc]`
  Source: https://it.cornell.edu/teams/microsoft-teams-feature-updates-july-2026 ; https://mc.merill.net/message/MC1234574
- [ ] **@Mentions** view: one list of your personal @mentions across chats, meeting chats and channels, including hidden channels. Selecting a mention opens it in context in a **right-side pane**, where you can react or reply. In Separate view it only covers chats (in Chat) or channels (in Teams). `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] **Tag mentions** view: tag @mentions from channels gathered into one interactive list. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] **Followed threads** view, for channel threads you follow. `[doc]`
  Source: https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] **Saved** view: appears after the first saved message. Filters by **chats** / **channels**. Selecting an item opens the conversation in a new pane at that message. Items reflect later edits by the author. A deleted item keeps its title with a note that the author deleted it. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/save-a-chat-or-channel-message-in-microsoft-teams
- [ ] **Drafts** quick view: unsent compose drafts from every chat and channel in one place, where you can find, edit and send them. Chats with an unsent draft show a draft (pencil) icon in the list. `[new]` (March 2026) `[verify]` the icon.
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] **Discover** view (named in the April 2026 quick-view screenshot caption alongside Drafts and Tag mentions). `[verify]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/whats-new-in-microsoft-teams--april-2026/4515907
- [ ] `[new]` Personal **message reminders** (MC1470887, GA mid-Nov to Dec 2026). Set from a message's menu item ("Message Reminder"). A **Reminders view** lists upcoming, active and completed reminders. A toast fires when one is due and the Chat icon gets a badge. Reminders can be updated, completed or deleted, and are private to you. `[doc]`
  Source: https://mc.merill.net/message/MC1470887
- [ ] Copilot entry in the chat list: Copilot is pinned as a chat or app entry in the list for licensed users. `[verify]` where it sits (top of Chats vs. app bar).
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/microsoft-teams-february-2026/4497206

## 5. Chat list item: context menu ("More options" … / right-click)

- [ ] **Mark as unread** / **Mark as read**. The chat shows unread the next time you open it. Shift+Esc marks **all** chats and channels read. `[doc]`
  Source: https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066 ; https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] **Move to** > Favorites / an existing custom section / **New section**. **Remove from section**. **Show in** is used for channels. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] **Mute** / **Unmute**: you stay in the chat but get no notifications except @mentions. A mute icon shows next to the participant names. In a muted group chat the mute icon replaces the group image. Unread items stay bold but don't count toward the badge. Slash commands `/mute` and `/unmute` do the same. `[doc]`
  Source: https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066 ; https://support.microsoft.com/en-US/teams/chat/personalize-your-group-chat-image-in-microsoft-teams
- [ ] **Hide** / **Unhide** (1:1). The chat and its history are hidden until someone posts a new message. `/hide` does the same. To unhide, search for the person: a hidden chat's name shows in *italics*, then use **More options > Unhide**, or use Filter. **Show hidden chat history** reveals the old messages. `[doc]`
  Source: https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066 ; https://support.microsoft.com/en-us/office/delete-a-chat-thread-in-teams-6d2358d2-8d5b-48d3-b529-c685574f579d
- [ ] **Remove chat history** (1:1 only). This replaced the old **Delete chat**. It removes the chat from *your* list and search, and you can no longer reach it. The other person keeps it. `[doc]` `[admin]` (policy "Delete chat", on by default, asks for confirmation).
  Source: https://support.microsoft.com/en-us/office/delete-a-chat-thread-in-teams-6d2358d2-8d5b-48d3-b529-c685574f579d ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] **Leave** (group and meeting chats). The confirmation dialog has a checkbox to **remove chat history** from your chat list and search, then the **Leave** button. After leaving you can't send, and only a re-invite brings you back. A meeting *owner* can't leave or delete their meeting chat, but participants can. `/leavechat` does the same. `[doc]`
  Source: https://support.microsoft.com/en-us/office/delete-a-chat-thread-in-teams-6d2358d2-8d5b-48d3-b529-c685574f579d ; https://support.microsoft.com/en-US/teams/chat/leave-or-remove-someone-from-a-group-chat-in-microsoft-teams
- [ ] **Open chat in new window** (pop-out). Also opened by double-clicking the chat name, double-clicking a profile picture, `/window`, Ctrl+O (open the current conversation in a new window) and Ctrl+Shift+N (start a new chat in a new window). Several chats can be popped out, but the same chat can't be opened twice. The pop-out window can be resized, moved and closed independently. Scheduling a meeting, attaching OneDrive files and adding apps need the main window. Ctrl+Shift+T pins a window on top. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/open-a-chat-in-a-new-window-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Block** / **Unblock** (1:1 from an internal contact, when the chat-request policy applies). The blocked person isn't told. You can also unblock from the profile card: **More options > Unblock contact**. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/accept-or-block-chat-requests-from-people-inside-your-organization-in-microsoft-teams
- [ ] Hovering a chat row shows a pop-out icon and a "…" button. `[doc]` (pop-out icon on hover) `[verify]` the other hover icons.
  Source: https://support.microsoft.com/en-us/teams/chat/open-a-chat-in-a-new-window-in-microsoft-teams

## 6. New chat and group creation

- [ ] **New message** button (pencil icon) at the top of the list, or Ctrl+N. One compose surface handles chats *and* channel posts. The **To** field searches people, existing chats and channels. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf ; https://support.microsoft.com/en-us/office/start-a-chat-in-teams-0c71b32b-c050-4930-a887-5afbe742b3d8
- [ ] **Group name** field: the down arrow at the far right of **To** reveals it. Enter the name, then add people. `[doc]`
  Source: https://support.microsoft.com/en-us/office/overview-of-group-chats-in-teams-d563174d-ca98-440c-ade1-69176512122d
- [ ] Group size limit is **250 people**, and only **200 can be added at once**. Above **20 members** Teams turns off: Outlook auto-replies and status messages, the typing indicator, video and audio calling, screen sharing, read receipts, and the **Set delivery options (!)** button. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Start a chat with a distribution list, mail-enabled security group or Microsoft 365 group by typing the group name in **To** `[admin]` (policy "Chat with groups"). Tags can also be used in To. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams ; https://support.microsoft.com/en-us/teams/chat/add-or-invite-people-outside-your-org-to-a-chat-in-microsoft-teams
- [ ] Start a 1:1 from a profile card (click a picture in a channel or in search). Ctrl+Shift+N starts a chat in a new window. `[doc]`
  Source: https://support.microsoft.com/en-us/office/start-a-chat-in-teams-0c71b32b-c050-4930-a887-5afbe742b3d8
- [ ] Self-chat **"(You)"**: start a chat with your own name and use it for drafts, notes and files. The docs suggest dragging it to the top of Favorites. `[doc]` `[verify]` the "(You)" suffix rendering and that self-chat shows no call buttons.
  Source: https://support.microsoft.com/en-us/office/first-things-to-know-about-chats-88ed0a06-6b59-43a3-8cf7-40c01f2f92f2
- [ ] External (federated / Teams Free / Skype for Business) 1:1 by email address. Teams Free users can also be reached by phone number. If the person has no account, they get an email invite to create an unmanaged account, and the invite comes from the sender's own address. A Teams Free user must **accept** before chatting. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/add-or-invite-people-outside-your-org-to-a-chat-in-microsoft-teams
- [ ] Chat request banner from new contacts: **Accept** / **Block** (internal policy-driven requests). External first-contact requests have their own accept/block/delete flow. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/accept-or-block-chat-requests-from-people-inside-your-organization-in-microsoft-teams
- [ ] `[new]` External trust badges next to external users: **external-familiar**, **external-unfamiliar**, **guest**, **email verified**, **unverified**, shown as a full badge or icon only. Group and meeting chats that include external users are marked external. `[doc]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/microsoft-teams-february-2026/4497206
- [ ] **External** label at the top of the chat and next to external names in participant lists. A chat stays labelled external even after every external person leaves. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/add-or-invite-people-outside-your-org-to-a-chat-in-microsoft-teams
- [ ] External chats can't share or attach files, or use tabs or apps. Formatting, delivery options, emoji, GIFs and stickers, @mentions, edit and delete are allowed. Skype for Business users get plain text only. `[doc]` Exception: files and Loop components in external chats are auto-shared to every participant when the admin enables it `[new]` (March 2026).
  Source: https://support.microsoft.com/en-us/teams/chat/add-or-invite-people-outside-your-org-to-a-chat-in-microsoft-teams ; https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] External people can only be added to a group chat that already has an external member. Otherwise Teams creates a new group chat. An external chat goes **read-only** if every member of the originating org is removed. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/add-or-invite-people-outside-your-org-to-a-chat-in-microsoft-teams
- [ ] `[new]` AI phishing detection on first-contact external chats, and a "High-risk warning banner" (MC1519866). `[doc]`
  Source: https://mc.merill.net/message/MC1519866

## 7. Group membership, naming and image

- [ ] People button (participant count) in the header = **View and add participants**. Hovering it lists names. `/participants` does the same. `[doc]`
  Source: https://support.microsoft.com/en-us/office/start-a-chat-in-teams-0c71b32b-c050-4930-a887-5afbe742b3d8 ; https://support.microsoft.com/en-us/teams/chat/use-commands-in-microsoft-teams
- [ ] **Add people** (the current label is **Add people, agents, and bots**). Type a name or email, pick how much history the new person sees, then **Add**. History options are **Don't include chat history**, **Include history from the past [N] days** and **Include all chat history** `[verify]` exact labels. History sharing is only possible for existing *group* chats. Adding someone to a 1:1 creates a new group chat. `[doc]`
  Source: https://support.microsoft.com/en-gb/office/add-or-remove-people-in-a-group-chat-e089e1fe-cb11-489c-9381-fdecb1864a9d ; https://support.microsoft.com/en-us/office/overview-of-group-chats-in-teams-d563174d-ca98-440c-ade1-69176512122d
- [ ] Remove a person: hover the name in the participant list, choose **X Remove**, then confirm. The chat needs **3 or more people** `[admin]` (policy "Remove users from group chats"). A system message tells everyone. The removed person keeps the earlier history but can't send or react, or see new messages or files. `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/leave-or-remove-someone-from-a-group-chat-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] Former members keep the history they had. Messages *edited* after someone left are hidden from that former member. Messages from people who left stay in the chat. `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/leave-or-remove-someone-from-a-group-chat-in-microsoft-teams
- [ ] Rename a group chat: pencil icon next to the name in the header on desktop `[verify]`. On mobile it's **Group chat name** > **Save**. A rename posts a system event message. The name is held in Graph `chat.topic`. `[doc]` (mobile and Graph).
  Source: https://support.microsoft.com/en-us/office/overview-of-group-chats-in-teams-d563174d-ca98-440c-ade1-69176512122d ; https://learn.microsoft.com/en-us/graph/api/resources/chat
- [ ] Group chat image: hover the avatar left of the group name and choose **Change profile picture**. Pick **Upload** (max **4 MB**), a pre-set illustration or an emoji, then **Save**. Returning to the default is supported. Desktop and Web only. Not available for 1:1 or meeting chats. `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/personalize-your-group-chat-image-in-microsoft-teams
- [ ] System event messages (member added or removed, renamed, picture changed, meeting started or ended, and so on) render inline as small grey text. Graph `messageType = systemEventMessage` with `eventDetail`. `[doc]` (API) `[verify]` the text strings.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessage

## 8. Chat header

- [ ] Left side: avatar (presence dot for 1:1, group image or mosaic for groups) and the chat name. For a 1:1, clicking the name opens the profile card `[verify]`.
  Source: https://support.microsoft.com/en-US/teams/chat/personalize-your-group-chat-image-in-microsoft-teams
- [ ] Tabs: **Chat**, **Shared**, **+ Add a tab**. Meeting chats also get **Recap** (plus the meeting's own tabs). Alt+1…Alt+9 open the 1st–9th tab. **Shared** can't be removed. `[doc]` `[verify]` that Recap appears on meeting chats only.
  Source: https://support.microsoft.com/en-us/teams/chat-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **+ Add a tab**: choose an app, then **Add**. A file tab can only use a file already shared in that chat (pick the app for its type, choose the file, **Save**). Right-click a tab for **Copy link to tab** and **Remove**. In 1:1 and group chats any member can remove a tab, except defaults, tabs locked by policy and personal-app tabs. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams
- [ ] **Shared** tab: files, links and media shared in the chat, with an upload button (**Attach cloud files** / **Upload from this device**) and a **Links** folder. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/do-your-one-on-ones-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/chat/search-for-messages-and-more-in-microsoft-teams
- [ ] **Open notes** icon (collaborative notes) top right in group chats. It opens a Loop-based notes pane that anyone in the chat can edit. @mentions in it assign tasks that show up in To Do and Planner. **Close notes** shuts the pane. Desktop and Web only. Guests can't edit. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-collaborative-notes-in-microsoft-teams-chats
- [ ] 1:1 call buttons: **Video call** and **Audio call** in the header. Alt+Shift+V and Alt+Shift+A start them, and `/call` works too. Calling from a chat is capped at **20 people**, and the buttons are disabled when the chat has more than 20 members. `[doc]`
  Source: https://support.microsoft.com/en-us/office/start-a-call-from-a-chat-in-teams-f5138c9d-df4c-43d8-9cf6-53400c1a7798 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Group chats: **Meet now** button starts an instant meeting tied to the chat. `/meetnow` does the same. Other members see in their chat list that a meeting started, and a **Join** button appears in the chat. A live indicator at the top shows participants. In-meeting there's **Ring others to join** with per-person **Ring** and **Ring all**. The meeting ends when the last person leaves. `[doc]`
  Source: https://support.microsoft.com/en-us/office/start-an-instant-meeting-in-teams-ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Meet now **dropdown** (chevron). Typical items are **Meet now** / **Video call**, **Audio call**, **Schedule a meeting** (pre-filled with the chat members) and **Get a link to share** `[verify]`. MS docs don't list these items.
  Source: https://support.microsoft.com/en-us/office/start-an-instant-meeting-in-teams-ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] **Screen sharing** from the chat (**More chat options > Screen sharing**). Choose a screen or **Window**. Others must accept. It starts a muted call that can be escalated to a meeting. Group shares continue until the last person leaves, and others can **Join**. Not supported on Linux. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/share-your-screen-in-a-chat-in-microsoft-teams
- [ ] **Open Copilot** button (top right) for licensed users. See section 16. `[doc]`
  Source: https://support.microsoft.com/en-us/office/use-copilot-in-microsoft-teams-chat-and-channels-cccccca2-9dc8-49a9-ab76-b1a8ee21486c
- [ ] **Open Chat details** / **Close chat details** icon (Alt+P toggles the details pane). See section 9. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/show-chat-info-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Find in chat** magnifier icon (Ctrl+F). See section 18. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/show-chat-info-in-microsoft-teams
- [ ] Pop-out icon in the header (opens the chat in a new window). `[verify]` (the pop-out is documented from the list and by double-click).
  Source: https://support.microsoft.com/en-us/teams/chat/open-a-chat-in-a-new-window-in-microsoft-teams
- [ ] **More chat options (…)** in the header. Documented items: **Screen sharing**, **Mark as unread**. Typical others: Mute, Pin/Favorite, Leave or Remove chat history, Open in new window, Notifications `[verify]` the full list.
  Source: https://support.microsoft.com/en-us/teams/chat/share-your-screen-in-a-chat-in-microsoft-teams ; https://support.microsoft.com/en-us/office/send-and-read-messages-in-teams-b29e60ec-76af-4d97-8c3c-a4e36f2b64aa
- [ ] Pinned-message banner under the header: the latest pinned message is shown truncated to one line, with author and date. Clicking it jumps to the original. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/pin-a-chat-message-to-the-top-of-a-chat-in-microsoft-teams
- [ ] `[new]` Pinned resources bar under the header (MC1473153, GA early–mid Nov 2026). Pin several messages plus files and links below the header, organised into **folders**. This replaces the **In this chat** / **In this channel** panes. `[doc]`
  Source: https://mc.merill.net/message/MC1473153
- [ ] Out-of-office / status-message banner above the composer in 1:1 chats (disabled in groups over 20). `[doc]` (limits page names "Outlook automatic replies and Teams status messages") `[verify]` the layout.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams

## 9. Chat details pane

- [ ] Opens on the right for 1:1, group and meeting chats. Sections: **People** (up to 7 with presence; clicking one starts a chat; **See all**), **Pinned messages** (up to **10**; the most recent also shows as the header banner), **Shared** (files and links; per-item **More options** with copy, download and view; **See all** opens the Shared tab). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/show-chat-info-in-microsoft-teams
- [ ] Note the conflict on pin limits: the Pin article says "only one message can be pinned at a time", while Show-chat-info and MC1473153 describe up to 10 or several pins. Build for multiple pins, with the newest as the banner. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/pin-a-chat-message-to-the-top-of-a-chat-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/chat/show-chat-info-in-microsoft-teams

## 10. Composer: basics

- [ ] Compose box at the bottom ("Type a message" placeholder `[verify]`). Enter sends and Shift+Enter adds a new line. Ctrl+R focuses the composer. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] `[new]` **Enter key behaviour** setting in **Settings > Chats and channels**: Enter = send (default) or Enter = new line, in which case Ctrl+Enter sends. Shift+Enter is *always* a new line. The setting roams across devices. Not available for personal accounts. `[doc]`
  Source: https://it.cornell.edu/teams/microsoft-teams-feature-updates-july-2026 ; https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] **Show Formatting options** (the "Format" pen icon) expands the composer into the rich editor with a toolbar. Ctrl+Shift+X does the same. In expanded mode Ctrl+Enter sends. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/format-a-message-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Bottom-row composer buttons: **Emoji, GIFs and Stickers**; **Attach file** (paperclip; Alt+Shift+O); **Loop components**; **Actions and apps** (+), which holds Attach file, Schedule message, Set delivery options, Record a video clip and apps; **Open Copilot** (licensed); **Send**. `[doc]` `[verify]` the left-to-right order.
  Source: https://support.microsoft.com/en-us/teams/chat/schedule-chat-messages-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/chat/send-an-emoji-gif-or-sticker-in-microsoft-teams
- [ ] Discard an unsent message: in the expanded composer, **Delete** (trash) at the top right. `[doc]`
  Source: https://support.microsoft.com/en-us/article/5f1fe604-a900-4a07-b8b7-8cf70ed6b263
- [ ] Drafts persist per chat when you switch away, appear in the **Drafts** quick view, and show a draft indicator in the list. `[doc]` `[new]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] Spell check: red underline as you type, and right-click shows suggestions. Spelling works in multiple languages. There's no separate grammar check. `[doc]` Autocorrect in compose `[new]` (rollout done by Jan 2026).
  Source: https://support.microsoft.com/en-us/teams/chat/format-a-message-in-microsoft-teams ; https://it.osu.edu/news/2026/01/28/fresh-features-smarter-tools-microsoft-365-updates
- [ ] **Suggested replies**: chips above the composer after someone sends a few messages. Choosing one sends it straight away. Some include emoji. In groups they can reply to an @mention (and mention back) or to a quoted message. Toggle in **Settings > Chats and channels > Suggested replies** (on by default) `[admin]`. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-suggested-replies-to-respond-to-messages-without-typing-in-microsoft-teams
- [ ] **Text predictions** (ghost text): mobile only, **US English** only. Setting **Text predictions** under Chats and channels `[admin]`. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-editor-text-predictions-to-type-faster-in-microsoft-teams
- [ ] File suggestions while replying (mobile **Share file** chips; toggled with Suggested replies). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-file-suggestions-to-quickly-share-content-in-microsoft-teams
- [ ] Message size limit is about **100 KB per message**, including mentions and reactions but not base64 images. Keep the text under 80 KB to be safe. **10 file attachments** per message and **100 MB** per file in chat. Over the limit, an error message appears. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams

## 11. Composer: rich text formatting

- [ ] Toolbar and shortcuts: **Bold** Ctrl+B, **Italic** Ctrl+I, **Underline** Ctrl+U, **Strikethrough** Ctrl+Alt+X. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Text highlight**, **Font color**, **Font size** (three sizes: Small, Medium, Large). `[doc]` (highlight, size and colour are documented; the exact colour palette is `[verify]`).
  Source: https://support.microsoft.com/en-us/teams/chat/format-a-message-in-microsoft-teams
- [ ] **Paragraph styles**: Ctrl+Alt+P = Paragraph; **Heading 1/2/3** = Ctrl+Alt+1/2/3; **Monospace** style (mobile "rich style editor" lists heading, paragraph and monospaced). `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Bulleted list**, **Numbered list**, **Decrease indent** / **Increase indent**. `[doc]` (lists) `[verify]` (indent buttons).
  Source: https://support.microsoft.com/en-us/teams/chat/format-a-message-in-microsoft-teams
- [ ] **Quote** (block quote) Ctrl+Alt+4. **Insert link** Ctrl+K (**Format > Insert link**). Pasting a link onto selected text turns that text into a hyperlink. Ctrl+Shift+V pastes the raw URL with no formatting or truncation. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 ; https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams
- [ ] **Inline code** Ctrl+Shift+C on Windows; the web uses Ctrl+Alt+Shift+C. "Insert code" Ctrl+Alt+5. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Insert table**, **Horizontal rule**, **Clear all formatting**, **Undo/Redo** in the expanded toolbar's **More options (…)** overflow. `[doc]` (overflow menu, "Clear all formatting") `[verify]` (table and rule).
  Source: https://support.microsoft.com/en-us/teams/chat/format-a-message-in-microsoft-teams
- [ ] Live Markdown-style autoformat while typing: `*bold*`, `_italic_`, `~strike~`, `1. ` numbered list, `* ` / `- ` bullet list, `[text](url)`, `` `code` ``, ```` ``` ```` code block, `# ` / `## ` / `### ` headings, `> ` quote. Ctrl+Z undoes the autoformat. Formatting is a live preview in the box. On mobile you can view Markdown-formatted messages but not create them. `[doc]` `[new]` Further Markdown syntax is on the roadmap for November 2026 (desktop, Linux and Mac).
  Source: https://support.microsoft.com/en-US/teams/chat/use-markdown-formatting-in-microsoft-teams ; https://windowsforum.com/news/microsoft-teams-to-expand-compose-box-markdown-support-in-november-2026.449167/
- [ ] **Add Loop paragraph** Ctrl+Alt+L (Alt+Shift+L in the navigation list). `/loop` does the same. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 ; https://support.microsoft.com/en-us/teams/chat/use-commands-in-microsoft-teams
- [ ] Alt+F10 moves focus to the toolbar from an edit field. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 12. Composer: code blocks

- [ ] Insert a code block four ways: `/code`, the **Code block** toolbar button, three backticks, or Ctrl+Shift+B (Windows desktop; Ctrl+Alt+Shift+B on web and in another article). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-code-blocks-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Language dropdown above the block (C#, HTML, Java, Python, Plain Text…) drives syntax highlighting. The last language chosen is remembered. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-code-blocks-in-microsoft-teams ; https://support.microsoft.com/en-au/office/add-a-code-snippet-to-a-message-5613646e-2144-4943-821d-952939c9268e
- [ ] `[new]` **Line numbers on by default**, better keyboard navigation inside blocks (July 2026). The block's **More options > Display options > Wrap text** wraps long lines. `[doc]`
  Source: https://it.cornell.edu/teams/microsoft-teams-feature-updates-july-2026 ; https://support.microsoft.com/en-us/teams/chat/use-code-blocks-in-microsoft-teams
- [ ] **Make this collaborative** (block **More options**, before sending only) converts the block to a Loop code block. Pasting more than **30,000 characters** converts it automatically. Code blocks can only be *created* on desktop. Recipients can copy code from the sent message. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-code-blocks-in-microsoft-teams

## 13. Composer: emoji, GIFs, stickers and custom emoji

- [ ] **Emoji, GIFs and Stickers** picker on the right of the composer, with tabs **Emoji / GIFs / Stickers**, a search box and category galleries. On mobile the categories are Smilies, Hand gestures, People, Animals, Food, Travel and places, Objects, Activities, Symbols (800+ emoji). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-an-emoji-gif-or-sticker-in-microsoft-teams
- [ ] Emoji shortcodes: type `:` plus a name (for example `:smile:`). An autocomplete list appears and Enter inserts the top match. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-an-emoji-gif-or-sticker-in-microsoft-teams
- [ ] Skin tone: emoji with a grey corner dot can be personalised. Right-click shows the variants. A default skin tone is set in **Customize default reactions**. Recent emoji sync across devices. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-an-emoji-gif-or-sticker-in-microsoft-teams ; https://support.microsoft.com/en-us/topic/834681bf-ad45-4c12-a384-82db7208d5c8
- [ ] GIFs come from **Giphy**, searchable `[admin]` (policy "Use Giphy in conversations"; content rating No restriction / Moderate / Strict; also needs Optional Connected Experiences). `/gif` does the same. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams ; https://support.microsoft.com/en-us/teams/chat/use-commands-in-microsoft-teams
- [ ] Stickers and memes: items with an edit icon accept caption text (caption boxes, then **Done**). Desktop and Web only for captions `[admin]` (policies "Memes in conversations" and "Stickers in conversations"). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-an-emoji-gif-or-sticker-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] Custom (org) emoji: **Your org's emoji** (the **Custom** category) at the bottom of the Emoji tab, then **Add emoji** (+): pick an image or GIF (JPEG, PNG or GIF, square, **under 256 KB**, compressed on upload) and enter a name. Up to **5,000 per tenant**. Right-click shows who created it and when, and offers **Delete** to those allowed. A deletion can take up to 24 h to reach everyone. Your own creations show first. Usable in messages and reactions. Not available for EDU tenants `[admin]` (Upload / Delete custom emojis; tenant toggle). `[doc]`
  Source: https://support.microsoft.com/teams/chat/use-custom-emoji-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/teams-custom-emojis

## 14. Composer: attachments, images, links and media

- [ ] **Attach file** (**Actions and apps > Attach file**, or Alt+Shift+O): recent files, **Attach cloud files** (OneDrive or SharePoint picker) and **Upload from this device**. 1:1 and group chat files go to the sender's OneDrive (needs a OneDrive / SharePoint licence). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Permission check before sending: if a recipient lacks access, a banner shows on the file chip with **Give access** and then **Update access**. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams
- [ ] Background upload with a progress indicator, so you can keep chatting while it finishes. Messages may reorder once the upload completes. `[doc]` `[new]` (September 2026)
  Source: https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams
- [ ] Paste or drag-and-drop images into the composer. They're sent as inline images (hosted content). Up to 5 images per forwarded message. `[verify]` (paste and drag). `[doc]` (hostedContents)
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessage ; https://support.microsoft.com/teams/chat/forward-messages-in-microsoft-teams
- [ ] Inline previews: images, videos and many document types preview automatically. A single PDF or 3D file (GLB, STL, FBX, OBJ) previews inline. With more than 3 attachments the preview only appears after sending. No preview when you lack permission, the file has a sensitivity label, or the chat includes external users. `.zip` never previews. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams
- [ ] `[new]` EXIF metadata (GPS, device) is stripped from shared images by default. `[doc]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] Image viewer (lightbox): scroll through *all* images in the conversation, with the current one highlighted. **Show message associated with the featured image** jumps to its message, and more images load as you scroll. `[doc]` `[new]` (March 2026)
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/what’s-new-in-microsoft-teams--march-2026/4506985
- [ ] Link previews: pasted URLs unfurl into a preview card, which the sender can remove before sending (the X on the card) `[verify]`. ATP Safe Links warn on unsafe links, and long URLs may be truncated `[admin]` (policy "URL previews"). `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams ; https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams
- [ ] **Record a video clip** (**Actions and apps**, or Alt+Shift+E, or `/record`). Modes are camera, **Screen** and audio-only (toggle **Camera**). Max **1 minute**. Pause and resume, **Trim** > **Confirm trim**, **Continue**, re-record with the back arrow. Captions are auto-generated. Hovering a sent clip gives **More video clip options**: **Download Transcript** and **Download video** (.mp4) `[admin]` (policy "Video messages"). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/record-a-video-or-audio-clip-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] Voice messages (audio clips; mobile hold-to-record) `[admin]` (policy "Create voice messages": chats and channels / chats only / off). `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] Share a contact: type `@` and choose **Share someone's contact info**, pick one or more people, then **OK**. This sends a link to their contact card without notifying them. Org members only. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/share-a-contact-in-a-chat-or-channel

## 15. Composer: Loop components, apps and slash commands

- [ ] **Loop components** button in the composer. Types include paragraph, table, checklist (plus bulleted list, numbered list, task list, Q&A, voting table, progress tracker `[verify]` the full menu). Recipients edit inline. Type `/` inside to insert a mention, date or component, and `//` to comment. **Copy link** (top right) pastes it live elsewhere. **See who has access** shows viewers' avatars. Opening the linked file name opens it on Office.com (Loop). Files are saved to OneDrive. Needs a OneDrive licence. `[doc]`
  Source: https://support.microsoft.com/en-us/office/first-things-to-know-about-loop-components-in-microsoft-teams-ee2a584b-5785-4dd6-8a2d-956131a29c81
- [ ] Slash commands in the composer: /apps, /available, /away, /brb, /busy, /chat, /code, /dnd, /gif, /goto, /hide, /hidelivecaptions, /leavechat, /loop, /meetnow, /mute, /notifications, /offline, /participants, /record, /reset, /schedulemessage, /settings, /shortcuts, /showlivecaptions, /starttranscription, /stoplivetranscription, /unmute, /window, /workflows, plus app commands (/Github, /Jira…). Built-in commands are desktop only. `[doc]` `[new]` /createworkflow (Apr–May 2026); app slash commands (July 2026).
  Source: https://support.microsoft.com/en-us/teams/chat/use-commands-in-microsoft-teams ; https://m365admin.handsontek.net/microsoft-teams-new-slash-command-compose-create-workflows/
- [ ] Messaging-extension apps from **Actions and apps** (search apps, insert app cards). Apps can also be inserted inline. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/apps-service/insert-app-content-in-microsoft-teams-messages
- [ ] Praise (send Praise badges) from apps. `[doc]` (listed in the support TOC)
  Source: https://support.microsoft.com/en-us/office/first-things-to-know-about-chats-88ed0a06-6b59-43a3-8cf7-40c01f2f92f2

## 16. Composer and chat: Copilot

- [ ] **Open Copilot** in the chat header opens a side pane that reads the chat (default **30 days** of history unless you name a range). It gives recaps, action items and decisions, and answers "Summarize what I've missed", "What links were shared?" and similar. Suggested prompts sit under its compose box (**Show more**; meeting chats use **View prompts**). **Sources** links jump to the cited messages. There's a copy icon and thumbs feedback, and **Generate next response** when the range overflows. It can't read images, Loop components or files. In meeting chats it uses the transcript when one exists. `[doc]`
  Source: https://support.microsoft.com/en-us/office/use-copilot-in-microsoft-teams-chat-and-channels-cccccca2-9dc8-49a9-ab76-b1a8ee21486c
- [ ] Compose Copilot (**Open Copilot** beneath the message box, or Alt+A): **Rewrite** and **Adjust** (tone and length; **Custom tone** takes free text such as "longer and cheerful and in Spanish"). Works on a selection or the whole draft, and also on sent messages through Edit. Limited to about **75 words** and plain text. `[doc]` (via Microsoft support search results; the page itself was rate-limited during research).
  Source: https://support.microsoft.com/office/rewrite-and-adjust-your-messages-with-copilot-in-microsoft-teams-53315d9c-93be-45ab-9004-2f8205725cc7 ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] `[new]` Agents in chat: partner agents (Linear, Cursor, Atlassian Rovo) can be invoked in chats. **Targeted messages** from agents are visible only to one user in a group or meeting chat, and can be updated or removed by the agent (Graph `targetedChatMessage`). `[doc]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/whats-new-in-microsoft-teams--april-2026/4515907 ; https://learn.microsoft.com/en-us/graph/api/resources/chat

## 17. Composer: delivery options, scheduling and @mentions

- [ ] **Set delivery options** (**Actions and apps > Set delivery options**, or the "!" button): **Standard**, **Important**, **Urgent**. Important shows a red "IMPORTANT!" label and Ctrl+Shift+I toggles it. Urgent shows "URGENT!" and re-notifies recipients **every 2 minutes for 20 minutes** or until read `[admin]` (policy "Send urgent messages using priority notifications"). An **urgent message can't be edited** after sending. Importance can be changed on a sent message through Edit (Important / Standard). The button is hidden in groups over 20. Graph `importance` = normal / high / urgent. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/mark-a-message-as-important-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] **Schedule message** (**Actions and apps > Schedule message**, `/schedulemessage`, or right-click / long-press Send): a date and time picker, then **Continue**, then **Send**. The message waits in the chat as scheduled. Edit it with the pencil. Reschedule through Edit with the chevron by the scheduled time, then **Continue** and **Done**. Delete with **More options > Delete**. You can only schedule in a conversation that already exists. Viva Insights can suggest a send time for messages that would arrive after hours. `[doc]` `[verify]` the scheduled-message banner and its max horizon.
  Source: https://support.microsoft.com/en-us/teams/chat/schedule-chat-messages-in-microsoft-teams ; https://support.microsoft.com/en-US/viva/insights/schedule-send-suggestions-in-teams-chat
- [ ] @mentions: typing `@` opens a people picker. A mention notifies the person, links to the message from Activity, and is stored in Graph `mentions` (user, bot, team, channel, chat, tag). Backspacing inside a resolved mention shortens it to the first name `[verify]`. `[doc]`
  Source: https://support.microsoft.com/en-us/topic/eb4f059d-320e-454e-b111-03361d4d6855 ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
- [ ] **@everyone** in group chats notifies every member. `[doc]`
  Source: https://support.microsoft.com/en-us/topic/eb4f059d-320e-454e-b111-03361d4d6855
- [ ] Tag mentions (`@tagname`) notify a tag's members in channels, and a new chat can be started with a tag. Limits are 200 tags per team and 200 members per tag. `[doc]`
  Source: https://support.microsoft.com/en-us/office/using-tags-in-teams-667bd56f-32b8-4118-9a0b-56807c96d91e ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Mentioned messages get an "@" marker in the chat list and an Activity notification. Muted chats still notify on @mentions. `[doc]`
  Source: https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066

## 18. Message rendering and states

- [ ] Message grouping: consecutive messages from the same sender collapse under one avatar and name header. Your own messages are right-aligned bubbles in a different shade, and others' are left-aligned with avatar and name. Timestamp on hover `[verify]` pixel details.
  Source: https://support.microsoft.com/en-us/teams/chat/change-the-spacing-of-your-chat-messages-in-microsoft-teams
- [ ] Delivery states on your last message: **Sending** (spinner) `[verify]`, **Sent / Delivered** (Delivered icon), **Seen** (eye icon) once the recipient reads it in the chat window, and **Failed to send** with Retry `[verify]`. `[doc]` (Delivered and Seen).
  Source: https://support.microsoft.com/en-us/teams/chat/use-read-receipts-for-messages-in-microsoft-teams
- [ ] Read receipts: on by default `[admin]` (User controlled / On for everyone / Off for everyone). User toggle in **Settings > Chats and channels > Read receipts**. They work in 1:1 and in groups of **20 or fewer**. Not shown for external users or when either side has receipts off. Seeing a message in a toast, the Activity feed, a banner or a profile card doesn't count as read. Not supported in channels. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-read-receipts-for-messages-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] **Read by** (message **More options > Read by**) lists who has read a message in groups of 20 or fewer. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-read-receipts-for-messages-in-microsoft-teams
- [ ] Typing indicator ("Name is typing…" with animated dots) at the bottom of the conversation, and in the chat list `[verify]` the list placement. Disabled in chats over 20 members. Graph `messageType` includes `typing`. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
- [ ] **Edited** label on edited messages (Graph `lastEditedDateTime` triggers the "Edited" flag). `[doc]`
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
- [ ] Deleted message placeholder ("This message has been deleted.") with **Undo** for the sender. `[doc]` (Undo) `[verify]` the placeholder text.
  Source: https://support.microsoft.com/en-us/office/send-and-read-messages-in-teams-b29e60ec-76af-4d97-8c3c-a4e36f2b64aa
- [ ] Unread divider / "new messages" marker and **Jump to last read or newest message** (Ctrl+J). `[doc]` (shortcut) `[verify]` the divider styling.
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Day separators between messages from different days `[verify]`.
  Source: https://support.microsoft.com/en-us/teams/chat/preview-messages-in-microsoft-teams
- [ ] Reactions render as pills under the message, each with an emoji and a count. Clicking your own pill removes your reaction. Hovering shows who reacted `[verify]`. The cap is **20 distinct reactions per message**. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/send-an-emoji-gif-or-sticker-in-microsoft-teams ; https://support.microsoft.com/en-us/topic/834681bf-ad45-4c12-a384-82db7208d5c8
- [ ] Quoted-reply rendering: a quote block with the original author, time and snippet sits above your reply. Clicking it scrolls to and highlights the original. `[doc]`
  Source: https://support.microsoft.com/office/reply-to-a-specific-message-in-chat-940c614c-4f07-41d4-850b-90f11da8329b
- [ ] Forwarded-message rendering: a "Forwarded" header with the original sender and a clickable timestamp that opens the original if you have access (otherwise a "content isn't available" notice). Multi-forwards bundle up to 5 messages in their original order. `[doc]` `[new]` link to the original (MC1157710, Sept 2025).
  Source: https://support.microsoft.com/teams/chat/forward-messages-in-microsoft-teams ; https://mc.merill.net/message/MC1157710
- [ ] Adaptive Cards from bots, connectors and apps render inline. Teams supports **Adaptive Card schema ≤1.6**, plus Hero, Thumbnail, List, Receipt, Sign-in and O365 connector cards and carousels (max 10 cards). No positive or destructive action styling, no file upload, no `isEnabled` on Action.Submit. Card images are at most 1024×1024 PNG, JPEG or GIF. Supported actions include Action.OpenUrl, ShowCard, ToggleVisibility, Execute and Submit. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/cards-reference
- [ ] Meeting-related system cards in chats: "Meeting started" with a **Join** button, meeting ended plus duration, recording and transcript cards in meeting chats `[verify]`.
  Source: https://support.microsoft.com/en-us/office/start-an-instant-meeting-in-teams-ff95e53f-8231-4739-87fa-00b9723f4ef5
- [ ] Message font size setting: Small, Medium, Large `[verify]` (support article "Change message font size in Microsoft Teams").
  Source: https://support.microsoft.com/fi-fi/teams/notifications-settings/change-message-font-size-in-microsoft-teams

## 19. Message actions (hover bar and More options)

- [ ] Hover bar on a message: up to **5 quick reactions** (customisable), a **More reactions** (+ smiley) button, **Edit** (pencil, own messages) and **More options (…)**. Ctrl+Alt+R reacts to the last message. `[doc]`
  Source: https://support.microsoft.com/en-us/topic/834681bf-ad45-4c12-a384-82db7208d5c8 ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **More reactions** opens the full emoji picker, so *any* emoji can be a reaction, including custom org emoji. **Customize default reactions**: hover a default and click its **X** to remove it, **+** adds one (max 5), choose a skin tone, then **Save**. `[doc]`
  Source: https://support.microsoft.com/en-us/topic/834681bf-ad45-4c12-a384-82db7208d5c8 ; https://support.microsoft.com/teams/chat/use-custom-emoji-in-microsoft-teams
- [ ] **Reply** (quoted reply): **More options > Reply** puts a quote preview in the composer that can be dismissed. Works in 1:1, group and meeting chats on desktop and web. Alt+Shift+R replies to the last message. Graph `replyWithQuote` supports quoting one *or several* messages. `[doc]`
  Source: https://support.microsoft.com/office/reply-to-a-specific-message-in-chat-940c614c-4f07-41d4-850b-90f11da8329b ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
- [ ] **Edit** (own messages): the message turns editable in place. **Done** (check mark) saves and Esc cancels. Edits are unlimited `[admin]` (policy "Edit sent messages"). Not allowed on **urgent** messages. Up arrow in an empty composer edits your last message `[verify]` (Mac Option+Shift+E is documented). `[doc]`
  Source: https://support.microsoft.com/en-us/article/5f1fe604-a900-4a07-b8b7-8cf70ed6b263 ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] **Delete** (own messages): **More options > Delete** replaces the message with a placeholder and an **Undo** button `[admin]` (policies "Delete sent messages", "User can delete messages sent by bots", "Users with full chat permissions can delete any message"). Graph `softDelete` / `undoSoftDelete`. `[doc]`
  Source: https://support.microsoft.com/en-us/article/5f1fe604-a900-4a07-b8b7-8cf70ed6b263 ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
- [ ] **Pin** / **Pin for everyone**: the message goes to the top banner and the details pane. **Unpin for everyone**. Any non-guest member can pin, replace or unpin. Graph `pinnedMessages`. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/pin-a-chat-message-to-the-top-of-a-chat-in-microsoft-teams ; https://learn.microsoft.com/en-us/graph/api/resources/chat
- [ ] **Save this message** / **Unsave this message**. Saved items appear in the **Saved** quick view. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/save-a-chat-or-channel-message-in-microsoft-teams
- [ ] **Forward**: a dialog takes a person, group chat or channel (adding several people creates a group chat), an optional note on top, then **Forward**. A **View** toast follows. **Forward > Multiple messages** shows checkboxes on messages; pick **up to 5**, then **Next** (desktop and web; mobile can view but not create). Forwardable content: text, files, Loop components, app cards, images (≤5). Hidden when a sensitivity label blocks it. `[doc]` `[new]` multi-forward (GA Feb 2026, MC1199767).
  Source: https://support.microsoft.com/teams/chat/forward-messages-in-microsoft-teams ; https://mc.merill.net/message/MC1199767
- [ ] **Copy link**: a deep link to the message. Opening it scrolls to and highlights the message. People outside the chat can't open it. A deleted target shows a notification bar. Graph `webUrl`. `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/share-a-link-to-a-specific-message ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
- [ ] **Copy** (copy text) on the message, plus normal text selection with Ctrl+C. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/copy-and-paste-text-in-microsoft-teams
- [ ] **Share to Outlook**: opens an email compose with a copy of the single chat message. Add recipients and attachments, then send. Not on mobile. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/teams-channels/share-to-outlook-from-microsoft-teams
- [ ] **Translation > Translate** / **See original**. An inline **Translate** suggestion appears on foreign-language messages, with **Never translate (language)**. **Translation > Turn on auto-translation**. **Translation options** offers Settings and Give feedback. Settings are in **Settings > General > Translation**: target language, **Ask me before translating** / **Auto-translate all messages** / **Never translate**, and a "Never translate messages in these languages" list. Suggestions and auto-translation are chat only. Short messages aren't auto-translated `[admin]` (policy "Translate messages"). `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/translate-a-message-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] **Immersive Reader** (read aloud, focus) `[admin]` (policy "Immersive reader for messages"). `[doc]`
  Source: https://support.microsoft.com/en-us/office/send-and-read-messages-in-teams-b29e60ec-76af-4d97-8c3c-a4e36f2b64aa ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] **Mark as unread** from a specific message, so the chat goes unread from that point. `[doc]`
  Source: https://support.microsoft.com/en-us/office/send-and-read-messages-in-teams-b29e60ec-76af-4d97-8c3c-a4e36f2b64aa
- [ ] **Read by** (groups of 20 or fewer). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/use-read-receipts-for-messages-in-microsoft-teams
- [ ] **Report this message**, with reasons **Security concern** / **Not a security concern** (only for messages carrying URL warnings; optional text) / **Inappropriate**, then **Report** and a confirmation. Not available in the Copilot app `[admin]` (policies "Report inappropriate content" and "Report a security concern"). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/report-messages-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams
- [ ] `[new]` **Message Reminder** (set a reminder on a message). `[doc]`
  Source: https://mc.merill.net/message/MC1470887
- [ ] **More actions** submenu: app message actions (Create task in Planner, workflows "Start a workflow", Create work item…). Workflows from messages arrived on mobile in April 2026. `[doc]`
  Source: https://techcommunity.microsoft.com/blog/microsoftteamsblog/whats-new-in-microsoft-teams--april-2026/4515907
- [ ] "Turn on notifications" for a specific message or thread: channels only (`/notifications`). There's no chat equivalent beyond Mute and Unmute `[verify]`.
  Source: https://support.microsoft.com/en-us/teams/chat/use-commands-in-microsoft-teams
- [ ] Right-click a message opens the same menu as **More options** `[verify]`.
  Source: https://support.microsoft.com/en-us/topic/834681bf-ad45-4c12-a384-82db7208d5c8

## 20. Search within and across chats

- [ ] **Find in chat** (Ctrl+F, or the magnifier in the header): type a term, then **Go**. Results list in a right pane titled **Find in chat**, and selecting one jumps to the message. `[new]` Filters for date, person and attachments. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/search-for-messages-and-more-in-microsoft-teams ; https://support.microsoft.com/en-us/topic/d7092a6d-c896-424c-b362-a472d5f105de
- [ ] Global search box (Ctrl+E). Result tabs **Messages**, **Files**, **People**, **Teams and Channels**, **Group chats**. Message filters: **Type** (Chats / Channels), **Teams and channels**, **From**, **Date**, **More** (@Mentions, has attachments, hide app and bot messages). Group chats with no activity for 180+ days may not appear. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/search-for-messages-and-more-in-microsoft-teams
- [ ] Search operators: `From:`, `In:`, `Subject:`, `Sent:` (no space after the colon), a trailing `*` wildcard, and "quoted phrases". People search handles spelling corrections and nicknames. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/search-for-messages-and-more-in-microsoft-teams
- [ ] **Go to** (Ctrl+G, or `/goto`): the search bar switches to a "Go to" mode that jumps to a chat or channel by participant or channel name. `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf
- [ ] Text search filter inside the chat list (under **More filters**). `[doc]`
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf

## 21. Notifications tied to chat

- [ ] Toasts for new chat messages with an inline **Reply** box `[verify]`. Toast content follows **Settings > Notifications and activity > Display > Show message and content previews in notifications**. Ctrl+Alt+T focuses the toast and Win+Shift+Y focuses the notification. `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/preview-messages-in-microsoft-teams ; https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] App badge and Chat-icon unread count. Muted chats are excluded. Meeting-chat-section items are included. `[doc]`
  Source: https://mc.merill.net/message/MC1269864
- [ ] `[new]` **Activity in other accounts and orgs** panel (desktop): notifications from up to 10 per tenant, grouped by tenant. Clicking one opens that chat in a separate window without switching tenant, and viewing doesn't mark it read. Up to 3 tenants can be pinned to the left rail. `[doc]`
  Source: https://it.cornell.edu/teams/microsoft-teams-feature-updates-july-2026

## 22. Mobile-only or platform differences (for reference)

- [ ] **Catch up** (mobile only): cards for @mentions, 1:1, group and meeting chats (unless muted) and followed threads. Swipe right to **Mark as read**, swipe left to **Keep unread**, with **Undo**. **Sort by** offers **@Mentions first** / **Recent**. Ends with "You're all caught up". `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/catch-up-on-conversations
- [ ] Mobile limitations: Markdown can't be created, code blocks can't be created, Share to Outlook isn't available, multi-forward can't be created, and meme or sticker captions aren't available. Text predictions are mobile only. `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/use-markdown-formatting-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/chat/use-code-blocks-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/teams-channels/share-to-outlook-from-microsoft-teams
- [ ] Mac shortcut differences: Cmd+Return sends, Option+Shift+E edits the last message, Shift+Cmd+X expands the composer. On the web, inline code and code block shortcuts add Alt. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 23. Keyboard shortcuts relevant to chat (Windows desktop)

- [ ] General: Ctrl+. or Alt+/ (shortcut list; `[new]` the dialog is searchable by name or keys), Ctrl+E search, Ctrl+Shift+F filter, Ctrl+N new chat, Ctrl+Shift+N new chat in a new window, Ctrl+O open the current conversation in a new window, Ctrl+G go to, Ctrl+, Settings, Esc close, Ctrl+= / Ctrl+- / Ctrl+0 zoom, Ctrl+Shift+T pin window on top. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 ; https://techcommunity.microsoft.com/blog/MicrosoftTeamsBlog/what%E2%80%99s-new-in-microsoft-teams--july-2026/4542510
- [ ] Navigation: Ctrl+L focus the chat list, Ctrl+M focus the message pane, Ctrl+R focus the composer, Ctrl+H history menu, Alt+Left / Alt+Right back and forward, Ctrl+F6 / Ctrl+Shift+F6 next and previous section, Ctrl+1…9 app bar. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Messaging: Shift+Esc mark all read, Ctrl+J jump to last read or newest, Ctrl+F find in chat, Alt+1…9 header tabs, Alt+P details pane, Alt+Shift+R reply to the last message, Ctrl+Alt+R react to the last message, Ctrl+Alt+U/C/A/B/Z filters, Ctrl+Alt+Shift+Up/Down move the chat in the list, Alt+Q collapse folders. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- [ ] Compose: Ctrl+Shift+X expand, Ctrl+Enter send (expanded), Shift+Enter new line, Alt+Shift+O attach, Ctrl+Shift+I important, Alt+A Copilot rewrite, Alt+Shift+E video recorder, Ctrl+Alt+L Loop paragraph, Ctrl+K link, Ctrl+B/I/U, Ctrl+Alt+X strikethrough, Ctrl+Alt+1/2/3 headings, Ctrl+Alt+P paragraph, Ctrl+Alt+4 quote, Ctrl+Alt+5 code, Ctrl+Shift+C inline code, Ctrl+Shift+B code block, Ctrl+Shift+V paste plain, Alt+F10 toolbar focus. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2 ; https://support.microsoft.com/en-us/teams/chat/send-a-file-picture-or-link-in-microsoft-teams
- [ ] Calls from chat: Alt+Shift+A audio call, Alt+Shift+V video call, Ctrl+Shift+R open meeting chat from a meeting notification. `[doc]`
  Source: https://support.microsoft.com/office/2e8e2a70-e8d8-4a19-949b-4c36dd5292d2

## 24. Settings > Chats and channels (and related) affecting chat

- [ ] **Combined / Separate** view, **Show message previews for chats and team names for channels**, **Show time stamps**, **Message density** (Comfy / Compact), **Read receipts**, **Suggested replies**, Enter key behaviour, **Muted chats** section toggle, **Meeting chats** section toggle (the docs' label is "Show meeting chats in their own section"). `[doc]`
  Source: https://support.microsoft.com/en-us/teams/chat/change-the-spacing-of-your-chat-messages-in-microsoft-teams ; https://support.microsoft.com/en-us/teams/chat/preview-messages-in-microsoft-teams ; https://mc.merill.net/message/MC1269864 ; https://support.microsoft.com/en-us/office/hide-unhide-mute-pin-or-mark-a-chat-as-unread-in-microsoft-teams-9aee02ef-713d-495b-8a73-9762d8e4b066
- [ ] **Settings > General > Translation** (see section 19). `[doc]`
  Source: https://support.microsoft.com/en-US/teams/chat/translate-a-message-in-microsoft-teams
- [ ] Admin messaging policies the client must honour: Owners can delete sent messages, Delete sent messages, Delete messages sent by bots, Delete chat, Edit sent messages, Read receipts (3 modes), Upload / Delete custom emojis, Chat (off = no new chats), Chat with groups, Giphy plus rating, Memes, Stickers, URL previews, Report inappropriate content, Report a security concern, Translate messages, Immersive reader, Urgent priority notifications, Voice messages (3 modes), Remove users from group chats, Text predictions, Suggested replies, Chat permission role (supervised chat), Full-permission delete any message, Video messages, Viva Engage experiences, Designer backgrounds. `[doc]`
  Source: https://learn.microsoft.com/en-us/microsoftteams/messaging-policies-in-teams

## 25. Backing Microsoft Graph surface (for implementers)

- [ ] Chats: `GET /me/chats` (with `$expand=lastMessagePreview`), `POST /chats` (oneOnOne / group; `topic`), `PATCH /chats/{id}` (rename), members (`/chats/{id}/members` add / remove), `tabs`, `pinnedMessages` (pin / unpin), `installedApps`. `viewpoint` gives `isHidden` and `lastMessageReadDateTime`. `chatType` = oneOnOne / group / meeting. `[doc]`
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chat
- [ ] Messages: `GET/POST /chats/{id}/messages`, `softDelete` / `undoSoftDelete`, `setReaction` / `unsetReaction`, `replyWithQuote` (one or several messages), `hostedContents` (inline images and code). Properties: `importance` (normal / high / urgent), `mentions`, `attachments`, `reactions`, `messageHistory`, `lastEditedDateTime` (Edited flag), `deletedDateTime`, `eventDetail` (system events), `webUrl` (Copy link). Change notifications are available. Note that Graph v1 *update* for user messages is documented only for `policyViolation`; editing goes through the client APIs. `[doc]`
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessage
