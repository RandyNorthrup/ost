---
id: TASK-0200
title: Link cards from installed apps and apps that need sign-in, as Teams
status: In Progress
assignee: []
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-21T15:46:00Z'
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
- [ ] #2 An app card that asks to sign in (GitHub's Show Preview) signs in and then shows the card, as Teams
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
<!-- SECTION:NOTES:END -->
