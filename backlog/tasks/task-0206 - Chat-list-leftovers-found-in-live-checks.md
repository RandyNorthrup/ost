---
id: TASK-0206
title: Chat list leftovers found in live checks
status: To Do
assignee: []
created_date: '2026-11-16T20:22:00Z'
updated_date: '2026-11-21T02:45:00Z'
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
<!-- SECTION:NOTES:END -->
