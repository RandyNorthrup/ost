# Custom (organisation) emoji — Teams desktop behaviour (spec)

Source: the Teams client's own bundles (same build as `messages-and-composer.md`),
main-thread chunks plus the data-layer web workers (`inner_b` emoji manager,
`inner_c` workflows, `inner_d` GraphQL resolvers, `inner_services_i` HTTP
services). Module ids are given so this can be re-checked. Strings are en-us,
resolved from the hashed keys (`k` + base36(poly131(`"ns:key"`) mod 2^40)).
Prod config values come from `config-prod-*.js`. Nothing here was exercised
live; items marked **unconfirmed** are read from code only, or are inferred.

---

## Components (module index)
| area | module(s) |
|---|---|
| Id helpers, image URL builder | 280767 (`eO` shortcut, `Pp` documentId, `SY` isCustom, `qz` name rule, `JT`/`o8` URL) |
| Constants (category id, fallback thumbnail, grid columns) | 327053 (`OW`="customEmoji", `I_` thumbnail path), 446619 (`Cm`="CustomEmoji") |
| Custom emoji image components | 133984 (`D`, URL + blob), 476859 (`L`, `<img>`), 978939 (placeholder), 336850 (renderer switch) |
| Compose insert / send serializer | 522295 (`a2` → `x`), async-entry `CustomEmojiSerializer` (`We`), 696152 `CustomEmojiHandler`, 721466 `CustomEmojiComposeDeserializer` |
| Message render | 721466 `CustomEmojiDeserializer` (14618), container 756240 (443282) |
| Picker grid, categories, entry points | 599484 (`Ge`, `ge`, `Nn`), 869839 (custom category query), 791494 (`_J` entry point, `lE` first-time, file input, resize), 16535 (context menu + delete), 205928 tabs (`w`, `B`), 472667 (unified picker, paging) |
| Add dialog | 416188 (`components-custom-emoji-dialog`, `CustomEmojiDialog`), launched by `launchCustomEmojiUpload` → entity command `customemojiupload` |
| Reactions | 21117 (mutation), 573742 (toggle), 77708 (key map), 763654 `vt` (title), 37994 (summary filter), 719107 (reserved keys) |
| GraphQL (client ↔ worker) | `emojiSearch`, `emojiById`, `emojisByIds`, `emojiByShortcut`, `customEmojiCount`, `customEmojiPage`, `createCustomEmojiMetadata`, `deleteCustomEmojiMetadata`, `addEmojisInRecent` (schema inner_d 82848; resolvers inner_d `$t`) |
| Worker emoji manager / store | inner_b `qA` (store `emoji-manager` v5: `custom-emoji-metadata`, `custom-emoji`), jobs 80507 (create), 43820 (sync) |
| Workflows | inner_c `HE` (sync, debounced), `ZE` (create) |
| HTTP service | inner_services_i 61080 (`CustomEmojiService`, endpoint `B`), 89353 (constants), AMS 128561/`uploadItem` |
| AMS cookie | async-entry 169797 (`aadtokenauth`) |
| Telemetry names (no UI) | 922579 |

---

## 1. Data model
- **Id**: `"{shortcut};{documentId}"` — exactly two `;`-separated parts (280767 `SY`). `eO(id)` = shortcut, `Pp(id)` = documentId (the AMS object id of the image). Teams emoji ids never contain `;`; everything that tests "is custom" tests for `;`.
- **GraphQL type** `CustomEmoji {id, createdOn:BigInt!, creator, documentId, etag, isDeleted, keywords[], searchMatch, shortcuts[]}` (inner_d 82848). `shortcuts[0]` is the name; `keywords` = `[name]`.
- **Category**: one `EmojiCategory` with `id:"customEmoji"`, title `custom_emoji_category_title` "Custom" (worker default `{id:"customEmoji",title:"Custom Emoji",…}`, inner_b `_l`).
- **Receive side needs no list**: anything that only has an id (message HTML, reactions, recents) builds the emoji from the id alone when `customEmojiConfig.enableReceive`: `{__typename:"CustomEmoji", id, documentId:Pp(id), shortcuts:[eO(id)], keywords:[eO(id)], creator:"", createdOn:undefined}` (721466 `m`; async-entry 8551318 `U`/`F`).
- **Order in the picker** (inner_d `Q`): records are stored sorted by `createdOn` ascending and listed **newest first**, with the current user's own emoji first. "Own" = `creator` equals the user's oid, or, when `creator` contains `_`, the part after the first `_` equals the oid without dashes (format of `creator` **unconfirmed**).
- **creator → person**: the context menu looks up `user(userId)` with `creator` if it is already an MRI, else `8:orgid:{creator}` (16535 `N`).

## 2. Services
### 2.1 Endpoint and auth (inner_services_i 61080 `B`)
- Base: the CSA (chat service aggregator) host, `https://teams.microsoft.com/api/csa/` (prod `csaService.apiConstants.host`; `teams.cloud.microsoft/api/csa` for OCDI; GCC `chatsvcagg.gcc…`; GTM `chatSvcAggAfd` when `useHostFromGtmTable`) (44091 `uf`).
- Paths are `api/v1/customemoji/metadata…` relative to that base → `https://teams.microsoft.com/api/csa/api/v1/customemoji/metadata`.
- Auth: AAD bearer for resource `https://chatsvcagg.teams.microsoft.com` (`apiConstants.resource`, overridable by `Auth.csaResource`) (38625 `c`). No skype token for these api names (12583 `i` returns false), unless `CsaService.onlySkypeTokenForAllAPIs`.
- Extra headers on every call: `x-ms-client-version: {clientVersion}`, `x-ms-client-type: web|windows|mac`, `x-ms-request-id: {correlationId}`. `rejectHttpError:true`.

### 2.2 List / sync — `GET api/v1/customemoji/metadata`
- Headers: `x-ms-request-id`, and `x-ms-continuation: {token}` for a delta sync (omitted for a full fetch, `fetchEntireMetadata`).
- No query paging; the server list is fetched whole (prod `maxEmoji` 5000).
- Response (**inferred from the consumer**, inner_c `HE`): JSON `{categories:[{id:"customEmoji", title, description, emoticons:[CustomEmoji…]}], continuationToken}`. Each emoticon carries `id, documentId, shortcuts, keywords, creator, createdOn, etag, isDeleted`.
- Merge (inner_b `mergeCustomEmojiMetadata` / `writeCustomEmojiRecords`): records with `isDeleted:true` are removed, others upserted by `id`. So a delta returns tombstones.
- `continuationToken` is stored and is a **Unix time in seconds**: a refetch is due when `now − token×1000 ≥ jitter(metadataSyncTTL, deltaSyncJitter)` (prod TTL 86 400 000 ms = 24 h, jitter default 0.1) (inner_b `shouldTriggerFetchMetadata`). No token → fetch.
- Non-forced syncs are debounced by `customEmojiSyncDebounceMs` 120 000 / `customEmojiSyncDebounceMaxWaitMs` 300 000 (inner_c `HE`).
- After a sync, deleted ids are also stripped from the user's default reactions and recents (inner_b `filterDefaultReactions` / `filterRecentReactions`).
- Not fetched when `enableCustomEmoji` is off or the user is anonymous.

### 2.3 Add — AMS upload, then `POST api/v1/customemoji/metadata` (61080 `uploadCustomEmoji`)
1. Image upload to AMS (`asyncMediaService.uploadItem(blob, "*:tid:{tenantId}", "IMAGE", "CustomEmojiService", …, withRetry)`; base = region GTM `ams`; auth `{source:"asyncMediaService"}`, i.e. the AMS skype-token auth):
   - `POST v1/objects/` with `Content-type: application/json`, `x-ams-post-sharing-mode: {mode}`, `ms-cv`, body `{"type":"pish/image","permissions":{"*:tid:{tenantId}":["read"]},"sharingMode":…}` → `{id}`.
   - `PUT v1/objects/{id}/content/imgpsh` with `Content-type: application/octet-stream`, body = the image bytes.
   - The whole tenant gets read access.
2. `POST api/v1/customemoji/metadata` with `Content-type: application/json`, `Accept: application/json`, `x-ms-request-id`, body `{"shortcuts":["{name}"],"documentId":"{amsObjectId}"}`.
   - The response body is the new CustomEmoji record, which is merged into the store.
- Errors (61080 `h`):
  - 409 → `AlreadyPresent`: the dialog shows the duplicate-name error.
  - 400 whose body `title` matches `/Max number of emojis (\d+) has been exceeded/` → `MaxLimitReached`: the limit dialog.
  - 403 is an expected outcome (policy). Anything else → generic error.
  - The error body is JSON with a `title`, or text when `content-type: html/text`.

### 2.4 Delete — `DELETE api/v1/customemoji/metadata/{id}`
- `{id}` is the full `"{shortcut};{documentId}"`, interpolated unencoded (61080 `y`). Header `x-ms-request-id`.
- Success → the worker writes a tombstone (`createDummyMetata(id,true)`) and the client evicts the `CustomEmoji` from the Apollo cache. 403 = expected (no rights).
- The AMS image is not deleted by the client.

### 2.5 Policy inputs (async-entry 16100 mapping; worker 49087)
| core setting | policy field | from |
|---|---|---|
| `enableCustomEmoji` | `teamsMessagingConfiguration.customEmojis` | MT `beta/users/useraggregatesettings` |
| `enableCustomEmojiCreation` | `messagingPolicy.createCustomEmojis` | MT `beta/users/effectivePolicies` |
| `enableCustomEmojiDeletion` | `messagingPolicy.deleteCustomEmojis` | MT `beta/users/effectivePolicies` |
| `isTenantAdmin` (UserResources) | `userResourcesSettings` | MT `beta/users/useraggregatesettings` |

The method and body of the two MT calls are **unconfirmed** (base GTM `middleTier`, MT auth). The policy values override the ECS defaults in §8.

## 3. Image URLs (280767 `O`, 133984, 476859)
- Domain: `{amsV2}` = region GTM `amsV2` (ends with `/`; e.g. `https://{region}.asyncgw.teams.microsoft.com/`).
- Views: **`imgt2`** (static) and **`imgt2_anim`** (animated). No other views or sizes are requested; the client scales.
- Plain: `{amsV2}v1/objects/{documentId}/views/imgt2[_anim]`.
- User-scoped (cookie mode, when `customEmojiConfig.enableAMSUrl && enableAMSAuthServiceWithAADToken`): `{amsV2}v1/{authenticatedUserId}/objects/{documentId}/views/imgt2[_anim]`. Whether the id is the oid is **unconfirmed** (likely).
- Fetching:
  - **Cookie mode**: the `<img>` loads the URL directly, with `crossOrigin="use-credentials"` when `crossOriginIsolated`, and `?v={customEmojiConfig.version}` appended in that case (prod version 0).
    - The cookie is set by `POST {amsV2}v1/{userId}/aadtokenauth` (`credentials:include`, `ms-cv`; expire: `GET …/aadtokenauth/expire`), driven by the IC3-gateway AAD token subscription (169797). Exact token **unconfirmed**.
  - **Otherwise**: the image is fetched as a blob through the AMS download path (`useBlobResult`, source `CustomEmoji`, auth `{source:"asyncMediaService"}` = `Authorization: skype_token …`, as for AMS images in `message-types.md`) and cached per user (`amsImageCache`).
  - Both modes ask for `imgt2_anim` unless animations are disabled (OS reduced motion, or the caller's `disableCustomEmojiAnimation`) → `imgt2`. With `enableEmojiAnimationConfig` (prod **false**), the static image is shown and `imgt2_anim` is swapped in only while a hover or viewport animation trigger runs.
  - Animation duration on focus: 10 000 ms for custom emoji (252621, vs 3 iterations for Teams emoji).
- On load error, or when `enableCustomEmoji` is off: `{staticsPath}/evergreen-assets/personal-expressions/v2/assets/categories/customEmoji/thumbnail.svg`, drawn with `opacity:0.5` (476859 `imageErrored`; compose uses object-fit cover, bottom, opacity 0.5).
- `<img>`: `alt`/title = shortcut, `data-tid="custom-emoji-{shortcut}"`, `itemID=id`, `itemType=…/CustomEmoji`, not draggable. The container is `display:inline-flex`.
- Rendered sizes (Griffel classes resolved by hash):

| size | px |
|---|---|
| extra-small | 18 × 18 |
| small | 20 × 20 |
| medium | 30 × 30, radius `borderRadiusMedium` |
| large | 50 × 50, radius `borderRadiusMedium` |

## 4. Message HTML
- **In the compose box** (522295 `x`):
  - `<readonly itemtype="http://schema.skype.com/CustomEmoji" contenteditable="false" aria-label="{name}" data-announcement="{name} emoji">`
  - containing `<img alt="{name}" aria-label="{name}" itemid="{name};{docId}" src="{display url}" data-orig-src="{amsV2}v1/objects/{docId}/views/imgt2_anim" draggable="false" style="height:20px;width:20px;margin:0 1px;border-radius:2px;vertical-align:bottom;position:relative;top:-1px">`.
- **On the wire** (`CustomEmojiSerializer`, async-entry ≈6228474):

  ```html
  <span contenteditable="false"><img alt="{name}" itemid="{name};{documentId}" itemtype="http://schema.skype.com/CustomEmoji" src="{amsV2}v1/objects/{documentId}/views/imgt2_anim" style="width:20px;height:20px;"></span>
  ```
  - `src` = `data-orig-src` (never the user-scoped or blob URL).
  - 20 px is `small`; it is 50 px (`large`) when the message is sent with `superSizeEmoticons`.
  - The send telemetry counts `"DataBag.customEmoji"`.
- **Receiving** (721466 `CustomEmojiDeserializer`):
  - Applies only when `enableReceive`.
  - The emoji is rebuilt **from `itemid` only** (`src` and size are ignored). With `enableRoamMessageDraft`, `itemid` may sit on the inner `<img>`.
  - Rendered with 133984: `small` (20), or `large` (50) when the message is super-sized.
  - Hover title = name.
- **Plain-text forms**: the preview, notification and copy-as-text form is `:{name}:` (204961 `_transformImg`, 395276, worker services_i). The structured-content schema has `{"type":"customemoji","id":"{id}"}`.
- **Quoted reply** (with `enableNewEmojisForQuotedReply`):
  - Preview text uses `:{name}:`.
  - The reply card appends `<span itemprop="emojis"><span itemprop="{id}" itemid="{index}" alt="{name}" itemtype="true"></span></span>`; the `itemtype` value is the string `"true"`/`"false"` for isCustom (async-entry ≈6281598).
  - Without the flag the preview text is `({name})`.

## 5. Reactions
- **Key** = the emoji id unchanged: `{"emotions":{"key":"{name};{documentId}","value":<epoch ms>}}` on the usual `PUT …/properties?name=emotions` (77708 maps only `yes`/`like`/`star`; 573742 sends `a(id)`). Nothing else differs in the body. The literal key on the wire is **unconfirmed**; expect the `;` as-is.
- No skin tones: `commonKey` = key (the `-tone\d` strip never matches).
- **Showing**: with `enableReceive` any key except `star`, `follow`, `acks` is shown; without it only known Teams reaction keys are shown, so custom reactions are hidden (37994 `R`, 719107).
- **Name** (pill aria, who-reacted header, tooltip) = `eO(key)`, the shortcut (763654 `vt`).
- **Image sizes**:
  - Pill image: `extra-small` 18 px (`isReactionCountStyle`).
  - Hover-bar quick reaction: `small` 20 px (Teams emoji there are `medium`).
- Custom ids may appear in `defaultMessageReactions` (Customize reactions resolves them via `emojisByIds`) and in recents. Recents store them as `{id, description:creator, unicode:"{createdOn}", etag:"CustomEmoji"}` (async-entry 8545024 `T`).
- Activity telemetry classifies a reaction key containing `;` as `"CustomEmojiId"`.

## 6. Picker UI
### 6.1 Tab and grid (599484, 869839, 205928)
- The custom category is appended **last** in the category tabs.
- It is present when `enableCustomEmoji && customEmojiConfig.enableSend`, and not in the group-chat-avatar picker or comment streams.
- Tab:
  - Icon: the mask `{pes categories base}/customEmoji/thumbnail.svg`, the same as other tabs.
  - Tooltip and aria: **"Your org's emoji"** (`custom_emoji_category_tooltip`). The section heading is **"Custom"** (`custom_emoji_category_title`).
  - `data-tid="emoji-categories-tab-{index}"`, id `emoji-categories-tab-customEmoji`.
- Cells:
  - The normal emoticon cells; the image is `medium` (30 px) in the 46 × 46 cell.
  - Title "{name}\nShortcut: :{name}:" (`emoticon_combined_title`).
  - Custom cells have a context menu and add "has context menu" to the aria.
- **Non-empty + `enableCustomEmoji && enableCustomEmojiCreation`**: the **first grid cell** is the add button (791494 `_J`, id `custom-emoji-entrypoint-in-picker`, `data-tid="custom-emoji-upload-entrypoint"`):
  - a 30 × 30 Fluent button with margin 8 and the **AddRegular** icon;
  - tooltip below: "Add emoji", or "Your org has hit the {{limit}} emoji limit." when `customEmojiCount ≥ maxEmoji` (5000), in which case it is disabled.
- **Empty + creation enabled**: the first-time block replaces the grid (791494 `lE`, `data-tid="custom-emoji-entrypoint-wrapper"`): a centred column with
  - the text "Add your own emoji that everyone in your org can use." (block, 220 px wide);
  - a primary **large** button "Add emoji" (220 × 32).
- **Empty without creation**: "We didn't find any matches." (`funStuffPicker_search_noResults`).
- **Unified picker** (472667):
  - The same entry points (first row element `customEmojiUploadEntrypoint`).
  - In search results, a large button `custom-emoji-upload-entrypoint-in-search`: a filled icon (name unresolved) + " Add emoji".
  - With `enableCustomEmojiPickerPagination` it pages `customEmojiPage(first:500, after)` from the worker snapshot (server cap 1000 per page, own-first order, a `generation` that resets paging when the set changes).
- **Autocomplete**:
  - `:name` (colon) autocomplete includes custom emoji when `enableCustomEmoji && customEmojiConfig.enableAutoCompleteColon` (prod true).
  - `(name)` autocomplete includes them only with `enableAutoComplete` (prod **false**).
  - Shortcut search is `emojiSearch(searchType:shortcuts)`; the name must match `/^[a-z0-9-_]{1,50}$/`.

### 6.2 Add emoji flow (791494, 416188)
1. The entry point clicks a hidden `<input type="file" id="upload_custom_emoji" accept=".png,.jpeg,.gif">`. `.jpg` is not listed.
2. Resize (791494 `oe`):
   - GIFs and animated PNGs are kept as-is.
   - Anything else is drawn into a **400 × 400** canvas, scaled by `min(398/w, 398/h)` (small images are scaled up too), centred, and exported as PNG.
   - No client-side byte limit was found (**unconfirmed**).
3. A blob URL plus the file name opens the dialog (`launchCustomEmojiUpload` → entity command `customemojiupload`, chat-app). It is gated by `enableCustomEmoji` and `enableCustomEmojiCreation`.
4. Dialog `custom-emoji-upload-dialog`:
   - Title "Name your emoji". An info MessageBar: "Emoji you add will be available to everyone in your org. Your identity is linked to your emoji and visible to everyone."
   - Field "Name" (required): a large input `custom-emoji-name-input`, spellcheck off, placeholder "(Enter a name for your emoji)" with the parentheses added.
   - "Preview": a mock chat.
     - "Clippy" (the 28 px avatar is the paperclip emoticon `1f4ce_paperclip/default/50_f.png`, status available) at "10:23 AM": "Great choice on the new emoji. {emoji}", with a reaction pill of the emoji (extra-small) and count 3.
     - Your reply at "10:25 AM": "Thanks! I thought you’d like it. {emoji}".
   - Buttons: Cancel (secondary), **Add emoji** (primary; a tiny spinner while uploading).
5. Default name from the file name: drop the extension, lowercase, replace `\W` and `_` with `-`, collapse `-`, trim `-`; kept only if it matches `/^[a-z0-9-_]{1,50}$/`, else empty.
6. Validation on each change (trimmed):
   - Non-empty and failing the rule → "Names must be lowercase and can’t contain special characters or spaces." (Add disabled).
   - Equal to `star`/`follow`/`acks`, or to an existing Teams-emoji shortcut or custom emoji shortcut → "An emoji with that name already exists. Try another name." (disabled).
   - Otherwise Add is enabled when the name is non-empty.
7. Add:
   - Announces "Adding {{emoji}}", then mutation `createCustomEmojiMetadata(name, blobUrl)` (worker: §2.3).
   - Success → toast "{{emoji}} was added" (Success, 4 s), close, refetch the custom category.
   - 409 → the duplicate error (button stays enabled).
   - Limit → a nested dialog "Your org has hit the {{limit}} emoji limit." with "OK".
   - Other errors → "Something went wrong. Please try again."

### 6.3 Context menu and delete (16535)
- Right-click (`openOnContext`) a custom cell → menu `custom-emoji-context-menu-popover`:
  - **"Delete emoji for org."** (Delete icon), only if `enableCustomEmojiDeletion || isTenantAdmin`;
  - a divider, then an info row "Created by {{customEmojiCreator}} on {{customEmojiCreationDate}}" (display name from `user(8:orgid:{creator})`, short date). It is shown only when `creator` and `createdOn` are known (not for id-only emoji). It is announced when the menu opens.
- Delete → dialog `custom-emoji-delete-dialog`: "Are you sure you want to delete it?", with Cancel (secondary) and **Delete** (primary).
  - Success → toast "{{customEmojiName}} deleted for your organization." (3 s).
  - Failure → toast "Unable to delete. Please try again." (Error, 3 s).

## 7. Strings (en-us, verbatim)
| key (`messaging:` unless noted) | text |
|---|---|
| `custom_emoji_category_tooltip` | Your org's emoji |
| `custom_emoji_category_title` | Custom |
| `custom_emoji_entrypoint_label` | Add your own emoji that everyone in your org can use. |
| `custom_emoji_upload_button_label` | Add emoji |
| `custom_emoji_max_limit_error_message` | Your org has hit the {{limit}} emoji limit. |
| `custom_emoji_error_dialog_confirmation` | OK |
| `custom_emoji_upload_dialog_title` | Name your emoji |
| `custom_emoji_upload_dialog_info` | Emoji you add will be available to everyone in your org. Your identity is linked to your emoji and visible to everyone. |
| `custom_emoji_name_input_label` | Name |
| `custom_emoji_name_input_placeholder` | Enter a name for your emoji |
| `custom_emoji_name_input_invalid_name_error_label` | Names must be lowercase and can’t contain special characters or spaces. |
| `custom_emoji_name_input_invalid_error_label` | An emoji with that name already exists. Try another name. |
| `custom_emoji_upload_generic_error_message` | Something went wrong. Please try again. |
| `custom_emoji_name_preview_label` | Preview |
| `custom_emoji_name_preview_group_label` | Emoji preview |
| `custom_emoji_preview_user_name` | Clippy |
| `custom_emoji_preview_message_timestamp` | {{time}} AM |
| `custom_emoji_preview_chat_message` | Great choice on the new emoji. |
| `custom_emoji_preview_chat_message_reply` | Thanks! I thought you’d like it. |
| `custom_emoji_upload_dialog_cancel_button_label` | Cancel |
| `custom_emoji_uploading_message_aria_label` | Adding {{emoji}} |
| `custom_emoji_upload_success_message` | {{emoji}} was added |
| `custom_emoji_creator_info` | Created by {{customEmojiCreator}} on {{customEmojiCreationDate}} |
| `custom_emoji_delete_title` | Delete emoji for org. |
| `custom_emoji_delete_dialog_header` | Are you sure you want to delete it? |
| `delete_button_text` / `cancel` | Delete / Cancel |
| `custom_emoji_delete_success_msg` | {{customEmojiName}} deleted for your organization. |
| `custom_emoji_delete_failure_msg` | Unable to delete. Please try again. |
| `tmp_messages_aria_has_context_menu` | has context menu |
| `funstuff:emoticon_combined_title` | {{name}}⏎Shortcut: {{shortName}} |
| `funstuff:funStuffPicker_search_noResults` | We didn't find any matches. |
| `compose:emoji_announcement` | {{emojiName}} emoji |

ESP "what's new" cards (not core UI): "Introducing Custom Emoji", "Create your own emoji", "Make anything an emoji", "Use pictures and screenshots to create emoji that everyone in your org can use.", "Express yourself uniquely with any picture or GIF as an emoji.". The loc file also has an unreferenced "Add your own emoji" (`ka7i3k1c5`, key unknown).

## 8. Settings / flags (category `messaging`; prod values)
| flag | prod | effect |
|---|---|---|
| `enableCustomEmoji` | true (false for EducationStudent/EducationFaculty licences) | master switch: sync, tab, rendering of the tab/fallback; policy `teamsMessagingConfiguration.customEmojis` |
| `enableCustomEmojiCreation` | true | add entry points and dialog; policy `messagingPolicy.createCustomEmojis` |
| `enableCustomEmojiDeletion` | true | the Delete menu item (tenant admins always get it); policy `messagingPolicy.deleteCustomEmojis` |
| `customEmojiConfig.enableSend` | true | custom tab present in pickers (so you can send) |
| `customEmojiConfig.enableReceive` | true | render custom emoji in messages and reactions from ids |
| `customEmojiConfig.metadataSyncTTL` | 86 400 000 | ms between list syncs |
| `customEmojiConfig.deltaSyncJitter` | (unset → 0.1) | TTL jitter fraction |
| `customEmojiConfig.maxEmoji` | 5000 | org limit; disables the add button at the limit |
| `customEmojiConfig.enableAutoComplete` | false | include custom emoji in `(name)` autocomplete |
| `customEmojiConfig.enableAutoCompleteColon` | true | include custom emoji in `:name` autocomplete |
| `customEmojiConfig.enableAMSUrl` | true | with `enableAMSAuthServiceWithAADToken`: user-scoped AMS URLs and cookie auth |
| `customEmojiConfig.customEmojiSyncDebounceMs` / `…MaxWaitMs` | 120 000 / 300 000 | sync workflow debounce |
| `customEmojiConfig.version` | 0 | cache-buster `?v=` on cookie-mode image URLs (cross-origin-isolated only) |
| `enableAMSAuthServiceWithAADToken` | true on platforms 49, 50, 51, 1415, 1454 | AMS AAD cookie (`aadtokenauth`) |
| `enableCustomEmojiPickerPagination` | unset (off) | unified picker pages `customEmojiPage` |
| `enableCustomEmojiDBSchemaMigration` | unset (off) | per-record IndexedDB store `custom-emoji` instead of one blob |
| `enableEmojiAnimationConfig` | false | trigger-based animation (static image until hover or viewport) |

## → TODO / unconfirmed
- The exact list-response JSON (§2.2) and the create-response body: capture `GET {csa}/api/v1/customemoji/metadata` live on winpc.
- Whether `{authenticatedUserId}` in user-scoped URLs is the oid, and which token `aadtokenauth` takes.
- A reaction key with `;` on the wire (§5), and how other clients render it.
- The server-side image size/byte limits and the accepted MIME types.
- The `creator` field format (oid vs `x_oid`).
