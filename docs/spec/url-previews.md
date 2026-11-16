# Link previews (URL previews)

Teams' link previews, read from its bundles and measured on winpc on 2026-11-15 ("OST TEST 158/159"). OST's engine side is `api::url_preview`; compose is in `ComposeBox.qml` and the card is `UrlPreviewCard.qml`.

## Compose
- **AutoLink.** A web address becomes a link when Space or Enter follows it, or when the whole pasted text is one. The rules:
  - the word must be longer than 5 characters;
  - it must start with `http://`, `https://` or `www.`;
  - trailing punctuation and an unmatched closing bracket stay outside the link;
  - `www.` addresses get `http://`.
- **Which link.** Only the first link in the message gets a preview, 125 ms after the text changes. These links get none:
  - Teams links to messages, channels, chats and meeting recaps;
  - `mailto:`;
  - SharePoint and OneDrive file links;
  - links in notes to self, forwarded messages and edits.
- **Service.** The request is `GET {regionGtm urlpV2}/v1/url/richInfo?url=…` (Teams' default), falling back to `v1/url/info`. OST sends the skype token, which Teams also falls back to.
  - A preview counts when it has two of picture, title and description.
- **The card** (`url-preview-card`) sits 11.4 px in and 11 px under the text, and its X removes the preview.
  - It stays removed for that link and is sent with `previewenabled:false`.
  - A different first link fetches again.
- **Send-time fallback.** If the message is sent before a preview arrives, it is fetched as the message goes, within 3 s. This is Teams' URLPreviewSerializer with `postSendTimeoutInMs` 3000.

## Wire format
`properties.links` is a JSON string. No HTML is added to the message body.

```json
[{"@type":"http://schema.skype.com/HyperLink","itemid":"0","url":"https://www.rust-lang.org/","previewenabled":true,
  "preview":{"previewurl":"https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/image/Thumbnail?url=…","previewmeta":{"width":…,"height":…},
  "title":"…","description":"…"}}]
```

- `previewmeta` comes only from the `info` path.
- The favicon is never sent.
- The picture is already behind Teams' URL proxy. OST downloads it with the skype token (`remote_image_file`), and only from Teams' proxy and media hosts.

## Messages
- Teams fetches nothing for received links. It shows the sender's preview only when all of these hold:
  - it is enabled;
  - it is valid;
  - its URL is the message body's first link.
- The card is 460 × 96 and sits 6 px under the text, and the bubble ends 14.6 px under the card. The whole card opens the link.
- The sender sees Remove URL Preview. It sends `PUT {chat}/v1/users/ME/conversations/{conv}/messages/{id}/properties?name=links` with body `{"links": "<the same list, previewenabled false>"}`.

## Privacy and policy
No previews are fetched, sent or shown when either of these holds:
- Optional connected experiences is off (user property `controllerConnectedServicesEnabled` = "false");
- your messaging policy has `allowUrlPreviews` false (read from `effectivePolicies`).

## App link cards (app link unfurling)
Measured on winpc on 2026-11-16 ("OST TEST 168a/168b") and read from Teams' AppBasedLinkService and app-based-link helpers. OST's engine side is `api::link_unfurl`; the card is `AppLinkCard.qml`.

- **Which app.** An app's message extension lists the links it unfurls: the catalog's `inputExtensions[0].messageHandlers[0].value.domains` (Teams' GraphQL calls them `messageExtensions`).
  - Teams looks among your installed apps first, then among all apps. An app you haven't installed unfurls only when it allows anonymous use: `supportsAnonymousAccess`, or ECS `extensibility.anonymousAppBasedLinkApps`. The commercial default list is Wikipedia Search (`25492237-…`) and YouTube; `enableAnonymousAppBasedLink` is on by default.
  - An app that matches but isn't installed and isn't anonymous gives Teams' install prompt; OST then keeps the plain preview.
  - When an app matches, Teams fetches no URL preview (no `richInfo` request).
- **Domains.** A domain without "/" matches `^https://{domain}((/|\?).*)?$`, case-insensitive, with `*` for one label (`[^/^.]+`). A domain with "/" is a pattern (`*` → `(.*)`) found anywhere in the URL. Domains with a `*` in their last two labels, or with one label, are ignored.
  - So `*.wikipedia.org` matches `https://en.wikipedia.org/wiki/Lighthouse`; GitHub's app takes `github.com` but not `www.github.com`, which keeps the plain preview.
- **Asking the app.** `POST {chat service}/v1/agents/28:{bot}/invoke` with `{"name":"composeExtension/anonymousQueryLink","appId":"…","value":{"url":"…"},"imdisplayname":"…","userAadToken":"…","conversation":{"id":"19:…"}}`. An installed app gets `composeExtension/queryLink`.
  - The reply is `{composeExtension: {attachments: [{contentType, content, preview}]}}`. The first attachment is the card; its `preview` (or the card itself, for hero and thumbnail cards) is the collapsed form.
  - Wikipedia's card is a thumbnail card whose title is a link (`<a href=…>`), with `<span>`s in the text.
  - `type` `auth` or `config` asks for sign-in (GitHub's "Show Preview"). OST doesn't do the sign-in yet and keeps the plain preview.
- **The card in compose** (`app-based-link-preview-card`): 16.67 in (padding 0 16 8), 16.4 under the text.
  - The frame is 452 wide, white, with a 0.67 px #E0E0E0 border, radius 4 and padding 16.67.
  - The header is 24 tall: the app's icon (24, round, on #FAFAFA) and its name (12/600, #242424) 12 to the right. Collapse preview (ArrowMinimize 20) sits 10 left of Remove URL Preview (Dismiss 20) at the end.
  - The app's card is 12 under the header. A thumbnail card shows its 100 × 100 picture 8 down, then the title (a 16 px #4F52B2 link on a 22 line), then the text 8 under it (12 px #424242 on a 15 line).
  - For an app used without installing it, a footer follows. It is 10 down, with a 0.67 px line, then "By using {app}, you agree to the privacy policy, terms of use, and permissions." (12 on a 17.14 line, links #4F52B2) and a settings button (32 × 31.33). The settings button opens Settings ▸ Privacy.
- **Collapse preview** turns the card into the plain preview card (url-preview-card, 460 × 96) with Expand preview (ArrowMaximize 20) 32 left of the X. Collapsed, it is sent as a plain preview: `properties.links` with `previewenabled:true` and the app's preview, `cards` `[]`, and no span (OST TEST 168b).
- **Sent as a card** (OST TEST 168a):
  - The body ends with `<span class="inline-compose-card" itemid="app-preview-card-ps{32 hex}" itemscope itemtype="http://schema.skype.com/InputExtension"><span content="{same id}" itemprop="cardId"></span></span>`.
  - `properties.cards` is `[{"appIcon","appId","appName","cardClientId":"app-preview-card-ps…","contentType","content"}]`.
  - `properties.links` carries the preview with `previewenabled:false` (the title, the text without tags, and the picture).
- **In messages**, a card whose `cardClientId` starts with `app-preview-card` shows the same frame and header without the buttons and footer. It sits 8 under the text and 15.67 in, and the bubble ends 8.67 under it.
- **Verified live (2026-11-16):** Teams' OST TEST 168a card renders in OST. OST's OST TEST 168c, sent with the card from OST, renders as the Wikipedia Search card in Teams on winpc.
- **The index.** The middle tier's catalog takes OST tens of seconds to page through, so OST keeps the link apps (about 170) in `~/.cache/ost/link-apps.json`. It loads the file at sign-in and rebuilds it once a day.
