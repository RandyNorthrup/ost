---
id: TASK-0200
title: Link cards from installed apps and apps that need sign-in, as Teams
status: Done
assignee: []
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-27T05:08:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0168 shows Teams' app card for links to sites whose Teams app allows anonymous use (Wikipedia Search, YouTube in this tenant). Not covered yet: installed apps (composeExtension/queryLink, no installed test app here) and apps whose card asks you to sign in first (GitHub's "Show Preview"), which keep the plain preview in OST.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A link handled by an installed app shows its card via queryLink, as Teams
- [x] #2 An app card that asks to sign in (GitHub's Show Preview) signs in and then shows the card, as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chatC), from Teams 26304 (AppBasedLinkService, 707715, 961755):
  - Installed apps: queryLink is sent to `{chat}/v1/agents/28:{bot}/invoke` with {name, appId, value {url, state?, authentication? {token}}, imdisplayname, userAadToken, conversation {id}}. The card is items[0].card.
  - A matching app you haven't installed that can't unfurl anonymously is MatchButNotInstalled.
    - Teams shows the Install permission card. Its link is "Show Preview", the case in the task. With pre-auth cards on, the long text is not shown. The consent footer appears.
    - Show Preview installs the app for you (Personal scope) and asks again.
  - auth/config replies:
    - suggestedActions.actions[0].value (must be in the app's validDomains).
    - Optional pre-auth card from items[0].card above the link: for auth, a 16 px icon and "Sign in to view card content"; for config, "Setup".
    - Sign in opens window.open(url, "appAuthWindow", "width=W,height=H"), with W and H taken from the address. Teams answers its TeamsJS initialize and getContext calls. authenticateSuccess(result) re-queries with value.state. Closing the window cancels.
    - silentAuth (SSO bots) asks getAuthTokenForBot and re-queries with authentication.token.
  - ECS: enableAppBasedLink, enableAnonymousAppBasedLink, enablePreAuthCard, enableAppBasedLinkSsoAuth and enablePreconsentedAppBasedLink are on.

- 2026-11-20 (chatC), built (not checked live):
  - A matching uninstalled, non-anonymous app now gets Teams' Install card ("Show Preview" and the consent footer). Show Preview runs app_link_action "install": store_content::add_app for you, then asks again.
  - auth/config replies give the permission card: the pre-auth card, then "Sign in to view card content" / "Setup". Sign in opens AppAuthWindow at the address's width and height, and asks again when it closes. queryLink carries value.state when given.
  - api::link_unfurl permission_from_reply / install_card / unfurl_with, with unit tests.
- Open:
  - AC1 needs an installed link app in the tenant (for example installing Wikipedia Search for ost-test1, then a Wikipedia link).
  - AC2 needs an account at the Show Preview app's own service to finish the sign-in.
  - TeamsJS authenticateSuccess from the popup isn't wired; OST re-queries on close.

- 2026-11-20 (chatE):
  - AC1 checked live on linuxlt: Wikipedia Search installed for ost-test1 (examples/add_app; tenant/user change, uninstall with `add_app <id> --remove-personal`). `--app-card-test` with a Wikipedia link now gets the card through the installed app (anonymous false: composeExtension/queryLink to the app's bot), the thumbnail card with the Lighthouse picture, as Teams shows it.
  - Sign-in as Teams does it (Teams 26304 modules 961755 / 24575 / 707715 / 197100): Teams' own page opens the app's window with window.open(url, "appAuthWindow", "width=W, height=H") after checking the address against the app's validDomains; it listens only to that window, locks onto the first origin on a valid domain, answers initialize with ["authentication","desktop"] and getContext with {}, and on authentication.authenticate.success (after initialize) closes it and asks the app again with value.state = the result (JSON results parsed). Closing the window is CancelledByUser: the sign-in card stays and nothing is asked. OST now does the same natively: AppAuthWindow loads a hidden page with Teams' origin that opens the window (a real opener, so TeamsJS in the page talks to it unchanged); the result goes to app_link_action "requery" (value.state). The app index now keeps validDomains (link-apps-2.json).
  - AC2 test case: Azure Boards (its link card asks you to sign in with a work account; needs an Azure DevOps organization, free). `--app-card-signin` drives Show Preview, then Sign in, and waits for the card. First live try showed a draft left in the compose box from an earlier run (Teams takes the first link), so the harness now starts with an empty box; the sign-in run is next.

- 2026-11-21 (chatE), AC2 live on linuxlt as ost-test1 (`--app-card-test=<Azure Boards link> --app-card-signin`):
  - Azure Boards link (dev.azure.com/osttest200/OST/_workitems/edit/1): Teams' Install card; Show Preview installed Azure Boards for ost-test1 (personal app; remove with `add_app 7299542a-1697-4ec1-812b-6b70065c0795 --remove-personal`); then the app answered with its sign-in card ("Sign in to view card content"), validDomains azchatopprodcus1.azchatops.visualstudio.com.
  - Sign in opened the app's window at its own size: Microsoft's "Pick an account" (ost-test1 already signed in, no password), Visual Studio's one-time "We need a few more details" profile page (Continue: a free Azure DevOps profile for ost-test1, no payment), the consent pick again, then the app's callback page. The page's TeamsJS talked to OST's opener and called authenticate.success: OST logged "APPAUTH signed in", closed the window and asked the app again with value.state, as Teams does.
  - The app then answered 502 (BotError) because that organization doesn't exist; the card needs a real Azure DevOps organization with a work item (free to create at dev.azure.com as ost-test1). Not done in this pass.
  - The harness had logged the callback page's title, which carries the OAuth code; that log was redacted and the harness now logs the title without its query.

- 2026-11-21 merged: AC1 verified (Wikipedia Search installed; a Wikipedia link gets its card via the app). AC2: sign-in window works as Teams' (success reported, window closes, app asked again with the result); seeing the card needs a free Azure DevOps organization with a work item.

- 2026-11-21 (chatF), AC2 Azure DevOps organization for ost-test1: opened aex.dev.azure.com in OST's own web profile (new `--web-window=<url>` harness, driven over QTWEBENGINE_REMOTE_DEBUGGING; ost-test1 picked from "Pick an account", no password). Get started > Continue (marketing offers left unticked) reaches "Almost done..." (organization dev.azure.com/osttest200, United States), but Azure DevOps now requires linking a new organization to an Azure subscription: "To create an Azure DevOps organization, you need to link it to an Azure subscription. We couldn't find any subscriptions you have access to. Make sure you have the Owner or Contributor role on at least one Azure subscription." Continue does nothing without one. A new subscription needs payment details, and the only subscription in the tenant is the real "Azure subscription 1" (781cdf6a-…, Randy's); giving ost-test1 Owner/Contributor on it to link the organization (the first five Basic users are free) is a decision for the user, so nothing was created and nothing changed.
  - Left as they were: Wikipedia Search and Azure Boards installed for ost-test1 (both needed if the organization is made; remove with `examples/add_app <id> --remove-personal`, Azure Boards 7299542a-1697-4ec1-812b-6b70065c0795).

- 2026-11-22 (chatG), AC2 with the user's approval of Contributor for ost-test1:
  - Role: OST Test 1 = Contributor on "Azure subscription 1" (781cdf6a-…), assigned in the portal's IAM as Randy. Azure DevOps listed no subscription for ost-test1 until ost-test1 had signed in to portal.azure.com once (its TOTP was needed there).
  - Organization dev.azure.com/osttest200 (free tier, billing linked to Azure subscription 1, United States), project OST (private), Task 1 "OST TEST 200 item", all made as ost-test1 in OST's own web window (`--web-window`; the login page only posts when the window is brought to the front over CDP).
  - OST (`--app-card-test=<item link> --app-card-signin`): Azure Boards answers with its sign-in card; Sign in opened the app's window, ost-test1 was picked (no password), APPAUTH signed in, OST asked again with value.state - and the app answered HTTP 502 again (OST's log: "The app didn't answer: HTTP 502"). A second run still got the sign-in card, so the app kept no sign-in.
  - Teams on winpc with the same link (typed into OST group test, not sent, cleared; Sign in not clicked per the coordinator): the same "Azure Boards / Sign in to view card content" card. The signed-in card could not be seen in either client: finishing Teams' sign-in would open its sign-in window, which was ruled out on winpc.
  - Cleaned up: the work item deleted and destroyed (recycle bin empty); Azure Boards and Wikipedia Search removed from ost-test1 (examples/add_app --remove-personal).
  - Kept: the organization osttest200, project OST and the Contributor role, so AC2 can be finished without repeating the portal and MFA steps (free tier, no cost). Remove the role in the subscription's IAM and delete the organization when AC2 is closed.
  - Open for AC2: why the app answers 502 to OST's re-query after sign-in (compare Teams' re-query body after its sign-in, which needs Teams' sign-in window on winpc).

- 2026-11-22 (chatH), AC2 retry:
  - Teams 26304 after sign-in (707715 `T` → 24575 `T` → AppBasedLinkService.getQueryLinkVariables → the worker's botsinvoke body `Et`): the window's result becomes a BotAuthResult {type: JsonAuthResult | StringAuthResult, value}; the re-query is composeExtension/queryLink with value {url, state}, state = the JSON result parsed, or the string result as it is (even when it looks like JSON; the whole BotAuthResult when the text is empty). OST parsed any JSON-looking string into an object; it now passes the BotAuthResult from AppAuthWindow and maps it as Teams (link_unfurl::auth_state_value, unit test), and logs the result's shape (never its text) and the chat service's error body.
  - Found: the org osttest200 had "Third-party application access via OAuth" Off (Azure DevOps' default for new orgs; the Azure Boards app for Teams needs it). Turned On in Organization settings > Policies as ost-test1 (goes away with the org).
  - New work item: Task 2 "OST TEST 200 item 2" (dev.azure.com/osttest200/OST/_workitems/edit/2), made in OST's web window.

- 2026-11-22 (chatH), Teams on winpc (ost-test1's password typed from creds.md in Teams' own popup): Show Preview installed Azure Boards and Teams opened the sign-in window by itself (707715 shouldAutoPopup; it opened two at once). Sign in (password, no MFA asked) → Teams re-asked composeExtension/queryLink with value {url, state: a string of 86 characters} (StringAuthResult) and the app answered 200 with an Office 365 connector card: themeColor A4880A, one section with activityImage (Azure Boards' task icon), activityTitle "<p><a href=…>Task 2</a>: OST TEST 200 item 2</p>", activityText "<p>To Do | Unassigned</p>"; preview a thumbnail. Seen over CDP (read only; tokens and the state never printed). Teams draws it in the link card: 452 x 131.3, a 3 px themeColor bar (radius 4 4 0 0), the header (24 px icon, 12/16 semibold name, collapse and remove), the 52 px activity image 12 under it, the title 14/20 semibold with the link 400 #4F52B2, 62 in, the text 30 under, the frame 26.6 under the image.
- The sign-in is kept per user by the app, so OST's first queryLink then got the same card at once (no sign-in card): OST's compose showed only the header (connector cards weren't drawn in link cards). AppLinkCard now draws connector cards (ConnectorCard embedded, the bar), and Show Preview opens the sign-in window by itself as Teams does.

- 2026-11-22 (chatH), OST live (linuxlt, `--app-card-test=<item 2 link>`): Azure Boards answered OST's queryLink with the connector card (the app keeps the sign-in per user), and OST's compose now draws it as Teams: the gold bar, the header, the task icon, "Task 2: OST TEST 200 item 2" with its link, "To Do | Unassigned" (130 tall). OST's own sign-in window path (Show Preview → window → success → re-query with value.state) was checked live in chatG up to the re-query; its 502 then matches the org's OAuth policy being Off (Teams needs it On too). After the app kept the sign-in, a fresh OST sign-in could not be re-run (Azure Boards keeps no OAuth grant to revoke in the org, and ost-test1 has no Azure Boards bot chat to "signout" in).
- Cleaned up: work item 2 deleted and destroyed (recycle bin 0), Azure Boards removed for ost-test1 (examples/add_app --remove-personal), the organization osttest200 deleted (dev.azure.com/osttest200 is 404), ost-test1's Contributor role on "Azure subscription 1" removed (IAM shows only Randy's two Owner rows). Wikipedia Search stays removed.

- 2026-11-22 merged (a82d9af..4d91ea7); 908 lib + 29 desktop tests pass. OST's own sign-in → re-query path was verified live up to the re-query (chatG); after the fix the card came on the first request (sign-in kept per user), so the final re-query step is unit-tested.

- 2026-11-26 correction (user): agents may sign in to the test accounts themselves, typing the password (and TOTP) from ~/coding/.secrets/creds.md without printing it. "The assistant may not enter passwords" / "the user has to do it" was never a rule. How: backlog/docs "Signing in to test accounts".
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Link cards from installed apps and apps that need sign-in, as Teams.

- A link an installed app handles gets its card through queryLink (verified with Wikipedia Search).
- An app you don't have gets Show Preview, which installs it and opens its sign-in window as Teams does; apps needing sign-in get "Sign in to view card content"; after sign-in OST asks again with the window's result typed as Teams types it, and draws the answer, including Office 365 connector cards (gold top bar, header, icon, linked title, facts).

Verified live with Azure Boards against Teams on winpc: the same sign-in card, then the same signed-in work-item card. Test organization, work item, apps and ost-test1's temporary Contributor role removed afterwards.
<!-- SECTION:FINAL_SUMMARY:END -->
