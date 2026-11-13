# Non-text chat message types — how Teams renders them (spec)

Source: the Teams client itself, build 26276.513, the same bundles as
docs/spec/messages-and-composer.md. That means the minified webpack chunks
plus the data-layer web worker (`precompiled-web-worker-inner_*.worker.js`).
Module ids are given so this can be re-checked against later builds.

Strings are the en-us texts, resolved from Teams' obfuscated keys
(`k` + base36(poly131(`"ns:key"`) mod 2^40)). Sizes come from the Griffel CSS
of the bundles; Teams sets `1rem = 10px`, so `0.8rem` = 8px. "Live" values are
the winpc tenant settings dump used by the other specs. "live ?" means the
flag is not in that dump.

Icon names are Fluent System Icons; `Regular`/`Filled` is the variant used.
"Office file-type icon" means the coloured document icons, not Fluent system
icons.

This spec does not repeat messages-and-composer.md. Visible types per chat
kind are in its §1. Control-message text for `Event/Call`, `AddMember`,
`ConsentInvites`, recording rows and so on is in its §9. Bubble layout,
grouping and the "Edited"/"Updated" details are in its §3 and §6.

Anything not confirmed from code is marked **(unconfirmed)**.

---

## Components (module index)
| area | module(s) |
|---|---|
| Chat message frame; body/attachments/preview slots | 318259 (`_renderMessageRenderer`, `_renderMessageContent`, `_getMessageContent`, `_renderAttachmentContent`, `_renderAttachments`, `_renderUrlPreview`) |
| Body pipeline: plain `<p>` vs deserializers | 923733 (`kt` → `Ft` → `He`) |
| Deserializer engine (filter matching, DOM-depth guard) | 836697 (`tG`, `dL` decorator) |
| Teams deserializer list (HTML, Media_Card, Collaborate, Embed) | 721466 `cD` (+ `RecapChicletDeserializer` in 923733) |
| Skype/TFL deserializer list | 289206 `Ft` |
| `isSkypeMessage` rule | worker 68245 → 787276 `io`; UI 96509 `$` |
| Itemtype URLs (`http://schema.skype.com/...`) | 681372 |
| Card content types | 384884, 810957 |
| Message-type enum (wire names) | 201110; item types 991060 |
| Unsupported placeholder | 230655 `$` |
| Section error boundary ("Error loading attachments or previews.") | 318259 `St` |
| Skype contacts, location, poll, call invite, images, files, quote | 289206; preview text 544647 |
| Voice message | 405072 (Teams card), 289206 (Skype `Audio.1/Message.1`), player 849161, duration 877513, AMS download 750336/382411 |
| Bot cards (`RichText/Media_Card`) | 740332 → 941065 → 511225 → 944311; SWIFT parse 49385; host config 824631; helpers 255529 |
| Card actions | 729520, handler map 511225 `Qt`; invoke 730589; imBack 924759; messageBack 455054; Execute 246298; Refresh 563117; O365 POST 667838; OpenUrl 545049; footer 58255/127570 |
| Cards in HTML messages (`InputExtension`) | 457859 → 717287; code snippet 379122 |
| File attachments | grid 544824; chiclet 388605; file-type icon 153e3; ··· menu 149099 → 280014 → 359380; error boundary 330096; worker 71026 |
| Files hyperlink in body | 798787 |
| `ThreadActivity/FileAdd` | 75579 `Pa` |
| Loop (Collaborate / Embed) | 602214, 713611, 459203, 604685, placeholder 802652, header 629024, fallback link 427415 |
| Link preview | 361558 → card 25636; worker 86706 |
| Quoted reply | 331955 → card 977647; worker 68245 `Xr` |
| Forward card | 721466 `ForwardCardDeserializer` → 953683; worker 61388 |
| "Also sent to chat" / "Replied in thread" label | 288364 |
| Cloud recording | parser 420044 (names 856564); card 307208; chooser 886048; data 397395; not-saved card 358638; control text 75579 `en` |
| Local recording | 422270, 75579 `qa` |
| Transcript | 560170 (1:1 legacy), 618581/103652 (card), 963821 (parse) |
| Recap chiclet | 983864 (chat), 676304 (channel), 102674; UI 174639 (not traced) |
| Message move | worker `qS`/`YS` (inner_d), 8819; UI 75579 `ha`, 318259 `fg`/`Ym` |
| Smart-card rows (item types 7/8/9) | 434910 `ln`/`on`/`dn`; 497560, 205036, lazy 113431, lazy 977412 |
| SMS | send 955743; delivery reports 947361; codes 759872 |

## Type index
| wire `messagetype` | body path (§1) | renderer | section |
|---|---|---|---|
| `RichText/Contacts` | Skype list; otherwise plain `<p>` | 289206 `SkypeContactCardDeserializer` | §2 |
| `RichText/Location` | Skype list; otherwise plain `<p>` | 289206 `SkypeLocationDeserializer` (placeholder only) | §3 |
| `Poll` | Skype list; otherwise plain `<p>` | 289206 `SkypePollDeserializer` (placeholder only) | §4 |
| `RichText/ScheduledCallInvite` | Skype list; otherwise plain `<p>` | 289206 `SkypeEventCardDeserializer` (placeholder only) | §5 |
| `RichText/UriObject` | Skype list | 289206 image / sticker / Tenor GIF | §6 |
| `RichText/Media_GenericFile`, `RichText/Media_Video` | Skype list (always Skype) | 289206 → file attachment 544824 | §7 |
| `RichText/Media_AudioMsg` | Skype list (always Skype) | 289206 → player 849161 | §8 |
| voice message in `RichText/Html` | Teams list | 405072 → player 849161 | §8 |
| `RichText/Media_Card` | Teams list | 740332 (SWIFT card) | §9 |
| cards in `RichText/Html` (`properties.cards`) | Teams list | 457859 | §10 |
| `RichText/Files` | plain `<p>` body + `properties.files` | attachments 544824 | §11 |
| `ThreadActivity/FileAdd` | control row | 75579 `Pa` | §11 |
| `Collaborate` | Teams list / Loop host | 602214 | §12 |
| `Embed` | Teams list | 459203 | §13 |
| link preview (`properties.links`) | attachment slot | 361558 → 25636 | §14 |
| quoted reply (`<blockquote itemtype=…/Reply>`) | Teams list | 331955 → 977647 | §15 |
| forward (`<blockquote itemtype=…/Forward>`) | Teams list | 953683 | §16 |
| `RichText/Media_CallRecording` | item type 4 | control row or card 307208 | §17 |
| `RichText/Media_LocalRecording` | item type 6 | control row 422270 | §18 |
| `RichText/Media_CallTranscript` | item type 5 | 560170 / 618581 (1:1 only) | §19 |
| `RichText/Media_MeetingObjects` | folded into the call-ended row | none | §20 |
| `ThreadActivity/MessageMoveStarted` / `MessageMoveCompleted` | control rows | 75579 `ha` | §21 |
| `ThreadActivity/ConsentInvites` | control row | 75579 `rn`/`on` | §22 |
| `SmartCard` (+ `MeetingOrientationSmartCard`, `FollowedMeetingTopicsCard`) | client-made rows, item types 7/8/9 | 497560, 113431, 977412 | §23 |
| `RichText/Sms` | plain `<p>` | 955743, 947361 | §24 |
| anything unsupported | — | 230655 and friends | §25 |

---

## 1. How the body is chosen (318259 → 923733)
- **Frame** (318259 `_renderMessageRenderer`): calls 923733 `kt(message, …)`. That returns `{content, text, messageData}`. `messageData` carries flags set by deserializers: `isContentUnsupported`, `isCardUnsupported`, `containsAudio`, `containsInlineVideo`, `isSingleImageMessage`, `isSingleCardOnly`, `previewUrl`, `hasUnverifiedQuotedMessage`.
- **`_renderMessageContent`** order:
  1. deleted → tombstone (messages-and-composer.md §6);
  2. `isContentUnsupported` → 230655 placeholder instead of the body (§25);
  3. meeting-object chiclet (§20);
  4. otherwise `_getMessageContent`, which stacks:
     - the text slot (`_renderTextContent`: shared label, DLP, unsafe-sender indicator, quote-validation banner, announcement/title, the body);
     - the AI footer;
     - the attachment slot (`_renderAttachmentContent`: channel deeplinks, the file grid when `files.length`, then the URL preview).
- **Section error boundary**: with `enableMessageSectionErrorBoundary`, the attachment grid and the URL preview are each wrapped in 318259 `St`. A render error there shows **"Error loading attachments or previews."** (`messaging:tmp_message_section_default_error_boundary_message`).
- **923733 `Ft`**:
  1. Takes `content` (or the translation), and strips U+200B.
  2. `Collaborate` with Loop allowed → Loop path (§12).
  3. Bot sender (`28:`) → content from `%TEMP_SCHEMA%` on is cut.
  4. Then by type:

| messageType | body |
|---|---|
| `RichText/ExtendedMarkdown` | markdown renderer (when `enableExtendedMarkdown`) |
| `RichText/Media_CallRecording` | `<p>`"Recording has started"`</p>` (`messaging:calling_recording_progress`). The timeline does not use this; it renders item type 4 (§17) |
| `RichText/Html`, `RichText/Media_Card`, `Collaborate`, `Embed`, `TargetedMessage/SsoAuth`, `TargetedMessage/AgentInteractionPrompt`, any message with an image file (695004 `ZZ`), any Skype message (96509 `$`) | `He`: HTML parse + deserializers |
| **everything else** (including non-Skype `RichText/Contacts`, `RichText/Location`, `Poll`, `RichText/Sms`, `RichText/Files`) | **`<p>{content}</p>` with the raw string as text** (no HTML parsing) |

- **`He`**:
  - Optional image split (bubbleless images, collage).
  - Then `836697.tG(list, content, data)`: the Skype list 289206 `Ft` when the message is Skype, otherwise `[RecapChicletDeserializer, ...721466.cD]`.
  - A parse exception gives the 230655 placeholder with **"Error encountered while rendering this message"** and no icon.
- **Deserializer engine** (836697):
  - Parsing: the content goes through htmlparser2 with `decodeEntities`. Tag names are lower-cased, so the filters see `uriobject`, `swift`, `originalname`.
  - Matching: a filter matches by tag name, attribute name, or exact `attribute=value` (`{type:"Picture.1"}`, `{itemtype:"http://schema.skype.com/Reply"}`).
  - The list is tried in order, and the first handler that returns a value wins:
    - `undefined` = not handled (try the next one, then default rendering);
    - `null` = remove the element.
  - `maxMessageDOMDepth` (Messaging setting) exceeded → the body becomes `<p>`**"This content is currently not supported."**`</p>`.
- **Teams list order** (721466 `cD`, after `RecapChiclet`): CodeBlockEditor, CustomEmoji, 324986 (not identified), MeetingCopilotImage, Giphy, ItemProp, InlineImage, InlineVideo, AtMention, Emoticon, EmojiOne, EmptyParagraph, Math, Text, ScheduledMeetingCancelled, ScheduledMeetingCreated, ScheduledMeetingUpdated, FluidEmbed, AudioCard, Card, MediaCard, FileAttachmentLink, ATPSafelinks, TableHandler, TableElement, QuotedReply, ForwardCard, ListHandler, Topic, NegativeMargin, LegacyThemeLightGrey, BotCitation, PromptPreview, StaticImage.
  - The module of each entry is in the list `je` of 721466. Filters and modules of the ones that matter here are in the per-type sections.
- **Skype list order** (289206 `Ft`): SkypeEmoticon `ss` → SkypeImage (`Picture.1`/`Sticker.1`) → SkypeAudioCard (`Audio.1/Message.1`) → SkypeAtMention `at` → SkypeQuotedReply `quote` → ATPSafelinks `a` → SkypeTenorGif (`SWIFT.1`) → SkypeFileAttachment (`File.1…`, `Video.1…`, `Audio.1`) → SkypePoll (`Poll`) → SkypeEvent (`ScheduledCallInvite.1`) → SkypeLocation `location` → SkypeContactCard `contacts`.
  - A `<URIObject>` whose `type` matches none of these falls through to default rendering of its children **(unconfirmed exact output)**.

### When a message counts as Skype (TFL)
- **Worker** (field `isSkypeMessage`, 68245 → 787276 `io(properties, originalArrivalTime, convId, settings, productContext, messageType)`):
  - `Messaging.enableSkypeMessagesInTFL` off → `false`.
  - `properties.formatVariant` present → Skype ⇔ `formatVariant === "SFL"` (`"TEAMS"` = not Skype).
  - Otherwise Skype when any of:
    - `messageType ∈ {RichText/Media_AudioMsg, RichText/Media_GenericFile, RichText/Media_Video}` (always);
    - arrival < `goldenGateCutOffDate` (default `1738368000000` = 2025-02-01Z) and `threadProperties.productContext === "SFL"`;
    - the conversation id starts with `19:` and contains `@oneToOne.skype`, `@thread.skype` or `@p2p.thread.skype`, and arrival < `csv2MigrationCutOffDate` (default `1751328000000` = 2025-07-01Z).
- `isSkypeForwardedMessage` = `JSON.parse(properties.forwardMetadata).isForwarded === true`.
- **UI check** (96509 `$`): `enableSkypeMessagesInTFL && __typename === "Message" && isSkypeMessage`.
- **Gating for Skype messages**:
  - **Never forwardable** (96509 `E`). Voice messages (`Media_AudioMsg`, or a card of type `…card.audio`) are never forwardable either.
  - **Edit hidden** (263162 `Ls`):
    - Skype `Poll`, `ScheduledCallInvite`, `Location`, `Contacts`, `Media_Video`, `Media_GenericFile` (92099 `jA`);
    - Skype forwarded messages and Skype `SWIFT.1`/`Sticker.1` URIObjects (96509 `CF`, 92099 `Xb`);
    - every voice message.
  - **Skype `Poll` and `RichText/ScheduledCallInvite`** (92099 `Y5`, 318259 `es`): no reactions row, no hover action bar, no right-click menu.
- **Chat-list preview** of Skype bodies (544647):

| element | preview text |
|---|---|
| `Picture.1`/`Sticker.1` | "Sent an image" |
| `SWIFT.1` | "📷 GIF" |
| `Audio.1` | "🎙 Audio message" |
| `File.1` | "Sent a file" |
| `Video.1` | "🎥 Video" |
| `Poll` | "Sent a Poll" |
| `ScheduledCallInvite.1` | "Scheduled a call" |
| `location` (with both coordinates) | "📍 Location" |
| `contacts` | " Sent a contact card" (leading space) |
| `ss` | `utf`/`alt`, else `type`, else "📷 Emoji" |
| `at id="*"` | "Everyone" |

## 2. RichText/Contacts (289206 `SkypeContactCardDeserializer`, filter tag `contacts`)
- **Wire**: `messagetype: "RichText/Contacts"`.
  - The renderer reads only the **first child** of `<contacts>`: attribute `f` = display name and `s` = Skype id.
  - The child's tag name is not checked. `<c>` is the conventional name (unconfirmed).
  - Example: `<contacts><c t="s" s="live:jane_1" f="Jane Doe"/></contacts>`. The `t` attribute is not read.
- **Render** (`_t`, `data-tid="skype-contact-card"`):
  - Card: the Skype placeholder card style (§25), gap 12px.
  - Icon **Person** (20px).
  - Column (`font-weight: semibold`):
    - Header: a **mention pill** with the display name (955873 `B`, `atMention:true`), wrapped in the persona hover card (231316 `B`, `renderMention` 992211) for `userId = "8:" + s`. aria "Mentioned {{displayName}}" (`messaging:tmp_at_mention_aria_label`).
    - Second line: the raw Skype id `s`, Text size 200, `--colorNeutralForeground3 !important`.
- **Actions**: hovering or clicking the name opens the persona card of `8:{s}` (the standard mention behaviour). There is no add-contact or chat button.
- **Fallback**: `f` or `s` missing → the deserializer returns `undefined` (not handled; default rendering of the element).
- **Preview text** (544647): " Sent a contact card" (`messaging:skype_message_preview_sent_a_contact`, leading space).

## 3. RichText/Location (289206 `SkypeLocationDeserializer`, tag `location`)
- **Wire**: `<location latitude="…" longitude="…" …>…</location>`. Only `latitude` and `longitude` are read. Other attributes (address, `<a>` map link) are ignored (unconfirmed what they contain).
- **Render**: Skype placeholder card (§25). Icon **Location**, header **"Location"** (`messaging:location_placeholder_text`), secondary "Unsupported content". **No map, no address, no link.**
- **Fallback**: either coordinate missing → returns `null` (the element is removed and nothing renders).
- **Preview**: "📍 Location" (`skype_message_preview_sent_a_location`, `\u{1F4CD}`), only when both coordinates are set.

## 4. Poll (289206 `SkypePollDeserializer`, `<URIObject type="Poll">`)
- **Wire**: `messagetype: "Poll"`, content contains a `URIObject` with `type="Poll"`. No attribute or child is read.
- **Render**: Skype placeholder card (§25). Icon **Poll**, header **"Poll"** (`messaging:poll_placeholder_text`), "Unsupported content". **No options, no voting, no service call.**
- Reactions, the hover menu and the context menu are hidden (see §1).
- **Preview**: "Sent a Poll" (`skype_message_preview_sent_a_poll`).

## 5. RichText/ScheduledCallInvite (289206 `SkypeEventCardDeserializer`, `type="ScheduledCallInvite.1"`)
- **Wire**: `<URIObject type="ScheduledCallInvite.1" …>`. Nothing else is read.
- **Render**: Skype placeholder card (§25). Icon **CalendarClock**, header **"Scheduled Call"** (`messaging:scheduled_call_placeholder_text`), "Unsupported content". No join or time.
- Reactions and menus are hidden.
- **Preview**: "Scheduled a call" (`skype_message_preview_scheduled_call`).
- The worker also has `scheduledCallStatus` on messages (68245); the UI use of it is unconfirmed.

## 5b. GIFs and stickers from Teams' fun picker (RichText/Html, measured live 2026-11-07)
Sent from Teams web into "OST group test" and read back raw. Both are plain `RichText/Html` messages, `<p>&nbsp;</p>` around one `<img>`:
- **GIF**: `<img src="https://media3.giphy.com/media/…/giphy.gif" width="444" height="250" alt="{GIPHY title} (GIF Image)" style="height:auto; margin-top:4px; max-width:100%">`. There is no itemtype; the URL is GIPHY's own.
- **Sticker**: `<img src="https://teams.public.onecdn.static.microsoft/evergreen-assets/stickerassets/{pack}-250x250/en-us/{id}.gif?v=5" height="180" alt="{sticker name}" width="180" itemtype="http://schema.skype.com/Sticker">`. For example `clippy-250x250/en-us/Clippy_HelloThere.gif` with alt `Clippy says "Hello there"`. Meme stickers use `-500x500`.
- **Rendering on winpc**:
  - the GIF is shown at 404 × 227 (wider than 404 scales down), in a span with radius 6, without a bubble;
  - the sticker sits in a 180 px frame;
  - both were still (GIPHY's `giphy_s.gif`) under a play button: a 48 px circle `rgba(0,0,0,.8)` with a white play icon.
- **Autoplay** (262200): `shouldAutoPlayGifs` = the message is newer than the chat's consumption horizon when it was opened. Otherwise it shows still with the play button, and clicking plays it.

- **Order** (measured on Teams web, 2026-11-07, message "OST TEST 58 before the GIF"): the body is one HTML flow, so text, GIFs, stickers and pictures show in the order they were written. Teams draws each `<p>&nbsp;</p>` as an empty 20 px line, and a GIF has a 4 px top margin. Text, blank line, GIF, blank line, text measured 20 + 20 + 4 + 250 + 20 + 20. (On winpc, one message whose emoticon was a real Emoji span showed no blank lines; a plain one did. The cause is not known.)
- **OST**: `view_of` marks each picture in the sanitised HTML. `html` holds the text before the first picture; `flow` holds the pictures and the text between them in order. It is empty when the pictures only follow the text.
- **Editing** keeps every emoticon, custom emoji, GIF, sticker and picture, as Teams' edit box does. OST gives your own messages an `edit_html` and `edit_media`, which the edit box loads. They go back out in Teams' own form. This was verified live: two edits of the message above kept the GIF and its layout byte for byte.

## 5c. Emoticons in the body and big emoticons
- **Wire format**: an emoticon is `<span class="animated-emoticon-20-{id}"><img itemscope itemtype="http://schema.skype.com/Emoji" itemid="{id}" src="https://statics.teams.cdn.office.net/evergreen-assets/personal-expressions/v2/assets/emoticons/{id}/default/20_f.png" title="{name}" alt="{char}" width="20" height="20" …></span>`. Teams draws its own Fluent picture for `{id}`, not the platform's emoji font.
- **Big emoticons** (BigEmoticonPreprocessor, async entry): a message whose body is only 1–3 emoticons or custom emoji shows them at 50 px instead of 20. Any other text, a `<br>`, another image, files or cards keeps them at 20.
- **Rendering**: a big-emoticon message has no bubble, like an image-only message; each line is 50 px tall.
- **OST**: the sanitizer turns each Teams Emoji img into an `ost-emoticon:{id}` placeholder. The desktop app fetches the emoticon picture from the catalogue (50 px, or 100 px for big), caches it and swaps in the file. A text-only view falls back to the alt character.

## 5d. Formatting in received messages (measured on winpc, 2026-11-07, "OST TEST 66" and "68")
- **Wire format** (Teams sent; classes and CSS variables are stripped):
  - highlight is `<span style="background-color:#FDD472">`;
  - font colour is `color:#B6424C`;
  - Large is `font-size:x-large` (Small `small`, Medium removes the size);
  - Quote is `<blockquote><p>…</p></blockquote>`;
  - a code block is `<p itemtype="http://schema.skype.com/CodeBlockEditor" id="x_codeBlockEditor-{uuid}">&nbsp;</p>` then `<pre class="language-{id}" itemid="codeBlockEditor-{uuid}"><code>…</code></pre>`.
- **Rendering.**
  - x-large is 24/34.3 (lines are 1.4286 × the size).
  - Quote box: white, 0.67 #D1D1D1 border, radius 4, padding 7/15, margin 7/0, fit to its text. The bar is 2.67 wide at (3, 3), its height the box − 6, radius 1.5, #D1D1D1.
  - The empty CodeBlockEditor paragraph isn't drawn.
- **Code card** (`code-block-editor-deserialized-*`):
  - it fills the message width;
  - a 32 px header: white, radius 8 8 0 0, holding the code icon at 10.7, the language name 12/16 #616161 at 36.7 (Teams' names: Plain Text, JavaScript, C#…), and Copy (24 × 23.3, copy-20) 6 from the end;
  - then the `pre`: white, 0.67 #D1D1D1, radius 0 0 8 8, padding 8/12, Cascadia Mono 14/24, line numbers in a 42 px gutter;
  - it sits 6 under the text before it.
- **OST.** Styled spans keep `background-color`, `color` and `font-size` (keywords become px as a browser draws them). Quotes and code blocks become flow parts (`quote`, `code`), drawn natively. Cascadia Mono ships with OST.
- **Not done yet.** Syntax colours by language (Teams runs CodeMirror's modes), and headings, rules and tables measured on the receiving side.

## 6. RichText/UriObject — images, stickers, GIFs
### 6a. `Picture.1`, `Sticker.1` (289206 `SkypeImageDeserializer`)
- **Wire**: `<URIObject type="Picture.1" uri="https://…/v1/objects/{id}" doc_id="{id}" width="…" height="…" alt="…"><OriginalName v="photo.jpg"/></URIObject>`.
  - Attributes read: `uri` (required), `doc_id`, `type`, `alt`, `width`, `height`, and `style` (`width:…;height:…` is parsed into width/height when they are missing, 605712 `CS`).
  - Child read: `<OriginalName v>`.
- **Alt**: `alt` → `OriginalName v` → "Image". It is also pushed into the message's text, so it counts for aria and copy.
- **Picture**:
  - `src = Mw("{uri}/views/imgo", amsV2Domain)`. 52909 `Mw` swaps the origin for `amsV2Domain` when the URL is an AMS URL.
  - Lightbox/gallery full size: the same URL with `/imgo` → `/imgpsh_fullsize`. It is added to the message gallery with `itemID = doc_id`.
- **Sticker**:
  - `src = uri.replace("static.asm.skype.com","static-asm.secure.skypeassets.com") + "/views/thumblarge?etag=v1"`.
  - `itemID` = the part of `uri` after `/items/`.
  - Not added to the gallery.
- **Component**: image 741265 `f`, with `itemType = http://schema.skype.com/AMSImage` and `isInlineImageWrapper:false`. `isImageInlineOrAttached = Messaging.enableImprovedImageHandling`. GIFs autoplay per `shouldAutoPlayGifs`. Width and height are parsed as ints.
- **Click**: opens the image lightbox (telemetry `messageOpenImage`, module `imageLightbox`).
- **Fallback**: no `uri`, or the element is not `uriobject` → `undefined` (not handled).
- **Preview**: "Sent an image".
### 6b. `SWIFT.1` Tenor GIF (289206 `SkypeTenorGifDeserializer`)
- **Wire**: `<URIObject type="SWIFT.1"><Swift b64="{base64(JSON)}"/></URIObject>`.
  - The JSON is `{attachments:[{content:{…}}]}`. Each `content` object is stringified, then parsed again.
  - The GIF content is `{dimensions:{width,height}, images:[{url, stillUrl, alt}]}`.
- **Size**: width = `dimensions.width` or **404**. If width > 404, it is scaled to 404 and height = floor(h·404/w).
- **Render**: image 741265 with `src = images[0].url`, `noAnimationSrc = stillUrl`, `alt`/aria = `alt`, `shouldAutoPlay:true`, `isGiphyPlaceholder:true`.
- **Fallback to the "Unsupported content" fallback card when**:
  - `url` contains `bot-framework.azureedge.net`, or
  - `url` is not an allowed image URL. 903222 `nD`: https, and the host is the statics host, the same origin, a host matching the tenant's allowed-image regex (setting, value unconfirmed), or `teams.microsoft.com/asm/…`, and the path does not contain `logout`. `data:image` URLs are also allowed.
- Missing `<Swift>`, a bad b64, or a missing `images[0]` → `undefined` (not handled).
- **Preview**: "📷 GIF" (`skype_message_preview_sent_a_gif`).

## 7. RichText/Media_GenericFile, RichText/Media_Video, Skype `Audio.1` (289206 `SkypeFileAttachmentDeserializer`)
- **Filter types**: `File.1`, `File.1/Excel.1`, `File.1/PDF.1`, `File.1/Word.1`, `File.1/Powerpoint.1`, `Video.1`, `Video.1/Message.1`, `Audio.1`.
  - **`Audio.1/Message.1` is caught earlier by the audio card (§8).**
  - These message types are always Skype (§1).
- **Wire**: `<URIObject type="File.1/PDF.1" uri="https://…/v1/objects/{id}" url_thumbnail="https://…/views/…" doc_id="{id}"><OriginalName v="report.pdf"/>…</URIObject>`.
  - Read: `uri` (required), `url_thumbnail`, `doc_id`, `<OriginalName v>`. The element must have children.
- **Mapped to one Teams file**: `{id: doc_id, shareId: doc_id, previewUrl: url_thumbnail, objectUrl = shareUrl = "{uri}/{view}", title: OriginalName, baseUrl: uri, type: <text after the first "." of the name>, serviceName:"skype"}`.
  - `view` = `views/original` (File), `views/video` (Video), `views/audio` (Audio).
- **Render**: the standard attachments component 544824 `C`.
  - With a `previewUrl` (thumbnail) it renders the image-preview tile.
  - Otherwise it renders the file chiclet 388605 (file-type icon, title, description).
  - **A video gets no inline player in this path**; it shows as a thumbnail or chiclet. What clicking does for `serviceName:"skype"` is unconfirmed. See §11 for the chiclet.
- **Expiry**: when `now − lastEditedDateTime > Gallery.skypeMediaTTL` days (default **30**):
  - `expiredFilePlaceholderText` = **"No longer available"** (`messaging:chat_media_expired_content`).
  - The chiclet shows it as its description and drops the action button.
  - A click shows an error toast **"This file is no longer available for download"** (`messaging:chat_file_expired_content`, intent Error, 4000 ms, urgent) and does nothing else.
- **Fallback**: no children, an unknown type, or no `uri` → `null` (removed).
- **Preview**: "Sent a file" / "🎥 Video" / "🎙 Audio message".

## 8. RichText/Media_AudioMsg and Teams voice messages
### 8a. Skype `Audio.1/Message.1` (289206 `SkypeAudioCardDeserializer`)
- **Wire**: `messagetype: "RichText/Media_AudioMsg"` (always Skype), `<URIObject type="Audio.1/Message.1" uri="https://…/v1/objects/{id}" duration_ms="12345">…</URIObject>`.
- **Mapping**: `{duration: round(duration_ms/1000) s, mediaUrl: "{uri}/views/audio"}`. No `objectId` is passed, so the transcript query runs with no id (unconfirmed what it shows).
- Sets `containsAudio = true`. Wrapped in a Flex, then the player 849161 (§8c).
- **Fallback**: no `uri` → `isContentUnsupported = true` and `null`. The message then shows the generic unsupported block (230655).
### 8b. Teams voice message (405072 `AudioCardDeserializer`, filter `itemtype="http://schema.skype.com/InputExtension"`)
- **Wire**: `RichText/Html` content with an element carrying `itemtype="http://schema.skype.com/InputExtension" itemid="{cardClientId}"` (tag unconfirmed).
  - `properties.cards` is a JSON string array. The entry with that `cardClientId` and `contentType: "application/vnd.microsoft.card.audio"` has a `content` JSON string such as `{"duration":"PT12S","media":[{"url":"https://…/v1/objects/{objectId}/views/audio"}]}`.
  - `duration` is ISO-8601 (`P…T{h}H{m}M{s}S`, decimal commas allowed; 877513 `K`).
  - `objectId` comes from `/objects/([^/]+)/views/audio/`.
- It is in the Teams list 721466 `cD` before the generic `CardDeserializer`.
- **Fallback**: bad JSON → `isContentUnsupported = true` → the generic unsupported block.
### 8c. Player (849161, `data-tid="AudioCardWrapper"`)
- **Download**: `downloadAmsItem(urlOrObjectId: mediaUrl, type: AudioCard)` (382411).
  - The worker does `GET {mediaUrl}` with `Accept: */*` and `ms-cv`, `authOptions {source:"asyncMediaService"}`. The auth header is unconfirmed (AMS token).
  - Retried on timeout/409/5xx up to `amsDownloadMaxRetryCount`.
  - The blob URL is fed to a hidden `<audio controls=false>`. Only one card plays at a time; starting one pauses the previous.
- **States**:
  - Loading: the card with a spinner, aria **"Loading a message."**
  - Error:
    - circular primary button, icon **ArrowClockwise** (filled), aria **"Try again"**;
    - red text **"We were unable to retrieve your message. Please try again."**;
    - the button retries the download.
  - Ready: a row with `gap.medium`, vertically centred:
    1. Circular primary button, icon **Play** / **Pause** (filled), `data-tid AudioCardPlayback-Play|Pause`. aria:
       - before playing: "Play message. Message is {{minutes}} minutes, {{seconds}} seconds long.";
       - while playing: "Pause message. {{minutes}} minutes, {{seconds}} seconds played.";
       - when paused mid-way: "Play message. {{minutes}} minutes, {{seconds}} seconds played.".
    2. Slider (569319), aria **"Audio message"**, max = duration (the `<audio>` duration, else the card duration), value = current second. Dragging seeks.
    3. Remaining time `MM:SS`, semibold, `min-width 40px`, `nowrap`, aria-hidden. It is computed per field (minutes and seconds separately, each clamped at 0).
    4. When `Messaging.enableAudioMessageTranscript` is on: a transparent button, icon **SlideTextEdit**, tooltip and aria **"View transcription"**. It opens a popover (`before-top`).
- **Sizes**:
  - Card padding `1rem 1.8rem` = 10px 18px (Teams 1rem = 10px). Its width rule is written `27.5 rem`, which is invalid CSS, so in effect there is no width.
  - With the visual refresh (186643 `r`), the radius is `--borderRadius2XLarge`.
  - Buttons are 30×30, with no shadow.
- **Transcript popover**:
  - GraphQL `audioMessageTranscript(objectId)` → worker `asyncMediaService.getTranscript` → `GET {ams}/v1/objects/{objectId}/views/transcript` (`Accept: */*`, `x-ms-client-version`).
  - Surface: max-height 390px, padding 4px 0.
  - Title **"Transcript"**: base200, semibold, NeutralForeground3, padding 8px 16px.
  - Copy button: icon **Copy**, aria **"Copy Transcript"**, disabled while empty. It shows the tooltip **"Copied to clipboard"** for 2000 ms.
  - AI line: **LightbulbFilament** + **"Generated by AI. Check for accuracy."**, or **"Generating..."** while loading with a progress bar.
  - Paragraphs: the transcript split on `\n`, base300 regular.
  - Body: min-width 300, max-width 320, max-height 386, scrolls, padding 12px 16px.
  - Error or empty: **"Transcription is temporarily not available."**
- **Chat list preview**: "🎙 Audio message" (`messaging:recent_conversations_sent_an_voice_message`).

## 9. `RichText/Media_Card` (bot, connector and workflow cards)

### Wire format
- `messagetype: "RichText/Media_Card"`, `contenttype: "text"`, sent by bots (`from` = `28:<botId>`), connectors, Workflows.
- `content` is XML whose root is `<URIObject>`. The card JSON travels in a `<Swift>` child:
  - preferred: `<Swift b64="BASE64(utf-8 JSON)"/>` (worker `getMediaCardFromMessage`: `XMLParser({ignoreAttributes:false}).parse(content).URIObject.Swift["@_b64"]`; client 49385 `D`: `DomUtils.getAttributeValue(swift,"b64")` → UTF-8 decode → `JSON.parse`).
  - fallback: the first text child of `<URIObject>` is JSON when it `trimStart().startsWith("{")` (49385 `Z`/`ee`).
  - Element names are matched case-insensitively on receive; the forward path normalises `uriobject|title|swift|description` to `URIObject|Title|Swift|Description` (721466 `ve`).
  - A human fallback text is present in the content; the client strips everything up to and including `cards.unsupported` (49385 `_`) and the preview strips `" - access it on https://go.skype.com/cards.unsupported. Card"` (223490 `R`). Exact attribute set of `<URIObject>` other than `Swift` is **unconfirmed** (e.g. `type="SWIFT.1"` is what the client itself builds in 49385 `Qm`: `<URIObject type="SWIFT.1" fromCDL="true">{escaped JSON}</URIObject>` and 9272 `u`: `<URIObject type="SWIFT.1">{encodeURIComponent(JSON)}</URIObject>`).
- SWIFT JSON (fields read by 740332/941065/worker):
  - `type`: `"message/card"` or `"message/card.carousel"` (carousel when `=== "message/card.carousel"`, 941065 `i`).
  - `attachments`: `[{contentType, content, appId?, templatedAppId?}]` — `content` is an object (49385 `j` stringifies it; 740332 parses it back).
  - `text` (optional): rich text shown above the cards.
  - `summary` (optional): used by the chat-list preview / search text (worker).
- Minimal example (content before base64):
  ```json
  {"type":"message/card","attachments":[{"contentType":"application/vnd.microsoft.card.hero","content":{"title":"Hello","text":"World","buttons":[{"type":"openUrl","title":"Open","value":"https://example.com"}]}}]}
  ```
  → `content`: `<URIObject type="SWIFT.1"><Swift b64="eyJ0eXBlIjoi…"/></URIObject>` (wrapper attributes unconfirmed).

### Renderer (740332 → 941065 → 511225 → 944311)
- 740332 `transform`: parse SWIFT; if any attachment's `contentType` is not supported (255529 `Bd` = every `Jf`) → `isContentUnsupported = isCardUnsupported = true` (placeholder, §25). Pushes the card's aria text (873869 `JR`) into the message text.
- `isSingleCardOnly` = SWIFT has `type`, is not a carousel, the attachment exists and has no Adaptive `metadata.webUrl` (924822 `X`); later cleared unless the sender is a bot (`641734.Ve(from, senderType)`) and the message has no feedback loop (`botMetadata.feedbackLoop.type` CUSTOM/DEFAULT or `feedbackLoopEnabled`) (923733 `He`).
  - Effect in 318259: reactions use the `"overlay"` placement; reaction pill `top:5px` (`top:-8px` with diverse reactions).
- Cards are not interactive (`disableInteractivity`) when the message was moved (`moveSourceThreadId`) or converted from a chat; forward-card copies disable actions and OpenUrl inside the forward dialog.
- **941065** (card list): returns nothing if both `attachments` and `text` are empty. Column flex, `gap.medium`, `clear:left/right`.
  - `text` → rich text (514637) above the cards.
  - carousel → Fluent carousel (829867 `FN`) with paddles; strings: intro "There might be more than one card on the carousel. Swipe on the touchscreen or use the carousel arrows to navigate", "Next", "Previous", position "Card {{index}} out of {{size}}". Full-width carousel when any card has `msteams.width:"full"`.
  - else a plain list (147602).
  - Per attachment: `hideCardBorder` = `content["x-request-no-border"]`; edge-to-edge = carousel full width, or `content["x-width"]==="stretch"`, or (in a team) `msteams.width:"full"`.
- **511225** (per card): looks up the bot's app (`getAppDefinitions`, GraphQL chat query `isOneOnOneBotChat`, group-copilot `allowInteraction`), accent colour = app `accentColor` (ignored if `#ffffff`), adds a result footer (58255/127570), dispatches actions (below).
- **944311 `Qn`** (frame):
  - Box `isCardRendererBox`: `display:block; position:relative; max-width:100%; overflow-wrap:anywhere; width:36rem` (**360px**); `margin-top:0.8rem` without a wrapper. Width **452px** at slot container ≥720px (`45.2rem`), **616px** when full-width (`61.6rem`), `width:100%` when edge-to-edge. Focus-visible border `1px solid --colorBrandForeground1`.
  - Accent strip (`isCardBorder`, when border shown): absolute, height **3px**, full width, top radii `--borderRadiusMedium`, colour = accent or `--colorNeutralStroke3`.
  - Card body (`isCard`): `width:100%`, background `--colorNeutralBackground1`, text `--colorNeutralForeground2`, **padding 16px**. Border: legacy `2px solid --colorNeutralStroke3` left/right/bottom with bottom radii medium; V2 (`enableAdaptiveCardLoopSharing`) `1px solid --colorNeutralStroke2`, radius medium. Hidden border → padding-left/right 0.
  - Adaptive card extra (`isAdaptiveCard`): background `--colorNeutralCardBackground`, `overflow:hidden`, radius `--borderRadiusLarge`; without wrapper `border:none; box-shadow:--shadow2`; container padding 2px.
  - Inner column `gap.small`, `role="group"`, aria label from 944311 `YL` (Adaptive: card text; Hero/Thumbnail/O365/Signin/Profile builders). Card `tap` action → whole card clickable (`cursor:pointer`).
  - Adaptive loader height 125px (`12.5rem`).

### Content types (810957) and per-type component (944311 `Ks`)
| contentType | supported when (255529 `Jf`, needs `enableCards`) | component |
|---|---|---|
| `application/vnd.microsoft.card.adaptive` | always | Adaptive Cards renderer (`Me.M`, adaptivecard-react chunk) |
| `…card.hero` | always | `me` (`data-tid="hero-card"`): title, subtitle, image (16:9 box, `padding-bottom:56.25%`), text (`--colorNeutralForeground1`, `white-space:normal`), buttons; column `gap.smaller` |
| `…card.thumbnail` | always | `he`: image **100×100** left of title/subtitle/text (text 12px, line-height 1.25); below 360px container the image stacks above with 8px gap; buttons below; `gap.small` |
| `…teams.card.o365connector` / `…card.o365connector` | always | lazy 388704 (loader 125px); edge-to-edge in channels |
| `…teams.card.list` | always | `st` (`data-tid="list-card"`): title, items (`section` / `list-item` with icon, title, subtitle, tap), buttons; `gap.medium` |
| `…teams.card.profile` | always | `Rs` |
| `…card.codesnippet` | `enableCodeSnippets` | code snippet (379122 `l`, Copy code) |
| `…card.videoMessage` | always | `VideoMessageCard` (compose) |
| `…card.oauth` | `enableGroupScopeBotSso` | converted to an Adaptive card (`Ht.c`) |
| `…card.signin` | `enableSignInCard` | `Yn` (`data-tid="signIn-card"`) |
| `…teams.card.file.consent` | `enableBotsFileSharing` | `Vn` |
| `…card.receipt`, `…card.audio` (in SWIFT), anything else | no | → unsupported placeholder |
- Hero/Thumbnail/List buttons (944311 `g`/`D`): at most **6** buttons (`r=6`), wrapped flex, container margin −4px, each button margin 4px, optional 16×16 button image; tooltip = title (+ "This is a card action with a link" for openUrl/signin).
- Images: AMS URLs and URLP-proxied URLs are fetched through the AMS/URLP image hook; failure icon `P6O` (unresolved name). URLP proxy URL form: `https://{urlp host}/v1/url/content?url={encodeURIComponent(url)}`, host from region GTM key `urlp`, default `urlp.asm.skype.com` (255529 `wt`/`vt`). Which images are rewritten in the chat timeline: **unconfirmed**.

### Adaptive Card host config (824631)
- fontSizes small 12 / default 14 / medium 14 / large 18 / extraLarge 24; weights lighter 300, default `fontWeightRegular`, bolder `fontWeightSemibold`; family `fontFamilyBase`.
- lineHeights 16 / 20 / 20 / 24 / 32. imageSizes small 36, medium 54, large 108. separator 1px `colorNeutralStroke1`.
- actions: `maxActions 6`, `buttonSpacing 8`, horizontal, left-aligned, ShowCard inline with `inlineTopMargin 16`.
- factSet table: columnGap 16, rowGap 6; stack: titleValueGap 0, rowGap 8.
- spacing: extraSmall 4, small 8, default 12, medium 16, large 20, extraLarge 24, padding 16. Input label spacing ExtraSmall.
- containerStyles (light/dark/HC tokens): default bg `colorNeutralCardBackground` (border `colorNeutralStroke2`); emphasis bg `colorNeutralBackground3`; accent bg `#f2f4fc` light / `#00061d` dark / `#000000` HC (border `colorBrandStroke2`); good `colorPaletteLightGreenBackground1`; warning `colorPaletteMarigoldBackground1`; attention `colorStatusDangerBackground1`.
- foreground: default `colorNeutralForeground1`, subtle `colorNeutralForeground3`, accent `colorBrandForeground2`, good `colorStatusSuccessForeground1`, warning `colorPaletteMarigoldForeground2`, attention `colorStatusDangerForeground3`; highlight `#ffedd6` light / `#4d2a00` dark.

### Actions (729520 `I6`; handler map 511225 `Qt`)
| card action `type` | handler | what happens |
|---|---|---|
| `openUrl` | 545049 | `https?://` or `mailto:` URLs (regex check when `enableSanitizeUrls`) go through safelinks/deeplink handling (Teams `…/l/…` links open in-app; `/l/task/…` and `/l/stage/…` open dialogs); otherwise `window.open(url,"_blank")` |
| `imBack` | 924759 `Sc` | posts a normal chat message via the send mutation: `{content:value, messageType:"Text"}`; in non-bot group chats `messageType:"RichText/Html"` with `<div><mention mri="{botMri}" type="bot" appid="{appId}">{name}</mention> {value}</div>` |
| `messageBack` | 455054 → 730589 | if `displayText`, first posts it as a chat message with `messageType:"BotMessageBack"`; then bot invoke with `name:"messageback"`, `text`, `value` |
| `invoke` | 730589 `TN` | bot invoke, `name` unset (task/fetch and tab/submit payloads ride in `value`) |
| `execute` (Action.Execute) | 246298 | `sendExecuteInvoke` → bot invoke with `name:"adaptiveCard/action"`; the response may replace the card |
| `refresh` | 563117 | Action.Execute refresh (gated by `enableRefreshInBotAdaptiveCard`) |
| `showCard`, `toggleVisibility` | 338406 | local only |
| `signin`, `executeAuthentication` | 29093 / 950406 | auth popup / SSO flow |
| `O365HttpPOST` | 667838 | GraphQL `submitO365Action` / `connectorHttpPostAction` |
| `pinTab` | 511225 `Ye` | WhoBot only: `createPlatformTab` mutation |
| `allowFileUpload` / `declineFileUpload` | 511225 `Ee` | `getBotFileUploadUrl` then `postFileUploadInfoAndUserConsent` |
- **Action.Submit mapping** (adaptivecard-react `De`): `data.msteams.type` → `messageBack` (`value` = data merged with inputs, `displayText`, `text`), `invoke`, `imBack` (`value`), `signin`, or `task/fetch` / `tab/submit` → `invoke`. **No `msteams` → `messageBack`** with `text` = data when it is a string, `value` = data (stringified). Action.OpenUrl → `openUrl`.
- **Bot invoke HTTP** (worker inner_services_i, `apiName:"botsinvoke"`): `POST {chatService}/v1/agents/{botMri}/invoke`, `content-type: application/json`, body
  `{name, appId?, text, messageType, value:<parsed JSON object>, imdisplayname, userAadToken, serverMessageId, clientMessageId, conversation:{id:threadId}, complianceData?:{action:{type,title}}}`.
  Headers: `X-MS-AutoRefreshRequestInThread: {threadId}` for automatic refresh, `MS-CV` when present. `threadId` = reply-chain-aware conversation id (197100 `a9`).
- Policy checks before an action (511225 `Ht`): federated chat, app blocked by policy/tenant, blocked by user, unsupported capability, app missing → footer error instead of the call.
- **Footer result text** (127570, `extensibility`):
  - success: "Your response was sent to the app" (Execute may show the bot's own message instead)
  - bot error: "Unable to reach app. Please try again."; other failure: "Something went wrong. Please try again."
  - unsupported: "Send your message first then select the button to perform this action."; power bar: "That action isn't supported here."
  - "This bot is disabled. Contact your IT admin for more information." / TFL: "This feature isn’t available yet in your version of Teams. We’re working on it."
  - "This action is unavailable because you are using Teams with an org-managed account."
  - "This card action is disabled because you've blocked {{appName}}." / "This card action is not supported by {{appName}}." / "This action isn't supported by {{appName}} in this context."
  - "Something went wrong. Make sure you've successfully added the app." / "This action can't be performed since the app does not exist or has been uninstalled." / "To interact with this card, you'll need to add the app." / "We were unable to add {{ appName }}. Try adding again or contact your IT admin for support".
- **"Updated"**: card messages (`Media_Card`, or `RichText/Html` with cards) always pass the details-row condition (318259 `ml`), so a bot edit shows "Updated" (messages-and-composer.md §6).

### Previews / aria
- Chat-list preview of a `Media_Card` with `imDisplayName`: "{{title}} message" (`bot_message_title_preview_suffix`); otherwise the text with the cards.unsupported tail removed. A message with cards and no text: "Sent a card".
- Screen-reader prefix "This is a card message." (`botcards_aria_label_message_header`).

### Measured (winpc, 2026-11-07; a card posted as a message-extension card in a group chat)
- Users can't send `RichText/Media_Card` (HTTP 400, "Client not allowed to send RichText/Media_Card message"). They can send `RichText/Html` with `properties.cards` (§10), which the desktop client renders with the same frame.
- Frame: 448 wide in an 892 px pane, NeutralCardBackground #FAFAFA, radius 6, shadow2. Content is 16 in at the sides and bottom and 26 from the top. Inside your own bubble the card is 17.3 in and 8 down, and the bubble ends 10.7 under it.
- Element spacing is a 12 px `ac-horizontal-separator`; `spacing: None` gives 0. A separator line sits 6 down in its 12 (0.67 px).
- Text:
  - Large Bolder is 18/24, weight 600, #242424. Default is 14/20. Small is 12/16. Subtle is #616161.
  - Accent text and links are #4F52B2 (BrandForeground1); markdown bold is 700.
- ColumnSet: an auto column holds its content (a small image is 36), then a 12 px gap.
- FactSet: titles 600, 16 to the values, rows 26 apart (20 + 6).
- An emphasis container is #F5F5F5 with padding 16.
- Actions: buttons 31.3 tall, padding 5 12, a 0.67 px #D1D1D1 border, radius 4, white, 14/20 semibold, 8 apart, 12 under the body.
- ShowCard:
  - opening it turns its button brand-filled with white text (aria-expanded);
  - the card opens 16 under the actions, edge to edge, #F5F5F5 with padding 16.
- Inputs (Fluent v9 in the card host, measured from a second card):
  - A label is 14/20 #242424, with the input 4 under it.
  - Input.Text is 32 tall (multiline 90, padding 6 12). It has a 0.67 px #D1D1D1 border, a #616161 bottom, radius 4, and text 12 in.
  - Input.ChoiceSet compact is a Fluent Combobox (placeholder, ChevronDown 20, 10 from the end). Expanded options are Radio rows: 32 tall, 8 apart, a 16 px indicator 8 in, and the label at 36 in #616161.
  - Input.Toggle is a Checkbox row of the same shape.
  - Input.Date is a DatePicker field, "Select a date..." with a calendar button.
- Table: a 0.67 px #E0E0E0 frame and lines between rows (no vertical lines). Cells are padded 8, at least 36 tall; the header row is 600. A 1:2 split gave 138.2 / 276.4.
- ImageSet: small images are 36, 10 apart. RichTextBlock bold is 600; highlight is #FFEDD6.
- Hero card (measured once winpc's client was restarted):
  - The frame is 452 wide, white, with a 0.67 px #E0E0E0 border and radius 4. Content is 16.7 in; the title is 26.7 down.
  - The title is 16/22, weight 600, #424242. The subtitle is 14/20, weight 600, #424242, 8 under the title.
  - The image is 16:9 (object-fit cover), 8 under the subtitle. The text is 14/20 #242424, 8 under the image.
  - The buttons come 4 under the text: 32 tall, padding 0 20, a 0.67 px #C5CBFA border, radius 4, white, 14/20 semibold #5B5FC7, 8 apart.
- Thumbnail card (measured 2026-11-12, "OST TEST 114"): as the hero card, but its text is 12/15 #424242.
- List card (`…teams.card.list`, measured 2026-11-12, "OST TEST 115"): the hero card's frame and title. Items start 26.7 under the title, 4 further in, and sit 19.7 apart:
  - A result item has its title (14/18.67, weight 600, #424242), then 2 lower its subtitle (12/16 #424242). Its tap is clickable.
  - A section is 12/16, weight 700, #616161.
  - Buttons sit 26.7 under the last item.
- O365 connector card (`…teams.card.o365connector`, measured 2026-11-12, "OST TEST 116"):
  - A 3 px bar in its `themeColor` (radius 4 4 0 0) sits on top of the hero card's frame, 452 wide.
  - The title is 16/22, weight 600, 26.7 down. The text is 14/20, 8 under it.
  - Each section's activityTitle (600), activitySubtitle and activityText (14/20) come 8 after what's above, then 10 apart.
  - Facts follow: the name (600), then the value 10 after the widest name.
  - Everything is #424242, with 26.6 below the last line.
  - An `OpenUri` potentialAction showed no button.
- Card images arrive rewritten to Teams' URL proxy, `https://{region}.asyncgw.teams.microsoft.com/urlp/v1/url/content?url={encoded}`. It answers 401 without the skype token (`Authorization: skype_token …`, as AMS).
- Important (`properties.importance: "high"`):
  - The name line gets "IMPORTANT" (12/16, weight 600, #D13438, uppercase), 8 after the time.
  - A 16 px Important20Filled badge in #D13438 sits 4 from the bubble, 12 down, on the bubble's start side for your own messages.
  - Urgent was not sent live: it re-notifies the recipient every 2 minutes for 20.
- Teams web showed such cards as a loading skeleton, then hid them; the desktop client rendered a card with display elements only. Inputs could not be compared live.

## 10. Cards inside `RichText/Html` messages (`properties.cards`)
- Used by message extensions, app link unfurls, bots that send HTML, SSO cards, code snippets, voice messages.
- `content` holds a placeholder per card:
  `<span itemid="{cardClientId}" itemscope="" itemtype="http://schema.skype.com/InputExtension"><span itemprop="cardId" content="{cardClientId}"></span></span>`.
- `properties.cards` = **JSON string** of `[{cardClientId, contentType, content:<object>, appId?, appName?, appIcon?, locale?, userSpecificContent?}]`. The worker (`toCards`, inner_services_i) maps it to GraphQL `message.cards[]` with `content` re-stringified.
- 457859 `CardDeserializer`: finds the card by `cardClientId`; unsupported type → placeholder; code snippet → 379122 with "Copy code"; else 717287 `e9` (same frame/actions as §9, `moduleType` input-extension, optional app footer when `enableMessageExtensionCardFooter`).
- 405072 `AudioCardDeserializer`: `contentType:"application/vnd.microsoft.card.audio"`, content `{duration, media:[{url}]}`; AMS object id from `/objects/{id}/views/audio`; renders the voice-message player 849161 (§8).

## 11. `RichText/Files` and file attachments in any message
**Wire**:
- `properties.files` is a JSON **string** holding an array.
- Send side (68245 `Kr`): one object per file, then one per channel deeplink:

```json
[{"itemid":"<id>","fileName":"Report.docx","fileType":"docx",
  "fileInfo":{"itemId":"<driveItemId>","fileUrl":"<objectUrl>","siteUrl":"<baseUrl>",
              "serverRelativeUrl":"","shareUrl":"<shareUrl>","shareId":"<shareId>"},
  "fileChicletState":{"serviceName":"<svc>","state":"<state>"},
  "@type":"http://schema.skype.com/File","version":2,
  "id":"<id>","baseUrl":"<siteUrl>","objectUrl":"<url>","openUrl":"<url>","type":"docx","title":"Report.docx",
  "state":"<state>","altText":"…","chicletBreadcrumbs":{"sourceTeamName":…,"sourceChannelName":…},
  "providerData":…,"botFileProperties":{"url":"<downloadUrl>"},"isUploadError":false,
  "progressComplete":100,"permissionScope":"…","partialSuccessError":…,
  "filePreview":{"previewUrl":"…","previewHeight":0,"previewWidth":0},
  "sharepointIds":…,"publication":…,"site":…}]
```

- Constants (86706): `@type` = `http://schema.skype.com/File` (`tt`), `version` = **2** (`X`).
- A deeplink entry has `fileType:"deeplink"`, `type:"deeplink"` and `fileInfo.serverRelativeUrl`/`siteUrl`/`fileUrl`.
- **Receive** (71026 `Q`, worker → GraphQL `File`):

| GraphQL `File` field | read from |
|---|---|
| `id` | `id` |
| `itemId` | `itemid` |
| `baseUrl` | `baseUrl` |
| `chicletBreadcrumbs` | `chicletBreadcrumbs` |
| `objectUrl` | `objectUrl` |
| `shareId` | `fileInfo.shareId` |
| `shareUrl` | `fileInfo.shareUrl` |
| `openUrl` | `fileInfo.openUrl` |
| `type` | `type` |
| `title` | `title`, falling back to `fileName` |
| `previewUrl`, `previewHeight`, `previewWidth` | `filePreview.*` |
| `state` | `fileChicletState.state` |
| `serviceName` | `fileChicletState.serviceName` (only values in enum 51628 `IS`) |
| `progressComplete`, `permissionScope`, `sharepointIds`, `publication`, `site` | same names |

  - Another worker path (search/gallery) also reads `fileInfo.fileUrl` and `fileType`/`fileName` as fallbacks.
  - Entries with `type:"deeplink"` become `message.deeplinks` (86706 `Dt`): `{id, title, state, serverRelativeUrl, channelId, siteUrl, objectUrl}`.
- **Body**:
  - `RichText/Files` gets no special handling in the worker or renderer.
  - In 923733 `Ft` it falls to the default branch: unless a file is an image (`695004 ZZ`), the `content` string is rendered as a plain `<p>` text node, with no HTML parsing.
  - Attachments always come from `message.files`.
  - What legacy senders put in `content` for this type is unconfirmed.

**Attachment grid** (544824 `Fn`, rendered by 318259 `_renderAttachments` when `files.length`):
- Not rendered when `message.isForwardedMessage` is set (the forward card shows its files instead) or when DLP blocks the content for a receiver.
- Root: `data-tid="file-attachment-grid"`, `id="attachments-<messageId>"`, flex wrap.
  - When every attachment is an image with a preview: `data-message-object="image-attachment"`, plus `data-message-object-touches-top-boundary` / `-bottom-boundary` when there is no text above or below.
  - Those flags come from 318259: top = no text and no deeplinks; bottom = no URL preview. The bubble uses them to drop its padding.
- Style variables (103464):
  - `isMessageAttachments` = `clear:left; padding-top:8px; max-width:100%`.
  - `isMercuryMessageAttachments` (when `enableMercuryShell2_5`) = `padding-top:0; column-gap:6px; display:inline-flex`.
  - With previews: `display:grid; grid-gap:8px; padding-top:8px`, columns `repeat(auto-fit, 240px)` (190px below 480/640), max-width 736px (≥1440) / 488px (≥1280) / 240px / 190px.
  - With `enableResponsiveFwDeprecation` (live true) these are container queries: ≥1280 488px, ≥720 240px, ≥640 190px, ≥480 240px, ≥360 grid 190px.
- An all-images set renders as a collage (`267039 Oe.e`) when `enableImageCollageForAttachments` is on (live ?) and no rich previews are shown.
- In federated chats with `disableChicletRenderingInFederatedChat`, files are rendered as **plain links** (`<a href=shareUrl||objectUrl>title</a>`). A link that already appears in the body is skipped.

**File chiclet** (388605, base style `fileChiclet` in 103464):
- Box: height **48px**, padding `0 12px` (`0 4px 0 12px` in edit mode), max-width **364px**, radius `borderRadiusLarge`, `box-shadow: shadow2`, transparent 1px border, margin `0 4px 4px 0`, background `background1`.
  - Hover → `background`; active → `background2`.
  - Failed upload → `red[100]` background.
  - With `noFilePreview`/`previewAsIcon` the width is **320px**, or **240px** when the message has more than `me.a` files.
  - Rich or interactive preview: 320×236, or 240×191 when there are many files. Images with dynamic styles: fit-content, 140–400px wide, 200px tall. Stream/interactive: 16:9.
- Content:
  - File-type icon (`153e3 Qo`: Word/Excel/PowerPoint/OneNote/PDF/Visio/video/Loop (`fluid`,`loop`)/Page/md/Whiteboard/SharePoint list…, generic otherwise). These are Office file-type icons, not Fluent system icons.
  - Title (`file.title`), then a description line (`$` component: permission and breadcrumb text; exact text not traced).
  - `actionButton` = ··· menu.
  - Upload progress uses `progressComplete`.
- `uriScheme` per type (used to open in the desktop app): `ms-word`, `ms-excel`, `ms-powerpoint`, `onenote`, `ms-visio`.
- aria (strings `files:`):

| state | key |
|---|---|
| uploading | `files_chiclet_fileUploading_sender/receiver_accessibilty` |
| upload failed | `files_chiclet_fileUploadFailed_sender/receiver_accessibility` |
| normal | `files_fileAttachmentAriaLabelView` / `files_externalFileAttachmentAriaLabelView` ({{fileName}}) |
| rich preview | `files_rich_file_preview_suffix` |

- **Click**: opens the file with the user's file-open preference (Teams / Browser / Desktop app). Image types open the lightbox gallery when `enableLightBoxForRichFilePreviewForImages` is on.
- **··· menu** (359380 `qe`, in order; unavailable items are dropped; `actionContext:"ChatChicletActionMenu"`):

| # | key | en-us |
|---|---|---|
| 1 | open-with submenu (641342) | **"Open in"** ▸ `edit_in_teams` "Edit in Teams" (with "default" when it is the preference) / Browser / Desktop app, separator, "Change default". Browser and desktop item texts not traced |
| 2 | `present_to_teams` | (flag `enablePresentToTeamsActionForChiclets`) |
| 3 | `copy_image` | (images) |
| 4 | `download` | "Download" (`files_menuLabelDownload`) |
| 5 | `quick_share` | (flags `enableChicletQuickShareAction` + type) |
| 6 | `copy_link` | "Copy link" (`files_menuLabelCopyShareLink`); may open the Copy-link dialog (`enableLaunchCopyLinkDialogOnContextClick`) |
| 7 | `add_to_loop_workspace` | "Add to Loop Workspace" |
| 8 | `favorite` | |
| 9 | `delete` | (`enableFileDeleteAction`) |
| 10 | `make_as_a_tab` | |
| 11 | `workflows` | |
| 12 | `summarise_file_copilot` | |
| 13 | `go_to_chat` | "Go to chat" (shared-files tab only) |

- **Fallbacks**:
  - If the chiclet throws, the error boundary (330096) renders `<a href=shareUrl||objectUrl target=_blank>{title||href}</a>`, or nothing when that URL is already in the body.
  - Expired file: `expiredFilePlaceholderText` as the description.

### `<a itemtype="http://schema.skype.com/HyperLink/Files">` in the body (798787)
- `itemid` must match a `message.files[].id`, and every URL attribute must pass the safe-URL check (52909 `D$`). Otherwise the deserializer does nothing.
- Renders a safe link (`822641`); click calls the file-open action (16622) instead of navigating. `title` attribute falls back to href.

### ThreadActivity/FileAdd (75579 `Pa`)
- Control row, only when `FluidThread.enableFileAddControlMessage` is on (live ?) and the content has `<type>loop</type>` and `<subtype>loopthread</subtype>`. Anything else → no row.
- Text: `<0><0></0></0> have been created in this chat.`, where the inner link reads **"Notes"**. aria: "Notes have been created in this chat."
- Link click: with `enableFluidThreadAsTab` it opens the chat Notes tab; otherwise it toggles the info pane `infoPaneType:"chatfluidthread"`. Disabled for non-members.

## 12. Collaborate (Loop component message)
**Wire**:
- `content` is HTML with one `<a itemtype="http://schema.skype.com/FluidLink" href="<loop url>">title</a>`, optionally with `itemprops` (escaped JSON `{sourceType:"Paste"|"Compose", contextType:"NonEmbed"|"Embed"}`).
- `properties.cards` holds **exactly one** card whose `content` JSON has `componentUrl`.
**Render**:
- 318259 and 923733 check `713611 e_(chatType, allowFluidCollaborate, fluidSettings, licenseType)`:
  - chat: `fluid.loadEnabled` + tenant Loop setting + edu rule;
  - channel: `embedModeLoadEnabled && loadInChannelEnabled`.
- If allowed, 602214 `V`: the preprocessor reads `cards[0].content.componentUrl`; when there is none → `isContentUnsupported`.
- Otherwise it renders `W` (lazy `fluid-message-container` → `@fluidx/loop-page-container`) with `contextType:"NonEmbed"`, `sharedHeaderV2Id:"messageSharedHeader"`, scenario `FluidLoadMessage`.
- If the domain check fails (`enableLoopDomainRestriction`), it shows the raw URL as a link instead.
- Loading placeholder (802652):
  - Box: column flex, background `NeutralBackground1`, border `1px solid NeutralStroke1`, radius **12px**, margin `9px 0 7px`, padding 1px; `width:100%` when expanded.
  - Header (629024): padding 16px, side margins 6px, max-height 48px, shimmer Loop icon (20×20), then the inner shimmer.
- Header (629024):
  - Loop icon **20×20**.
  - **"Loop component"**: small, semibold, `NeutralForeground2`. It becomes a subtle link (`fontSizeBase200`, 600, `NeutralForeground2Link`) with tooltip **"Open in browser"** when an open handler is given.
  - Optional dismiss button (Dismiss icon, aria "Dismiss").
  - The live component UI (title, content, actions) comes from the external Loop package and is not in the Teams bundles.
- Fallbacks:
  - Unsupported → 230655 with **"This content is currently not supported."** (no icon for Collaborate). The generic text for other types is "Go back to the main window to see this content." with a 32px icon (639401 `Fh`).
  - When hydration is not allowed, `Collaborate` still takes the HTML path (923733 exclusion list), so the FluidLink anchor renders as an ordinary link.
- a11y text pushed: "Message containing a Loop component." (`tmp_messages_a11y_header_message_with_fluid`).
- With `enableQuotedReplyServiceGeneration` **off** (live: on), 604685 fetches the Loop file title (994265, `fileDetailsViaGraphApi`) for quote and forward previews.

## 13. Embed (Loop embed card)
**Wire**:
- `content` contains `<span itemtype="http://schema.skype.com/FluidEmbedCard" itemid="<cardClientId>">`. The auto-embed variant is `<a itemtype="http://schema.skype.com/FluidAutoEmbedLink" href=…>`.
- `properties.cards[]` has an entry with `contentType:"application/vnd.microsoft.card.fluidEmbedCard"`, `cardClientId` = itemid, and `content` = JSON string `{componentUrl, sourceType, …}`.
**Render** (459203):
- Only when `messageType === "Embed"` and not in a channel message body.
- It finds the card by `cardClientId` and checks the URL (353927 `DP`).
- If `vX(containerType, allowFluidCollaborate, fluid, licence)` passes (`embedModeLoadEnabled`; in channels also `loadInChannelEnabled`) → same Loop host as Collaborate, with `contextType:"Embed"`.
- Auto-embed links need `enableUnfurlFluidAutoEmbedLink` (live true); `enableExpandedWidthForAutoEmbedLink` makes them full width.
- **Fallback**:
  - With `sourceType:"Compose"` → a plain link (427415): `<a href=componentUrl itemtype=…/FluidLink target=_blank>`. Its text is "Loop component", or the anchor text for auto-embed.
  - Otherwise nothing, and the default HTML is shown.
  - Invalid card JSON → logs an error and the default render is used.
- html-canvas-container URLs need `enableHtmlCanvasContainer`, or they fall back to the link.

## 14. Link previews (`properties.links`)
**Wire**:
- `properties.links` = JSON string array, built on send by 68245 `Or` = `[...Et(urlPreview), ...embeddedLinks]`:

```json
[{"@type":"http://schema.skype.com/HyperLink","itemid":"0","url":"https://example.com/",
  "previewenabled":true,
  "preview":{"previewurl":"<thumbnail>","previewmeta":{"width":1200,"height":630},
             "title":"…","description":"…"}}]
```

- Alternative `properties.urlpreviews`: `[{value:{url,title,description,thumbnail,thumbnail_meta:{width,height}}}]`. `previewEnabled` = thumbnail present.
- **Receive** (86706 `kt`):
  - `urlPreview` = the **first** parsed entry `{url, thumbnail, title, description, previewEnabled, thumbnailMeta}`. URL and thumbnail are kept only for http/https (plus `blob` for thumbnails).
  - `embeddedLinks` = entries carrying `fileShareUrlMeta` or `recapSharingLinkMeta`, plus meeting-recap links found in content.
**Render** (318259 → 361558 `Nt`). Shown only when all of these hold:
  - `message.urlPreview` is set, `enableLinkHoverPreviews` is off (live false), and this is not a Copilot chat from self;
  - connected experiences are enabled and `previewEnabled` is true;
  - the preview is valid (526233 `Cn`);
  - `previewUrl` (href of the **first** `<a>` in the body, from 784122) equals `urlPreview.url` after HTML-unescape.
- Variants:
  - Teams meeting join URL with `enableCalendarMeetingJoinUrlUnfurling` → meeting card (861964).
  - Meeting-recap sharing link with `enableRecapSharingLinkCard` → recap card (215364).
  - Otherwise the standard card.
- **Card** (25636 `me`, `data-tid="url-preview"`):
  - Wrapper: margin `6px 0 6px`, max-width **460px**. The whole card is a safe link to `url` (aria = title or url, no underline).
  - Container: radius `borderRadiusLarge`, background `NeutralBackground4`, `shadow2` (no shadow in high contrast).
  - Thumbnail: left, **120×96**, min-width 76px, left corners rounded `borderRadiusMedium`, alt "Url Preview for {{title}}". Collapsed (app tip shown) 76×60.
  - Body: background `NeutralBackground2`, padding `8px 12px`, flex 1, column.
    - Title: semibold, one line, ellipsis.
    - Description: small, clamped to 2 lines.
    - Hostname: small, `NeutralForeground3`, pushed to the bottom (`margin-top:auto`), 2 lines.
  - Header row gap `spacingHorizontalM`.
  - Loading placeholder: the same 120px + 340px boxes, 96px tall, `NeutralBackground3` / `NeutralBackground2`.
- **Remove (sender only)**:
  - Button: 20×20, transparent, Dismiss icon, `NeutralForeground2`, aria "Remove URL Preview".
  - Calls GraphQL `updateMessageLinks(convId, messageId, links)`. `links` = the links JSON rebuilt with the preview's `previewenabled:false`, plus the `embeddedLinks`.
  - The worker sends this as a message-property update with name `links` (`setMessageProperty`). By the existing pattern that is `PUT {chatsvc}/v1/users/ME/conversations/{conv}/messages/{id}/properties?name=links`; the exact URL and body wrapping are unconfirmed.
- Optional app-suggestion tip (`enableUrlAppSuggestions`): a 20×20 app icon, the `url_suggestion_tip` text and a link button.
- Fallback: when previews are not allowed (`areUrlPreviewsAllowed`, live true) or there is no title, nothing is shown.

## 15. Quoted replies inside a message
**Wire**:
- In `content`:

```html
<blockquote itemscope itemtype="http://schema.skype.com/Reply" itemid="<quotedMessageId>">
  <strong itemprop="mri" itemid="8:orgid:<guid>">Display Name</strong>
  <span itemprop="time" itemid="<epoch ms>"></span>
  <p itemprop="preview">preview text</p>
  <!-- optional --><span itemprop="emojis"><span alt="😀" itemprop="grinning" itemid="<index>" itemtype="false"></span></span>
  <!-- optional, service generated --><span itemprop="isReplyDeleted"></span>
</blockquote>
<p>reply text</p>
```

- `properties.qtdMsgs` = JSON `[{messageId, sender, time, sharedRefId?, replyChainId?}]` (68245 `Xr`). On receive the client also gets `quotedMessages[].validationResult`.
**Render** (331955 → 977647):
- Requires itemid, preview, name and mri; otherwise the default HTML is kept.
- With `isReplyDeleted` (when `enableQuotedReplyServiceGeneration`, live true) → tombstone `data-tid="quoted-reply-deleted-tombstone"`, italic **"This message has been deleted."**, padding `5px 11px 5px 1px`.
- **Card** (`data-tid="quoted-reply-card"`, `data-message-object="quoted-reply"`, role group, tabIndex 0). Two styles, depending on `enableStandardizedMessageChiclets` (live ?):

| style | look |
|---|---|
| standardized (`root`) | background `NeutralForegroundInverted`, radius Medium, `shadow2`, margin `4px 0`, padding `8px 8px 8px 16px`, `width:fit-content`, max-width 100%. A **2px left bar** (`::before`, inset 4px top/bottom/left, radius 2px, `NeutralStroke1Hover`). Header (component 1743/`xe.b`): **TextQuote** icon, author name, date |
| legacy (`rootLegacy`) | background `NeutralBackground2`, border `1px solid NeutralStroke3`, radius Medium, `shadow2`, padding `3px 5px`. A separate bar element `quotedReplyLine` (3px `NeutralStroke1Hover`, radius 1.5px). Inner padding `3px 2px 5px` |

  - Visual refresh: radius `borderRadius2XLarge`, padding-top 9px.
  - Name and timestamp: `fontSizeBase200`, regular, `NeutralForeground3`, `lineHeightBase200`; name is one line, gap "smaller".
  - Timestamp: `formatDateTime(date, {day, month, year, hour, minute})` (494393 `mT`), e.g. "11/6/2026 10:32 AM".
  - Preview: `fontSizeBase300`/`lineHeightBase300`, padding-top 1px, clamped to **2 lines** unless `enableRemoveQuoteElipsis`. Emojis are re-inserted from the `emojis` list. An empty preview shows **"Replied with quote"** when `enableEmptyQuotedReplyPreviewPlaceholder` is on.
- aria: "Begin Reference, {{preview}}, {{userName}}, {{datetime}}, End reference" (no-date variant without datetime). Screen-reader text "Begin quote"/"End quote" with `enableAccessibleQuotedMessages`.
- **Click / Enter**:
  - Queries the quoted message (GraphQL `message(convId, messageId[, replyChainId])`).
  - In the same reply chain with threading → highlight in place (`updateDeeplinkedMessageId`).
  - In channels → `messageById` navigation event.
  - Otherwise → `chat.chatById(convId, {messageId, focusOnLoad: DeeplinkedMessage, replyChainId, …})`.
  - Nothing happens if the message is not found.
- **Unverified quotes**:
  - With `enableQuotedReplyValidation` (live true), a quoted id whose `validationResult` is `NOT_VERIFIED`, on a message newer than `quotedReplyValidateAfterTimestamp`, and with no more than `quotedReplyValidationMaxCount` (default 5) quotes, sets `hasUnverifiedQuotedMessage`.
  - The banner shows only with `enableQuotedReplyValidationUI` (live **false**): a Warning icon (regular) and "Unable to verify the content of this message. Proceed with caution."
  - Per quote, `isNonCompliant` (service generation; status Delivered/Received; arrival after the validation start) adds an info icon with tooltip "This quoted message isn't verified by Teams."

### Skype quoted reply (289206 `SkypeQuotedReplyDeserializer`, tag `quote`)
- **Wire**: `<quote author="8:live:x" authorname="Jane" timestamp="1700000000" conversation="19:…" messageid="1700000000123"><legacyquote>…</legacyquote>quoted text<legacyquote>…</legacyquote></quote>`.
  - `timestamp` is in seconds (×1000).
  - **Preview text** is built from the children:
    - `legacyquote` is skipped;
    - `uriobject` gives the §1 preview strings;
    - `ss` gives `utf`/`alt`, or `type`, or "📷 Emoji";
    - `contacts` gives " Sent a contact card";
    - `location` gives "📍 Location";
    - `at` gives its text, or "Everyone" for `id="*"`;
    - `br` gives a space;
    - text is kept;
    - then 390776 `Fj`.
  - **The preview is empty when the quote has fewer than 2 child nodes.**
- **Render**: the standard quoted-reply card 977647 `Z` `{from, messageId, preview, timestamp, userName}`, with clicks disabled for moved messages. Its aria is pushed as "Begin Reference, {{preview}}, {{userName}}, {{datetime}}, End reference".
- **Skype forwarded** (`isSkypeForwardedMessage`): rendered instead as the forward card 953683 `TA` with `{id: messageid, content: sanitized preview, from: "8:"+author, messageType:"RichText", convId: conversation}`.
- **Fallback**: `messageid`, the preview, `authorname` or `author` missing → the Skype fallback card ("Unsupported content", Warning).
- Other Skype body elements:
  - `<ss type>`: emoticon (118746), medium.
  - `<at id>`: mention. `id="*"` → "Everyone" (`peoplePicker:compose_mention_everyone_tag`). The own id or `*` gets the "me" style.

## 16. Forwarded messages
**Wire**:
- The message is ordinary `RichText/Html`. Its `content` holds `<blockquote itemtype="http://schema.skype.com/Forward">…original HTML…</blockquote>` (markers in 18823), followed by any comment.
- `properties.originalMessageContext` = JSON `{originalSender, originalSentTime, messageId, parentMessageId, messageType, originalThreadId, subject, isDeleted, files…, cards…, announcement…}`.
- Multi-forward (`enableForwardMultiselectConsumption` + `additionalMessageContext`): `originalMessageContext`, `originalMessageContext1` … up to `forwardMultiselectMaxAllowedForwardCardsPerMessage` (default 100). Each one is paired with the n-th Forward blockquote.
- The worker (61388) produces `forwardedMessageContext[]` with these fields:

| `forwardedMessageContext` field | source |
|---|---|
| `originalSenderMri` | `originalSender` |
| `originalArrivalTime` | `originalSentTime` |
| `originalMessageId` | `messageId` |
| `originalParentMessageId` | `parentMessageId` |
| `originalMessageContent` | the blockquote HTML |
| `originalMessageType` | `messageType` |
| `originalThreadId` | `originalThreadId` |
| `originalChannelPostSubject` | `subject` |
| `originalMessageFiles` | from the context |
| `originalMessageCards` | from the context |
| `originalMessageContains.fluid` | blockquote contains a Fluid itemtype |
| `originalAnnouncement` | from the context |
| `originalMessageIsDeleted` | `isDeleted` |

- `originalMessageContains.mediaCard` is read by the renderer but not set in 61388 (unconfirmed where it comes from).
**Render** (721466 `ForwardCardDeserializer` → 953683 `TA`):
- One card per Forward blockquote, in order. It needs `originalMessageId`, `originalSenderMri` and `originalArrivalTime`; otherwise the blockquote renders as normal HTML.
- The inner content is sanitized and re-rendered with the normal pipeline. Its type is Embed if fluid, MediaCard if a media card, Markdown if markdown, otherwise HTML.
- **Card** (`data-tid="forward-message-card"`). Two styles, depending on `enableStandardizedMessageChiclets` (live ?):

| style | look |
|---|---|
| standardized | 1px `NeutralStroke1` border, radius Medium, padding `8px 8px 8px 16px`, margin-top 8px, background `NeutralBackground1`, the same **2px left bar** as quotes, `width:fit-content`, max-width 100%, `overflow-x:auto` |
| legacy | the same border and background, padding 12px |

  - Full width in the forward dialog, for multiselect, or for Embed.
- **Header**:
  - **ArrowForward** icon (16px).
  - Avatar (size "smallest", no presence).
  - Author name: small, `NeutralForeground3`, one line. Bots show `appMetaData.name`.
  - Timestamp `mT` format: `NeutralForeground3`, nowrap.
  - When deeplinking is possible (`enableForwardDeeplinkInChat`, or `…InChannel` for `thread.tacv2`/`thread.skype` after `minForwardDeeplinkInChannelBuild`), the timestamp is a link with tooltip "Go to original message". Otherwise the tooltip is "Go to original message is unavailable".
  - The standardized header instead has a separate **"View original"** link (`colorBrandForegroundLink`).
- **Deeplink URL**:
  - Channel: `https://teams.microsoft.com/l/message/{origConv}/{msgId}?parentMessageId={parent||msgId}&forwardedArrivalTime={t}&isForwardDeeplink=true`.
  - Chat: `…/l/message/{origConv}/{msgId}?[parentMessageId=…&]context=%7B%22contextType%22%3A%22chat%22%7D&isForwardDeeplink=true`.
- Below the header:
  - Announcement banner, if any.
  - Channel post subject: `fontSizeBase500`, semibold.
  - Content: links in BrandForegroundLink with underline, plus styled code/pre/blockquote/table.
  - Original files: attachment grid 544824.
- Original deleted → *"This message was deleted."* (em).
- aria: "Begin Reference, {{subject}} {{preview}}, {{authorName}}, {{datetime}}, End reference".
- The parent message's own attachment grid is suppressed when `isForwardedMessage`.

### Shared-to-main / replied-in-thread label (`sharedFromMessageId`, `sharedToMessageId`)
- This is **not** a forward label. 318259 `_renderSharedMessageLabel` → 288364, which needs `enableSendToL1MessageLabel` (live ?).
- Shown when `sharedToMessageId` is set, or when `sharedFromMessageId`, `sharedFromReplyChainId` and `sharedFromThreadPreview` are all set.
- Text: `fontSizeBase200`, `NeutralForeground3`, padding-bottom 8px. Icon `fontSizeBase400` with a 4px end margin.

| case | icon | text |
|---|---|---|
| `sharedToMessageId` | ChannelArrowLeft | "Also sent to channel" (channel) / "Also sent to chat" |
| from a thread | ChatMultiple | "Replied in thread: <link>{{sharedFromThreadPreview}}</link>" |

  - The link has tooltip "Go to thread" and opens the thread. The title updates live from the `replyChainEvents` subscription.
- `sharedFromMessageId`/`sharedToMessageId` also break grouping (434910).

## 17. `RichText/Media_CallRecording` (cloud recording)

### Wire format
- `messagetype: "RichText/Media_CallRecording"`, `content` = XML. One recording produces several messages over time with the same `callId`:
  start (`code="0" status="Initial"`), stop (`code="202" status="ChunkFinished"`), result (`code="200" status="Success"` or an error code), retries (`status="ExportRetryStarted|ExportRetrySuccess|ExportRetryFailure"`).
- The UI sanitizes `content` with DOMPurify, `PARSER_MEDIA_TYPE: "application/xhtml+xml"` (so it must be well-formed, case-sensitive XML), allowed tags = 856564 `Gl`, attributes = `iR`. All lookups use `getElementsByTagName` (any depth), so nesting does not matter to the client.
- Elements and attributes the client reads (420044):

| element | attributes read | meaning |
|---|---|---|
| `URIObject` | `url_thumbnail` (https only) | thumbnail |
| `RecordingStatus` | `code` (int; 0 / 202 / 200 / 503 / 400 / 403 / 500…), `status` (`Initial`, `ChunkFinished`, `Success`, `Failure`, `ExportRetry*`, `botData`, `tokenConversion`), `subCode`, `shortChunk="True"` | state |
| `RecordingContent` | `timestamp` (ISO start), `duration` (`hh:mm:ss[.fff]`), `contentTypes` (`Recording` \| `Transcript` \| `Recording+Transcript`), `canVideoExpire="true"` | content; **a message without `contentTypes` is ignored** (`isLegalRecordingMessage`) |
| `item` (many) | `type` + `uri`; for ODB also `driveId`, `driveItemId`, `id` | `type="video"` → Stream `url`; `amsVideo` → `downloadUrl`; `amsTranscript` → AMS transcript URL; `onedriveForBusinessVideo` → `odbUrl`, `driveId`, `driveItemId`; `onedriveForBusinessTranscript` → `transcriptUri`, `odspTranscriptId`, `transcriptDriveId`, `transcriptDriveItemId`. Every URI must be https (`q.Jf(uri,["https"])`) or it is dropped |
| `Id` (many) | `type`, `value` | `callId`, `callLegId`, `chunkIndex`, `StreamVideoId`, `AMSDocumentID`, `destinationListContainsOnlyMTR` |
| `ExportResult` | `type` = `ExportToStream` \| `ExportToOnedriveForBusiness` \| `NoExport` | export target |
| `RecordingInitiatorId` | `value` (MRI), `isAutoRecording="True"` | initiator |
| `RecordingTerminatorId` | `value` | who stopped it |
| `RecordingStorage` | `type` = `RecordingInitiatorOneDrive` \| `MeetingOrganizerOneDrive` \| `MeetingCoOrganizerOneDrive` \| `SharedSharePoint`; `userId` | owner (owner MRI = `userId`, prefixed with Calling setting `userIdPrefix` when it does not start with `8:`) |
| `MeetingOrganizerId`, `MeetingOrganizerTenantId`, `CallProcessingId`, `SessionEndReason` (`SessionStillOngoing` \| `RecordingStopCommand` \| `CallEnded`), `ChunkEndReason`, `ICalUid`, `IdOfCallLogMessageToUpdate`, `AutomaticRecordingTranscriptThreadId`, `CallLogsOwnerId` | `value` | ids |
| `Title` | text | meeting title |
| `OriginalName` | `v` | original file name |
| errors inside `RecordingStatus` | `amsErrorResult[statusCode,subCode]` (`NoContent`/`Failed`), `transcriptAmsErrorResult[subCode]`, `StreamExportErrors[errorStatusCode,errorCode]` (`402`+`InsufficientUserLicense`), `RoleAssignment`, `PostToChannel`, `VideoUpload>ErrorReport[errorCode="QuotaExceeded"]`, `OnedriveForBusinessExportError[responseCode,errorCode,failingOperation]` (`CreateUploadSession`, `CreateSharingLink`), `MsGraphError[errorCode,innerErrorCode]`, `RecordingUploadError[errorCode,errorDescription,isUserError,isUserRetryable,failingOperation]` (codes 2001 site read-only, 2004 SPO not found, 3001 license, 3002 quota, 3003 IP policy, 3004 managed device, 3005 (+`423` locked), 3006 access restricted) | failure state |
| `ExportRetry` | children `CallbackUrl`, `StorageType`, `StorageLocation`, `FileName`, `GroupId`, `SessionRegion` (`Value`), `AmsObjectId`, `OwnerMri`, `DriveId`, `SiteId` (`value`), `Participant[Id]` | needed for "Retry upload" |

- Minimal example (element names/attributes from the parser; the `URIObject type` value and the nesting are **unconfirmed**):
```xml
<URIObject type="Video.2/CallRecording" url_thumbnail="https://…">
  <Title>Weekly sync</Title>
  <RecordingStatus code="200" status="Success"/>
  <RecordingContent timestamp="2026-11-06T10:00:00Z" duration="00:12:34.000" contentTypes="Recording" canVideoExpire="true">
    <item type="amsVideo" uri="https://eu-api.asm.skype.com/v1/objects/0-weu-d1-…"/>
    <item type="onedriveForBusinessVideo" uri="https://contoso-my.sharepoint.com/…/Recordings/….mp4" driveId="b!…" driveItemId="01…"/>
  </RecordingContent>
  <Identifiers><Id type="callId" value="…"/><Id type="chunkIndex" value="0"/></Identifiers>
  <ExportResult type="ExportToOnedriveForBusiness"/>
  <RecordingInitiatorId value="8:orgid:…" isAutoRecording="False"/>
  <RecordingStorage type="RecordingInitiatorOneDrive" userId="…"/>
  <MeetingOrganizerId value="8:orgid:…"/><ICalUid value="…"/>
</URIObject>
```

### State machine (420044 `Oe`, enum 8125 `k8`)
- **Successful** when `(code -1 or 200) && export Stream && StreamVideoId`, or `200 && export ODB && odbUrl`, or `200 && export Skype`.
- `0 + Initial` → Ongoing; `202 + ChunkFinished` → Processing; `503` → FailedAllInstancesBusy.
- Otherwise the error elements pick one of: FailedQuotaExceeded, FailedInsufficientLicense, FailedAMSNoContent, FailedAMSViewGeneration, FailedTokenError, FailedODB*, FailedSiteReadOnly, FailedSPONotFound, soft failures (Stream post-to-channel / role assignment), FailedAADError (403), else Failed.
- `amsVideo` on a host matching `allowedSkypeRecordingHosts` (default `*.asm.skype.com`) with `enableSkypeRecordingPlayback` → `exportRequestType = Skype`, `isSkypeRecording`, `downloadUrl = uri + "/views/video"`.

### Control row or card (318259 `_renderRecordingMessageOrControl`, flag `enableSeparateRecordingMessages`)
- **Control row** (time + EM SPACE + text; icon from `Cp`):

| condition | icon | text (75579 `en`) |
|---|---|---|
| `code 0, Initial` | Record (brand) | auto: "Recording started automatically per the organizer's setting." / with initiator (`enableShowWhoStoppedRecording`): "{{initiator}} started recording." / "Recording has started" |
| `code 202, ChunkFinished` | RecordStop | AMS-only stop: "Recording stopped." / "{{terminator}} stopped recording."; recap on, not Stream: "Recording stopped." / "{{terminator}} stopped recording."; terminator known: "{{terminator}} stopped recording. Saving recording…"; Stream: "Recording stopped. We're saving it to Microsoft Stream, and it'll be available here shortly."; ODB: "Recording stopped. Saving recording…" |
| saved, and "who keeps" applies (`enableWhoKeepsRecordingMessage` and (ingested into recap, or 1:1 with native recap + VNext)) | CloudArrowUp | "Recording has been saved to {{owner}}'s OneDrive" / "Recording has been saved to OneDrive" / channel: "Recording has been saved to this channel's SharePoint site"; flag off: "Recording has been saved." |
| `contentTypes=Transcript` | SlideTextEdit | "Transcription has started" / "{{initiator}} started transcription" / "Transcription started automatically per the organizer's setting" / "Transcription stopped" / "{{terminator}} stopped transcription" / "Transcript has been saved to OneDrive" / "Transcript has been saved to {{owner}}'s OneDrive" / "Transcript has been saved to this channel's SharePoint site" |
| `Recording+Transcript` (or paired with a transcript message) | Record / RecordStop / CloudArrowUp | "Recording and transcription has started", "{{initiator}} started recording and transcription", "Recording and transcription started automatically per the organizer's setting", "Recording and transcription stopped", "{{terminator}} stopped recording and transcription", "Recording and transcript have been saved to OneDrive", "…to {{owner}}'s OneDrive", "…to this channel's SharePoint site" |

  Names come from `RecordingInitiatorId` / `RecordingTerminatorId` / `RecordingStorage userId`. An unknown name becomes "" (local recording: "Unknown user").
- **Auto-recording not saved** (`enableShowCollapseRTNotSavedMessage`, auto-recording and (stopped with `shortChunk="True"`) or (`shortChunk` + `NoExport`)): collapsible row `fp` with "<time> EM SPACE Recording stopped and wasn't saved as it was too short.", expanding to the not-saved card (below).
- Anything else (result messages) → **card** (`_renderRecordingMessage`), wrapped in a control-style row (`tr`) whose icon slot is empty.
- **Hidden** (434910 `wt`): in group/meeting chats with the native recap chiclet (`enableTeamsNativeRecapChiclet` and (`hasRecap`, or VNext for ad-hoc/group)), a recording message is added to the call's `recapData` and dropped when it is a successful save or a paired transcript start/stop. It then appears inside the recap chiclet on the "Call ended" row. A transcript-only start/stop paired with a recording is also dropped.
- 1:1 with native recap + VNext and a recap-worthy item → the whole item renders as the recap chiclet (`pp`, aria "This meeting contains recordings").

### As seen in a meeting chat (OST calendar test, winpc 2026-11-10)
- Teams shows only the recording's rows, all as control rows: the time, then the text, with a 20 px icon.
  - Start: "{initiator} started recording.", Record icon in brand.
  - Stop: "{terminator} stopped recording.", RecordStop icon.
  - Saved: "Recording has been saved to {owner}'s OneDrive and will expire in {N} days." with a brand "Remove expiration" link and the CloudArrowUp icon.
- Transcript-only start, stop and saved messages, and the transcript half of a Recording+Transcript pair, show nothing.
- N counts up from the recording's `RecordingContent timestamp` + 120 days: a recording from Sunday 4 PM showed 119 on Tuesday morning.
- That chat's calls read "Meeting ended: **{duration}**" with the video icon.
- OST does the same (messages::recording_event). Its "Remove expiration" opens the recording in the browser; in Teams it opens the Stream player's About panel, which is web content (TASK-0038).

### Card (307208 `Ha`; data 397395 → 420044 `LE`)
- Shown only if allowed (886048 `pe`): `enforceShowingRecordingChiclet`, or 1:1 → `enableOneToOneRecording`, group → `enableGroupRecording`, meeting → `enableCallRecordingPrivate`, channel → `enableCallRecordingChannel`. Hidden when `enforceHidingMeetingRecapChiclets`.
- `contentTypes=Transcript` → transcript card instead (§19). `Recording+Transcript` → recording card followed by a transcript card.
- Screen-reader heading `role=heading aria-level=4`: "Recording {{title}}".
- **Layout** (Griffel; 1rem = 10px):
  - Wrapper: width **227px** (300px when the pane is ≥360px; 252px in the Calls app), radius 4px, `--shadow4`.
  - Card (`data-tid="recording-message-wrapper"`, Fluent attachment, actionable): `--colorNeutralBackground1`, hover `--colorNeutralCardBackgroundHover`, pressed `…Pressed`, radius `--borderRadiusMedium`, no border (high contrast: 1px `--colorNeutralForeground1`).
  - Thumbnail box (`recording-preview-wrapper`): **128×72** (140×90 at ≥360), black (`--colorNeutralForeground1Static`, opacity .9), left corners `--borderRadiusMedium`. The image is requested at 128×72 or 160×90. Alt "Recording image". Tooltip = `playVideoTooltip` ("Play video", "Download video locally" or an error).
  - Duration badge: absolute, bottom 6px, right 6px, padding 4px 6px, radius small, white 14px regular, text from `tmp_calling_duration_mf` ("#h #m #s", zero parts empty), aria "Duration is {{durationText}}".
  - Failed or no-license states: the thumbnail is replaced by a 32px icon (ErrorCircleIcon, DownloadIcon or PlayIcon, custom; fill `--colorNeutralForegroundInverted`), plus "Download now" in the download state.
  - Text column: padding 6px (8px 8px 8px 12px at ≥360).
    - Title "Recording", semibold 14px, one line with ellipsis.
    - Subtitle: owner name (when `enableWhoKeepsRecordingMessage`), else initiator name; `--fontSizeBase200`, truncated below 360px.
    - Error line (small, red) when `errorMessage` is set.
    - Without the expiration feature: a "Download" link plus "(expires in # days)".
    - Info button (DarkOrange) whose tooltip is `tooltipText`.
    - A small spinner while Processing.
  - "More options" button (MoreHorizontal, circular, transparent, `recording-message-more-options`). Right-click on the card opens it.
  - **Banner** under the card, when `enableRecordingExpiration` and (`bannerText`, or `canVideoExpire` + `odbUrl`):
    - Box: padding 6px 12px, 12px text, width 227px, card bottom corners squared.
    - Colours: warning = DarkOrange background/border; error = Red; MTR info = neutral.
    - Expiration text: "This recording has an expiration date. Click <here> to view or change it. <Learn more>". "here" opens `odbUrl` with `?referrer=Teams.<client>&referrerScenario=MeetingChicletExpiration.view`; "Learn more" opens setting `recordingExpirationLearnMoreUrl`.
- **Click** (`_handleClick`):
  1. Local AMS download possible and not Skype → download `downloadUrl` (toasts "Downloading recording..." → "Recording downloaded" / "Download failed. Please try again").
  2. ODB and Successful → ad-hoc/1:1 with `enableDownloadAndDeleteTranscriptFromODSP`: open the in-app Calling recap. Scheduled meetings with recap: open the meeting Recap tab. Otherwise open `odbUrl` in the browser.
  3. Skype recording → "Recording player" dialog (lazy chunk `skype-recording-player`, module 982029; Close = Dismiss icon) playing `downloadUrl`.
  4. Stream → `https://web.microsoftstream.com/embed/video/{StreamVideoId}/?autoplay=true&app=microsoftteams`, else the `video` item URL.
- **More options** (`Pt`):

| export ODB | export Stream (`_itemsWithoutODB`) |
|---|---|
| Open in Stream (custom Stream icon; opens `odbUrl` + `referrer=Teams.<client>&referrerScenario=MeetingChicletOpenInStream.view`), Get link (Link), Upload (ArrowUpload; retry, when retriable), Learn more (Info → `https://aka.ms/recordmeeting`), Report a problem (Warning), Report a problem for failed uploads (`enableBrbAndFeedbackDialogForFailedRecording`, opens feedback category MeetingsRecording), Delete (Delete; only when failed/skipped and the user is the organizer or creator; disabled with "Only the meeting organizer can delete this recording." when the organizer is someone else) | Open in Microsoft Stream (MicrosoftStreamCustomIcon), Share (Molecule; Stream share dialog, same tenant only), Get link, Learn more, Report a problem, Company recording policy (Document; opens `policyUrl`), Delete |

  - Get link dialog: title "Get link" (ODB) or "Get Stream Link", buttons "Cancel" / "Copy", URL decorated with `referrerScenario=MeetingChicletGetLink.view`.
  - Delete dialog: "Delete Recording" / "Are you sure you want to delete the recording? You won't be able to undo this." / "Cancel" / "Delete".
  - Report dialog: "Having trouble? Tell us about it." / "Send feedback".
- **Failure texts** (751172): see the failure-strings table below.

### Not-saved card (358638 `Xe`/`Je`, `data-tid="recording-not-saved-message"`)
- Custom purple play icon (`VideoPlayerIcon`, gradient #6B2C91→#a766e8).
- Title "Recording".
- Subtitle "`{duration} · Expires in # days.`" or "This recording has expired and is no longer available."
- Menu (MoreHorizontal): Download (ArrowDownload; AMS download), Upload (ArrowUpload; retry).
- Expiry = `downloadRecordingExpirationDays` (fallback **20**) − round((now − `timestamp`)/1 day).

### Services
- **Download**: GraphQL `downloadFile(downloadUrl, httpMethod?)`. The resolver downloads AMS URLs through the async-media service (authenticated blob fetch, then a blob save), and other URLs natively. Skype recordings pass `httpMethod:"GET"`.
- **Retry upload**: GraphQL `retryUploadRecording` → `POST https://api.flightproxy.teams.microsoft.com/api/v2/ep/{ExportRetry.CallbackUrl without scheme}`.
  - Headers: `Content-Type: application/json`, `X-Microsoft-Skype-Chain-ID: <callId>`.
  - Auth: token for Calling setting `callRecorderResource`.
  - Body: `{errorReport, notificationData, exportMetadata:{callbackUrl,storageType,storageLocation,fileName,groupId,driveId,siteId,…}, ownerObjectId, ownerTenantId, ownerMri, userToken, amsObjectId}`.
  - Retries: 3 tries, backoff 1000 ms × 1.5ⁿ.
  - Toasts: `calling_{recording|transcript}_retry_upload_ongoing` / `…_failure`.
- Expiration lookup: hook 488939 `_` with `{location: odbUrl, driveId, driveItemId}` (ODSP file info: remaining days, permission). Endpoint **unconfirmed**.

### Fallbacks
- No `contentTypes` → nothing is rendered.
- Unparseable XML → card state None.
- Invalid (non-https) URI → dropped and logged.
- Generic text renderers (923733 `Ft`) show a `RichText/Media_CallRecording` as `<p>Recording has started</p>` (`calling_recording_progress`). Which surfaces use this path (search, previews) is **unconfirmed**.

### Recording failure strings (751172)
| state | text |
|---|---|
| soft: post to channel | This recording was saved to Microsoft Stream, but it's not linked to a Stream channel. |
| soft: role assignment | We couldn't set viewing permissions for some people. Please contact {{author}} to get permission to view this recording. ({{author}} = initiator, or "meeting organizer") |
| soft: both | This recording was saved to Microsoft Stream, but it's not linked to a Stream channel. Also, we couldn't set viewing permission for few users. |
| soft: other | The recording ended unexpectedly |
| ODB session | Recording failed to upload to OneDrive. Session could not get created |
| ODB share link | There was an error while uploading to OneDrive. Sharing link could not get generated. |
| quota (Stream) | Your recording wasn't saved because you ran out of storage in Stream. Delete something or ask your IT admin for more space. |
| AMS | Something went wrong with this recording, and no audio, video or sharing was captured. If this keeps happening, contact support. |
| token | Recording ended unexpectedly and won't be saved. Before you try again, log out of Teams and then log in again. If this keeps happening, contact support. |
| busy | Recorder is busy. Please try again later. |
| generic | Recording failed to upload. |
| retrying | Uploading recording... |
| ODB license | Recording upload failed to OneDrive. (organizer) / Recording upload failed because the owner's OneDrive isn't set up. (participant); SharePoint variants exist |
| ODB quota | Recording upload failed because of not enough space in your OneDrive. (organizer) |
| IP / device policy | Your org doesn't allow uploading from this network location. / Your org doesn't allow uploading from untrusted devices. |
| locked | Recording upload failed because the owner's OneDrive is locked. (participant) |
| SPO not found | Recording upload failed because SharePoint folder is not ready or not found yet. |
| ODB generic | There was a problem uploading this recording to OneDrive. / …to SharePoint. |
| AMS copy still downloadable | banner: "This recording couldn't be uploaded and will expire in # days. Select the recording to download." (=0 "less than a day", =1 "# day"); Teams Rooms: "The recording initiated by Teams Rooms is saved temporarily and will expire in # days. You can download and save recording in your OneDrive if needed." |
| AMS copy expired | This recording has expired and is no longer available. / "Download Expired" |
| suffix on banners | "Expires in # days." (organizer) / "It will expire in # days." / "Recording expires in # days." |
| retry links | "Obtain and <set up an OneDrive license>, and then <retry upload>" / "Remove some files and <retry upload>" / "Contact the IT administrator to resolve it and <retry upload>" / "Contact the owner to resolve it, then <retry upload>" / plain "Retry upload" |

## 18. `RichText/Media_LocalRecording`
- Item type `LocalRecordingMessage`. Always a **control row** (318259 `_renderLocalRecordingControlMessage` → 422270 `kX` → 75579 `qa`).
- Content: the same XML family. The client reads `RecordingStatus@status` (`Initial` = started, `Success` = stopped; anything else is logged as an error) and `RecordingInitiatorId@value` for the name.
- Text: "<time> EM SPACE {{initiator}} started recording to their computer." / "Recording stopped. Saving recording to {{initiator}}'s computer...". Unknown name → "Unknown user". aria "{{message}} at {{time}}".
- Icon (Cp): Record / RecordStop.
- Desktop host APIs nearby (`GetLocalRecordingLocation`, `ChangeLocalRecordingLocation`) belong to settings, not the row.

## 19. `RichText/Media_CallTranscript` and transcript cards
- **Legacy transcript message** (`Media_CallTranscript`, item type TranscriptMessage):
  - `content` is escaped JSON (963821 `Gb`: strip U+200B, remove backslashes, `unescape`, `JSON.parse`; retried with `\&quot;` → `"`). Fields used: `scopeId` (becomes `callId` when missing), `iCalUid`, `isExportedToOdsp`.
  - Only **rendered in 1:1 chats**. In group/meeting chats it is attached to the call-ended row as `transcript` and dropped, and it is also dropped when the call has recap data (434910 `wt`).
  - Renderer 560170: `data-tid="transcript-message"`, title "Call", body = card 618581.
- **ODSP transcript card** (618581 `Ot`; for recording messages with `contentTypes` Transcript or Recording+Transcript when `enableDownloadAndDeleteTranscriptFromODSP`; not for Skype recordings):
  - Card `data-tid="transcript-message-wrapper"`: width 227px (300px at ≥360 container), margins 8px (4px small).
  - Icon: custom 32×32 `MeetingTranscriptIcon` (document with lines #5C5FC7 and a play box).
  - Title "Transcript": 14px semibold.
  - Subtitle (base200, ellipsis): "Deleted" / "Deleting..." / "No content" (AMS `NoContent`) / "Upload failed".
  - aria note "Press enter to go to meeting transcription".
  - **Click** (when actionable: not external, deleted or failed, and channel meetings need recap or the flag): open the ODSP transcript panel, or `odbUrl` in the browser (channel meeting without recap), or navigate to the transcript tab.
  - **Menu** (MoreHorizontal, `transcript-chat-tile-menu-button`):
    - "Download as .docx" / "Download as .vtt" (FilesTextColoredIcon).
    - "Delete transcript" (Delete); dialog "Delete transcript?" / "Are you sure you want to delete the transcript? You won't be able to undo this." / "Delete" / "Cancel".
    - Permissions come from GraphQL `odspFileInfo(location, driveId, driveItemId) { accessViewpoint {canDownload, canDelete} }`. When both are false: toast "Don't have the permission".
  - **Upload failed**: menu "Download as .vtt/.docx" from AMS (ArrowDownload). The URL is the `amsTranscript` item URI with its path tail swapped between `/transcript` (vtt) and `/transcript_docx` (docx); saved as `transcript.<fmt>` via `downloadFile`. Also Delete, "Report a problem", and the retry link "Retry upload" ("Uploading transcript..." / "There was a problem uploading this transcript to OneDrive.").
  - Toasts: "Downloading transcript..." / "Transcript downloaded" / "Download failed. Please try again" / "Delete failed. Please try again".
- `RichText/Media_CallLogRecording` / `Media_CallLogTranscript` are in no visible-type list (434910), so they are never rendered in the chat timeline (call history only; **unconfirmed** beyond that).

## 20. `RichText/Media_MeetingObjects`
- `content` = JSON. The client reads only `callId` (75579 `sa`: `JSON.parse(content).callId`).
- 434910 `wt` stores it by `callId` and attaches it to the matching "Call ended" item as `meetingObjects`. The same JSON is passed as `meetingObjectsContent` to `isAttendanceReportAvailableAfterCallEnded`, which gates the attendance-report entry in the recap.
- Listed as visible only in meeting chats, but there is **no dedicated renderer**. If one reaches the generic path it would render as plain `<p>{content}</p>` (923733 default branch). In practice it is probably never visible: **unconfirmed**.
- Not to be confused with the **meeting object chiclet** (318259 `xi` → `mm` scheduled / `Sm` meet-now / `Em` group-chat meet-now). That chiclet is driven by `properties.meeting` (`scheduledMeetingInfo`, `meetingTitle`) on posts in threaded channels (L1 view) and threaded group chats (`enableMeetingObjectInThreadedGroupChat`). Its aria is `tmp_messages_meetingScheduledMessageAria`. Its layout and buttons were not traced (**unconfirmed**).
- **Recap chiclet** on the call-ended row:
  - 983864 (chat) / 676304 (channel) build it from the call-end XML (102674 `kW`: `MeetingDetails`/`InstanceDetails` → `MeetingType`, `Subject`, `StartTime`, `EndTime`, `ICalUid`, `ConversationStartTime`, `HasEphemeralTranscript`, `IsRecapEnabled`) plus `recapData` (the folded recording messages, parsed with 420044).
  - Title `meetingRecap:call_recap_chiclet_title_mf`. UI module 174639 was **not traced** (layout, buttons and strings unconfirmed).
  - `RecapChicletDeserializer` (itemtype `http://schema.skype.com/FluidRecapChiclet`) renders the same chiclet inside facilitator (AI notes) HTML messages. 434910 rewrites `FluidAutoEmbedLink` anchors in facilitator messages to that itemtype and replaces the paragraph text with `facilitator_recap_chiclet_message`.

### Scheduled-meeting chiclets inside ordinary messages
- `<… itemtype="http://schema.skype.com/ScheduledMeetingCreated|ScheduledMeetingUpdated|ScheduledMeetingCancelled">` elements in an HTML message are replaced (deserializers 982330 / 761989 / 762845, base 965221) by the meeting chiclet 240923.
- The chiclet's props: `chicletType` Created/Updated/Cancelled, `meeting` (from `properties.meeting`), `convId`, organizer name/id, arrival time; calendar banners are disabled in teams (`teamId` set).
- Rendered only if `enableUserMeetingChiclet` (1:1) / `enableGroupMeetingChiclet` (group) and the message has `meeting`.
- An HTML message carrying `meeting.scheduledMeetingInfo` as a root post in a threaded channel renders as a control row "MeetingScheduled" (icon Calendar) when `enableUIUpdatesForMeetingObjectChicletInThreadedChannels` is on (318259 `_shouldRenderScheduledMeetingMessageAsControlMessage`).
- Chiclet layout **unconfirmed** (240923 not traced).

## 21. `ThreadActivity/MessageMoveStarted` / `MessageMoveCompleted` and moved messages
- Gated by `enableMoveMessagesToChannel` or `enableMoveMessagesToChannelConsumption`.
- **Wire**: `properties.moveResult` or `properties.moveMetadata` (JSON string):

```json
{"initiatorId":"8:orgid:…","targetThreadId":"19:…@thread.tacv2","rootPostMessageId":"1730…","failedBatches":[],"aadGroupId":"…","sourceRetentionMode":"hide"}
```

  - Worker `qS` maps it to `moveContext {initiatorId, destinationThreadId, destinationChannelName (looked up from the target thread), destinationRootPostMessageId, isPartial (= failedBatches non-empty), groupId, hidesMovedMessages (= sourceRetentionMode "hide")}`.
  - A missing `targetThreadId` → no context, so no row.
- **Rows** (75579 `ha`): control rows; icon `MessageMoveStarted` = 318259 `Zu` (not resolved), Completed = ChatCursor.
  - Started (`data-tid="move-messages-source-started"`): "<initiator> is moving messages from this chat to the {{channelName}} channel. A link to the channel thread will be shown when the move is complete." Variants: "…to a channel…" (unknown channel); no initiator: "Messages are being moved from this chat to the {{channelName}} channel. A link to the channel thread will be shown when the move is complete."
  - Completed (`move-messages-source-completed`): "<initiator> moved messages from this chat to the {{channelName}} channel." Partial adds " Some messages couldn't be moved."; no initiator: "Messages were moved from this chat to the {{channelName}} channel."; unknown channel: "…to a channel.". Then a link "**Go to channel thread**" (`move-messages-source-view-thread-link`, base200 semibold) → open channel `destinationThreadId` deep-linked to `rootPostMessageId`.
  - The initiator is a plain display name (`de.K` user render), not a persona card.
- **Visibility** (434910 `Lt`):
  - A Started row older than the newest Completed row is hidden.
  - With `enableHideMovedMessages` and `moveContext.hidesMovedMessages`, the Completed row itself is hidden.
- **Moved messages in the source chat** (worker `YS`, 8819):
  - `properties.isMovedAway` ("true"/true) and/or `properties.moveTombstone` (any value) → `movedInfo {isMovedAway, isMovedTombstone}` (needs `enableHideMovedMessages`).
  - Tombstone → rendered as a **control row** (item type Control, icon ChatCursor) with the Completed text. Its context comes from the `moveTombstone` JSON (`targetThreadId`, `rootPostMessageId`, `initiatorId`, `aadGroupId`, `movedMessageCount`/`totalMessagesInRange`/`boundReached` → partial) or `properties.moveContext` with `targetThreadId`.
  - Moved-away without a tombstone: no date divider is computed. Whether it is hidden is **unconfirmed**.
- **Destination channel post** (318259 `fg`/`Ym`): `properties.moveContext`/`MoveContext` JSON with `sourceThreadId` → `moveSourceThreadId` (+ `moveSourceMessageId`). Root posts in threaded channels show "Thread moved from a **chat**" (`data-tid="moved-from-chat-status"`, size 200). The "chat" link (tooltip "Go to original chat") deep-links to the source chat/message. A post with only a subject renders subject-only.
- Multi-select move limit: 100 messages (818360 `l`).

## 22. `ThreadActivity/ConsentInvites` (additions to messages-and-composer.md §9)
- Wire: XML with `<eventtime>`, `<initiator>` (MRI) and `<friendlynames>` (comma-separated display names). No `friendlynames` → warning and **no row**.
- Names are plain text (`ge`), not personas. 1 → "<0></0> won't be added…", 2 → "<0></0> and <1></1> won't be added to the chat until the message is accepted.", ≥3 → "<0></0> and {{otherTargets}} won't be added…" with `{{otherTargets}}` = "# other"/"# others" (count − 1).
- Icon PersonAdd. No accept/consent UI or service call in the row (**the accept flow itself was not traced**).

## 23. SmartCard, MeetingOrientationSmartCard, FollowedMeetingTopicsCard
- **Not wire messages.** 434910 inserts synthetic rows `{key, content, itemType, messageType, isFromCurrentUser:false}`; they are rendered by 318259 `_renderChatItemDividerOrControl` inside `data-tid="chat-pane-item"`. No service message with `messagetype:"SmartCard"` was found in the code (unconfirmed whether the service ever sends one).

| row | item type (991060) | inserted when | renderer |
|---|---|---|---|
| `smart_card` (`messageType:"SmartCard"`) | 7 | `enableSmartCardInChat`, or `summarizeUnreadChatL1` contains `Inline`/`Pill`/`Proactive`; chats only (not channels/ConvUX) unless the threaded-L2 flags; placed at the "Last read" divider (or the last-message position when landing on last read is off) | 497560 `K` |
| `meeting_orientation_smart_card` | 8 | meeting chat, `enableMeetingOrientationSmartCardInChat`, not channel/ConvUX; placed at the last message or top | lazy 113431 |
| `followed_meeting_topics_card` | 9 | meeting chat with `chat.showFollowedMeetingTopicsCard` and `meetingInformation` | lazy 977412 |

- **SmartCard (497560)** — a Copilot "catch up" summary:
  - Inline mode: brand-appearance divider with a small subtle button (`data-tid="inline-summary-button"`, Copilot icon `RAN`), label "Summarize # unread" (`summarize_unread_count_button_mf`) or "Summarize 10+ unread" when >10 (205036), tooltip "Summarize what you missed".
  - Click opens the summary card (Copilot prompt `AiChatThreadSmartCard` / `AiChannelSmartCard`). Requires Copilot; for OST it can be omitted (no Copilot licence).
- **Meeting orientation (113431)**: only when `chat.meetingOrientationSmartCardInfo {eventId, eventStartTime}` is set, the meeting starts within −5 min…+10 min of now, not in the calling window; GraphQL `isMeetingSummaryWorthy(eventId)` then `meetingPrepSummary(eventId){summary,headline,insights}` → markdown (headline + first 3 insights). Copilot feature.
- **Followed topics (977412)**: title "Get notified about topics in this meeting", description "Add topics you want to track. We'll notify you when they're discussed or when your input is needed.", placeholder "Describe a topic, question, or decision you'd like to be notified about.", "Add", "Visible only to you", "Manage topics", "No topics added yet", limit "You've reached the topic limit. Remove a topic before adding another."; GraphQL `facilitatorGetFollowedMeetingTopics` / `facilitatorSetFollowedMeetingTopics`. Facilitator (Copilot) feature.

## 24. `RichText/Sms`
- Teams-for-Life (consumer) two-way SMS: chats with phone-number members (`50:sms:` / `50:smsunverified:` MRIs, 250613; TFL SMS prefix `243546.gNc.TFLSmsPrefix`). Gated by `enableSms` / `enablePaidSmsChat`.
- **Send** (955743 `ke`): when the chat is an SMS chat, `messageType = "RichText/Sms"` and `content` = **plain text** of the sanitized HTML (`DomUtils.getText(parseDOM(sanitizeHtml(content)))`). Same POST as normal messages.
- **Receive/render**: not in the deserializer list, so the body is `<p>{content}</p>` (plain text). Grouped and shown like a normal message.
- **Properties**: `properties.smsDeliveryReports` → `message.smsDeliveryReports: [{key:"Sent"|"Failed", users:[{mri, value:'{"errorCode":N}'}]}]`; `properties.deliveryState` → `interopDeliveryState` (e.g. `"480/52018"`). `diagnosticInfo.diagnosticErrorCode` from the send response.
- **Failure detection** (947361): only for `RichText/Sms` with `enableSms`: `E4` picks the `Sent`/`Failed` report for the sender; failed at gateway = a Failed report exists and no Sent report. Failed unless the error is fraud (`3003` FraudSenderBlockedByRecipient, `3005` FraudSpamDetected) — those are hidden from the sender (`A`).
- **Failure text** (`mx`, under the bubble, red, `data-tid="message-error-container"`): gateway error code via 759872 `sx`:
  - 2002, 3001, 3002, 3004, 3006, 4001 → "Failed to send. Contact your administrator."
  - 4002, 4003, 4004 → "Failed to send. Phone number is invalid."
  - 4005, 4006 → "Failed to send. Phone number is unreachable."
  - others → "Failed to send".
  - `diagnosticErrorCode` 10001 → "Your picture is too large to be sent."; 1400 (`RESERVED_TARGET_PHONE_NUMBER`) → "Failed to send" and **Retry hidden**.
  - Invite containing a URL: "You cannot send links in this message until the invite is accepted."
  - Interop delivery states (non-SMS too): `603/52090`,`480/24023`,`408/52090` declined; `480/52018`,`480/24115` DND; `480/1034`,`480/13012`,`486/52067` unavailable; `488/52091` not supported; `504/27002`,`504/1017` federation; `403/10004` tenant restricted; `488/13028` interop not enabled; other → "We ran into a problem sending your message. Please share diagnostic code {{errorCode}} with your admin to help them troubleshoot the issue."
- **`TWO_WAY_SMS_SPAM_THROTTLED` (diagnostic 401)**: sets `hasSentTooManyTwoWaySMSInvites`, which removes Retry from the failed-message actions (318259 `getFailedActionMenuProps`: `canRetry = !failedAtGateway && retryable && !chatDisabled && !throttled && !scheduled`). The code is in the retained-diagnostic set with 10001 and 10004.
- SMS member names get a suffix when `enableSMSUserSuffix` (People settings; text owned by the header spec).

## 25. Fallbacks
| situation | what is shown | module |
|---|---|---|
| type not in the deserializer path (§1) | the raw `content` string as plain text in a `<p>` | 923733 `Et` |
| deserializer sets `isContentUnsupported` (unsupported card type, bad SWIFT/audio JSON, code snippets off, Loop not allowed or no `componentUrl`) | 230655 placeholder (below) | 230655 |
| HTML parse exception | 230655 placeholder, no icon, "Error encountered while rendering this message"; message text "Failed to process message" | 923733 `He` |
| DOM deeper than `maxMessageDOMDepth` | `<p>`"This content is currently not supported."`</p>` | 836697 |
| attachment grid or URL preview throws | "Error loading attachments or previews." | 318259 `St` |
| file chiclet throws | plain `<a href=shareUrl‖objectUrl target=_blank>{title‖href}</a>`, or nothing if that URL is already in the body | 330096 |
| Skype Location / Poll / ScheduledCallInvite | Skype placeholder card (below) | 289206 `oe` |
| Skype quote or Tenor GIF that can't be built | Skype fallback card (below) | 289206 `Q` |
| Skype media older than `Gallery.skypeMediaTTL` (30 days) | "No longer available" | §7 |
| quoted original deleted | "This message has been deleted." | §15 |
| forwarded original deleted | "This message was deleted." | §16 |

### Unsupported placeholder (230655 `$`)
- Fluent `Attachment`, `margin:0; padding:10px`, `id="content-{messageId}"`, `aria-label` = the text.
- `AttachmentIcon` (32×32) holds **WindowNew** Regular at 32px. There is no icon for `Collaborate` or when `hideIcon` is set.
- `AttachmentHeader` text: `--fontSizeBase300`, line-height 1.4286, regular weight, `--colorNeutralForeground2`.
- Text:
  - `Collaborate` → **"This content is currently not supported."** (`messaging:tmp_semantic_message_unsupported_content`);
  - everything else → **"Go back to the main window to see this content."** (`messaging:tmp_messages_unsupported_content`).
- For a bot message with an unsupported card, 318259 also mounts 215090 `pD`, a telemetry hook that renders nothing.

### Skype placeholder card (289206 `oe`, `data-tid="skype-unsupported-card"`)
- Row: icon box + a column of header and secondary line.
- Card: `background --colorNeutralBackground1`, `border-radius 4px`, `margin 4px 0`, `padding 5px 12px`, `color --colorNeutralForeground1`, `gap 12px`.
- Icon: 20px (963507 `large`), in a box with `flex-wrap:wrap; align-items:center`.
- Header: semibold (the per-type string).
- Secondary: size 200, `--colorNeutralForeground2`, **"Unsupported content"** (`messaging:skype_unsupported_content_text`).

### Skype fallback card (289206 `Q`, `data-tid="skype-fallback-card"`)
- The same card with `gap 7px` and `align-items:center`.
- Content: **Warning** icon (20px) + "Unsupported content" in `--colorNeutralForeground2`.

---

## Unconfirmed points
**Skype/TFL family**
- The tag name of the contact child (`<c>`). The renderer reads only `f`/`s` of the first child.
- `<location>` attributes beyond `latitude`/`longitude`.
- The output for an unknown `<URIObject type>` in a Skype message (default rendering of its children).
- Whether non-Skype threads ever receive Contacts/Location/Poll/ScheduledCallInvite. If they do, they show as raw text.
- The UI use of `scheduledCallStatus`.
- Clicking a Skype file or video tile (`serviceName:"skype"`).
- The tenant allowed-image regex for Tenor GIF URLs.

**Voice messages**
- The HTML tag that carries the voice-message `InputExtension` `itemid`.
- The auth header on AMS audio download and transcript calls.
- The transcript button on Skype voice messages, which pass no objectId.

**Cards**
- The `<URIObject>` attributes of received `RichText/Media_Card` other than `<Swift>`. `type="SWIFT.1"` is only what the client itself builds.
- Which card images are rewritten through the URLP proxy.
- The exact link from GraphQL `sendInvoke`/`sendExecuteInvoke` to the worker's `botsinvoke` request. The endpoint itself is confirmed.
- Whether bot cards sit inside the coloured bubble or replace it.
- The Fluent name of the card-button image-failure icon (`P6O`).
- The single-card class `r4xauy`, which is missing from the CSS file.
- The O365 connector card's potentialAction buttons (an OpenUri one showed none), markdown in its text, and section images.
- Adaptive Cards renderer internals beyond the host config.

**Smart cards**
- Whether the service ever sends a real `messagetype:"SmartCard"` message.

**Files**
- What legacy senders put in `content` for `RichText/Files`.
- The chiclet description line strings.
- The Browser and Desktop app item texts in "Open in".
- The live values of `enableFileAddControlMessage`, `enableImageCollageForAttachments`, `enableStandardizedMessageChiclets` and `enableSendToL1MessageLabel`.

**Loop**
- The inner Loop component UI (title, content, actions). It lives in the external Loop package, not in the Teams bundles.

**Link previews**
- The exact URL and body of the remove-preview call. It goes through `setMessageProperty("links")`, probably `PUT …/messages/{id}/properties?name=links`.
- The `enableLinkHoverPreviews` variant (off on the tenant).

**Forwards**
- Where `originalMessageContains.mediaCard` is set.

**Recordings and transcripts**
- The `URIObject@type` value and the XML nesting of recording messages. The parser reads elements at any depth.
- The endpoint behind the expiration/permission hook 488939 and `odspFileInfo`.
- The Skype recording player (982029) and the TFL/intelligent-recap chiclets.
- The recap chiclet UI (174639).
- The meeting-object chiclets (`mm`/`Sm`/`Em`) and the scheduled-meeting chiclet 240923.
- Whether `RichText/Media_MeetingObjects` ever reaches the generic renderer.

**Message move**
- Whether moved-away messages without a tombstone are hidden.
- The Fluent name of the MessageMoveStarted icon (318259 `Zu`).

**Consent invites**
- The consent-invite accept flow.
