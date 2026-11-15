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

## Not built
App link unfurling (for example GitHub's and Wikipedia's Teams apps) is out of scope for this task. Those links get the app's card in Teams.
