# App details (About) and Share app

Teams' app details dialog (`app-details-northstar-dialog`) and its Share form (`shareToTeams`).

- **Where they open:**
  - an app header's ··· menu (About, Share app);
  - a shared app's card in a chat (View details, the share button);
  - `teams.microsoft.com/l/app/{id}` links;
  - the Store.
- **Sources:**
  - measured on winpc 2026-11-09 with Teams 26276.513 (dumps in the session scratchpad `ab/`);
  - Teams' bundles: `platform-modal` (the dialog), the web worker's `inner_d` chunk (More like this), module 523993/96201 (permissions), and module 61199 (the shared card);
  - a read-only probe of every endpoint.
- **OST:**
  - `teams_cli::api::app_details` (data, derivations, the share message);
  - `AppDetailsDialog.qml`, `ShareForm.qml`, `AppCardFooter.qml`;
  - the `Icon` element and `roundedCorners` images in `AdaptiveCard.qml`.

## 1. Data

| What | Request | Notes |
|---|---|---|
| Definition | `POST {middleTier}/beta/users/apps/batchedDefinitions` with body `["<appId>"]` | Raw manifest fields plus `state`, `categories`, `supportedHubs`, `supportedLanguages`. |
| Rating | `GET {suggestions}/api/v2/apps/ratings` (a list of every rated app, matched by `id`) | `{average, count, breakdown{oneStar..fiveStars}}`. The desktop worker reads this; `GET {middleTier}/beta/users/apps/{id}/rating` answers 500. The shown average is `+average.toFixed(1)`. |
| Installs in the last month | `GET {suggestions}/odata/v1/apps/{id}?$expand=usage` | `usage.installCount`; 404 means 0. |
| Reviews | `GET {suggestions}/odata/v1/apps/{id}/reviews?$filter=…&$orderby=…&$count=true`, header `Prefer: odata.maxpagesize=N` | `@odata.count` is the stats row's "N reviews" (shown above 1). The next page is `@odata.nextLink`. |
| More like this | `GET {middleTier}/beta/users/apps/definitionsv2` (paged with `x-ms-continuation`, about 3,900 apps) and `POST {suggestions}/api/v1/users/apps/suggestions` with body `[]` | See §3. |
| Write a review | `POST {suggestions}/odata/v1/apps/{id}/reviews` with `{rating, title?, content?, anonymous}` | |
| Report review | `POST {suggestions}/odata/v1/apps/{id}/reviews/{rid}/reports` with `{content, reason}` | `reason` is OffensiveContent, SpamAndAdvertising, InvalidReview or Other. |

- `{suggestions}` is region GTM `appsSuggestionService` with its trailing `/api` removed. Its token audience is `https://prod.appsuggestions.teams.core.microsoft`.
- Requests send `clientInfo: os=…; lcid=en-us; …; clientName=skypeteams; …`.
- Review filter (no filter chosen): `length(Content) gt 0 or length(Title) gt 0 or author/me eq true`.
- Review order:
  - Most recent: `author/me desc, updatedAt desc`;
  - Highest rating: `rating desc, content desc`;
  - Lowest rating: `rating asc, content desc`.
- Review dates use date-fns `formatDistanceStrict` with a suffix ("2 days ago", "1 year ago").

## 2. Derived from the definition

- **Works in:** `supportedHubs` named (TEAMS Teams, COPILOT Copilot, OUTLOOK, OFFICE, WORD, EXCEL, POWERPOINT "Power Point"), joined as an English list; "Teams" when empty.
- **Pricing** (stats row / Details):
  - "Free" / "Free to add and use", unless there is a subscription offer ("Subscription" / "Plans available").
  - A declarative copilot shows "Usage" for Consumption and "License" for Licensed.
- **Capabilities in Teams**, in this order:

  | Row | Shown when | Icon |
  |---|---|---|
  | Agent | copilot | Sparkle |
  | Bot | bots | Bot |
  | Mail and Calendar extensions | extensions | TabDesktop |
  | Messaging | messageExtensions | Chat |
  | Notifications | connectors | Alert |
  | Personal app | a staticTab with scope Personal | Person |
  | Tab | galleryTabs, or a staticTab with scope Team | TabDesktop |

- **Permissions:** keys come from module 523993:
  - base keys by capability;
  - Team / GroupChat key sets by supported scope;
  - RSC names `Resource.Action.Scope` → `app_details_permission_<resource>_<actions>_<scope>`, joined when Teams has a string for the joined key;
  - device permissions for apps without tabs.

  The config `permissionCategoriesMap` files each key under:
  - **Permission to read and access:** Information related to you (Person), Information in chats, channels, and meetings (PeopleTeam), and Other read access (Teams' logo; OST's own).
  - **Permission to perform these actions:** Send and receive messages and notifications (AlertBadge), Content and settings (Settings), Manage media and devices (Video), and Other (CursorClick).

  The sentences (`src/api/app_permission_strings.json`) come from Teams' en-us `extensibility` strings.
- **Languages:** codes become native names (`src/api/app_locales.json`, Teams' module 401656).
  - A code with a region matches exactly.
  - A bare language takes the first entry of that language, with "(…)" dropped ("fr" → "Français").
  - Collapsed, the list shows your language (else the first) + " and" with a "{n} more" link; expanded, the full list and "See less".

## 3. More like this (the worker's `appsBySameCategory`)

1. The category is the app's first category that isn't "Microsoft".
2. The candidates come from the catalog, minus:
   - apps the user has as InstalledAndPermanent or InstalledAndDeprecated;
   - apps with custom bots;
   - uploaded apps without a tenant.
3. Keep candidates that share any category with the app, or its tenant or developer.
4. Order them by the suggestions ranking. Unranked apps come after, in catalog order.
5. Leave out the first six apps by the same developer (or tenant), then take the first six in the category.

For Help this gives Survey Agent (Preview), Walkie Talkie, Customer Connect, Doorbell, UserLike and Aircall Notifications, as Teams shows. Opening one adds a Back button.

## 4. Layout (899 x 564, radius 8)

- **Hero:**
  - the tile is 64 px at (56, 29) and drawn as a squircle (`corner-shape: superellipse(2)`, radius 50%);
  - the name is 20/28.57 semibold at (142, 33); the developer is 12/17 NeutralForeground3;
  - Open/Add (96 x 32) and share sit 74 under the tile top. Add shows for apps you don't have; Open shows for apps you have, when the dialog was opened from a chat or the Store (not from the app's own header).
- **Rule:** a #F0F0F0 line at 148 (180 with buttons).
- **Stats row:** 201 px columns with 1 x 24 dividers. Each column has a 14/20 semibold value and 10/14 semibold lines (NeutralForeground3). Tapping the rating scrolls to Reviews.
- **Descriptions:** the short description (14/36 semibold), then the long one (14/20 NeutralForeground2).
- **Capabilities card:** #FAFAFA, radius 12; header 62 tall; rows of a 20 px icon, a 14/20 semibold title and a 12/20 description.
- **Reviews** (only with ratings):
  - "Powered by Microsoft AppSource | View Terms";
  - the summary: a 20 px star, the average at 28/36, "N ratings" and "N installs in the last month" (10/14), and 5..1 bars (157 x 8, brand on #E8EBFA, radius 4);
  - the two highest reviews, then Write a review and See all reviews (outline, 31 tall).
- **Permissions overview:** "View detailed permissions" (brand link). Two 376 px cards, 20 apart: a 16/24 semibold heading with a chevron, a divider, and a row per group (20 px icon + 14/20 title).
- **Details:** Created by (link), Version, Pricing, Languages; three 244 px columns.
- **More like this:** 378 x 84 cards (radius 8) in two columns; tile 52; name 16/22 semibold; description 12/16, one line.
- **Footer** (fixed, 60 tall): "By using {app}, you agree to the privacy policy, terms of use, and permissions." "permissions" scrolls to the overview.
- **Sticky header:** 80 tall, shown once the hero scrolls away. It has a 40 px tile, the 16/22 name, Open/Add at 707, close at 811, and a 2 px brand scroll-progress line at 77.
- **Views** share a header (Back at 14, tile 40, name 16/22, the view 12/16):
  - **All reviews:** summary on the left (bars 221). "N reviews" 14/20 bold; Sort (Most recent / Highest rating / Lowest rating with calendar, star, star icons). Reviews sit 36 apart, each with title, stars, | author | date, content and "Report review" (flag). Pages load as you reach the end. The footer reads "Powered by …".
  - **Permissions:** a #FAFAFA card per category. The heading is 18/26 semibold, then a divider. Groups have a 16 px icon and a 16/24 semibold title, with items at 14/24.
  - **Write a review:**
    - "Rating *" with five 28 px stars;
    - Title (32 tall) and Description (200 tall) on #F5F5F5;
    - "Post my review publicly as {sign-in name}." with "(If unchecked, the review will be posted as Anonymous.)";
    - Submit, which is disabled until a rating is chosen.
  - **Report review:** "Provide a reason for reporting this review"; the radios Offensive content (chosen), Spam or advertising, Invalid review and Other; the comment box under the chosen reason; Submit.
- **App header menu:** Reload app, a divider, About (Info), Share app (Share).

## 5. Share app

- **The link:** `https://teams.microsoft.com/l/app/{id}?source=app-header-share-entrypoint`.
- **The form** (600 wide; `ShareForm.qml` has the measurements):
  - "Share to" with "Type the name of a person, group, or channel"; suggestions are grouped under People, Chats and Channels;
  - "Say something about this", prefilled "Take a look at this app.", then the link and the card under an "App" header;
  - Copy link ("Link copied") and Share ("Sharing");
  - then "Your message has been shared." with View and Done;
  - on failure: "Something went wrong while trying to share to Teams."
- **The message** (as Teams posted it in OST group test):
  - `RichText/Html` content: `<p>{note}<br><br><a href=LINK rel="noreferrer noopener" title=LINK target="_blank">{name}</a></p>`, then `<span itemid="{cardClientId}" itemscope="" itemtype="http://schema.skype.com/InputExtension"><span itemprop="cardId"></span></span>`;
  - `properties.cards`: `[{appId: "08648EF4-F8B6-45DA-AB44-74F21AABD840", cardClientId: "app-preview-card-ps{uuid}app-store-link-preview", appName, sourceType: "APP_HEADER_SHARE_ENTRYPOINT", contentType: "application/vnd.microsoft.card.adaptive", content}]`;
  - `properties.links`: `[{"@type": "http://schema.skype.com/HyperLink", itemid: "0", url, previewenabled: false, preview: {}}]`;
  - the card (version 1.5) holds:
    - Image (Small, roundedCorners) with the bolder Medium name and the subtle Small developer;
    - the short description (Small, maxLines 2);
    - a row of Icon Star (xxSmall, filled, accent), the bolder average and "(N ratings)";
    - `selectAction` Action.OpenUrl to the link with the app's id.
- **In a chat**, Teams draws the card 16 from the top and adds, under it:
  - "Privacy | Terms of use | Permissions" (10/14, 1 x 10 dividers 8 either side);
  - Open (brand, 60 wide), View details (outline) and a share button.

  OST matches this in `AppCardFooter.qml`.
- **Adaptive Card `Icon`** (Teams' renderer):
  - Fluent icons by name from `https://res-1.cdn.office.net/assets/fluentui-react-icons/2.0.226/{Name}/{Name}.json`;
  - sizes xxSmall 16, xSmall 20, Small 24, Standard 32, Medium 48, Large 56, xLarge 72, xxLarge 96;
  - the nearest drawn size is used.
