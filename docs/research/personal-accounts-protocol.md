# Personal Microsoft accounts (Teams free): protocol map

Research for planning support for personal Microsoft accounts (MSA,
"Microsoft Teams (free)", teams.live.com) in OST. It compares what OST
uses for work and school accounts today with what Teams free uses.

Researched 2026-11-25 from documentation, the public web bundle and
open-source clients. **Checked live on 2026-11-27** with two personal test
accounts (TASK-0287): §7 lists every result, and the rows below that the
live check corrected say so.

## Confidence levels

- **Confirmed (bundle)**: read from Teams free's own web client
  configuration or code, downloaded unauthenticated from
  `https://teams.live.com/v2/` (see Sources). This shows what Microsoft's
  client is configured to do, not that a call succeeds.
- **Confirmed (probe)**: checked with an unauthenticated request on
  2026-11-25.
- **Confirmed in code**: used by a current open-source client that says
  it was verified live against Microsoft, with file and line cited.
- **Documented**: Microsoft Learn says so.
- **Guessed**: inferred by analogy. Must be verified live.
- **Verified live**: seen in a real capture on 2026-11-27 (§7).

## Sources

| Tag | What | Version |
|---|---|---|
| **TFL-cfg** | Teams free web config bundle `config-life-81228fa52093439f.js` (the `life` cloud) and, for comparison, `config-prod-6f2674e1d627c38c.js`, both from `https://tflteams.public.onecdn.static.microsoft/teams-modular-packages/hashed-assets/` | fetched 2026-11-25 |
| **TFL-js** | Teams web client code `async-entry-b5ec7df30e99338c.js` from the same CDN (the same code runs for work and life; the config picks the cloud) | fetched 2026-11-25 |
| **PT** | [EionRobb/purple-teams](https://github.com/EionRobb/purple-teams), personal build (`ENABLE_TEAMS_PERSONAL`) | `8673465`, last commit 2026-11-25 |
| **NS** | [Yannicked/NoSlacking](https://github.com/Yannicked/NoSlacking), `docs/research/microsoft-teams.md` and `src/teams/*` (a live personal-account probe, 2026-10-07) | `faf9fc3`, 2026-10-26 |
| **MX** | [YourSandwich/mautrix-teams](https://github.com/YourSandwich/mautrix-teams) (Go Matrix bridge) | `e1d3018b`, 2026-11-17 |
| **MT** | [gekiclaws/matrix-teams](https://github.com/gekiclaws/matrix-teams) (Go Matrix bridge) | `657a7592`, 2026-08-22 |
| **TM** | [zongwei-tang/teams-mcp](https://github.com/zongwei-tang/teams-mcp) | `ee0e81b2`, 2026-11-21 |
| **MN** | miranda-ng `protocols/Teams` | `c563b898`, 2026-11-18 |
| **TD** | [InvictusNavarchus/teams-chat-downloader](https://github.com/InvictusNavarchus/teams-chat-downloader), `docs/02-http-protocol.md` | `18e8ad93`, 2026-11-24 |
| **T4L** | [IsmaelMartinez/teams-for-linux](https://github.com/IsmaelMartinez/teams-for-linux): a web wrapper only; it allow-lists `teams.live.com` and `login.live.com` (`app/mainAppWindow/index.js:1217-1247`) and has no protocol details | `907566b8` |
| **MS** | Microsoft Learn pages, linked where cited | as of 2026-11-25 |

## Summary

- **Sign-in is new; the plumbing is mostly reusable.** OST's browser
  sign-in works for consumers if we swap the client, authority, redirect,
  origin and scopes. Teams free's web client is a single-page app with
  client `4b3e8f46-56d3-427f-b1e2-d239b2ea6bca` against
  `login.microsoftonline.com/consumers`, which hands off to
  `login.live.com`. Its return address is `https://teams.live.com/v2`.
  Instead of `api.spaces.skype.com`, the token audiences are the `fl`
  ("for life") resources: `https://auth.fl.teams.microsoft.com/teams.auth.readwrite`
  for authz and `https://mtsvc.fl.teams.microsoft.com/teams.mt.readwrite`
  for the middle tier.
- **The Skype token and regionGtms carry most of the rest.** The token
  comes from `teams.live.com/api/auth/{v1.0|v2.0}/authz/consumer`, and its
  response has a different shape (`skypeToken.skypetoken`, not
  `tokens.skypeToken`). OST already takes the chat service, middle tier
  and AMS hosts from regionGtms, so those subsystems follow automatically
  once authz works and the headers are right.
- **Identity is the biggest code change.** OST builds `8:orgid:{oid}` from
  the access token's `oid` claim in about 52 files. Personal access tokens
  are opaque (MSA tickets `EwA…`/`EwB…` or encrypted JWE). The personal MRI
  is `8:live:.cid.<hex>`, taken from the Skype token's `skypeid` claim; the
  id_token's `oid` is `00000000-0000-0000-<cid>` and its `tid` is the MSA
  tenant.
- **Live check (2026-11-27, §7):** the Teams free web client's Graph token
  only carries `Files.ReadWrite`, so the calendar, contacts and profile come
  from the consumer middle tier instead of Graph; chat push works over the
  Skype Trouter; CSA works for consumers; authz v1 does not.
- **Several subsystems have no consumer equivalent:** teams and channels,
  Graph presence, Substrate/Loki search and people cards, Viva Engage
  communities, Teams Premium, recording through the work recorder, and
  most ECS work features.
- **Calling is a different stack.** Consumer calls use
  `api.flightproxy.skype.com/api/v2/cpconv` with `X-Skypetoken` and
  `applicationType: "TFL"`, plus `edge.skype.com/trap/tokens` for TURN.
  The web client sends browser-style media (DTLS-SRTP, Opus, BUNDLE)
  rather than OST's desktop dialect.

## 1. Sign-in

### 1.1 What OST does today (work accounts)

| Item | OST value | Where |
|---|---|---|
| Client (browser sign-in) | `5e3ce6c0-2b1f-4285-8d4b-75ee78787346` (Teams on the web) | `src/auth/spa.rs:23` |
| Authority | `https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize` | `src/auth/spa.rs:31` |
| Redirect / origin | `https://teams.cloud.microsoft/v2/authv2`, `Origin: https://teams.cloud.microsoft` | `src/auth/spa.rs:26-29` |
| Primary scope | `https://api.spaces.skype.com/.default openid profile offline_access` | `src/auth/spa.rs:34-35` |
| Other audiences | Graph, IC3 and recorder, each minted from the refresh token | `src/auth/oauth.rs:12-14`, `:372-428` |
| Token endpoint | `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` | `src/auth/aad.rs:91` |
| Device-code client | `1fec8e78-bce4-4aaf-ab1b-5451cc387264`, tenant `common` | `src/auth/mod.rs:35-43` |
| Leftover personal config | client `8ec6bc83-…`, tenant `consumers`, redirect `…/common/oauth2/nativeclient`, scope `https://api.spaces.skype.com/.default`; never used | `src/auth/mod.rs:46-54` |
| Skype token | `exchange_skype_token(…, false)` is always called with `personal = false` | `src/auth/oauth.rs:107`, `:383`; `src/api/ecs.rs:152`, `:170` |

The leftover `personal()` config would not work as written, for two reasons:

- **The scope is refused.** NS found that `https://api.spaces.skype.com/.default`
  on the consumer client fails with AADSTS70011
  (NS `docs/research/microsoft-teams.md:398-400`, `src/teams/auth.rs:64-68`).
- **The redirect is refused.** Probed 2026-11-25: login.live.com refuses
  the redirect `https://login.microsoftonline.com/common/oauth2/nativeclient`
  for `8ec6bc83-…` and shows an error page. It accepts
  `msauth.com.microsoft.teams://auth`.

### 1.2 Teams free on the web (the model for OST's browser sign-in)

| Item | Value | Source | Confidence |
|---|---|---|---|
| Client ID | `4b3e8f46-56d3-427f-b1e2-d239b2ea6bca` | TFL-cfg `configs.auth.clientId` (prod has `5e3ce6c0-…` in the same place); MT `client.go:16`; NS doc:418 | Confirmed (bundle) |
| Authority | `login.microsoftonline.com` with audience `consumers`; it 302s to `https://login.live.com/oauth20_authorize.srf` | TFL-cfg `audience:"consumers"`, `cloudAuthorityMap` life → `https://login.microsoftonline.com/`; probe | Confirmed (bundle + probe) |
| Return address | **`https://teams.live.com/v2/authv2`** (what the client sends; §7.1). `/v2` is also accepted; a foreign host is not. | Live capture; probe; TFL-cfg; MT `client.go:13-17` | Verified live |
| Origin for code and refresh redemption | `https://teams.live.com`, required: without it AADSTS90023 | Live capture and probe (§7.1) | Verified live |
| Token endpoint | Code: `https://login.microsoftonline.com/consumers/oauth2/v2.0/token`. Refresh: the web client uses `…/9188040d-6c67-4c5b-b112-36a304b66dad/oauth2/v2.0/token`; `consumers` works too | Live capture and probe (§7.1) | Verified live |
| Authz scope (v2, on in life) | `https://auth.fl.teams.microsoft.com/teams.auth.readwrite` | TFL-cfg `authzResourceV2`, `enableAuthzResourceV2:true`; TFL-js constant `AUTHZ_AADV2_TFL` | Confirmed (bundle) |
| Authz scope (v1 fallback) | `service::api.fl.spaces.skype.com::MBI_SSL` | TFL-cfg `authzResource`; PT `teams_login.c:279`; NS | Confirmed (bundle + code) |
| Middle-tier scope | `https://mtsvc.fl.teams.microsoft.com/teams.mt.readwrite`; life always uses the AAD v2 MT token | TFL-cfg `mtResourceV2`; TFL-js (`useAadV2Token = … \|\| buildCloud === life`) | Confirmed (bundle) |
| Other scopes the web client warms | `service::api.fl.teams.microsoft.com::MBI_SSL`, `service::api.fl.sms-free.spaces.skype.com::MBI_SSL`, `https://chatsvcagg.teams.microsoft.com` | TFL-cfg `criticalResources`, `prefetchTokens` | Confirmed (bundle) |
| Groups service scope | `https://groupssvc.fl.teams.microsoft.com/teams.readwrite` | TFL-js constant `GROUPS_SERVICE`; TM `config.ts:47` | Confirmed (bundle) |
| Profile card (Loki) audience | `liveprofilecard.access` | TFL-js `LOKI_TFL_AUTH_TOKEN_AUDIENCE` | Confirmed (bundle), unused |
| Refresh token | 24 hours (`refresh_token_expires_in` 86400), with the same silent `prompt=none` renewal OST already does for work (`src/auth/spa.rs:12-15`): MSAL.js renews in a hidden frame once the refresh token ends, carried by login.live.com's persistent "Stay signed in" cookie `__Host-MSAAUTHP` (§9.1). Refresh tokens rotate; store the new one each time. | Live capture; [MS refresh tokens](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens) | Verified live (§9.1) |

### 1.3 Native client (alternative, not what Teams free web uses)

| Item | Value | Source | Confidence |
|---|---|---|---|
| Client ID | `8ec6bc83-69c8-4392-8f08-b3c986009232` | PT `teams_login.c:274`, MT, MX, TM, MN | Confirmed in code |
| Redirect | `msauth.com.microsoft.teams://auth` (accepted by login.live.com, probe). PT says v2.0 accepts only the native redirect for this client (`teams_login.c:287-292`). | Probe; PT | Confirmed (probe) |
| Device code | v1 `common/oauth2/devicecode` with `resource=https://api.spaces.skype.com` (PT `teams_login.c:944-956`), or v2 `consumers/oauth2/v2.0/devicecode` with the MBI_SSL scope (TM `oauth.ts:56-61`). The SPA client cannot use device code (AADSTS70002, NS doc:366-367). | PT, TM, NS | Confirmed in code |
| Refresh token | 90 days by default (not an SPA). | MS refresh tokens | Documented |
| Middle-tier limit | NS's native token gets 401 S2S12008 from `teams.live.com/api/groups/v1/threads`, and `fetchShortProfile` refused every token NS held. The middle tier may only accept the web client's tokens. | NS doc:342-370 | Confirmed in code |

**Recommendation:** follow the web client, as OST does for work. Use
`4b3e8f46-…` in OST's web view with `https://teams.live.com/v2` as the
return address and `https://teams.live.com` as the origin. This also keeps
embedded-app brokering (NAA) possible. The native client is a fallback for
headless or TUI sign-in.

### 1.4 Teams desktop on Windows

Teams desktop signs MSA users in through WAM/OneAuth (on Windows, the
`platform:[49,51]` branches of TFL-cfg), not MSAL.js. `enableMsal2` is set
only for the web platforms 1454 and 1415. Linux has no WAM, so OST would use
the web flow anyway, as it does for work. The desktop's MSA client ID was
not found in public sources. **Guessed**: capture it on winpc if needed.

### 1.5 Token contents (identity)

- Personal access tokens are opaque: MSA tickets (`EwA…`/`EwB…`) or, for
  the `fl` resources, encrypted JWE (`eyJ…` with five segments). Verified
  live (§7.4).
  Microsoft says clients must treat access tokens as opaque
  ([MS access tokens](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens)).
- OST reads `name`, `upn`/`unique_name`, `oid` and `tid` from the access
  token (`src/config/mod.rs:102-128`). None of these will work for MSA.
  The MSAL `id_token` and `client_info` (OST already asks for
  `client_info=1`, `src/auth/spa.rs:65`) and the Skype token's claims
  (`skypeid` = `live:.cid.<hex>`, `signinname`) must be the source instead
  (NS doc:336-338; MX `auth.go:108-122`).
- Tenant: the MSA tenant is `9188040d-6c67-4c5b-b112-36a304b66dad`
  (`docs/terminology/msa.md`; TFL-cfg `defaultConsumerTenantId`).

## 2. Skype token (authz)

| Item | Work (OST today) | Consumer | Source | Confidence |
|---|---|---|---|---|
| URL | `https://teams.microsoft.com/api/authsvc/v1.0/authz` (`src/auth/skype.rs:37`) | v2 (on in life): `https://teams.live.com/api/auth/v2.0/authz/consumer` with the `auth.fl…/teams.auth.readwrite` token. v1: `https://teams.live.com/api/auth/v1.0/authz/consumer` with the MBI_SSL token (already in `src/auth/skype.rs:38`). Also `…/v1.0/authzcore/consumer`. | TFL-cfg `authzAadV2Url`, `authzUrl`, `authzV2Url`; TFL-js picks `authzAadV2Url` when `enableAuthzResourceV2 && buildCloud === life`; PT `teams_login.c:242` | Confirmed (bundle + code) |
| Probe | n/a | Both endpoints are live. v1 without a token answers 400 `"Bearer token missing"`; v2 answers 401 `invalid_token`. | Probe 2026-11-25 | Confirmed (probe) |
| Request | `POST`, bearer, empty body | Same, plus the web client's headers: `ms-teams-authz-type: ExplicitLogin` or `TokenRefresh`, `x-ms-client-type`, `x-ms-client-version`, `claimsChallengeCapable: true`. Without the v2 resource, the web client adds `x-ms-skip-phone: true`. PT/MN add `X-MS-Client-Consumer-Type: teams4life`. | TFL-js header builder; PT `teams_connection.c:129-132` | Confirmed (bundle + code) |
| Response | `tokens.skypeToken`, `tokens.expiresIn`, `regionGtms`, `licenseDetails` (`src/auth/skype.rs:9-35`) | `skypeToken.skypetoken`, `skypeToken.expiresIn` (28,799 s, about 8 h), `skypeToken.skypeid` (`live:.cid.…`), `signinname`, `isBusinessTenant`, plus `regionGtms`, `regionSettings` and `consumerLicenseDetails` (§7.3). `AuthzResponse` must accept both shapes. v1 does not work with the web client's tokens. | Live capture (§7.3) | Verified live |
| regionGtms (consumer) | `chatService` (default `amer.ng.msg.teams.microsoft.com`, `src/api/client.rs:15`) | `chatService` = `https://msgapi.teams.live.com`; `chatServiceAfd` = `https://teams.live.com/api/chatsvc/consumer`; `middleTier` = `https://teams.live.com/api/mt`; also `unifiedPresence`, `ams`, `mcpService`, `chatSvcAggAfd` | NS doc:336-338; MX `auth.go:503-529`; TM `config.ts:67-69` | Confirmed in code |

## 3. Subsystem map

**Verdict** says whether the work code can be reused for consumers:

- **Reuse**: the same code works once auth, hosts and headers are set.
- **Adapt**: the same protocol on different hosts, scopes or headers.
- **New**: a consumer-only endpoint or flow.
- **None**: no consumer equivalent; hide the feature.

### 3.1 Auth and token plumbing

| Work today (OST) | Consumer | Confidence | Verdict |
|---|---|---|---|
| `AuthConfig::teams_web()` / `for_flow()` (`src/auth/mod.rs:59-77`); `TEAMS_WEB_FLOW` | A third flow ("teams-live") with the values in §1.2 | Confirmed (bundle + probe) | Adapt |
| Audiences minted after sign-in: Skype, Graph, IC3, recorder (`src/auth/oauth.rs:372-428`) | authz (`auth.fl…`), MT (`mtsvc.fl…`), Graph (`https://graph.microsoft.com/.default` works for MSA; the files config uses it, TFL-cfg `msGraphThumbnailApiResource`), groups (`groupssvc.fl…`). No IC3 (TFL-cfg has no `ic3CaeResource`; prod does) and no work recorder. | Confirmed (bundle) | Adapt |
| `access_token_for("https://api.spaces.skype.com/.default")`, 7 callers (for example `src/api/directory.rs:222`, `src/api/ecs.rs:149`) | `https://mtsvc.fl.teams.microsoft.com/teams.mt.readwrite` | Confirmed (bundle) | Adapt |
| Identity from the access-token JWT (`src/config/mod.rs:102-128`) | From the id_token, client_info and Skype-token claims (§1.5) | Confirmed in code | New |
| `needs_renewal()` AADSTS codes (`src/auth/spa.rs:147-153`) | login.live.com errors such as `login_required` and `invalid_grant`. TFL-cfg `interactionRequiredErrorCodes` lists `login_required`, `consent_required`, `interaction_required`, `invalid_grant`, `refresh_token_expired`, `bad_token`. | Confirmed (bundle) | Adapt |

### 3.2 Chat and messages (chat service)

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Base `chat_service_url()` from regionGtms `chatService` (`src/api/client.rs:364-373`) | regionGtms gives `https://msgapi.teams.live.com`. PT and MN use the front door `https://teams.live.com/api/chatsvc/consumer/v1/…`. TFL-cfg `chatServiceAfdHostnames` includes `teams.live.com`, and `useChatServiceAfd:true`. | PT `libteams.h:148-151`; MN `teams_http.cpp:29`; MX prefers `chatServiceAfd` | Confirmed in code | Reuse (prefer `chatServiceAfd`) |
| Paths `v1/users/ME/conversations`, `…/messages`, `v1/threads/{id}`, `users/ME/properties`, consumption horizons (`src/api/chat.rs`, `src/api/messages.rs:6186`, `src/api/preferences.rs:14`) | The same paths | PT `teams_messages.c:1475, 1836, 1875, 2098`; MT `consumption_horizons.go:16` | Confirmed in code | Reuse |
| Auth header `Authentication: skypetoken=…` (`src/api/client.rs:477-532`) | Same. The web client adds `ms-ic3-product: tfl`, `ms-ic3-additional-product: Sfl`, `behavioroverride: redirectAs404` and `clientinfo`; reads work without them, and `X-Skypetoken` is accepted too (§7.5). | Live capture and probe | Verified live | Reuse (add the TFL headers) |
| Chat list through CSA first, then chatsvcagg, then the chat service (`src/api/chat.rs:1536-1563`) | CSA works: `https://teams.live.com/api/csa/api/v3/teams/users/me?…` with `x-skypetoken` only (§7.6). | Live capture and probe | Verified live | Adapt (CSA at `teams.live.com/api/csa`, Skype token only) |
| New 1:1 chat `POST {chat}/v1/threads` (`src/api/chat.rs:1013-1086`) | The web client uses `POST https://teams.live.com/api/groups/v1/threads` (groupssvc bearer plus `x-skypetoken`). `{chat}/v1/threads` with the Skype token also works. 1:1 IDs are `19:uni01_…@thread.v2`. | NS doc:340, 456-460; PT `teams_messages.c:3262-3307` | Confirmed in code | Adapt |
| Sending (`src/api/chat.rs:1174-1225`) | Same; `clientmessageid` must be numeric | NS doc:342 | Confirmed in code | Reuse (check that the ID is numeric) |
| Activity feed `48:notifications` (`src/api/activity.rs:75`) | Probably the same on the consumer chat service | — | Guessed | Reuse? |
| Inline images and AMS (`ams_url()`, `src/api/client.rs:398`; `*.asm.skype.com` in `src/api/messages.rs:4584`) | `POST {ams}/v1/objects/` `{"type":"pish/image"}`, then `PUT …/content/imgpsh`, with `Authorization: skype_token <tok>`. Images are read with the `skypetoken_asm` cookie. | NS doc:462-466; MN `teams_files.cpp:140-216`; TD | Confirmed in code | Reuse (AMS host from regionGtms) |
| Custom emoji, folders and CSA aggregations (`src/api/custom_emoji.rs:11`, `src/api/folders.rs:14`) | Unknown | — | Guessed | Probably none |

### 3.3 Middle tier (profiles, settings, people)

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| `middle_tier_url()` from regionGtms (`src/api/client.rs:377`); `…/beta/users/fetchShortProfile` (`src/api/directory.rs:342`), profile pictures (`:261-282`), `beta/usersettings/8:orgid:{oid}/…` (`src/api/preferences.rs:396, 552`), `beta/contactsv3` (`src/api/contacts.rs:279-356`) | `https://teams.live.com/api/mt/beta/…`: `users/me`, `users/fetchShortProfile`, `users/fetchFederated` (work users), `users/fetchTflConsumers`, `users/searchV2`, `users/searchUsers`, `scd/lookup`, `contactsv3/`, `contacts/buddylist`, `userSettings/blocklist(/manage)` (also TFL-cfg `callBlockingSettings`). Pictures: `users/{mri}/profilepicturev2` with a cookie from `POST mt/beta/imageauth/cookie`. | PT `libteams.h:170`, `teams_contacts.c:1827-1829, 2910-2914`; TM `people.ts:274, 298`; NS doc:435-442 | Confirmed in code | Adapt |
| Auth: bearer `api.spaces.skype.com` | Bearer `mtsvc.fl…` **and** `x-skypetoken`; either alone gets 401. With the web client's tokens `fetchShortProfile` works. People search is `POST users/searchUsers` (not `searchV2`); pictures need the `imageauth/cookie` cookie (§7.7). | Live capture and probe | Verified live | Adapt |
| Privacy profile `beta/tenant/privacyProfile` (`src/api/directory.rs:99`) | No tenant | — | Guessed | None |
| Meet now and private meetings `beta/me/calendarEvents/privateMeeting/schedulingService/create` (`src/api/calendar.rs:1841, 1902`) | The same path on `teams.live.com/api/mt/beta/` | TM `config.ts:66` | Confirmed in code | Reuse |

### 3.4 Contacts and people search

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Graph `/me/contacts` (`src/api/contacts.rs:121-211`) | Graph `/me/contacts` supports personal accounts (Contacts.Read). TFL-cfg `freemium` uses `https://graph.microsoft.com/v1.0/me/contacts`. | [MS list contacts](https://learn.microsoft.com/en-us/graph/api/user-list-contacts?view=graph-rest-1.0) | Documented | Reuse |
| (none) | Skype buddy list `GET https://contacts.skype.com/contacts/v2/users/SELF?delta=&reason=default` with `X-Skypetoken` only; invites at `/users/SELF/invites`. The `mt/beta` buddy list is empty for consumers. | PT `teams_contacts.c:2706-2808`; MN `teams_contacts.cpp:138, 223` | Confirmed in code | New |
| People picker: Substrate `search/api/v1/suggestions` (`src/api/search.rs:630-668, 1110`); Graph `/users?$search` (`src/api/directory.rs:30-41`) | MT `users/searchV2` / `searchUsers` (find people by email or phone). Graph `/users` directory search does not apply to MSA. Graph `/me/people` supports MSA (People.Read). TFL-cfg `people.maxSkypeGraphResultsInPeoplePicker:20`. | PT, TM; [MS list people](https://learn.microsoft.com/en-us/graph/api/user-list-people?view=graph-rest-1.0) | Confirmed in code / Documented | New |
| Profile card: Graph `/users/{oid}`, manager, directReports, getSchedule (`src/api/profile.rs:47-89`); Loki (`:199-240`) | Graph `/users/{id}` for other users and `getSchedule` are not supported for MSA (only `/me`). Loki uses the TFL audience `liveprofilecard.access`; no public source uses it. | [MS get user](https://learn.microsoft.com/en-us/graph/api/user-get?view=graph-rest-1.0), [getSchedule](https://learn.microsoft.com/en-us/graph/api/calendar-getschedule?view=graph-rest-1.0); TFL-js | Documented | New (MT `fetchShortProfile` / `fetchTflConsumers`) |
| Off-network invites (none in OST) | MT `beta/users/me/invites` (1:1 or two-way SMS), `beta/join/{threadId}/invites`, `beta/join/{threadId}/announcement`; MRIs `8:tfloffnetwork:email:…`, `8:tfloffnetwork:phone:…`, `50:sms:` | TFL-cfg `consumerGroups`; TFL-js MRI constants | Confirmed (bundle) | New (later) |

### 3.5 Presence

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Graph `/me/presence`, `setUserPreferredPresence` (`src/api/presence.rs:39, 74`) | Not supported for personal accounts | [MS get presence](https://learn.microsoft.com/en-us/graph/api/presence-get?view=graph-rest-1.0) | Documented | None |
| `https://presence.teams.microsoft.com/v1/…` with a `presence.teams.microsoft.com` bearer (`src/api/presence.rs:82-83`; `me/endpoints`, `forceavailability`, `reportmyactivity`, `publishnote`, `presence/getpresence`, `:142-788`) | Unified presence at `https://teams.live.com/ups/global/v1/…`. TFL-cfg `presence.defaultPresenceAfdRegionGTM = "https://teams.live.com/ups/global/"`; prod's is empty. NS and TM use `ups/global/v1/presence/getpresence/` with the mtsvc bearer plus `x-skypetoken`. PT and MN still use `presence.teams.live.com/v1/…` with `X-Skypetoken` and `x-ms-endpoint-id` (a 2024 macro). regionGtms has `unifiedPresence`. | TFL-cfg; NS `presence.rs:8, 105-113`; TM `presence.ts:9`; PT `libteams.h:157` | Verified live (§7.8): the web client uses `teams.live.com/ups/global/v1/…` with bearer plus Skype token; the Skype token alone also works, on both hosts | Adapt (same paths, host from regionGtms `presenceUPS`) |
| Work location (`src/api/presence.rs:174`) | Probably not used by consumers | — | Guessed | None |
| Presence of work users seen from a personal account | Push doesn't arrive; PT polls it | PT `teams_messages.c:2543-2555` | Confirmed in code | Adapt |

### 3.6 Trouter and real-time notifications

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Negotiate `https://go.trouter.teams.microsoft.com/v4/a?epid=…` with `X-Skypetoken` (`src/trouter/session.rs:120`) | Chat: `go.trouter.skype.com`; the web client checks `/?check=` and connects straight to `wss://pub-csm-…-t.trouter.skype.com/v4/c`, then authenticates with `user.authenticate` (§7.9). Calling keeps `go.trouter.teams.microsoft.com`. | Live capture | Verified live | Adapt (host) |
| Registrar from the negotiate answer, defaulting to `prod.registrar.skype.com` (`src/trouter/mod.rs:188`, `src/api/better_together.rs:45`) | Chat: `https://edge.skype.com/registrar/prod/v2/registrations` (TFL-cfg `registrarDefaultEndpoint`; prod is `teams.microsoft.com/registrar/prod/v3/registrations`), with `X-Skypetoken` and `X-MS-Migration: True`. Calling: `https://teams.microsoft.com/registrar/prod/v2/registrations` (TFL-cfg `registrarServiceUrl`). | TFL-cfg; NS `socket.rs:374, 441`; PT `teams_trouter.c:711, 780-807` | Confirmed (bundle + code) | Adapt |
| Registrations `TeamsCDLWebWorker_2.1` with empty context; `SkypeSpacesWeb_2.4`; `DesktopNgc_2.5:SkypeNgc`; `platformUIVersion "49/1.0.0"` (`src/trouter/registrar.rs:13-37, 195-200`) | `TeamsCDLWebWorker` with **`templateKey TeamsCDLWebWorker_2.7`** and `productContext: "TFL"` (ttl 3600), plus `<id>_GG` with `TeamsCDLWebWorker_2.3`; calling `SkypeSpacesWeb` with `TFLSkypeSpacesWeb_2.0` and transport context `TFL` (§7.9). | Live capture | Verified live | Adapt (per-account table) |
| Re-registration TTL 86400 s (`src/trouter/mod.rs:187`) | The web client registers with `ttl 3600`; no timed re-registration was seen in 35 minutes (§7.9) | Live capture; PT; NS | Verified live (ttl) | Adapt |
| Chat push through Trouter | Chat messages **do** arrive by push on the Skype Trouter (`/messaging`, `NewMessage`); no polling needed (§7.9). | Live capture | Verified live | Adapt |
| Teams push service (TPS) | TFL-cfg `teamsPushService` lists `https://teams.microsoft.com/api/tps` | TFL-cfg | Confirmed (bundle) | Unknown |

### 3.7 Calling and meetings

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Conversation service `epconv` from regionGtms `calling_conversationServiceUrl` or `calling_potentialCallRequestUrl` (`src/calling/call_test.rs:685-709`), auth `Bearer {ic3_token}` (`src/calling/signaling.rs:205`; IC3 audience `src/auth/oauth.rs:14`) | `POST https://api.flightproxy.skype.com/api/v2/cpconv` (`conversationRequest`, `applicationType: "TFL"`), then `cp/{conv host}/conv/{id}`, with **`X-Skypetoken`**, not IC3. Same `X-Microsoft-Skype-Chain-Id`, `-Message-Id`, `ms-teams-ring: general`. Without the Skype token, flightproxy.skype.com answers 403 "Anonymous access is not allowed". | NS doc:470-490; PT `teams_calling.c:313-341, 360-370` | Confirmed in code | Adapt (host and auth; the call-agent callbacks and conversation model are the same family) |
| `X-Microsoft-Skype-Client: SkypeSpaces/1415/teams-cli/…` (`src/calling/signaling.rs:42`) | `SkypeSpaces/1415/26070217343/…TsCallingVersion=2026.24.01.6` | PT `teams_calling.c:310-311` | Confirmed in code | Adapt |
| TURN `api.flightproxy.teams.microsoft.com/api/v2/ep/relay/token` (`src/calling/turn.rs:66-70`) | `GET https://edge.skype.com/trap/tokens` with `X-Skypetoken`; relay `eu.relay.skype.com` / `world.relay.skype.com:3478` | TFL-cfg `TRAPServiceTokenUrl` (prod is `teams.microsoft.com/trap/tokens`); NS `calling/api.rs:28`; PT `CALLING.md:176` | Confirmed (bundle + code) | Adapt |
| Media: OST speaks the desktop dialect (SDES, `sdp-ngc`, `src/calling/sdp.rs`, `src/calling/srtp.rs`) | Teams free web uses browser media: BUNDLE, DTLS-SRTP, Opus first, H264/AV1, SCTP data, `sdp-ngc-1.0`. PT reached the Android dialect (SDES `AEAD_AES_256_GCM`, `sdp-ngc-0.5`). Whether consumer calls accept OST's desktop offer is unknown. | NS doc:495-505; PT `CALLING.md:170-181` | Confirmed in code (two dialects exist) | Must verify |
| Meeting links `teams.microsoft.com/l/meetup-join/…` and `/meet/{code}?p=` (`src/calling/outgoing.rs:3773-3789, 4144`; already strips `https://teams.live.com/l/meetup-join/` at `:3789`) | `https://teams.live.com/meet/<id>?p=…` (TFL-cfg `deepLinkDomain` `https://teams.live.com`, `deepLinkPath "/meet/"`; `shareMeetCodeLink` true for teams.live.com) | TFL-cfg; TM | Confirmed (bundle) | Adapt |
| Meeting options `teams.microsoft.com/meetingOptions` (`src/calling/outgoing.rs:3835`) | `https://teams.live.com/meetingOptions` | TFL-cfg `meetingOptionsUrl` | Confirmed (bundle) | Adapt |
| Scheduling service `api.scheduler.teams.microsoft.com/teams/` (`src/api/events.rs:1741`) | `https://api.scheduler.teams.microsoft.com/teamsforlife/`, auth resource `7557eb47-c689-4224-abcf-aef9bd7573df` | TFL-cfg `meetingSchedulingService` | Confirmed (bundle) | Adapt |
| Recording (`src/calling/recording.rs:25`, recorder token) | `tflRecordingConfig.resource = https://recordersvc.fl.teams.microsoft.com/access_recorder_service`, stored in OneDrive | TFL-cfg | Confirmed (bundle) | Adapt (later) |
| Breakout rooms, live events, town halls, room devices, PSTN/phone (`src/calling/*`) | Not offered in Teams free, or behind a paywall (TFL-cfg `hideChannelMeetingPaywallBanner`) | TFL-cfg | Guessed | None |
| Meeting chat `19:meeting_…@thread.v2` | Same thread family | NS doc:480-484 | Confirmed in code | Reuse |

### 3.8 Calendar

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Graph `/me/calendarView`, `/me/calendars`, `/me/events` (`src/api/calendar.rs:91-495`) | Graph supports personal accounts, but the Teams free client's Graph token has only `Files.ReadWrite` (`/me/calendarView` is 403). Teams free reads the calendar through the middle tier: `GET https://teams.live.com/api/mt/v2.0/me/calendars/default/calendarView?StartDate=…&EndDate=…&shouldDecryptData=false` (bearer plus Skype token) | Live capture and probe (§7.2, §7.12) | Verified live | Adapt (MT calendar) |
| `/me/memberOf/microsoft.graph.group` (group calendars, `src/api/calendar.rs:149`) | Not supported for MSA | [MS memberOf](https://learn.microsoft.com/en-us/graph/api/user-list-memberof?view=graph-rest-1.0) | Documented | None |
| `/me/calendar/getSchedule` (`src/api/profile.rs:89`) | Not supported for MSA | MS getSchedule | Documented | None |
| (none) | Teams free can also link a Google calendar and contacts (TFL-cfg `calendar.googleAuthConfig`; `externalAccounts`, `requestSource "TflCloudCache"`) | TFL-cfg | Confirmed (bundle) | New (later) |
| Events and webinars (`src/api/events.rs:36`) | Not in Teams free | — | Guessed | None |

### 3.9 Files (OneDrive personal)

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Graph `/me/drive/root/children`, `/items/{id}`, `/shares/…` (`src/api/drive.rs:73-319`) | Supported for personal accounts (Files.Read*). Personal drive items have IDs like `1312abc!1231`; OST's `check_id` (`src/api/drive.rs:59-68`) already accepts `!`. | [MS list children](https://learn.microsoft.com/en-us/graph/api/driveitem-list-children?view=graph-rest-1.0) | Documented | Reuse |
| `/me/drive/recent` (`src/api/drive.rs:196`) | Supported for MSA, but **deprecated, stops returning data after November 2026** for every account type | [MS drive recent](https://learn.microsoft.com/en-us/graph/api/drive-recent?view=graph-rest-1.0) | Documented | Replaced for work accounts by SharePoint `sp.RecentFileCollection.DeltaSync`, as Teams does (TASK-0301); personal accounts: TASK-0300 |
| `/groups/{id}/drive`, SharePoint `_api/v2.1/favorites`, `tenant-my.sharepoint.com` (`src/api/drive.rs:236, 279-298`) | No SharePoint for MSA | — | Documented | None |
| `/search/query` (`src/api/drive.rs:333`) | Not supported for MSA | [MS search query](https://learn.microsoft.com/en-us/graph/api/search-query?view=graph-rest-1.0) | Documented | None (use `/me/drive/root/search(q=…)`, guessed) |
| Chat file upload to `/me/drive/root:/Microsoft Teams Chat Files/…` and `/invite` (`src/api/files.rs:167-219`) | **Live (§7.12):** the web client uploads with Graph `PUT /v1.0/me/drive/root:/Microsoft Teams Chat Files/<name>:/content`, the same path as OST. The bundle also lists a OneDrive consumer path: TFL-cfg `files.oneDriveConsumerAppId 242df6f5-…`, `ODCConvergedEndpoint https://my.microsoftpersonalcontent.com`, the legacy "vroom" API `https://api.onedrive.com` with `WLID1.1` and `service::lw.onedrive.com::MBI_SSL` (`preferGraphOverVroom:false`). NS uses Graph. | TFL-cfg; NS doc:466 | Confirmed (bundle) | Adapt |
| Office web viewers (`officeapps.live.com`, already used) | Same, plus `odwebp.svc.ms/embed` one-up viewer | TFL-cfg | Confirmed (bundle) | Reuse |

### 3.10 Teams, channels and communities

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Graph `/me/joinedTeams`, CSA `teams.microsoft.com/api/csa/{region}/api/v1/teams/users/me/teams` (`src/api/teams.rs:110, 375-387`), channels (`src/api/channels.rs`) | Graph joinedTeams is not supported for MSA. Teams free has **communities** instead: invite links `https://teams.live.com/l/community/invite/{threadId}`, the groups service `groupssvc.fl…`, banner CDN `statics.teams.cdn.office.net/evergreen-assets/communities/`. The API surface is unknown. | [MS joinedTeams](https://learn.microsoft.com/en-us/graph/api/user-list-joinedteams?view=graph-rest-1.0); TFL-cfg `communities`, `strEndpointLinktoJoinCommunities`; TFL-js `GROUPS_SERVICE` | Documented / Confirmed (bundle) | None for teams; New for communities |
| Viva Engage communities `www.yammer.com/graphql` (`src/api/search.rs:422-431`) | Not for MSA (Engage is work-only). Teams free communities are a different product. | — | Guessed | None |

### 3.11 Search

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Substrate `searchservice/api/v2/query` (`src/api/find.rs:10-11`) | Message search through `https://msgsearch.skype.com` with `v1/query/tfl` (prod uses `us-prod.asyncgw.teams.microsoft.com`). TFL-cfg still lists `substrateTokenUrl https://substrate.office.com/M365.Access`; PT and MN request that scope for MSA. | TFL-cfg `serp.osearchBaseUrl`, `osearchQuery`; PT `teams_login.c:566` | Confirmed (bundle) | New |

### 3.12 Settings, user properties and ECS

| Work today (OST) | Consumer | Source | Confidence | Verdict |
|---|---|---|---|---|
| Chat-service `users/ME/properties` (`src/api/preferences.rs:14-245`) | Same on the consumer chat service | PT `teams_contacts.c:1291` | Confirmed in code | Reuse |
| MT `beta/usersettings/8:orgid:{oid}/…`, `useraggregatesettings` (`src/api/preferences.rs:349-659`) | Exists on the consumer MT (for example `userSettings/blocklist`); the MRI must be `8:live:…`. Which settings exist is unknown. | PT; TFL-cfg | Guessed | Adapt |
| ECS `GET config.teams.microsoft.com/config/v1/MicrosoftTeams/49_1.0.0.0` with agents `TeamsNorthstar,TeamsBuilds,Segmentation,TeamsNorthstarUserOverrides` (`src/api/ecs.rs:19-23`) | Same host. The web client asks for namespaces **`TflNorthstar`**, `TeamsBuilds`, `Segmentation` (`ecsNamespaces`, `criticalEcsNamespaces ["TflNorthstar"]`). The filters (tenant, licence) differ; `licenseDetails` may carry `isFreemium`. | TFL-cfg; TFL-js | Confirmed (bundle) | Adapt |
| Roaming settings | `https://roaming.officeapps.live.com/rs/v1/settings` with `service::officeapps.live.com::MBI_SSL_SHORT` (prod uses `api.office.net`) | TFL-cfg `officeRoamingUrl`, `officeRoamingTokenAudience` | Confirmed (bundle) | Adapt (if OST uses roaming) |
| Feedback / diagnostics | `api.msa.diagnostics.office.com` (prod `api.diagnostics.office.com`). OST sends feedback to GitHub, so this doesn't matter. | TFL-cfg | Confirmed (bundle) | n/a |
| Premium `teams.microsoft.com/api/authsvc/v1.0/lfts/TeamsPremium` (`src/api/premium.rs:12`) | Teams free has its own "freemium"/Microsoft 365 consumer upsell (TFL-cfg `freemium`, `monetization`) | TFL-cfg | Guessed | None |
| Privacy and legal links | Different fwlinks (for example privacy `linkid=2186904`, legal `linkid=2186905`) | TFL-cfg vs prod | Confirmed (bundle) | Adapt (strings) |

### 3.13 Other work-only services OST calls

These have no equivalent in TFL-cfg, or are work tenant services; hide
them for personal accounts:

- Copilot (`m365copilotapp.svc.cloud.microsoft`, `src/api/meeting_copilot.rs:32`)
- AugLoop Editor (`augloop.office.com`)
- Places / work location
- Hubble content
- Store and app suggestions (`src/api/app_details.rs:29`)
- Attendance reports (`src/api/attendance.rs:22`)
- Meeting notes service (`src/api/meeting_notes.rs:32`)
- Outlook substrate (`outlook.office.com/.default`)
- Loop
- Whiteboard
- Templates (`templates.teams.microsoft.com`)

TFL-cfg does list `augloop.office.com` and `api.flow.microsoft.com`
entries, but those may be inert defaults. Treat each one as None until it
is checked live.

## 4. Identity and MRIs

| | Work | Personal |
|---|---|---|
| User MRI | `8:orgid:{oid}` | `8:live:.cid.<hex>`, the cid **without leading zeros** (verified live: oid `00000000-0000-0000-0ca2-738c364862c6` is `8:live:.cid.ca2738c364862c6`). Older accounts migrated from Skype may be `8:live:<skypename>` (PT `teams_contacts.c:1222-1233`). TFL-js lists the consumer prefixes `live`, `sip_profile`, `myspace`, `c2c`, `sms`, `facebook`, `fb` after `8:`. |
| Source | `oid` claim of the access token (`src/config/mod.rs:125-128`) | `skypeid` in the Skype token (a JWT) or in authz `skypeToken.skypeid` |
| Tenant | `tid` claim | none (MSA tenant `9188040d-…`); `isBusinessTenant:false` |
| Other MRIs Teams free uses | | `8:tfloffnetwork:email:…` / `phone:…` (invited people not on Teams), `50:sms:`, `50:smsunverified:`, `8:teamsvisitor:` (anonymous), `tflfed:` (federation) (TFL-js MRI constants) |

OST impact: `8:orgid:` appears in 52 source files, with about 75
non-test sites that build, strip or test it. `object_id()` has 59 call
sites and `tenant_id()` has 25 (counted 2026-11-25 with `grep`). A
`Config::self_mri()` (and `user_mri(id)`) abstraction is a prerequisite
for everything else. So is a tenant-free path wherever a `tenantId` goes
into a URL or body: meeting links, `meetingOptions`, `fetchShortProfile`
bodies and ECS filters.

## 5. Federation (work account and personal account)

| Item | Value | Source | Confidence |
|---|---|---|---|
| Admin switch | "People in my organization can communicate with unmanaged Teams accounts" (`Set-CsTenantFederationConfiguration -AllowTeamsConsumer`, plus `AllowTeamsConsumerInbound`; per-user `EnableTeamsConsumerInbound`). On by default; not in GCC, GCC High, DoD. | [MS manage external access](https://learn.microsoft.com/en-us/microsoftteams/manage-external-access) | Documented |
| Work client flag | TFL-js `enableTfwTflFederation` (TFW is Teams for work, TFL is Teams for life): `true` in prod (`false` in GCC), `false` in life. So the work client hosts these chats. | TFL-cfg vs prod | Confirmed (bundle) |
| Chat flags | Conversation fields `hasTflConsumerUser`, `isTfwTflFedChat`, `hasTflOffnetworkUser`, `hasTflSmsUser`; these chats count as external | TFL-js GraphQL fragments | Confirmed (bundle) |
| MRIs across the boundary | A personal user sees work users as `8:orgid:<guid>`; a work user sees personal users as `8:live:…` | PT `teams_messages.c:2543-2555` | Confirmed in code |
| Profile lookup | From personal: MT `users/fetchFederated` for work users. From work: MT `users/fetchTflProfiles` (`{"mris":[…]}`) and `users/<email>/externalsearchv3?includeTFLUsers=true` for search (§7.13). | Live capture | Verified live |
| Starting a chat | Personal side: `searchUsers` by email finds the work user (`Federated`), then `groups/v1/threads`. Work side: the chat arrives quarantined (`relationshipState.inQuarantine`) with Block/Accept; the profile comes from `fetchTflProfiles`. A work user typing an undiscoverable personal email creates a B2B guest invite instead (§7.13). | Live capture | Verified live |
| The chat on the work side | `19:uni01_…@thread.v2`, `threadType` chat with `productThreadType` "OneToOneChat" (a 1:1 although its id is a thread's), thread `productContext` TFL, `tenantid` 0000…; members `8:live:…` (Admin) and the work user. `fetchTflProfiles` with `{"mris": […]}` gives `emailsInfo: []` for someone who doesn't share their address; with `{"invitersToThreads": {mri: thread}}` it gives `[{address, visibility: "Private"}]` (TASK-0289). | Live probe 2026-11-27 | Verified live |
| Answering a request (work side) | Accept: `POST {mt}/beta/userSettings/acceptlist/manage` `{"add": [mri]}`; the chat service then clears `inQuarantine`. Block: `…/userSettings/blocklist/manage` `{"add": [mri]}`. Teams also sets the conversation's `interopconversationstatus` (Accepted / Blocked) in its own store only: written to the chat service it is refused (400 ThreadPropertyNotAllowed). | Teams 26304 shared worker `acceptBlockUnblockChat`; live probe | Accept verified live (TASK-0289, ost-test1 ← OST Personal 2); Block from the bundle only |
| Requests on the personal side | A chat from someone who isn't in your contacts arrives with `relationshipState.inQuarantine` (1:1 and group alike, personal-to-personal too) and is listed under Teams free's Requests. Teams free's middle tier has no accept list (`userSettings/acceptlist/manage` answers 405). Its worker (`acceptBlockUnblockChat`, life build): Accept on a 1:1 adds the inviter to your contacts (`POST {mt}/beta/contacts/buddylist/TflContacts/managebuddies` `{"add":[{mri, displayName}]}`); Accept on a group sets your membership's `relationshipState` to "Accepted" (`PUT {chat}/v1/threads/{id}/members/{you}`); Block is `POST {mt}/beta/userSettings/blocklist/manage?ggEnabled=true` `{"add":[mri]}`. New chats: `POST teams.live.com/api/groups/v1/threads` (1:1: members role `User`, `isStickyThread`; group: role `Admin`), then the person goes in your contacts the same way. | Teams free worker bundle and web capture, 2026-11-28 (TASK-0293) | Verified live (creation, request list); answers from the bundle, see TASK-0293 notes |

For OST this matters even without personal sign-in. A work user in OST
can already receive chats from personal users, and OST would mishandle
`8:live:` members: names, pictures, presence and the "external" label.

## 6. Graph: which of OST's calls fail for personal accounts

| OST call | File | MSA |
|---|---|---|
| `/me` | `src/api/me.rs:43` | Supported for MSA in general, but **403 with the Teams free client's Graph token** (it only carries `Files.ReadWrite`; verified live, §7.12). Use the id_token and MT `users/me/` instead |
| `/users/{oid}`, `/manager`, `/directReports` | `src/api/profile.rs:47-63`, `src/api/teams.rs:1011`, `src/api/channels.rs:927`, `src/api/files.rs:373` | **Fails** (personal accounts read only their own profile) |
| `/users?$search=` | `src/api/directory.rs:30-41` | **Fails** (directory) |
| `/me/presence`, `setUserPreferredPresence` | `src/api/presence.rs:39, 74` | **Not supported** |
| `/me/joinedTeams`, channels | `src/api/teams.rs:110-123` | **Not supported** |
| `/me/memberOf` | `src/api/calendar.rs:149` | **Not supported** |
| `/me/calendar/getSchedule` | `src/api/profile.rs:89` | **Not supported** |
| `/search/query` | `src/api/drive.rs:333` | **Not supported** |
| `/groups/{id}/drive` | `src/api/drive.rs:236` | **Fails** (no groups) |
| `/me/calendarView`, `/me/calendars`, `/me/events` | `src/api/calendar.rs` | Supported for MSA, but 403 with the Teams free client's token; use MT `v2.0/me/calendars/default/calendarView` |
| `/me/contacts`, `/me/outlook/masterCategories` | `src/api/contacts.rs:121-211` | Supported for MSA, but 403 with the Teams free client's token |
| `/me/drive/…`, `/shares/…` | `src/api/drive.rs`, `src/api/files.rs` | Supported, also with the Teams free client's token (verified live: `/me/drive`, `/me/drive/root/children`) (`recent` deprecated for everyone; work accounts now use SharePoint's recent files service) |
| `/me/people` (not used yet) | — | Supported for MSA, but 403 with the Teams free client's token |

Sources: the Microsoft Graph v1.0 permission tables linked in §3. They
were read 2026-11-25.

## 7. Must verify live (verified 2026-11-27)

Every item below was checked live on 2026-11-27 (TASK-0287) with the two
personal test accounts (OST Personal 1 and 2, `ost-personal1-5135@outlook.com`
and `ost-personal2-0238@outlook.com`) and the work test accounts. How:

- **Web:** teams.live.com in two isolated headless Chrome profiles on the
  coordinator PC (Chrome 153, web client `1415/26101516645`), one per
  personal account, with a CDP network capture that kept only token shapes
  (prefix, length, segment count; JWT claims without signatures). A probe
  script then redeemed its own PKCE code for the Teams free client and
  called the endpoints directly. The work side (ost-test1) was captured the
  same way on teams.microsoft.com (web client `1415/26110100723`).
- **Desktop:** Teams `26304.1207.5384.858` on testpc2 with OST Personal 2
  added next to OST Test 2 (see the features doc). WebView2's DevTools
  endpoint hung each time Teams opened a new window or flyout, so the
  desktop checks are UI-level (UI Automation and screenshots).

Status per item: **Verified** (as written), **Corrected** (the earlier text
was wrong; the live value is given) or **Partly verified** (what is still
open and why).

1. **Return address and Origin. Corrected.** Teams free's MSAL (msal.js
   browser 5.6.3) sends `redirect_uri=https://teams.live.com/v2/authv2`, not
   `/v2`. The first authorize asks only `openid profile offline_access`
   with `tenant=consumers`, `response_mode=fragment`, `prompt=select_account`,
   `client_info=1` and PKCE; login.microsoftonline.com/consumers hands off to
   `login.live.com/oauth20_authorize.srf`. The code is redeemed at
   `https://login.microsoftonline.com/consumers/oauth2/v2.0/token` with
   `Origin: https://teams.live.com`. **Origin is required:** a redemption
   or refresh without it fails with AADSTS90023 ("Tokens issued for the
   'Single-Page Application' client-type should only be redeemed via
   cross-origin requests"), and that failed attempt burns the code.
   `response_mode=query` with `prompt=none` also works for the client.
   Refresh tokens: `refresh_token_expires_in` 86400 (24 h), rotated on every
   redemption. The web client redeems refreshes at
   `login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/oauth2/v2.0/token`
   (the MSA tenant GUID); `/consumers` works too.
   A new account also met: "Verify your email" (a code to the recovery
   address, with a "Use your password" link), "Stay signed in?", then a
   Teams welcome page ("Welcome, <name>", Continue) and a two-step "What is
   your primary use for Teams?" survey.
2. **Scopes one refresh token can mint. Verified, with corrections.** One
   SPA refresh token (client `4b3e8f46-…`, Origin set) minted all of these:
   `https://auth.fl.teams.microsoft.com/teams.auth.readwrite`,
   `https://mtsvc.fl.teams.microsoft.com/teams.mt.readwrite`,
   `https://groupssvc.fl.teams.microsoft.com/teams.readwrite` (granted with
   `…/teams.communities.export`), `https://recordersvc.fl.teams.microsoft.com/access_recorder_service`,
   `https://substrate.office.com/M365.Access`, `https://augloop.office.com/v2/.default`,
   `https://m365copilotapp.svc.cloud.microsoft/.default`,
   `https://consentservice.microsoft.com/checkin/UnifiedUserConsent.Read`,
   `liveprofilecard.access`, and the MBI_SSL style
   `service::api.fl.spaces.skype.com::MBI_SSL`, `service::api.fl.teams.microsoft.com::MBI_SSL`,
   `service::api.fl.sms-free.spaces.skype.com::MBI_SSL`, `service::lw.onedrive.com::MBI_SSL`.
   Graph: `https://graph.microsoft.com/.default` is granted as
   **`Files.ReadWrite` only** (the client also asks
   `https://graph.microsoft.com/Files.ReadWrite` directly); `User.Read` and
   `Calendars.Read` are refused. Refused with AADSTS70011 (invalid scope):
   `chatsvcagg.teams.microsoft.com/.default`, `searchsvc.fl…/teams.search.readwrite`,
   `teamsopenaisvc.fl…/teams.readwrite`, the scheduler resource
   `7557eb47-…/.default`, `service::officeapps.live.com::MBI_SSL_SHORT`.
   `presence.teams.microsoft.com/.default` fails with AADSTS9002332.
   `https://api.spaces.skype.com/.default` is silently dropped (the token
   comes back with only `openid profile`).
3. **authz v1 vs v2. Verified, with corrections.** The web client calls
   `POST https://teams.live.com/api/auth/v2.0/authz/consumer` with the
   `auth.fl` bearer, an empty body and `ms-teams-authz-type: ExplicitLogin`,
   `x-ms-client-type: web`, `x-ms-client-version: 1415/<build>`,
   `claimschallengecapable: true`, `clientrequestid`, `x-ms-request-id`
   (no `X-MS-Client-Consumer-Type`). The response has four top-level keys:
   `skypeToken` {`skypetoken`, `expiresIn` (28,799 s, about 8 h, not 24 h),
   `skypeid` (`live:.cid.<hex>`), `signinname` (the display name),
   `isBusinessTenant: false`}, `regionGtms`, `regionSettings`
   {`isUnifiedPresenceEnabled`, `isOutOfOfficeIntegrationEnabled`,
   `isContactMigrationEnabled`, `isAppsDiscoveryEnabled`, `isFederationEnabled`}
   and **`consumerLicenseDetails`** (not `licenseDetails`): `teamsFree`
   {`maxMeetingDurationMinutes` 60, `maxMeetingParticipants` 100,
   `copilotEnabled`, `callRecordingEnabled`, `premiumMeetingOptionsEnabled`,
   `decorateMeetingBackgroundEnabled`, `intelligentRecapEnabled`} plus the
   same fields at top level, `hasTeamsLicense: false` and
   `licenseVersionTimestamp`. The Skype token is an RS256 JWT with
   `skypeid`, `cid`, `scp: 956`, `csi`, `aat`, `iat`, `exp`.
   `regionGtms` has 42 keys: `ams` (`https://us-api.asm.skype.com`), `amsV2`
   (`https://experimental-api.asm.skype.com`), `chatService`
   (`https://msgapi.teams.live.com`), `chatServiceAfd`
   (`https://teams.live.com/api/chatsvc/consumer`), `chatServiceS2S`,
   `chatServiceAggregator` (`https://chatsvcagg.teams.microsoft.com`),
   `middleTier`, `mtImageService`, `teamsAndChannelsService`,
   `consumerLicenses`, `groupsService` (all `https://teams.live.com/api/mt`),
   `groupsServiceV2`/`communitiesServiceV2` (`https://teams.live.com/api/groups`),
   `unifiedPresence` (`https://presence.teams.live.com`), `presenceUPS`
   (`https://teams.live.com/ups/global`), `search` (`https://msgsearch.skype.com`),
   `searchService` (`https://teams.live.com/api/search`), `openAIService`,
   `eventService`, `authService`, `userIntelligenceService`, `vaultService`,
   `urlp`, `drad`, `userProfileService`, `appsDataLayerService`,
   `wikiService`, `powerPointStateService`, `calling_callControllerServiceUrl`
   (`https://api.cc.skype.com`), `calling_conversationServiceCaptchaUrl`,
   and `…EndpointMetadata` objects ({`endpointUrl`, `authority`,
   `tokenScopes`}) for groups, communities, groupsSvc, communitiesSvc,
   openAISvc, searchSvc, middleTierSvc, eventSvc and authSvc. There is **no
   `calling_conversationServiceUrl`** or `calling_potentialCallRequestUrl`.
   The **v1 endpoint does not work** with this client:
   `v1.0/authz/consumer` answers 400 `{"status":{"code":40013,"text":"Access token created for a different site."}}`
   for its MBI_SSL token and 401 code 40110 for the `auth.fl` token;
   `v1.0/authzcore/consumer` answers 404. Use v2.
4. **Opaque tokens. Corrected.** All access tokens are opaque to the
   client, in two forms: the `fl` resources, AugLoop, Copilot and the
   consent service come back as **JWE** (`eyJ…`, five segments,
   `alg: dir`/`enc: A256CBC-HS512` or `alg: RSA-OAEP`/`enc: A128CBC-HS256`,
   `zip: DEF`, lifetime 28,799 s), while `openid profile`, Graph,
   `liveprofilecard.access`, substrate and the MBI_SSL scopes come back as
   MSA tickets (`EwA…`/`EwB…`, one segment). Neither can be decoded. The
   identity comes from the `id_token` (`iss` …/9188040d-…/v2.0, `aud` the
   client, `name`, `preferred_username` (the email), `oid`
   `00000000-0000-0000-<cid as 4+12 hex>`, `tid` 9188040d-…, `puid`,
   `ageGroup`, `idtyp: user`, `signin_state: ["kmsi"]`, sometimes `email`)
   and from `client_info` {`uid` = `oid` = `home_oid`, `utid` = MSA tenant,
   `name`, `preferred_username`, `sub`}. The cid in the MRI drops leading
   zeros: OST Personal 2's `oid` is `00000000-0000-0000-0ca2-738c364862c6`
   but its MRI is `8:live:.cid.ca2738c364862c6` (15 hex digits).
5. **Chat service host. Verified, with corrections.** The web client uses
   the front door `https://teams.live.com/api/chatsvc/consumer/v1/…` from
   its web worker with `Authentication: skypetoken=…`,
   `ms-ic3-product: tfl`, `ms-ic3-additional-product: Sfl`,
   `behavioroverride: redirectAs404` and a `clientinfo` header; no
   `X-Stratus-Caller` and no `X-MS-Client-Consumer-Type`. Both hosts
   (`teams.live.com/api/chatsvc/consumer` and `msgapi.teams.live.com`)
   answered `users/ME/properties` and `users/ME/conversations` with
   `Authentication: skypetoken=`, with `X-Skypetoken`, and without the
   ic3 headers: **`X-Skypetoken` does not fail** there. `users/ME/properties`
   returns `primaryMemberName` (`live:.cid.…`), `cid`, `cidHex`,
   `skypeName`, `locale`, `firstLoginInformation`, `selfChatSettings`,
   `favorites`, `dogfoodUser`. New 1:1 and group chats are created with
   `POST https://teams.live.com/api/groups/v1/threads` (`groupssvc` bearer
   plus `x-skypetoken`; body `{"members":[{"id":…,"role":"User"},…],"properties":{"threadType":"chat","isStickyThread":"true"}}`),
   which returns `{"value":{"threadId":"19:uni01_…@thread.v2","membersStatus":[…]}}`.
   Messages are posted to `…/v1/users/ME/conversations/{id}/messages` as
   `RichText/Html` with a numeric `clientmessageid` and
   `properties.formatVariant: "TEAMS"`.
6. **CSA for consumers. Corrected.** CSA works for consumers:
   `GET https://teams.live.com/api/csa/api/v3/teams/users/me?isPrefetch=false&enableMembershipSummary=true&…`
   with `x-skypetoken` only (no bearer) returns `conversationFolders`,
   `teams`, `chats`, `users`, `privateFeeds` and `metadata` (`syncToken`,
   `hasMoreChats`); `…/me/updates?…` is the delta call. `api/v1/…` and
   `api/v2/…` also answer 200. Folder ids are
   `9188040d-…~<oid>~Favorites|RecentChats|TeamsAndChannels`.
   `api/csa/api/v1/translator/languages` is used too.
7. **Middle-tier auth. Verified, with corrections.** MT needs **both** the
   `mtsvc.fl` bearer and `x-skypetoken`: `users/me/` answers 200 with both,
   401 with either alone. `POST mt/beta/users/fetchShortProfile?…` with an
   MRI array works with both. People search by email or phone is
   **`POST mt/beta/users/searchUsers?ggEnabled=true`** with
   `{"emails":[…],"phones":[]}` (`x-ms-client-caller: people-picker`); it
   returns `{<email>: {"userProfiles":[…],"status":"Success"|"NotFound"}}`,
   with work users as `"type":"Federated"` plus `tenantId`/`tenantName`.
   `users/searchV2` does not exist on the consumer MT (404 "Controller is
   not registered"), and `users/fetchTflConsumers` answers 405. Work users
   are resolved with `POST mt/beta/users/fetchFederated` (`["8:orgid:…"]`).
   Pictures: `GET mt/beta/users/{mri}/profilepicturev2?displayname=…&size=HR64x64`
   uses a **cookie** set by `POST mt/beta/imageauth/cookie` (bearer plus
   Skype token); with headers alone it answers 401. Other MT calls seen:
   `users/me/`, `users/tenantsv2`, `users/istfluser`, `users/useraggregatesettings`,
   `users/updateNameAndSkypeAvatar`, `scd/searchability`, `contacts/buddylist`,
   `contacts/buddylist/TflContacts/managebuddies`, `contacts/syncSettings`,
   `contacts/sync/outlook`, `userSettings/blocklist`, `join/template`
   (invite links), `chats/{id}/apps/chatentitlements`, `me/engagementSurfaces`,
   `v1/users/tflIntent`, `v2.0/me/calendars/default/calendarView`.
8. **Presence. Verified, with corrections.** The web client uses UPS at
   `https://teams.live.com/ups/global/v1/…` (`PUT me/endpoints/`,
   `POST presence/getpresence/`, `POST pubsub/subscriptions/{endpoint}`)
   with the `mtsvc` bearer plus `x-skypetoken`, `x-ms-endpoint-id` and
   `x-ms-client-consumer-type: teams4life`. Direct calls: `getpresence`
   works with both, and with the Skype token alone; bearer alone is 401.
   `https://presence.teams.live.com/v1/presence/getpresence/` (regionGtms
   `unifiedPresence`) also answers with `X-Skypetoken` alone. Presence of
   a personal user is
   `{"sourceNetwork":"Unknown","availability":…,"activity":…}`.
9. **Trouter. Verified, with corrections.** There is no `v4/a` negotiate:
   the client checks `GET https://go.trouter.skype.com/?check=…&epid=…&tc=…`
   (answer `Trouter`), then opens
   `wss://pub-csm-<region>-t.trouter.skype.com/v4/c?tc=…&timeout=40&epid=…`
   and sends `user.authenticate` with `X-Skypetoken`,
   `X-MS-Migration: True` and `connectparams` (`sr`, `sp`, `se`, `st`).
   Chat registration: `POST https://edge.skype.com/registrar/prod/v2/registrations`
   (`X-Skypetoken`, `X-MS-Migration: True`, `x-ms-test-user: False`) with
   `appId TeamsCDLWebWorker`, **`templateKey TeamsCDLWebWorker_2.7`**,
   `productContext TFL`, `ttl 3600`, plus a second registration
   `<id>_GG` with `TeamsCDLWebWorker_2.3`, empty context, `ttl 86523`.
   Calling uses a separate socket on `go.trouter.teams.microsoft.com`
   (`ua SkypeSpaces`) registered at `teams.microsoft.com/registrar/prod/v2/registrations`
   with `SkypeSpacesWeb`/`TFLSkypeSpacesWeb_2.0`, transport context `TFL`,
   `ttl 3600`. **Chat messages arrive by push:** a work reply reached the
   personal client as a `/messaging` request (`resourceType NewMessage`,
   plus `ThreadUpdate`, `ConversationUpdate`) within a second; presence
   arrives on `/unifiedPresenceService`. Re-registration: no timed
   re-registration was seen within the 35 minutes observed (only after
   reloads), so use the registration `ttl` (3600 s).
10. **Calling. Partly verified.** A personal meeting (Meet > Create a meeting
    link > Join) joined from the web client: `POST https://api.flightproxy.skype.com/api/v2/cpconv`
    with `X-Skypetoken`, `X-Microsoft-Skype-Chain-ID`, `X-Microsoft-Skype-Message-ID`,
    `MS-Teams-Ring: general`, `X-Microsoft-Skype-Client: SkypeSpaces/1415/<build>/…/TsCallingVersion=2026.40.01.8/…`
    and a `conversationRequest` with `applicationType: "TFL"`. The answer's
    `Location`, `conversationController` and links point at
    `https://api.flightproxy.teams.microsoft.com/api/v2/ep/conv-usea-05-prod-aks.conv.skype.com/conv/…`,
    the broker (`…/ep/broker-…broker.skype.com/api/v1/subscribe/…`) and the
    call controller (`…/ep/cc-…cc.skype.com/cc/v1/…`). The meeting state is
    `conversationType: scheduledMeeting`, `isHostless: true`; others wait in
    the lobby until the organizer admits them. Without a Skype token
    cpconv answers 401/403 "Anonymous access is not allowed". TURN:
    `GET https://edge.skype.com/trap/tokens` with `X-Skypetoken` returns
    `realm`, `username`, `password`, `expires`. Media: the web client
    answered the server's offer (`cc/v1/negotiations/…/answer`) in the
    browser dialect (BUNDLE, DTLS `a=fingerprint`/`a=setup:active`,
    `a=ice-options:trickle`, H264). **Open:** whether consumer calls accept
    OST's desktop dialect (SDES) can only be tested by sending OST's offer,
    which needs the consumer calling code first (TASK-0298); the Windows
    desktop client's dialect could not be captured because its DevTools
    endpoint hung.
11. **ECS for consumers. Verified.** `GET https://config.teams.microsoft.com/config/v1/MicrosoftTeams/1415_1.0.0.0`
    with `environment=life`, `experience=react-web-client`, `buildType`,
    `browser`, `browserVersion`, `osPlatform`, `isOcdi`, `isPwa`,
    `id=<oid>`, `aaduserid=<oid>`, `tenantId=9188040d-…`, `experienceBuild`,
    `teamsLocale`, `mtmaCount`, `sessionId`, `clientId`,
    `agents=TflNorthstar,TeamsBuilds,Segmentation`, `ECSCanary=1`; no
    licence parameters and no auth header. The client also fetches
    `config/v1/Skype/1415_1.0.0.0` and `config.edge.skype.com/config/v1/CHILL/0.0.13`.
12. **OneDrive. Verified, with one open point.** The Graph token
    (`Files.ReadWrite`) works for `GET /me/drive` and
    `/me/drive/root/children`; `/me`, `/me/calendarView`, `/me/contacts`
    and `/me/people` answer 403 and `/me/presence` 400. Chat file upload
    uses Graph: `PUT https://graph.microsoft.com/v1.0/me/drive/root:/Microsoft%20Teams%20Chat%20Files/<name>:/content?@microsoft.graph.conflictBehavior=rename&select=*,sharepointIds`,
    after `GET /beta/me/settings/storage/quota` and `GET /v1.0/me/drive`,
    and the client stores `personalFileSite` = `{"driveId":"<cid>"}` with
    `PUT chatsvc/…/users/ME/properties?name=personalFileSite`. The compose
    box showed "Anyone with the link can edit". **Open:** the send of that
    file message never completed in the headless web client, so the
    message's `files` property and the link-creation call were not seen.
13. **Federation from the work side. Verified.** Search: the work client
    calls `GET mt/…/beta/users/<email>/externalsearchv3?includeTFLUsers=true`
    (`x-ms-client-caller: newChat`). For personal accounts whose email
    isn't discoverable it returns `[]`; the picker still offers the email
    with an "External" tag, and starting the chat then **invites the
    address as a B2B guest** (`PUT mt/…/beta/teams/inviteAndAddSingleGuestToTenant`
    `{"emailAddress":…}` → `{"invited":{"role":"Guest","userPrincipalName":"…#EXT#@…","mri":"8:orgid:…"}}`)
    and shows "Your invitation is on its way…". That is a guest chat, not a
    Teams-free chat. When a personal user starts the chat (personal side:
    `searchUsers` finds the work user as `Federated`, then
    `groups/v1/threads`), the work client gets a 1:1 thread
    `19:uni01_…@thread.v2` whose thread properties have
    `productContext: "TFL"`, `partnerName: "TFLGroupService"`,
    `tenantid 00000000-0000-0000-0000-000000000000`, creator `8:live:…`, and
    whose member properties carry **`relationshipState.inQuarantine: true`**
    until the work user accepts (CSA lists it with `hidden: true`). The
    work client resolves the person with
    `POST mt/…/beta/users/fetchTflProfiles?edEnabled=false&includeDisabledAccounts=true`
    (`{"mris":[…]}` or `{"invitersToThreads":{mri: threadId}}` →
    `resolvedUsers[]` with `"type":"TflConsumer"`, `skypeId`, `displayName`,
    `emailsInfo` with `visibility`), loads the picture from
    `GET mt/…/beta/users/<own oid>/profilepicturev2/8:live:.cid.…?displayname=…&size=HR64x64`,
    and gets presence from work UPS (`ups/noam/v1/presence/getpresence/`
    and a `pubsub` subscription), which answered `PresenceUnknown` (status
    50000) before the request was accepted. The UI is in the features doc
    (item 10).
14. **Teams desktop MSA client ID. Not needed.** The web client covers
    every flow OST needs, so this was not captured (the desktop signs in
    through WAM; its DevTools endpoint hung when the sign-in window
    opened).

## 8. Suggested backlog breakdown (for planning)

Foundations first; each item can ship and be tested on its own:

1. **Account identity abstraction.** `self_mri()`, `user_mri()`, an
   optional tenant, and a display name that doesn't depend on the access
   token JWT. Refactor the `8:orgid:` sites. Useful for work accounts too,
   because of federated `8:live:` members.
2. **Work side: render `8:live:` members.** Names, pictures, the external
   label, and presence polling in federated chats.
3. **Personal sign-in flow.** The client, authority, redirect and origin
   from §1.2 in OST's web view, plus the 24-hour silent renewal. Remove or
   fix the broken `AuthConfig::personal()`.
4. **Consumer authz and regionGtms.** Parse both response shapes and
   persist `skypeid`.
5. **Consumer chat service.** Hosts and headers; chat list (CSA or chat
   service), read, send, create a 1:1 chat.
6. **Consumer Trouter and registrar.** With polling as a fallback if push
   doesn't deliver.
7. **Consumer middle tier.** Profiles, pictures, people search by email or
   phone, block list.
8. **Consumer contacts.** Skype buddy list and invites.
9. **Consumer presence.** UPS.
10. **Calendar and Meet now** for personal accounts: Graph plus MT
    `privateMeeting`, and `teams.live.com/meet` links.
11. **OneDrive personal** for files and chat attachments.
12. **Hide work-only features** (§3.10–3.13) by account type, including
    the ECS `TflNorthstar` settings.
13. **Consumer calling.** cpconv, trap tokens, and a check of the media
    dialect. The largest item; it depends on the live check in §7.10.
14. **Communities** (Teams free's replacement for teams). Needs protocol
    research first.

## 9. Session renewal, teams-cli sign-in, push and presence (verified 2026-11-28)

Checked live for TASK-0292, 0294 and 0296 with OST Personal 1 and 2: an
isolated headless Chrome on linuxlt on teams.live.com (web client
`1415/26101516645`, msal.js browser 5.6.3) with a network capture that kept
only token shapes, plus direct calls.

### 9.1 How Teams on the web keeps a personal session past 24 hours

- **Cookies.** Answering "Stay signed in?" with Yes sets persistent
  cookies for about 390 days (Secure, SameSite=None): `__Host-MSAAUTHP`
  on login.live.com (HttpOnly), and `MSPAuth`, `MSPProf` and `WLSSC` on
  `.live.com`. The session-only twin `__Host-MSAAUTH` is deleted then.
- **MSAL's cache.** The refresh token's `expiresOn` is its cache time plus
  86,400 s. The OpenID token has no `login_hint` or `sid` claim (claims:
  `ver iss sub aud exp iat nbf name preferred_username oid tid
  signin_state puid ageGroup idtyp xms_idrel aio`). Teams also keeps its
  own encrypted copies of the tokens (`tmp.auth.v1.<oid>.Token.<resource>`,
  `…Discover.SKYPE-TOKEN`).
- **Renewal.** With the refresh token expired, MSAL logs
  `refresh_token_expired` and loads, in a hidden iframe,
  `login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/oauth2/v2.0/authorize`
  with `client_id=4b3e8f46-…`, `scope=https://auth.fl.teams.microsoft.com/teams.auth.readwrite openid profile offline_access`,
  `redirect_uri=https://teams.live.com/v2/authv2`, `response_mode=fragment`,
  `response_type=code`, PKCE, **`prompt=none`**, `login_hint=<email>`,
  `X-AnchorMailbox=Oid:<oid>@<tid>`, `client_info=1`, `clidata=1`, `nopa=2`,
  `coa=1`, `nonce`, `state`, `client-request-id`, `x-client-SKU`/`-VER`.
  login.microsoftonline.com 302s to `login.live.com/oauth20_authorize.srf`,
  which, sent the cookies above, 302s straight to
  `teams.live.com/v2/authv2#code=…`. The code is redeemed at
  `login.microsoftonline.com/<tid>/oauth2/v2.0/token`, giving a new
  24-hour refresh token.
- **OST's own silent URL works.** In the same browser, top-level
  navigations to the URL OST builds (`/consumers`, `openid profile
  offline_access`, `login_hint`, `prompt=none`) returned a code, as did
  every variant tried (no `login_hint`; the web client's exact set; the
  tenant GUID; `response_mode=query`; a QtWebEngine user agent).
- **What decides it.** In fresh browser contexts: no cookies, session
  cookies only, or everything but the four persistent ones answer
  `login_required: Silent authentication was denied`; the persistent
  cookies alone, or `__Host-MSAAUTHP` alone, give a code; a `login_hint`
  for another account gives `login_required`.
- **PR #69's `interaction_required`.** Not reproduced. A sign-in that
  answered login.live.com's "Verify your email" with "Don't ask me again
  on this device" unticked (an untrusted device) still renewed silently in
  Chrome, and OST's own web view, signed in through the email code and
  "Stay signed in", holds `__Host-MSAAUTHP` (to 2027-12-23) across
  restarts and renews silently ("browser sign-in renewed", also with its
  refresh token made unusable). Without those cookies the answer is
  `login_required`.
- **OST now:** a personal account renews silently like a work one (at
  start and every 12 hours, `BrowserSignIn::personal(hint, prompt=none)`
  in the shared web profile). When login.live.com wants the user, OST
  carries on with the refresh token and opens the sign-in page once that
  is refused.

### 9.2 teams-cli: device code with Teams' native client

Teams on the web for personal use's client is a single-page app, which
Microsoft refuses a device code (AADSTS70002). Teams' native client for
personal accounts, `8ec6bc83-69c8-4392-8f08-b3c986009232` ("Microsoft
Teams-T4L" on the consent page), gets one at
`login.microsoftonline.com/consumers/oauth2/v2.0/devicecode` with
`https://auth.fl.teams.microsoft.com/teams.auth.readwrite openid profile offline_access`
(verification page `https://www.microsoft.com/link`, which hands off to
`login.live.com/oauth20_remoteconnect.srf`). Its tokens: the `auth.fl`
token works at authz v2 (`consumer` Skype token, 28,799 s); the same
refresh token (no Origin needed, no `refresh_token_expires_in`: not held to
24 hours) mints `mtsvc.fl` (28,799 s; MT `users/me` and
`fetchShortProfile` answer 200 with it plus the Skype token), Graph
(3,599 s) and `groupssvc.fl`. Its OpenID token has the same claims as the
web client's (`oid` `00000000-0000-0000-<cid>`, `tid` 9188040d-…).
`teams-cli login --personal` uses it (`auth_flow = "teams-live-device"`).

### 9.3 Trouter

- `GET https://go.trouter.skype.com/v4/a?epid=<uuid>` with the consumer
  `X-Skypetoken` answers 200 like the work negotiate: `socketio`
  `https://pub-csm-<region>-t.trouter.skype.com:443/`, `surl`/`url`
  `https://pub-csm-<region>-f.trouter.skype.com:3443|8443/v4/f/<id>/`,
  `ttl`, `ccid`, `connectparams`, `registrarUrl`
  `https://edge.skype.com/registrar/prod/V3/registrations`. (The same
  token at `go.trouter.teams.microsoft.com` gives an enterprise socket and
  the `communications.svc.cloud.microsoft` registrar.)
- The web client itself skips the HTTP negotiate: `GET
  go.trouter.skype.com/?check=<ms>&cor_id=…&epid=…&tc=…` (answer
  `Trouter`), then `wss://go.trouter.skype.com/v4/c?tc=…&timeout=40&epid=…&ccid=&cor_id=…&con_num=<ms>_0`;
  after `1::` it sends `5:::{"name":"user.authenticate","args":[{"headers":{"X-Ms-Test-User":"False","X-Skypetoken":…,"X-MS-Migration":"True"}}]}`
  and gets `trouter.connected` with `id`, `ccid`, `url`, `surl`, `ttl`,
  `reconnectUrl` (`wss://pub-csm-<region>-t.trouter.skype.com:443/v4/c`),
  `registrarUrl` and `connectparams`. It reconnects to `reconnectUrl` with
  the saved `connectparams` in `user.authenticate`. `tc` is
  `{"cv":"2026.40.01.1","ua":"TeamsCDL","hr":"","v":"1415/26101516645"}`.
  Pings are `5:<n>+::{"name":"ping"}` about every 40 s.
- Chat registrations, `POST https://edge.skype.com/registrar/prod/v2/registrations`
  (`X-Skypetoken`, `x-ms-test-user: False`, `X-MS-Migration: True`; 202):
  `{"clientDescription":{"appId":"TeamsCDLWebWorker","aesKey":"","languageId":"en-US","platform":"chrome","templateKey":"TeamsCDLWebWorker_2.7","platformUIVersion":"1415/26101516645","productContext":"TFL"},"registrationId":"<epid>","nodeId":"","transports":{"TROUTER":[{"context":"","path":"<surl>","ttl":3600}]}}`
  and the same with `registrationId` `<epid>_GG`, `templateKey`
  `TeamsCDLWebWorker_2.3`, `languageId` and `productContext` empty, the
  path without its trailing slash and `ttl` 86523.
- Calling uses a second socket (`ua SkypeSpaces`) on
  `go.trouter.teams.microsoft.com` (`…/v4/c?…&dom=teams.live.com`), whose
  `user.authenticate` has only `X-Skypetoken`, registered at
  `https://teams.microsoft.com/registrar/prod/v2/registrations` as
  `SkypeSpacesWeb` / `TFLSkypeSpacesWeb_2.0`, transport context `TFL`,
  ttl 3600, twice (`<uuid>` and `<uuid>-gg`).
- Chat pushes arrive as `/v4/f/<id>/messaging` requests from
  Skype-NotificationHub with `{"type":"EventMessage","resourceType":"NewMessage"|"ThreadUpdate"|"ConversationUpdate","resourceLink":…,"resource":{…}}`,
  the work shape. No timed re-registration was seen in about 18 minutes.

### 9.4 Presence (UPS)

All on `https://teams.live.com/ups/global/v1/…` with `Authorization:
Bearer <mtsvc.fl>`, `x-skypetoken`, `x-ms-endpoint-id: <chat socket
epid>`, **`x-ms-client-consumer-type: teams4life`** (without it:
400 "Consumer client type header must not be empty"),
`x-ms-client-type: cdlworker`, `x-ms-client-user-agent: Teams-V2-Web`,
`x-ms-client-version`, `x-ms-client-caller`, `behavioroverride:
redirectAs404`, `x-ms-correlation-id`, `x-ms-session-id`.

- After Trouter connects: `POST pubsub/subscriptions/<epid>`
  `{"trouterUri":"<surl>unifiedPresenceService","shouldPurgePreviousSubscriptions":true,"subscriptionsToAdd":[{"mri":"8:live:.cid.<me>","source":"ups"}],"subscriptionsToRemove":[]}`
  (contacts are added later with `false`); `POST presence/getpresence/`
  `[{"mri":…,"source":"ups"}]`; `PUT me/endpoints/`
  `{"id":"<epid>","availability":"Available","activity":"Available","activityReporting":"Transport","deviceType":"Web"}`
  (201), re-PUT once about 3 minutes later. No `reportmyactivity`:
  activity goes over the socket as `user.activity`.
- Set status: `PUT me/forceavailability/` with `{"availability":"Available"|"Busy"|"DoNotDisturb"|"BeRightBack"|"Away"}`,
  `{"availability":"Offline","activity":"OffWork"}` for Appear offline,
  and an empty body to reset: the work bodies.
- Status message: `PUT me/publishnote` with `{"expiry":"9999-12-31T08:00:00.000Z","message":"…"}`
  (Never: 9999-12-31 local midnight), `{"expiry":"<iso>","message":"…"}`,
  or `{"message":""}` to clear. Plain text, at most 280 characters; expiry
  Never, Today, 1 hour, 4 hours or This week; no "Show when people message
  me".
- Pushes arrive at `/v4/f/<id>/unifiedPresenceService` (sender
  Microsoft.Skype.Presence.App/1.0) as `{"presence":[{mri,etag,source,presence{…}}],"isSnapshot":…}`,
  echoing `forcedAvailability` and `note`; the client answers each with
  status 200.

## 10. Calls, meetings, the Meet app and the calendar (verified 2026-11-28)

Checked live for TASK-0298 and TASK-0299 with OST Personal 1 and 2 in two
isolated headless Chrome profiles on linuxlt (teams.live.com, web client
`1415/26101516645`, Chrome's fake camera and microphone), with a network
and WebSocket capture that kept only token shapes. A 1:1 audio call from
Personal 1 to Personal 2, a meeting link made in Meet and joined by both
(Personal 2 by opening the link), and a meeting saved from the calendar's
New meeting form.

### 10.1 The calling socket

Next to the chat socket on `go.trouter.skype.com` (§9.3) the web client
opens a second Trouter socket for calls:
`GET https://go.trouter.teams.microsoft.com/?check=…&epid=<uuid>&tc={"cv":"2026.40.01.1","ua":"SkypeSpaces",…}`,
then `wss://go.trouter.teams.microsoft.com/v4/c?…&epid=<uuid>&dom=teams.live.com`,
and `user.authenticate` with `X-Skypetoken` only. `trouter.connected`
names an enterprise socket (`pub-ent-<region>-f.trouter.teams.microsoft.com`)
and the `communications.svc.cloud.microsoft` registrar, but the client
registers at `https://teams.microsoft.com/registrar/prod/v2/registrations`
(`X-Skypetoken`, `X-MS-Migration: True`; 202), twice:

```json
{"clientDescription":{"appId":"SkypeSpacesWeb","aesKey":"","languageId":"en-US","platform":"chrome","templateKey":"TFLSkypeSpacesWeb_2.0","platformUIVersion":"1415/26101516645"},"registrationId":"<epid>","nodeId":"","transports":{"TROUTER":[{"context":"TFL","path":"<surl>","ttl":3600}]}}
```

and the same as `<epid>-gg` with `languageId` and `productContext` empty
and the path without its trailing slash. OST's `v4/a` negotiate on the same
host with the consumer Skype token works too and gives the same kind of
socket.

### 10.2 A 1:1 call

- **Placing it:** `POST https://api.flightproxy.skype.com/api/v2/cpconv`
  with `X-Skypetoken`, `X-Microsoft-Skype-Chain-ID`, `-Message-ID`,
  `X-Microsoft-Skype-Client: SkypeSpaces/1415/<build>/…/TsCallingVersion=2026.40.01.8/…`
  and `MS-Teams-Ring: general` (no partition or region headers, no IC3
  bearer). The body is work Teams' single-shot call request with
  `conversationRequest.applicationType: "TFL"`, `groupChat: null` and
  `meetingInfo: null` (the chat is `19:uni01_…@thread.v2` but isn't named),
  `participants.to: [{id: "8:live:.cid.<callee>", participantId}]`,
  `callModalities: ["Audio"]`, every callback on the calling socket's
  `surl` (`…/callAgent/<endpoint id>/<hash>/call/…`), and a browser offer:
  `application/sdp-ngc-1.0`, BUNDLE of audio, two video lines and `x-data`
  (SCTP), DTLS (`a=setup:actpass`, a fingerprint), Opus first, ICE with a
  TURN relay candidate, `requiredFeatures: "nonByPass"`. The answer (201)
  is the conversation with links on
  `api.flightproxy.skype.com/api/v2/cp/conv-<region>-prod-aks.conv.skype.com/conv/<id>`.
- **Ringing:** the callee's calling socket gets a data frame at its own
  path (`/v4/f/<id>/`, from Skype-NotificationHub) with the body
  `{"evt":107,"gp":"<base64 JSON>"}`: a work-shaped `callNotification`
  (`from`, `to`, `links.attach|progress|reject` on
  `api.flightproxy.skype.com/api/v2/cp/cc-<region>-prod-aks.cc.skype.com/cc/v1/forked/…`,
  the caller's SDP, `fromApplicationType: "TFL"`) plus
  `conversationInvitation.conversationController`.
- **Answering:** `POST …/attach` (`attach.applicationType: "TFL"`, its
  `additionalActions` join with `conversationRequest.applicationType: "TFL"`),
  `POST …/incoming/…/progress` (`ringing`), then `POST …/accept` with
  `callAcceptance` and the browser answer: all with `X-Skypetoken`.
- **TURN:** `GET https://edge.skype.com/trap/tokens` (`X-Skypetoken`,
  `api-version: 2`) answers `{"tokens":[{"realm":"\"rtcmedia\"","username":…,"password":…}],"expires":604800}`.
- **Hanging up:** `POST …/conv/<id>/leave`; the other side gets `call/end`
  (`CallEndReasonLocalUserInitiated`) and `conversationEnd` (subCode 5002).

### 10.3 Meetings

- **Meet ▸ Create a meeting link** (title, "Create and copy link"):
  `POST https://teams.live.com/api/mt/beta/me/calendarEvents/privateMeeting/schedulingService/create`
  (`mtsvc.fl` bearer plus `x-skypetoken`) with
  `{"meetingType":"MeetNow","isStreamEnabled":false,"subject":…,"unhideChatThread":true}`
  → `value.links.join` = `https://teams.live.com/meet/<14 digits>?p=<18 chars>`,
  `groupContext.threadId` (`19:meeting_…@thread.v2`), `expiryTime` (60
  days), `meetingUrl` on `api.scheduler.teams.microsoft.com/teamsforlife/<id>`.
  The client then sets the meeting chat's `topic` and its `meeting`
  property (`{"subject",…,"meetingType":"MeetNow","meetingData":{"meetingCode","passcode"},"meetingJoinUrl","organizerId":"<cid hex>","tenantId":null,…}`)
  with `PUT {chatsvc}/v1/threads/<id>/properties?name=…`, as work Teams'
  Meet now does. The Meeting links list is those meeting chats (title,
  "Created just now", Join, Share link, More options, Edit meeting name).
- **Joining by link** (also opening `teams.live.com/meet/…` in a signed-in
  browser): no resolution call; `POST …/cpconv` with `meetingData`
  `{meetingCode, passcode, meetingUrl}`, `groupChat: null`,
  `meetingInfo: null`, `meetingPreferences: {"shouldResurrect":"resurrect"}`
  and no call, then the call to the conversation's controller. Others wait
  in the lobby until the organizer admits them.
- **In the meeting (free plan):** the bar is Mic, Camera, Share, React,
  Chat, People, Record, More and Leave; More has Timer, Captions, RTT,
  View, Join info and Settings (Accessibility settings, Hide me, Video
  effects and settings, Audio settings). No breakout rooms, Copilot, apps
  (Whiteboard), Notes or transcripts. **Record** opens Settings ▸ Plans and
  upgrades with a Microsoft 365 purchase dialog ("Record meetings, extend
  your calls, and more": Personal, Family, Premium).
- **Calendar ▸ Meet now** is work Teams' flyout ("Start a meeting now",
  Meeting name, Get a link to share, Start meeting). **New meeting** shows
  "With your current Teams plan, you get up to 60 minutes per meeting with
  up to 100 participants. Learn more", Title, attendees ("For non-Teams
  contacts, they will receive an email invite to the meeting with a join
  link."), date and times, All day, time zone, repeat, location, Meeting
  options and details. Save: `privateMeeting/schedulingService/create`
  with `{"isStreamEnabled":false,"meetingType":"Scheduled"}`, then
  `POST {mt}/v2.0/me/calendars/default/events?isOnlineMeeting=true&shouldDecryptData=false`
  with `{calendarEvent, schedulingServiceEvent}` (work Teams' body; the
  organizer attendee by `mri` only), then "Share meeting invite" with Copy.
- **Calendar view:** `GET {mt}/v2.0/me/calendars/default/calendarView?StartDate=…&EndDate=…&shouldDecryptData=false`
  → `{"value":[{objectId, startTime, endTime (with offset), subject,
  location, isOnlineMeeting, myResponseType, organizerName, showAs,
  bodyPreview, isOrganizer, isAppointment, skypeTeamsMeetingUrl
  (teams.live.com/meet/…), skypeTeamsDataObject.cid, iCalUID, …}]}`.

- **Event page:** `GET {mt}/v2.0/me/calendars/events/{objectId}` (the
  calendarView fields plus `attendees` [{type, name, address, mri, role}],
  `bodyContent`, `isReminderSet`, `reminderMinutesBeforeStart`). Save:
  `PUT …/events/{objectId}?isOnlineMeeting=false` with
  `{"updatedCalendarEvent": {subject, location, bodyContent, startTime,
  endTime, attendees, …, objectId, iCalUID, schedulingServiceUpdateUrl,
  skypeTeamsData}}` (204). Cancel meeting ("Do you want to cancel this
  meeting? This will cancel the meeting for all participants."):
  `DELETE …/events/{objectId}` (204).

### 10.4 Not seen

The 60-minute end of a free meeting and any warning before it (a meeting
with two people was not kept running for an hour), a group call from a
chat, video calls, and the Windows desktop client's calling dialect.

## 11. People app, profile cards, block list and invites (verified 2026-11-28)

Captured on teams.live.com (web client `1415/26101516645`) as OST Personal 1
and checked against Teams `26304.1207.5384.858` (OST Personal 2's window on
testpc2) for TASK-0295. All middle-tier calls carry the `mtsvc.fl` bearer
plus `x-skypetoken` (§7.7) and go through Teams free's web worker
(`x-ms-client-type: cdlworker`).

- **Contacts:** `GET {mt}/beta/contacts/buddylist?migrationRequested=true&federatedContactsSupported=true&ggEnabled=true`
  (`If-None-Match` with the last ETag; 304 when nothing changed). The
  answer is `{"value": [buddy group, …]}`; a group is `{id, displayName,
  groupType, buddies}` with `groupType` one of Custom, Favorites,
  SfBFavorites, Tagged, OtherContacts, **TflContacts** (your contacts) and
  TflBlocked, and a buddy is `{mri, displayName, email, phone, phones,
  companyName, jobTitle, isFederated, isIbBarred}`. The People app then
  reads names through `fetchShortProfile` and presence through UPS.
- **Delete** (People ▸ ··· ▸ Delete, "Delete this person?"): first
  `POST {mt}/beta/userSettings/blocklist/manage?ggEnabled=true`
  `{"add": [mri]}` (202 `{"value":{"status":"InProgress"}}`), then
  `POST {mt}/beta/contacts/buddylist/TflContacts/managebuddies?ggEnabled=true&skipBuddylistFetch=true`
  `{"delete": [{"mri": mri, "displayName": mri}]}`, which answers the group
  (`{"id":"TflContacts",…,"buddies":[…]}`) and also clears the block list
  entry (the dialog: "…will be removed from your blocked list").
- **Block** (People ▸ ··· ▸ Block, or the card's ··· ▸ Block contact, "Block
  this person?"): `blocklist/manage` `{"add": [mri]}`; **Unblock**
  (Settings ▸ People ▸ Blocked users): `{"remove": [mri]}`. The list:
  `GET {mt}/beta/userSettings/blocklist?ggEnabled=true` →
  `{"value": [mri, …]}`. Blocked users' **Delete** is the managebuddies
  delete alone.
- **Adding a contact:** there is no Add contact in Teams free's desktop
  People app; a person joins your contacts when you start a chat with
  them or accept their request (`managebuddies` `{"add":[{mri, displayName}]}`,
  TASK-0293). Opening an existing chat from New message adds nothing.
- **Invite to Teams:** `POST {mt}/beta/join/template` `{"messageType":"general"}`
  → `{"joinUrl":"https://teams.live.com/l/invite/<id>?v=g1","template":"Let's chat on Microsoft Teams! … %%joinurl%%","statusCode":"OK"}`;
  the People app copies the link (toast "Link copied to clipboard", or
  "Failed to copy the link").
- **Active now** lists the contacts that aren't off-network and whose
  presence isn't offline (contacts app bundle).
- **Off-network contacts** (synced from Outlook or a phone, not on Teams)
  show a single Invite button ("Invite via link") instead of Chat, Call and
  More. Neither test account has any, so this row wasn't seen live.
- **Sync settings:** `GET {mt}/beta/contacts/syncSettings` lists the synced
  sources (`{source: "Outlook"|"Skype", accountId, isSyncAllowed, …}`);
  removal is `beta/contacts/unsync/{source}?accountId=…` (bundle, not
  exercised).
- **Profile card** of a Teams free person: no service call beyond the
  short profile and presence. Header: picture with presence, name, Start
  a chat, Start a video call, Start an audio call, Find LinkedIn profile
  and More options (Report a concern, Block contact); tabs Overview,
  Contact, LinkedIn; the availability box, then "Contact information" with
  the shared email and phone, or "<name>'s contact details are hidden in
  Teams." (`emailsInfo[].visibility` "Private"). People's compact card
  (clicking a contact's picture) has the same content without tabs.

## 12. App shell, Settings and plans (verified 2026-11-28, TASK-0297)

Captured on teams.live.com (web client `1415/26101516645`, OST Personal 1,
the web worker's requests logged with tokens redacted) and checked against
Teams desktop `26304.1207.5384.858` on testpc2 (OST Personal 2, UIA).
Every setting changed for the capture was put back.

- **App bar.** Fixed: Chat `86fcd49b-…`, Meet `40472f6e-248f-4599-842c-ff3ed8f0ae34`,
  People `40472f6e-248f-4599-842c-ff3ed8f0ae35`, Copilot `43a6e7fb-bd10-4c0a-b02e-6a9c86ba272a`
  (a colour mark), Communities `3b95919f-59d8-4441-a975-2a8c2643c852`,
  Calendar `ef56c0de-…`, Activity `14d6962d-…`. No app menu on right-click,
  no Store or View more apps. At the bottom Upgrade
  (`data-testid=premium-upgrade-button`, ECS `core.isPremiumButtonInAppBarEnabled`)
  over the other-accounts hub.
- **Upgrade / purchase.** Upgrade opens Settings ▸ Plans and upgrades and
  auto-launches the in-app purchase dialog ("DIME Purchase",
  `https://offer.m365.cloud.microsoft/launchpad/v1/launchpad.metaos.html?partnerId=teamsmetaoswebconsumer&experienceId=persistent&…`)
  with Personal, Family and Premium offers; its "See all Microsoft 365
  plans" is `https://go.microsoft.com/fwlink/?LinkId=2360700` →
  `https://www.microsoft.com/microsoft-365/buy/compare-all-microsoft-365-products`.
  Nothing was bought.
- **Copilot (no plan).** Upsell page: `evergreen-assets/m365-subscription-upsell/upsell-{1,2,3}.png`,
  View all benefits opens the compare-all page in a new tab, Explore plans
  now opens the purchase dialog, Start using Copilot re-checks eligibility.
- **Communities.** Retirement banner (Learn more `fwlink 2375512`, Start
  chat), animation `evergreen-assets/communities/communities-empty-state-animation-new.webm`;
  Create your own and the templates open "Create a group chat"
  (`illustrations/webp/192/chat-people-l-standard-192x192.webp`).
- **Privacy.** Who can add you to groups / who can call you are chat-service
  user properties: `PUT {chatsvc}/v1/users/ME/properties?name=disableNonContactAddToGroup`
  `{"disableNonContactAddToGroup":"true"|"false"}` and the same for
  `disableNonContactCall` ("true" = Your contacts). Manage how people can
  find you reads `GET {mt}/beta/users/me/?skypeTeamsInfo=true&forceRefresh=true&ephemeralMeProfile=false&ggEnabled=true`
  (`searchableByProfile`, `emailsInfo[] {address, searchable, visibility}`);
  an address: `POST {mt}/beta/scd/searchability?ggEnabled=true`
  `{"msaEmails":[{"address":…,"searchable":bool}],"msaPhones":[]}` (turning
  off asks "Hide from search"); the name: `POST {mt}/beta/users/updateNameAndSkypeAvatar`
  `{"searchableByProfile":bool}` (from the worker bundle). Your profile:
  `PATCH {mt}/beta/users/me` `{"msaEmails":[{"address":…,"visibility":"Public"|"Private"}],"msaPhones":[]}`
  (hiding asks "Hiding your email"). Experiences that analyze your content:
  `GET/POST {mt}/beta/users/me/analyzecontentsettings {"isAnalyzeContentSettingsEnabled":bool}`.
- **People.** Blocked users `GET {mt}/beta/userSettings/blocklist?ggEnabled=true`,
  unblock `POST …/blocklist/manage?ggEnabled=true {"remove":[mri]}` (bundle);
  Synced contacts `GET {mt}/beta/contacts/syncSettings` (Outlook and the
  retired Skype source).
- **Teams Insider.** `GET {mt}/beta/users/insiders/status` (`isInsider`),
  Join `POST {mt}/beta/users/insiders`, Leave `DELETE` (bundle; not joined).
- **ECS.** Teams desktop's app id works for a personal account:
  `GET config.teams.microsoft.com/config/v1/MicrosoftTeams/49_1.0.0.0?environment=life&…&id=<oid>&aaduserid=<oid>&tenantId=9188040d-6c67-4c5b-b112-36a304b66dad&…&agents=TflNorthstar,TeamsBuilds,Segmentation&ECSCanary=1`
  (no auth, no licence filters) answers a desktop-flavoured `TflNorthstar`
  (for example `monetization.enableRefreshPlansAndUpgrades`,
  `communities.disableCommunitiesCreation`, `ai.enableCopilotChatConsumerApp`).
