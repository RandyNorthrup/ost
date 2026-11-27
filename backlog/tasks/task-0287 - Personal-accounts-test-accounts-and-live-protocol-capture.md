---
id: TASK-0287
title: 'Personal accounts: test accounts and live protocol capture'
status: To Do
assignee:
  - '@agent-personal287'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-27T20:29:00Z'
labels:
  - personal-accounts
dependencies: []
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams for personal use (personal Microsoft accounts: outlook.com, hotmail, live.com) uses different sign-in and services from work Teams. The research in docs/research/ is from documentation, Teams' public web client and open-source clients; nothing has been checked with a signed-in personal account. Before building, capture the real flows with dedicated personal test accounts (never the user's own account, so no real people are ever messaged), on teams.live.com and on the Teams desktop app on winpc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every item of 'Must verify live' in personal-accounts-protocol.md is confirmed or corrected from captures, and the doc marks each as verified
- [ ] #2 Every item of 'Verify on real Teams' in personal-accounts-features.md is checked on winpc's Teams desktop with a personal account next to ost-test1, with screenshots kept outside the repo
- [x] #3 The test tenant's setting for chat with personal accounts (AllowTeamsConsumer) is known, and enabled if it is off
- [x] #4 Two personal test accounts exist (created or signed in by an agent or the user) and are recorded in ~/coding/.secrets/creds.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26 correction (user): agents may sign in to the test accounts themselves, typing the password (and TOTP) from ~/coding/.secrets/creds.md without printing it. "The assistant may not enter passwords" / "the user has to do it" was never a rule. How: backlog/docs "Signing in to test accounts".

- 2026-11-27: two personal test accounts created by the coordinator: ost-personal1-5135@outlook.com (OST Personal 1) and ost-personal2-0238@outlook.com (OST Personal 2). Passwords in ~/coding/.secrets/creds.md under '# OST personal test account 1/2'. Recovery emails ost-test1/ost-test2@scnetsolutions.com (codes readable with examples/graph_beta_get on linuxlt, OST_PROFILE=test2 for ost-test2). No MFA set up yet.

- 2026-11-27 AC3: read with Teams PowerShell (Connect-MicrosoftTeams device login as Randy). Get-CsTenantFederationConfiguration (Global): AllowTeamsConsumer True, AllowTeamsConsumerInbound True, AllowFederatedUsers True, AllowedDomains AllowAllKnownDomains, ExternalAccessWithTrialTenants Blocked. External access policy Global: EnableTeamsConsumerAccess True, EnableTeamsConsumerInbound True; ost-test1 and ost-test2 have no policy of their own (Global applies). Already on: nothing changed in the tenant.

- 2026-11-27 AC1 capture setup: two isolated headless Chrome profiles on this PC (CDP ports 9333/9334, own user-data dirs, fake media devices, no real mic) signed in to teams.live.com as OST Personal 1 and 2; a redacting CDP capture (tokens shown only as prefix/length/segments, JWT claims decoded without signatures). Sign-in needed the email code to the recovery mailbox (read with graph_beta_get). Probe script redeemed its own PKCE code and tried scopes/endpoints directly.
- AC2 setup: testpc2 Teams: OST Personal 2 added via profile menu > Add another account (Verify your email > Use your password instead > password > "Use this account everywhere on your device": chose "Microsoft apps only"; no email code was needed there). Opens in its own window. WebView2 CDP on testpc2 hung twice when Teams opened a new window/flyout, so the desktop checks use UIA + screenshots (screenshots in ~/.local/share/ost-remaining/personal/).

- 2026-11-27 TENANT SIDE EFFECT (Teams' own behavior, recorded here): when a work user (ost-test2 on testpc2 desktop, ost-test1 on the web) starts a chat by typing a personal email that Teams' externalsearchv3?includeTFLUsers=true does not resolve, Teams calls PUT mt/beta/teams/inviteAndAddSingleGuestToTenant and creates an Entra B2B guest. Two guests now exist in scnetsolutions: ost-personal1-5135_outlook.com#EXT# (from ost-test2) and ost-personal2-0238_outlook.com#EXT# (8:orgid:28de4412-b652-418f-b073-1259e0332819, from ost-test1). Remove them in Entra (Users > guests) when no longer needed.
- Personal accounts' email discoverability was OFF after first sign-in (Settings > Privacy > Manage contact information: name on, email off) even though onboarding POSTed scd/searchability {searchable:true}. Turned email on for both personal accounts (desktop for personal 2, web for personal 1); ~45 min later searchUsers / externalsearchv3 still did not find them by email.

- 2026-11-27 AC1 results written to docs/research/personal-accounts-protocol.md §7 (each item Verified/Corrected/Partly verified). Main corrections: return address /v2/authv2; Origin required (AADSTS90023 otherwise); access tokens are MSA tickets or JWE (both opaque), identity from id_token/client_info (oid 00000000-0000-0000-<cid>), MRI cid has no leading zeros; authz v2 only (v1 40013), expiresIn 28799, consumerLicenseDetails; Graph token = Files.ReadWrite only (calendar via MT v2.0/me/calendars/default/calendarView); CSA v1-v3 work with x-skypetoken; MT needs bearer+skype, search is users/searchUsers, work users via fetchFederated, pictures via imageauth cookie; UPS ups/global works (skype token alone too); Trouter v4/c direct, TeamsCDLWebWorker_2.7/TFL ttl 3600, chat push confirmed; calling cpconv + flightproxy ep links, web media is DTLS/BUNDLE; work side: externalsearchv3?includeTFLUsers, fetchTflProfiles, inQuarantine request state, guest invite for unresolved emails.
- Open: OST desktop SDES dialect acceptance (needs the consumer calling code); file message send with attachment never completed in headless web; personal-to-personal chat request (email search kept answering NotFound); how a pasted teams.live.com/meet link opens in the desktop app.

- AC2 results written to docs/research/personal-accounts-features.md "Verify on real Teams" (16 items, testpc2 desktop with OST Personal 2 next to OST Test 2; screenshots in ~/.local/share/ost-remaining/personal/ac2-*). Partly verified: 7 (pasted meet link opening in desktop not tried), 8 (single-organizer meeting ran past 60 min with no warning, two-person end not observed), 9 (personal-to-personal request not seen: email search NotFound), 10 (file send from personal side did not complete in headless web), 12 (group-chat QR/join-link toggle not checked), 13 (subscribed account not available).
- Cleanup: headless Chromes and captures stopped, their profiles deleted; testpc2 Teams restarted without the debug port (env value removed, port closed), helper folder removed, tunnel closed; OST Personal 2 stays added on testpc2 for later tasks. Local ost-signin: ssh output now decoded with errors=replace (status crashed on non-UTF-8 output once two accounts were in Teams).

Reopened 2026-11-27 (Codex review on PR #51): AC #1 and #2 are not fully met.
Built so far: all AC #3/#4 work done; protocol doc items verified or corrected except consumer SDES acceptance (needs consumer calling code, TASK-0298); features doc verified except: meeting warning/end at 60 min with 2+ people present, personal-to-personal chat request (Teams answered NotFound for both personal emails), delivery of a file message from headless Chrome, the 20-person limit for calls from a chat (needs more accounts), opening a pasted teams.live.com/meet link in Teams desktop, and the group-chat QR code. See PR #46 docs.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Verified the personal-account (Teams free) research live and recorded the results in both research docs (PR #46, docs only).

What was done:
- Captured teams.live.com sign-in and services with OST Personal 1/2 in isolated headless Chrome (redacting CDP capture, plus a probe that redeemed its own PKCE code), the work side on teams.microsoft.com as ost-test1, and Teams desktop on testpc2 with OST Personal 2 added next to OST Test 2.
- personal-accounts-protocol.md: §7 marks all 14 items Verified/Corrected/Partly verified; contradicted rows in §1-§6 fixed.
- personal-accounts-features.md: all 16 "Verify on real Teams" items checked, with screenshots kept outside the repo.
- AC3: AllowTeamsConsumer and AllowTeamsConsumerInbound already on (Global); nothing changed.

Key facts for TASK-0289..0302: redirect /v2/authv2 + mandatory Origin; opaque tokens (MSA ticket or JWE), identity from id_token/client_info, MRI cid without leading zeros; authz v2 only (consumerLicenseDetails, expiresIn 28799); Graph token is Files.ReadWrite only (calendar via MT v2.0 calendarView, two-way with Outlook.com); CSA works with x-skypetoken; MT needs bearer+skype, search = users/searchUsers; chat push over Skype Trouter (TeamsCDLWebWorker_2.7/TFL); calling via cpconv/flightproxy ep links; work side uses externalsearchv3/fetchTflProfiles and quarantined requests; unresolved emails become B2B guest invites.

Not verified (reasons in the docs): OST desktop SDES offer on consumer calls, file-message delivery, personal-to-personal request, 60-minute end with 2+ people, 20-person chat-call limit.

Side effect: Teams created two B2B guests (ost-personal1/2 #EXT#) in scnetsolutions when work users started chats by email.
<!-- SECTION:FINAL_SUMMARY:END -->
