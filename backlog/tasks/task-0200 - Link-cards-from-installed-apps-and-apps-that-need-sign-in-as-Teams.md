---
id: TASK-0200
title: Link cards from installed apps and apps that need sign-in, as Teams
status: To Do
assignee: []
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-21T01:26:00Z'
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
- [ ] #1 A link handled by an installed app shows its card via queryLink, as Teams
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
<!-- SECTION:NOTES:END -->
