# Activity feed items — Teams desktop behaviour (spec)

Source: Teams 26304's shared worker (`precompiled-shared-worker-*`, its
activity processors), its activity renderer (`262631-*`), the apps'
manifests (`/beta/users/apps/batchedDefinitions`), and ost-test1's and
OST Test 2's feeds, compared item by item with Teams on winpc
(2026-11-22, TASK-0245).

## Apps' activities (`activityType: msGraph`, GraphActivityProcessor)

- **Shown only when Teams can word it** (isMessageValid): the app's
  definition is there; its `activities.activityItems` has an entry whose
  `type` equals the activity's `activitySubtype` (ignoring case, e.g. Audio
  Recap's `RecapPodcastReady`); every `{name}` in its `templateText` but
  `{actor}` is in `activityContext.templateParameters` (JSON text); the
  activity's `customTapAction` is a URL; and its `sourceThreadId`, if any,
  can be read. Apps in ECS's appsDisallowedForActivities are left out.
- **Who**: `activityContext.attributedToActor` ({Id, DisplayName}) stands
  for the sender when it is there.
- **Headline**: the templateText with each `{name}` replaced (first
  occurrence) by that parameter, then `{actor}` by who did it. ost-test1's
  and OST Test 2's feeds hold:
  | app | type | templateText | shown |
  |---|---|---|---|
  | Q&A (5db56dd0) | teamsQnAEnabledForMeeting | Q&A is enabled for this event. Ask your questions! | as is |
  | Meeting Recaps (981bbfd0) | recapIsReadyV2 | Recap ready: {subject} | Recap ready: OST TEST 73 agenda |
  | Audio Recap (d4288b02) | RecapPodcastReady | {title} | Audio recap ready: OST TEST 212 recap long |
  | Teams (2a84919f) | invitationAccepted / invitationSent | {actor} accepted an invite that needs approval / {actor} invited your team to a shared channel | OST Test 2 accepted an invite that needs approval |
  | Calendar (ef56c0de) | privateMeetingUpdated | {actor} updated | OST Test 1 updated |
- **Second line** (`activityContext.location`, JSON): `Custom` as is, with
  Teams' date markup worded (renderer module 542284): `<DateTimeRange>`
  → "Nov 20, 8:23 PM - 9:02 PM" (the end's date left out on the same
  day, the year only when not this year's), `<DateRange>`, `<DateTime>`,
  `<Date>`; `GroupChatId` → the chat's topic ("Event Group Chat: {topic}"
  for an event's backroom chat, "Planning Group: {topic}" for a
  meeting's); `TeamId` → Team › Channel.
- **Preview**: `messagePreview` (14 px NeutralForeground3).
- **Picture**: the app's icon (`activityContext.iconUrl`, else the
  definition's `largeImageUrl`), 32 px in Teams' app-icon squircle on
  #FAFAFA, with no kind badge.
- The other-accounts hub lists them with the actor's initials picture and
  the Apps glyph (16, brand) on its white disc.

## Channels

- A mention or reaction in a threads-layout channel
  (`activityContext.chatModalityType` "Conversational") on a reply
  (`sourceReplyChainId` ≠ `sourceMessageId`) reads "{name} mentioned you in
  a thread" / "{name} reacted to your message in a thread".
- A bot's activity names its app (`sourceAppDisplayName`, e.g. "OST TEST
  channel Agent") and shows the app's icon.
- The place is "Team › Channel" (Teams' MM): the conversation's
  `spaceThreadTopic`, then the channel's topic — a team's first channel's
  `topicThreadTopic`, else "General"; "Unavailable conversation" when the
  thread can't be read.
- teamMembershipChange / teamShareTeamOwnerNotify: "{name} shared a channel
  with your team".

## OST

`src/api/activity.rs`: `parse_feed` words what it can and marks the rest;
`feed` then asks the apps' definitions and the threads (once per session
each) and drops what Teams would. ActivityView draws the app icon and
Team › Channel; Theme.qml's `activityPlace` words the date markup.
