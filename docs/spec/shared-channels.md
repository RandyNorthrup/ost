# Private and shared channel members, sharing and invites (TASK-0087)

Measured in Teams desktop 26304 on winpc and read from its bundles (worker
`teamsAndChannelsProvisioningService`, 2026-11-20).

## Requests (provisioning service, token for https://templates.teams.microsoft.com)

- **Add people** (a private channel's member step and Add members, a shared channel's
  Share with people): `POST {prov}/teams/{team group}/channels/OID:{channel group}@
  {tenant}/users?forceSync=false {users: [{id: "OID:{user}@{tenant}", role}]}`, role
  1 member, 2 owner (Teams' NW: User 1, Admin 2, Guest 3); refusals come back in
  `multipleStatus[].statusSubCode`. The channel's group is its thread's
  `substrateGroupId`.
- **Share with a team** (invite a team owner): `POST {prov}/channels/OID:{group}@
  {tenant}/invitations {channelGroupId, userPrefixedIds: ["OID:{owner}@{tenant}"]}`
  → `{errors}`.
- **Share with a team you own:** `POST {prov}/channels/OID:{group}@{tenant}/
  linkedTeams?forceSync=false&allowAllTeams=true {teamPrefixedId: "OID:{team
  group}@{tenant}", teamThreadId}`; stop: `DELETE …/linkedTeams/OID:{team}@{tenant}`.
- **Shared with:** `GET {prov}/channels/internal/{channel thread}/sharedWithTeams` →
  `{linkedTeams: [{teamThreadId, displayName, isHostTeam, memberCount, …}]}`.
- **Sent invites:** `GET {prov}/channels/OID:{group}@{tenant}/invitations` →
  `{invitations: [{id, inviteeMri, state, systemExpirationDateTime, …}]}`; the host's
  approve / deny `POST …/invitations/{id}/approve|deny`, withdraw `DELETE`.
- **Pending invites** (the invitee's teams): `GET {prov}/users/me/invitations` (fields
  at the top: channelDisplayName, channelThreadId, channelPrefixedId,
  channelOrganizationName, inviterMri, state, systemExpirationDateTime); accept for one
  of your teams `POST …/users/me/invitations/{id}/accept {targetTeamThreadMri: <team
  thread>}` → `{state: "Pending"}` (the channel owner then approves); decline `POST …/decline`.

## UI

- The channel's menu has no Share item. A private channel's owners get **Add members**
  (before Edit channel).
- **Manage channel**: a private channel's tabs Members, Settings, Analytics, Apps, Tags;
  a shared one's Members, Invites and requests, Settings, Apps, Tags (Members first).
  - Members: "+ Add member" (private) or the "Share with people ▾" split button
    (shared; its 184 wide menu: Share with people, Share with a team, Share with a team
    you own) and "Search members"; sections Owners (n), Members (n) ("Members and
    guests" in a private channel) and, shared, Teams (n); columns Name, Title,
    Location, Tags (i), Channel role.
  - Invites and requests: "Sent invites (1 team)" with Name and Expires in ("13 days").
- **Share with people** (600 x 449): "Share the {channel} channel", "Type the name of
  someone in your org you want to add to this channel. You can also add people outside
  your org by typing…", picker "Type a name or email", Cancel / Share.
- **Share with a team** (600 x 599): "Share the {channel} channel. Start by sending an
  invite to a team owner." (20/28), "This person will accept the invite on behalf of
  their team. If the person is outside your org, type their email address. What's
  shared with the invite?", picker "Type a name or email of a team owner", Cancel /
  Send invite.
- **Share with a team you own** with no other team: 600 x 162 "The {channel} channel
  is already shared with all the teams you own." and Close.
- OST: `api::channels` (channel_members, add_private_channel_members,
  share_with_team_owner, share_with_own_team, shared_with_teams, channel_invitations,
  answer_channel_invitation, answer_invitation), `ManageChannel.qml` Members and
  Invites, `ShareChannelDialog.qml`, `AddMembersDialog` share mode, `YourTeams`
  Pending invites Accept / Decline; `--channel-share-test`.
