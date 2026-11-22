---
id: TASK-0206
title: Chat list leftovers found in live checks
status: In Progress
assignee: []
created_date: '2026-11-16T20:22:00Z'
updated_date: '2026-11-22T19:59:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while checking TASK-0150/0195/0204 against Teams on winpc (2026-11-16):
- A group chat's menu shows Mute where Teams now has "Manage notifications ▸".
- A typed search in the new chat form lists only people; Teams also lists chats and groups.
- Create team lacks Teams' new "Add Channel Agent" checkbox.
- A person picked in Add members can show a blank picture until it loads.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each item matches Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chatC), measured on winpc and read from Teams 26304.
  - Group chat menu: Open in new window | Mark as unread, Manage notifications ▸, Move to section ▸, Manage apps, Set workflows, Copy link | Leave, Hide.
    - Teams shows Manage notifications instead of Mute for a group chat you're in when Activity.enableGranularChatNotificationSettings and Messaging.enableThreadingInChat are on (158033).
    - Flyout (873861): "Select what content notifies you", then All new messages and Mute. The current one is checked; "Customized" follows it when you changed its parts. A line, then Customize.
    - Customize opens the chat version of the channel dialog: the chat's picture and name, "Manage notifications", the All new messages card with Follow all new threads and Everyone mentions, the Mute card, and the desktop preference ("Desktop notifications are on for all chats. Go to notifications settings for all chats", "Set a preference for this chat": Match settings used for all chats / Get notified for selected content / Don't get desktop notifications). Cancel, and Save (enabled once something changes).
    - Storage (shared-worker resolver): IC3 conversation properties.
      - conversationNotificationSettings: JSON {…old, everyone, dskNotif, allNewPosts}.
      - alerts: "false" for Mute.
      - followAllRc: appends the newest message's time; stopping closes the entry as "start:now".
      - A preset picked from the flyout resets Everyone to your global setting. Research: scratchpad chatC/n206-notif.md.
  - New chat, typed search: one peoplepicker.newChat request (People, Chat, Channel, Team), the same body as OST's recipients.
    - Typing "OST" lists only people. "OST group" lists the group chats "OST group test" and "OST TEST group call" (50 tall, the merged picture, the name alone, the typed words bold).
    - Picking a chat opens it and closes the new message.
  - Create a team (from scratch): an "Add Channel Agent" checkbox (data-tid auto-create-project-agent-checkbox) at 25, 431 in the 600-wide dialog, unchecked, with an info button.
    - The info tooltip reads "Keeps your plans on track and gets your team the answers it needs. It creates status reports, schedules meetings, and more."
    - No "agent id" second box (enableAgenticUserCreationToggle is off).
    - Checked, Teams installs the Channel Agent (project agent) in the first channel after creating the team: the installer hook passed into 785683's F, with entryPoint "autoInstallTeamToggle". That hook is not traced yet.

- 2026-11-20 (chatC), built and checked live on linuxlt as ost-test1:
  - Manage notifications ▸ for group chats, in Teams' place before Move to section. The flyout reads the chat's state ("chat-notify-load"; "Customized" label). A preset writes alerts, conversationNotificationSettings and followAllRc as Teams does. Customize is ChannelNotifyDialog in chat mode, 656 tall.
    - `--chat-notify-test=<OST group test>`: the menu items in Teams' order and the flyout match Teams on winpc; the state read back is {preset all, everyone true (global), follow false}.
    - Code: api::channels chat_notify_from / chat_notify_write / follow_all_rc_change / set_chat_notify, with unit tests.
  - New chat typed search: people who match, else group chats (Substrate peoplepicker.newChat; nameless chats, channels and teams left out). Picking a chat opens it (NewChat.openChat). `--new-chat-search-test`: "OST group" gives ["OST group test", "OST TEST group call"] as in Teams, and the pick opened OST group test; "OST" gives people only.
- Still open:
  - Teams lists only 4 people for "OST" (its local cache; OST lists Substrate's 9).
  - The Create team "Add Channel Agent" checkbox is not built: Teams' Channel Agent installer isn't traced, and a checkbox that does nothing would be a placeholder.
  - The Add members blank picture was not reproduced this pass.

- 2026-11-20 (chatE), new chat typed search, from Teams 26304 (worker resolver 81199, slots 964128, local chat search 54954/68583) and Teams on winpc:
  - Teams doesn't stop at 4 people for "OST": its list is a 225 px scrolling box with 22 rows (5 people incl. "OST Test 1 (You)" and two guests, 3 group chats, 3 channels, the team's group and OST Test Community, 15 more people, then what didn't fit: OST large chat test, OST test channel 2). The 4 seen before were only the rows in view.
  - OST now asks with the new chat form's own People filter and arranges the answer in Teams' slots (api::search::new_chat_arrange, unit test with the captured answer); local named group chats that match come in as Teams adds them; channels show their team, groups their address; the typed words are bold where a word starts with them (both lines). Picking a chat, channel or team opens it; a group adds its people.
  - Live (`--new-chat-search-test=OST`): OST lists 17 rows in Teams' order: OST Test 2, the guests, OST Test 3, OST group test, OST TEST group call, two channels, OST Test Team, OST Test Community, the other guests.
  - Still different: Substrate gives OST's token no "OST Test 1" row and two channels where it gives Teams four (examples/newchat_probe shows the raw answer); OST's chat list doesn't hold "OST empty chat test" / "OST large chat test", so those local matches are missing.
- Create team's "Add Channel Agent", traced live in Teams on winpc (team "OST TEST 206 agent", deleted afterwards): unticked by default; ticked, Teams creates the team, shows a bottom-left toast ("<channel>" / "Channel Agent is being added." / Go to channel) and the Teams Copilot Aggregator adds "<channel> Agent", which posts "Hi, I'm your Channel Agent…"; the channel shows "OST TEST 206 channel Agent has been added to the channel." (Teams also showed a "We ran into a problem / Please try again later" dialog right after Create, though the team and agent were made.)
  - Built: the checkbox (ECS messaging enableProjectAgentAutoCreationToggle + enableStatusReportAgent, Copilot licence, locale), api::project_agent (templatedApps check, POST {calling_TeamsCopilotAggregatorUrl}/agents?agentType=0 with Teams' body, the 40 s delay, waiting for the Welcome-AddAgent message) with unit tests, ChannelAgentToast with Teams' strings.
  - Live in OST (`--team-live=create:... --team-live-agent`, team "OST TEST 206 agent OST", deleted afterwards): the box shows and is ticked; the first run failed because Create team's answer had no thread yet; the toast now waits for the team to be listed (rechecked with the next build).
- Add members' blank picture: Avatar drew its canvas as soon as the picture loaded, before the pixels were there; it now keeps the initials until the picture is drawn (as Teams shows initials until the photo is in).

- 2026-11-21 (chatE), Add Channel Agent checked live end to end (`--team-live=create:OST TEST 206 agent OST2 --team-live-agent`): OST created the team with the box ticked, waited for the team's thread, asked the Teams Copilot Aggregator (OST's token for its resource works), and the "OST TEST channel Agent" bot posted "Hi, I'm your Channel Agent…" in the first channel; the toast went from "Channel Agent is being added." to "Channel Agent has been added to this channel." with Go to channel, as in Teams. The team was deleted afterwards (also "OST TEST 206 agent OST" and Teams' "OST TEST 206 agent").
  - Seen on the way (not part of this item): OST shows the agent's welcome as from "Project-Agent-Prod" and its add event as "OST Test 1 added OST TEST channel Agent here.", where Teams shows "<channel> Agent" with an "AI agent" tag and "<channel> Agent has been added to the channel.".

- 2026-11-21 (chatF):
  - Why "OST empty chat test" / "OST large chat test" were missing from OST's chat list: the chat service hands conversations out in time slices; the first page (156 here) holds only chats active since about 2026-11-18, its _metadata.backwardLink the older ones (110 more, including both chats and several channels). OST read only the first page; Teams' list comes from its full sync. api::chat::list_chats_data now follows backwardLink (up to 20 pages of 200; the older slices kept for ten minutes, the first page always fresh, ids de-duplicated), and the backroom lookups go 12 at a time.
  - New chat "OST", Teams on winpc (CDP, 22 rows): OST Test 2, OST Guest 02, OST Guest 01, OST Test 1 (You), OST Test 3, OST group test, OST TEST group call, OST empty chat test, OST layout test, OST test channel, OST threads test, OST Test Team, OST Test Community, OST Guest 03, 09…04, OST large chat test, OST test channel 2. Teams' Substrate request carries x-client-flights "EnableSelfSuggestion,TeamsHiddenPeopleDirectorySearch" (with it Substrate lists you, 4th) and gives only two channels (OST layout test, OST test channel); "OST threads test" and "OST test channel 2" are Teams' own matches from its teams store. OST now sends the same flights and adds your teams' matching channels (best match, then latest activity) after Substrate's.
  - Live (`--new-chat-search-test=OST`, before the flights): 22 rows with OST empty chat test (3rd chat) and OST large chat test (overflow) now present, the local channels added.
  - Channel Agent welcome, Teams on winpc (team "OST TEST 206 agent F2", made by OST's Add Channel Agent): sender "OST TEST channel Agent" (the message's properties.fromAppMetadata.name; imdisplayname is "Project-Agent-Prod"), then the "AI agent" tag (data-testid message-disclaimer: 10 px #616161, 0.67 px #E0E0E0 outline, radius 4, padding 0 2, 17.3 tall, 4 after the name; tooltip "AI-generated content may be incorrect"; messaging:group_copilot_disclaimer), then the time. The message has botPoweredByAI true. Teams showed no add-member / AddCustomApp rows in that (threads-layout) channel.
  - Built: MessageView.ai_agent and the app-instance name for bot messages; the tag in chats/threads (Conversation.qml) and channel posts (ChannelPosts.qml).

- 2026-11-21 (chatF), live after the fixes: `--new-chat-search-test=OST` lists the same 22 rows as Teams, in Teams' order (OST Test 1 (You) 4th, OST empty chat test 3rd chat, OST threads test 3rd channel, OST large chat test and OST test channel 2 last). The Channel Agent's welcome in "OST TEST 206 agent F2" showed as "OST TEST channel Agent" with the "AI agent" tag, as in Teams (`--chat-shot`). Both test teams (F, from a first run that quit early, and F2) were deleted with `--team-live=delete:`.
  - Still different: OST shows the add event "OST Test 1 added OST TEST channel Agent here." where Teams showed no event row in that threads-layout channel; OST draws the agent's initials where Teams shows its app icon; Teams' "@agent" suggested action and feedback buttons under the welcome are not drawn.

- 2026-11-21 (chatG), the three Channel Agent gaps, measured on winpc (Teams 26304, CDP) in "OST TEST 206 agent G" (made by OST's Add Channel Agent, threads layout; deleted afterwards with --team-live=delete) and read from Teams' code:
  - Raw messages: AddMember 28:<agent bot> (hidden as before), AddCustomApp (target = the agent's app instance 87daf61a…, targetName "OST TEST channel Agent"), then the welcome with properties.fromAppMetadata {id = that instance, name}, botPoweredByAI, botFeedbackLoopEnabled, and suggestedActions [{title "@agent", type Action.Compose, value {type Teams.chatMessage, data {body.content "<at id=0>OST TEST channel Agent</at>", mentions}}}].
  - Event row: Teams shows no row for the agent's AddCustomApp in a threads channel (75579 `cn` words a project agent's add "<agent> has been added to the channel." for posts channels). OST: api::messages::mark_agent_adds turns an AddCustomApp whose target is an AI agent's app (its messages' fromAppMetadata.id) into AgentAdded with Teams' sentence (messaging:k5zwsygs5); the threads view leaves it out.
  - Icon: Teams resolves the sender from fromAppMetadata.id (r_data-resolvers `Qe`: getAppDefinition(appId) → largeImageUrl) and draws it as "agent-avatar": a 32 px circle on #FAFAFA with the Available presence badge. The definition's icon is on teams.cloud.microsoft/v2/evergreen-assets/…, which answers "Unsupported browser" outside the client, so OST reads the same file from the assets' CDN (app_details::evergreen_asset_url). MessageView.sender_app carries the app id; the avatar's photo id is "28:<bot>#<app>".
  - "@agent": Teams' mention-project-agent-button inside the bubble, 8 under the text: 64 x 23.3, 12 px #242424 on white, #D1D1D1 0.67 hairline, radius 4, padding 3 8; then Like / Dislike (24 x 31.3, 16 px thumbs, #424242), the row 31.3 tall, the bubble 8.7 under it. In a threads channel @agent opens the message's thread with "OST TEST channel Agent" as a mention in the reply box (Send to: thread only); nothing is sent. Like/Dislike open "Submit feedback to Microsoft" ("What did you like?"), the thumb stays filled; OST opens its feedback form (FeedbackWindow) in the same way.
  - Also: Teams sets the welcome's paragraphs with no space between them (<p>s 20 apart); OST drew Qt's 12 px paragraph margins, which also pushed the new row over the text. Message text now has p margins 0, and lists use the text's real height.
- Built: the above (MessageView.sender_app / suggested / feedback_loop, suggested_actions parser and tests, Conversation actions row, ThreadsPane.applySuggestion, ComposeBox whole-name mentions, Avatar.photoBackground), harness `--agent-welcome-test --open-chat=<channel>`.
- Live (OST on linuxlt): AGENTWELCOME welcome {sender "OST TEST channel Agent", app 87daf61a…, ai, actions ["@agent"], feedback}; the add row gone from the threads view; the agent's logo in the avatar; @agent opened the thread with the mention in the reply box (cleared again, nothing sent).

  - Rechecked after the paragraph fix in a second team ("OST TEST 206 agent G2", deleted afterwards): paragraphs 20 apart and the list set off as in Teams, @agent and the thumbs 8 under the text inside the bubble, the logo avatar with the Available badge. Both test teams were deleted with --team-live=delete (OST no longer lists them).
  - Tests: 893 lib + 29 desktop pass.
  - Left: posts-layout channels (ChannelPosts) don't draw the suggested actions / thumbs row yet (no posts-layout Channel Agent to compare); OST parses only Action.Compose suggested actions (imBack / Action.Submit not drawn).

- 2026-11-22 (chatH), suggested actions, from Teams 26304 (r_data-resolvers-chat `Es` parser; 763654 `ja`/`$a`/`Wa`/`ba` renderers, `eo` handler; the worker's invoke transport):
  - Kinds (type without case): imBack (value → text; a button that sends "<mention of the bot> {text}", in a channel to the message's thread), Action.Compose (Teams.chatMessage: text and mentions to the compose box), Action.Submit (object value → an invoke named value.name or "suggestedActions/submit" with value.value or the whole value), openUrl (http/https only; "Preferences" / "Skills" get document-text / folder icons), Action.ODSL (Copilot statements: customizations, schedule meeting, ODSL; separate lazy chunks). At most 3 (4 for ECS copilotAppsIds bots); a non-text title or type drops them all. All are Fluent small buttons (12 px, padding 3 8, min width 64, #D1D1D1 hairline, radius 4); imBack wraps (min height 24), the rest truncate; an invoke disables its button while it runs.
  - Posts layout (Teams on winpc, team "OST TEST 206 agent H" made by OST's Add Channel Agent, its channel switched to posts with Edit channel's chatModalityType PostReply): the welcome post (716 wide) shows its text cut with "see more", then the row 8 under it at x 16: @agent 64 x 23.3, Like / Dislike 24 x 31.3 at 88 / 112, the row 31.3 tall; the reactions 16 under the row (56.3 under the text). @agent opens that post's reply box with "OST TEST channel Agent" as a mention (posts: setCopilotAtMention on the post's reply chain + showReplyCompose). Teams shows no row for the layout change (ModalityUpdate) nor for the agent's add in that channel.
- Built: api::messages::suggested_actions parses every kind as Teams (unit test); SuggestedActionsRow.qml (shared by chats/threads and posts); imBack sends, Action.Submit invokes (backend.suggestedInvoke → api::bot_invoke), openUrl opens; posts: the row at Teams' place, @agent opens the post's reply with the mention (the reply box sends rich text when it holds one), the ModalityUpdate post left out, post paragraphs with no space between them (MessageText).
- Live (OST on linuxlt, `--agent-welcome-test --open-chat=<posts channel>`): AGENTWELCOME welcome {actions ["@agent"], feedback, layout PostReply}; picked → post reply {"text": "OST TEST channel Agent ", "mention": true}; the row and the reply box as Teams.
- Open: Teams' "see more" cut of long posts isn't in OST's posts layout; ODSL kinds are parsed and counted but not drawn; imBack / Submit / openUrl come from Teams' code with unit tests only (no bot here sends them).

- 2026-11-22 (chatH), after the Teams check: posts channels also leave out the agent's add (AgentAdded) as Teams showed no row; rechecked live (agentposts3: the welcome alone, as Teams). Team "OST TEST 206 agent H" deleted (thread soft-deleted). Tests: 903 lib + 29 desktop pass.
<!-- SECTION:NOTES:END -->
