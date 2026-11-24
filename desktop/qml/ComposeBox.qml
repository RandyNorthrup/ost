import QtQuick
import QtCore
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import com.ost.desktop

// Teams' simplified compose (266342), measured on winpc. The same box is the
// chat's compose and the in-place editor of a message (Teams edits in place
// with this component).
// - The box: white, a 0.67 px NeutralStroke2 border, radius 6; focused, a
//   2 px brand line along its bottom.
// - Single-line state: the editor (padding 10 16 8 12, 14/20, min 38 tall)
//   with the side toolbar on its right: 32 px buttons 6.7 from the top, then
//   the send group (a 24 px divider 4 in, Send 8.7 in), 6.7 from the end.
// - Multiline state (the formatting bar open, a quote or files, or text over
//   one line): the editor across the box and a 44.7 px bottom toolbar with
//   the same buttons, 6 down, ending 6.7 from the right. While editing, the
//   send group is Cancel and Done.
// - The formatting bar (open with Format): 43 tall, 32 px buttons from
//   (6.7, 9.7) in groups 8.6 apart with a divider between; Discard (Cancel
//   while editing) at the end. The editor is then at least 104 tall.
// - Under the box, when it isn't empty: "Shift+Enter starts a new line."
//   (or "Enter starts a new line." with the bar open or Enter set to a new
//   line), 12/16, right-aligned 17 in; the key is a link to Settings.
// - Enter: Ctrl+Enter sends; Enter sends only with the Enter setting at its
//   default and the bar closed; Shift+Enter is a new line.
// - Cancelling an edit (or Discard) asks first: Teams' "Discard draft".
// - `post`: Teams' channel post composer (Post in channel, measured on
//   winpc 2026-11-09). A card (shadow 0 0 2 / 0 4 8) with the author row
//   (56.7, 16.7 in, a #E0E0E0 line: avatar 32, name 14/20 semibold at 58.7,
//   Close or Discard 48.7 from the right), "Add a subject" (18 px, padding
//   15 0 16, 10.7 in, a #616161 underline, brand when focused; 250
//   characters), the formatting bar always open with Announcement, the
//   editor (at least 104), then 16 under it the tools from 8.7 and Post (96
//   x 31.3) 16.7 from the right, 17.4 above the bottom. Announcement adds
//   the banner (12.7 in, 69.3 down, 244 tall, radius 4, its colour scheme):
//   "Type a headline" (40/52 semibold, centred, 44 characters) and, 12.8
//   from its bottom right, Color scheme and Upload an image; the subject
//   becomes "Add a subheading" 12 under it.
Item {
    id: root
    property bool editing: false
    // Editing a sent message (Teams' in-place edit box, measured on winpc
    // 2026-11-23, TASK-0263): Format, Emoji, Attach files, Write with
    // Copilot and Actions and apps, then Cancel and Done (no Loop
    // button). Attach is the compose box's popover, its files going into
    // the edit, and the message's own files show as cards to take out
    // (Remove attachment). Actions and apps is Teams' short menu:
    // Collaborate with Loop, Set delivery options (Standard or Important,
    // the IMPORTANT! line over the text), Record video clip. Done sends
    // them with the text (editExtras(): Teams' edit PUT carries the files,
    // the importance and a Loop component's card).
    /// The message's own files still in the edit ({key: objectUrl, name,
    /// kind, existing}), and their keys when the edit began.
    property var editFiles: []
    property var editFilesAtStart: []
    /// Files from this device added in the edit (their paths).
    property var editLocalFiles: []
    // The message's own video clip and Loop component in its edit box
    // (measured on winpc 2026-11-24, TASK-0265): the clip as the compose
    // box shows one (400 x 225 over the text, Remove video clip on hover),
    // the Loop component as the compose box's (its header's Discard asks
    // "Discard draft message" and deletes the component's file at once, as
    // Teams does). Done leaves out what was taken out.
    property var editClip: null
    property var removedClips: []
    property var editLoop: null
    property var removedLoops: []
    /// The conversation's team, for the edit's Attach (Browse Teams and
    /// Channels in a channel).
    property string editTeamId: ""
    property string editTeamName: ""
    readonly property var editAttach: editAttachLoader.item ? editAttachLoader.item.attach : null
    property string placeholder: qsTr("Type a message")
    property var quote: null
    property var files: editing ? editLocalFiles : []
    /// Files picked from OneDrive or SharePoint ({key, name, kind, loading,
    /// file, thumbnail}), drawn as Teams' attachment cards under the text.
    property var cloudFiles: editing ? editFiles.concat(editAttach ? editAttach.pending : []) : []
    property bool formatting: false
    // Teams' delivery option for the next message: "", "high" or "urgent";
    // offered outside channels, Urgent only up to 20 members.
    property string importance: ""
    /// A Threads-layout thread's reply target (Teams' "Send to:"): "" (none
    /// shown), "thread" (thread only) or "channel" (thread and channel).
    property string sendTo: ""
    /// A Threads-layout channel's new message: formatting adds Teams' "Add
    /// a subject" row (measured on winpc 2026-11-10: 55.7 tall under the
    /// formatting bar, 10.7 in; the subject 18/600, 12 in and 15 down).
    property bool threadSubject: false
    /// Schedule message (Teams' "+" ▸ Schedule message, measured on winpc
    /// 2026-11-10): when the message goes (epoch ms; 0 sends now), and
    /// whether this compose offers it.
    property real scheduleAt: 0
    property bool scheduleAllowed: false
    function scheduleText(tpl, ms) {
        const d = new Date(ms)
        return tpl.arg(theme.fmtDate(d, "dddd, MMM d")).arg(theme.time(d))
    }
    /// Teams' default: the next 8:00 AM.
    function nextEight() {
        const d = new Date(); d.setHours(8, 0, 0, 0)
        if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1)
        return d.getTime()
    }
    /// The width Teams' formatting bar picks its tier from (the
    /// conversation's).
    property real tierWidth: width
    readonly property real subjectRowH: threadSubject && formatting && !post ? 55.7 : 0
    property bool deliveryOptions: true
    property bool urgentAllowed: true
    signal scheduleMeetingRequested()
    // People who can be @mentioned here (the chat's members): [{mri, name, mail}].
    property var mentionables: []
    // Whether the picker also searches the directory (1:1 chats and
    // channels; group chats suggest their members, as Teams does).
    property bool mentionDirectory: true
    // Everyone (group chats): the conversation id, and how many are in it
    // (Teams: up to 250; two or fewer get plain text).
    property string everyoneId: ""
    // In a channel: the channel and its team, mentionable as Teams' channel
    // picker offers them ({id, name}; the team's id is its thread id).
    property var channelMention: null
    // Group chats offer "Add someone to the chat" in the @ picker.
    property bool canAddPeople: false
    signal addPeopleRequested()
    // Group chats and channels offer "Add agent to the chat / channel",
    // which opens Teams' agent Store.
    property bool canAddAgent: false
    signal addAgentRequested()
    property var teamMention: null
    // The team's tags ({id, name, count}), offered after the team and
    // channel as Teams' picker does.
    property var tagMentions: []
    property int memberCount: 0
    /// A meeting's chat (Everyone allows up to 1,000 others there).
    property bool meetingChat: false
    // Teams' Everyone rules (messaging settings, live: group chats 250
    // others, meeting chats 1,000; a banner past 50; module 168932).
    readonly property int everyoneOthers: Math.max(0, memberCount - 1)
    readonly property bool everyoneAllowed: everyoneOthers <= (meetingChat ? 1000 : 250)

    // Teams' compose banner (notificationBanner, measured on winpc
    // 2026-11-09): a 29.3 tall bar on top of the box, the box's width,
    // radius 4 4 0 0, #E6E6E6 with a #E0E0E0 line, its text 14/20 #424242
    // 16.7 in, Close notification (28, a 16 px dismiss) at the end. It goes
    // after 3 s. Danger banners (Everyone past 50) use Teams' alert danger
    // colours (red foreground, background1, border) and, as Teams' (measured
    // on winpc 2026-11-15 in a 54-person chat), have no Close button.
    property string bannerText: ""
    property bool bannerDanger: false
    property bool bannerDismissible: true
    // A standing note on top of the box (Teams' lobby chat awareness and
    // disabled banners, measured on winpc 2026-11-11): the box's width,
    // #F0F0F0, radius 6 6 0 0, a 0.67 #E0E0E0 line on top, padding 8 16 6,
    // its text 14/20 #424242 (#616161 when the chat is unavailable).
    property string noteText: ""
    property bool noteMuted: false
    readonly property real noteH: noteText ? noteLabel.implicitHeight + 14 : 0
    // Teams' DefaultBanner (pre-send checks, measured on winpc 2026-11-16:
    // "Please type a message to continue.") has no Close and is 28 tall,
    // its text 4 down; the dismissible kind is 29.3.
    readonly property real noticeH: bannerDismissible && !draftConflict ? 29.3 : 28
    readonly property real bannerShownH: (bannerText || draftConflict ? noticeH : 0) + noteH
    /// Another device's different draft for this chat (Teams' roamed-draft
    /// conflict): the banner offers "View draft" until it is resolved.
    property bool draftConflict: false
    function showBanner(text, danger, decayMs, dismissible) {
        bannerText = text; bannerDanger = !!danger; bannerDismissible = dismissible !== false
        bannerDecay.interval = decayMs || 3000; bannerDecay.restart()
    }
    Timer { id: bannerDecay; onTriggered: root.bannerText = "" }
    // The Enter setting: "send" (Teams' Default) or "newline".
    property string enterKey: backend.setting("enterKey") || "send"
    readonly property alias editor: input
    readonly property bool empty: input.length === 0 && files.length === 0 && cloudFiles.length === 0 && !quote && !clip && !loop
    // Once the text wraps the box stays multiline until it is empty again
    // (Teams 461103 / 458473).
    property bool grown: false
    // Teams' link preview (TASK-0148): the first link in the message gets
    // one from Teams' URL preview service, 125 ms after the text changes.
    // {url, title, description, thumbnail, thumbnail_meta, enabled}; the
    // X turns it off for that link (it is sent with previewenabled false),
    // a different first link fetches again. Off with Optional connected
    // experiences or the messaging policy, in a forwarded message and in
    // edits.
    property var urlPreview: null
    /// The first link the preview is for ("" while there is none).
    property string previewUrl: ""
    /// Link previews are allowed here (the conversation decides).
    property bool previewsAllowed: true
    readonly property bool previewShown: (!!urlPreview && urlPreview.enabled || appCardCollapsedShown) && previewsAllowed && !editing && cloudFiles.length === 0 && !clip
    // An app's link card (TASK-0168): a link to a site with a Teams app gets
    // that app's card (api::link_unfurl), which Collapse preview turns into
    // the plain preview (sent so) and X removes.
    property var appCard: null
    /// An app's sign-in window for the link card (AppAuthWindow); the
    /// newest is kept for --app-auth-test.
    property var lastAuthWindow: null
    function openAppAuth(u, domains) {
        const w = authWindow.createObject(null, { url: u, validDomains: domains })
        lastAuthWindow = w
        w.finished.connect((ok, result) => {
            if (ok) backend.appLinkAction("requery", root.previewUrl, root.chatId, result)
            Qt.callLater(() => w.destroy())
        })
        w.show()
    }
    /// Show Preview was pressed: the next sign-in answer opens its window.
    property bool autoPopupNext: false
    function showPreview() { autoPopupNext = true; backend.appLinkAction("install", root.previewUrl, root.chatId, root.appCard.app_id) }
    /// The conversation the link's app is asked from.
    property string chatId: ""
    // (An app's compose action can put its card here too: `fromApp`.)
    readonly property bool appCardShown: !!appCard && !appCard.removed && !appCard.collapsed && (previewsAllowed || appCard.fromApp === true) && !editing && cloudFiles.length === 0 && !clip
    readonly property bool appCardCollapsedShown: !!appCard && !appCard.removed && appCard.collapsed === true && !!appCard.preview
    readonly property var shownPreview: appCardCollapsedShown ? Object.assign({}, appCard.preview, { enabled: true }) : urlPreview
    function firstLink() {
        const m = String(formattedText()).match(/<a\s+href="([^"]+)"/g) || []
        for (const a of m) {
            const href = a.replace(/^<a\s+href="/, "").replace(/"$/, "").replace(/&amp;/g, "&")
            if (!href.startsWith("mention")) return href
        }
        return ""
    }
    Timer {
        id: linkWatch
        interval: 125
        onTriggered: {
            if (!root.previewsAllowed || root.editing) { root.previewUrl = ""; root.urlPreview = null; return }
            const url = root.firstLink()
            if (url === root.previewUrl) return
            root.previewUrl = url
            root.urlPreview = null
            if (!(root.appCard && root.appCard.fromApp)) root.appCard = null
            if (url) backend.fetchLinkPreview(url, root.chatId)
        }
    }
    Connections {
        target: backend
        function onUrlPreviewFetched(url, json) {
            if (url !== root.previewUrl || !json) return
            try { root.urlPreview = JSON.parse(json) } catch (e) {}
        }
        function onAppLinkCardFetched(url, json) {
            if (url !== root.previewUrl || !json || (root.appCard && root.appCard.fromApp)) return
            try { root.appCard = JSON.parse(json) } catch (e) {}
            // Teams (707715): after Show Preview installed the app, a
            // sign-in or setup answer opens the app's window by itself
            // (shouldAutoPopup).
            if (root.autoPopupNext && root.appCard && (root.appCard.permission === "auth" || root.appCard.permission === "config")
                    && (root.appCard.auth_url || "").indexOf("https://") === 0)
                root.openAppAuth(root.appCard.auth_url, root.appCard.valid_domains || [])
            root.autoPopupNext = false
        }
    }
    /// What goes with the message: the preview (on or removed), or "".
    function previewForSend() {
        if (!previewsAllowed || editing) return ""
        const link = firstLink()
        if (!link) return ""
        if (appCard && link === previewUrl) {
            // A removed app card goes as its preview turned off (Teams' X).
            if (appCard.removed) return appCard.preview ? JSON.stringify(Object.assign({}, appCard.preview, { enabled: false })) : ""
            return ""
        }
        if (urlPreview && link === previewUrl) return JSON.stringify(urlPreview)
        // Not fetched yet (sent at once): Teams gets it as it sends.
        return "fetch"
    }
    /// The app card that goes with the message (as its card, or collapsed as
    /// its preview), or "".
    function appCardForSend() {
        if (appCard && appCard.fromApp && !appCard.removed && !editing) {
            const a = Object.assign({}, appCard)
            delete a.removed; delete a.fromApp
            return JSON.stringify(a)
        }
        if (!previewsAllowed || editing || !appCard || appCard.removed || firstLink() !== previewUrl) return ""
        const c = Object.assign({}, appCard)
        delete c.removed
        return JSON.stringify(c)
    }
    function setAppCard(changes) { root.appCard = Object.assign({}, root.appCard, changes) }
    // Teams' AutoLink: a web address becomes a link when Space or Enter
    // follows it (more than 5 characters; trailing punctuation and an
    // unmatched closing bracket stay outside), or when the whole pasted
    // text is one.
    readonly property var webLink: /^(?:https?:\/\/|www\.)(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?::[0-9]+)?(?:[\/?]\S*)?$/i
    readonly property var badLink: /^[^?]+%[^0-9a-f]+|^[^?]+%[0-9a-f][^0-9a-f]+|^[^?]+%00|^[^?]+%$|^https?:\/\/[^?\/]+@|^www\.[^?\/]+@/i
    function linkHref(word) {
        if (!webLink.test(word) || badLink.test(word)) return ""
        return /^www\./i.test(word) ? "http://" + word : word
    }
    function linkRange(a, b) {
        const word = input.getText(a, b)
        const href = linkHref(word)
        if (!href || JSON.parse(rich.state(b)).link) return false
        rich.apply(a, b, "link", href + "\t" + word)
        return true
    }
    function autoLinkBeforeCursor() {
        const end = input.cursorPosition
        const before = input.getText(Math.max(0, end - 2048), end)
        const m = before.match(/\S+$/)
        if (!m) return
        let word = m[0]
        if (word.length <= 5) return
        let start = end - word.length
        word = word.replace(/[.+=\s:;"',>]+$/i, "")
        for (const [o, c] of [["(", ")"], ["{", "}"], ["[", "]"]])
            while (word.endsWith(c) && word.split(o).length < word.split(c).length) word = word.slice(0, -1)
        if (linkRange(start, start + word.length)) {
            input.cursorPosition = end
            // The Space or Enter that follows is not part of the link.
            const after = end
            Qt.callLater(() => { if (input.cursorPosition > after) { rich.apply(after, input.cursorPosition, "unlink", ""); input.cursorPosition = after + 1 } })
        }
    }
    property int pasteFrom: -1
    function autoLinkPaste() {
        const a = pasteFrom, b = input.cursorPosition
        pasteFrom = -1
        if (a < 0 || b <= a) return
        const text = input.getText(a, b)
        const t = text.trim()
        if (!t || /\s/.test(t)) return
        const lead = text.indexOf(t)
        linkRange(a + lead, a + lead + t.length)
        input.cursorPosition = b
    }
    // Editing always uses the multiline layout (Teams, measured).
    /// Teams' compact compose (pane under 480 px): the editor across the
    /// box and the tools in the bottom row.
    property bool compact: false
    signal appCardSettingsRequested()
    signal appCardPermissionsRequested(string appId)
    readonly property bool multiline: !!loop || hasPastedPicture || appCardShown || !!sendTo || scheduleAt > 0 || post || editing || compact || formatting || files.length > 0 || cloudFiles.length > 0 || !!quote || !!clip || grown || previewShown
    // Teams' channel post composer.
    property bool post: false
    property bool announcement: false
    property string subject: ""
    property string headline: ""
    property string bannerTheme: "0"
    // The banner's picture (the cropped PNG) and its size.
    property string bannerImage: ""
    property int bannerImageW: 0
    property int bannerImageH: 0
    readonly property real bannerH: bannerImage ? 200 : 244
    readonly property bool postEmpty: empty && !subject.trim() && !headline.trim() && !bannerImage
    // The post composer's "+" items (measured on winpc 2026-11-24,
    // TASK-0265, new posts and post edits alike): Change permissions ("Who
    // can reply": Everyone / You and moderators, Teams' replyPermission
    // "AuthorAndOwners") and Post in other channels ("Post in": This channel
    // / Multiple channels). Multiple channels adds Teams' cross-post row
    // under the author row (cross-post-toolbar: a 24 px "+" with a 0.67
    // #D1D1D1 edge 16.7 in, 10.3 under the row, then the channels as 95 x
    // 24 #F5F5F5 chips 100 apart from 49.7: the team's picture 24, the
    // channel's name 14 px at 29, a 20 px remove button at the end of the
    // other channels'); "+" opens Choose channels. Editing a post shows its
    // own, as Teams does: Close for Discard, no Announcement, Post saves.
    property string replyPermission: ""
    property string replyPermissionAtStart: ""
    property bool crossPost: false
    /// The post's other channels (ids), and those it had when the edit
    /// began (null until read).
    property var crossChannels: []
    property var crossChannelsAtStart: null
    property string crossPostId: ""
    readonly property string postChannelId: String(root.chatId || backend.currentChatId)
    readonly property real crossRowH: post && crossPost ? 43.4 : 0
    /// The chips in Teams' order: the post's channel first, or (editing a
    /// cross-post) its channels as Teams lists them, the post's own last.
    readonly property var crossChips: root.editing ? root.crossChannels.concat([root.postChannelId]) : [root.postChannelId].concat(root.crossChannels)
    /// The post's team's thread (the cross-post call names it).
    readonly property string postTeamThread: {
        for (const t of (backend.teamsJson ? JSON.parse(backend.teamsJson) : []))
            if ((t.channels || []).some(c => c.id === root.postChannelId)) return t.thread_id || ""
        return ""
    }
    function channelInfo(id) {
        for (const t of (backend.teamsJson ? JSON.parse(backend.teamsJson) : [])) {
            const c = (t.channels || []).find(c => c.id === id)
            if (c) return { team: t, name: c.general ? qsTr("General") : c.name }
        }
        return { team: null, name: "" }
    }
    Connections {
        target: backend
        enabled: root.post && root.editing && !!root.crossPostId
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "cross-post-channels" || !r.ok || !r.data || r.data.crossPostId !== root.crossPostId) return
            root.crossChannels = (r.data.channels || []).filter(c => c !== root.postChannelId)
            root.crossChannelsAtStart = root.crossChannels.slice()
        }
    }
    signal closeRequested()
    // The formatting bar shows (always in the post composer).
    readonly property bool fmtOn: formatting || post
    // The delivery header ("IMPORTANT!") is 26 tall above the editor; the
    // post composer's author row and subject (and banner) are above it.
    readonly property real headerH: post ? 57.3 + crossRowH + (announcement ? 12 + bannerH + 12 : 0) + 55.7 : importance ? 26 : sendTo || scheduleAt > 0 ? 25 : 0
    readonly property real boxHeight: post ? headerH + 43 + editorArea.height + 16 + 31.3 + 17.4
        : headerH + (multiline
        ? (formatting ? 43 : 0) + subjectRowH + editorArea.height + 44.7
        : Math.max(45.3, input.contentHeight + 18 + 7.3))
    signal submit()
    signal cancelled()
    signal quoteDismissed()
    signal fileRemoved(string path)
    signal emojiRequested(Item anchor)
    signal attachRequested(Item anchor)
    /// A cloud file's card closed (Remove attachment).
    signal cloudRemoved(string key)
    /// The card's link description: Teams' Link settings for that file.
    signal cloudLinkRequested(string key)
    /// The Loop component's link description: its link settings.
    /// The Loop component's Link settings (its file and current choice:
    /// scope as OneDriveShare numbers them, edit).
    signal loopLinkRequested(var fileRef, string fileName, int scope, bool edit)
    /// "+" ▸ Record video clip (offered where `canRecordClip`).
    signal recordClipRequested()
    property bool canRecordClip: false
    /// A recorded clip in the box (Teams puts it before the text):
    /// {path, thumb, width, height, duration, id, url, uploading, error}.
    property var clip: null
    /// The new chat form's box: there is no chat yet, so a clip is stored
    /// once the chat is made (as the message goes), and "+" is Teams' short
    /// list (Set delivery options, Schedule meeting, Record video clip; no
    /// app search).
    property bool newConversation: false
    signal clipRemoved()
    signal clipRetry()
    signal typed()
    signal settingsRequested()
    width: 748
    height: bannerShownH + boxHeight + 2 + (post ? 0 : 16)

    function plainText() { return input.getText(0, input.length) }
    // Teams' editor viewport stops growing at 270 (27rem, the editor's
    // 18 of padding included) and scrolls (measured on winpc 2026-11-20:
    // compose-editor-viewport max-height 27rem, overflow-y auto), so the
    // box and its banners stay in view. The post composer grows as before.
    readonly property real textMaxH: root.post ? 1e6 : 270 - 18
    readonly property real textH: Math.min(input.contentHeight, textMaxH)
    readonly property real inputTop: clipCardBox.visible ? clipCardBox.y + clipCardBox.height + 2 : quoteCard.visible ? 14 + quoteCard.height + 4 : fileChips.visible ? fileChips.y + fileChips.height + 8 : 10
    readonly property real textBottom: inputTop + textH
    property real textScroll: 0
    readonly property real maxTextScroll: Math.max(0, input.contentHeight - textH)
    onMaxTextScrollChanged: if (textScroll > maxTextScroll) textScroll = maxTextScroll
    function keepCursorInView() {
        const r = input.cursorRectangle
        if (r.y < textScroll) textScroll = Math.max(0, r.y)
        else if (r.y + r.height > textScroll + textH) textScroll = Math.min(maxTextScroll, r.y + r.height - textH)
    }
    // Teams' Editor: this box's text is checked as you type (one tile of
    // the Editor session); misspellings are squiggled and clicking one
    // opens Teams' Editor card.
    readonly property string editorDoc: "compose-" + Math.random().toString(36).slice(2)
    property var critiques: []
    property var openCritique: null
    Connections {
        target: backend
        function onEditorCritiques(doc, json) { if (doc === root.editorDoc) { root.critiques = JSON.parse(json); root.autoCorrect() } }
    }
    // Teams' "Correct words while typing": a critique whose first suggestion
    // may be applied automatically is, once the word is finished, in the
    // languages that have it on (Settings ▸ General ▸ Editor spellcheck).
    property var autoCorrected: ({})
    function autoCorrect() {
        const auto = root.critiques.filter(c => c.autocorrect && c.suggestions.length && !autoCorrected[c.id])
        if (!auto.length) return
        const langs = JSON.parse(backend.editorSettingsJson()).autocorrect
        const text = plainText()
        for (const c of auto) {
            const after = text.charAt(c.start + c.length)
            const done = after !== "" && /[\s.,;:!?)]/.test(after) && (input.cursorPosition < c.start || input.cursorPosition > c.start + c.length)
            if (!done || (c.language && langs.indexOf(c.language) < 0)) continue
            autoCorrected[c.id] = true
            const pos = input.cursorPosition
            input.remove(c.start, c.start + c.length)
            input.insert(c.start, c.suggestions[0])
            input.cursorPosition = pos + c.suggestions[0].length - c.length
            return
        }
    }
    Component.onDestruction: backend.editorClose(editorDoc)
    function checkSpelling() { backend.editorSetText(editorDoc, plainText()) }
    /// Test hooks: open the card of the i-th critique; close it.
    function critiqueCardForTest(i) { if (critiques[i]) openEditorCard(critiques[i]) }
    function closeCardForTest() { editorCard.close() }
    function applySuggestion(c, s) {
        input.remove(c.start, c.start + c.length)
        input.insert(c.start, s)
        input.cursorPosition = c.start + s.length
        input.forceActiveFocus()
    }
    function openEditorCard(c) {
        const r = input.positionToRectangle(c.start)
        const p = input.mapToItem(root, r.x, r.y)
        root.openCritique = c
        editorCard.critique = c
        // Above the word, its suggestions lined up with it; below when there
        // is no room.
        editorCard.x = Math.max(0, Math.min(root.width - editorCard.width, p.x - 16))
        // Its height from its parts (the suggestions aren't laid out yet).
        const h = 38 + 36 * c.suggestions.length + 45.3
        const top = root.mapToItem(null, 0, p.y).y
        editorCard.y = top - h - 6 >= 0 ? p.y - h - 6 : p.y + r.height + 6
        editorCard.open()
    }
    EditorCard {
        id: editorCard
        parent: root
        onPicked: s => { const c = root.openCritique; if (c) root.applySuggestion(c, s) }
        onIgnoreAll: if (root.openCritique) backend.editorIgnoreWord(root.openCritique.word)
        onAddToDictionary: if (root.openCritique) backend.editorAddWord(root.openCritique.word)
        onClosed: root.openCritique = null
    }
    // The text as clean HTML (RichText), for Teams' message HTML.
    function formattedText() { return rich.exportHtml() }
    // What applies at the cursor (the formatting bar's pressed buttons),
    // and where the quotes and code blocks are.
    property var richState: ({})
    property var richRegions: []
    function refreshRichState() {
        try { richState = JSON.parse(rich.state(input.cursorPosition)) } catch (e) { richState = ({}) }
        try { richRegions = JSON.parse(rich.regions()) } catch (e) { richRegions = [] }
    }
    // The code card's More options (Teams' code block menu, measured on
    // winpc 2026-11-10: 195 wide; "Display option" 32 tall in #616161, then
    // the "Auto-detect language" check item, its check 6 in and the label
    // at 50). Teams also offers "Make this collaborative" (a Loop
    // component; OST has no Loop yet).
    Popup {
        id: codeMenu
        property var region: null
        parent: Overlay.overlay
        width: 195; padding: 4
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Column {
            Item {
                width: parent.width; height: 32
                Text { x: 6; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Display option"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            }
            Rectangle {
                id: hcFill1
                width: parent.width; height: 32; radius: 4
                color: autoHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { visible: !!codeMenu.region && codeMenu.region.auto === true; x: 6; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.onFill(hcFill1, theme.textStrong) }
                Text { x: 50; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Auto-detect language"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill1, theme.textStrong) }
                HoverHandler { id: autoHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        const r = codeMenu.region
                        codeMenu.close()
                        if (r) { rich.apply(r.start, r.start, "autolang", r.auto ? "0" : "1"); root.refreshRichState() }
                    }
                }
                Accessible.role: Accessible.CheckBox
                Accessible.checked: !!codeMenu.region && codeMenu.region.auto === true
                Accessible.name: qsTr("Auto-detect language")
            }
        }
    }
    // Teams' code block languages (id, name), as its editor lists them.
    readonly property var codeLanguages: [["plaintext", qsTr("Plain Text")], ["bash", "Bash"], ["c", "C"], ["cpp", "C++"], ["csharp", "C#"], ["css", "CSS"],
        ["dart", "Dart"], ["dockerfile", "DockerFile"], ["dos", "DOS"], ["go", "Go"], ["graphql", "GraphQL"], ["html", "HTML"], ["http", "HTTP"],
        ["java", "Java"], ["javascript", "JavaScript"], ["json", "JSON"], ["jsp", "JSP"], ["jsx", "JSX"], ["kotlin", "Kotlin"], ["kql", "KQL"],
        ["latex", "LaTeX"], ["lisp", "Lisp"], ["markdown", "Markdown"], ["objectivec", "Objective-C"], ["octave", "Octave"], ["perl", "Perl"],
        ["php", "PHP"], ["powershell", "PowerShell"], ["python", "Python"], ["r", "R"], ["ruby", "Ruby"], ["rust", "Rust"], ["scala", "Scala"],
        ["scss", "SCSS"], ["shell", "Shell"], ["sql", "SQL"], ["swift", "Swift"], ["typescript", "TypeScript"], ["vbnet", "VB.NET"],
        ["vbscript", "VBScript"], ["verilog", "Verilog"], ["vhdl", "VHDL"], ["xml", "XML"], ["yaml", "YAML"]]
    function codeLanguageName(id) { const l = codeLanguages.find(l => l[0] === id); return l ? l[1] : qsTr("Plain Text") }
    MenuPopup {
        id: langMenu
        parent: Overlay.overlay
        property var region: null
        items: root.codeLanguages.map(l => ({ label: l[1], checked: !!langMenu.region && langMenu.region.lang === l[0] }))
        height: Math.min(implicitHeight, 320)
        onPicked: i => { if (region) { rich.apply(region.start, region.start, "lang", root.codeLanguages[i][0]); root.refreshRichState() } }
    }
    // A formatting bar command on the selection (or the word at the cursor).
    function format(op, arg) {
        const a = input.selectionStart, b = input.selectionEnd
        rich.apply(a, b, op, arg || "")
        // A new table takes the cursor into its first cell, as in Teams.
        if (op === "table") {
            for (let p = Math.max(a, b); p <= Math.max(a, b) + 3 && p <= input.length; p++)
                if (JSON.parse(rich.state(p)).table) { input.cursorPosition = p; break }
        }
        input.forceActiveFocus()
        refreshRichState()
    }
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function setPlain(t) { input.clear(); if (t) input.insert(0, escapeHtml(t)) }
    function setHtml(h) { input.clear(); if (h) input.insert(0, h); input.cursorPosition = input.length }
    function clear() { input.clear(); media = []; urlPreview = null; appCard = null; previewUrl = ""; loop = null }
    // The box as a draft, which Teams keeps with its formatting: the text
    // (the Drafts list's preview), RichText's HTML and the pictures in it.
    // A box holding a Loop component isn't kept as a draft: Teams drops
    // the whole draft (its text too) when you leave the chat, and the
    // component's file stays in your chat files (seen on winpc
    // 2026-11-20, OST group test, three times).
    function draftState() {
        const text = plainText()
        if (root.loop) return { text: "", html: "", media: [], loop: true }
        return { text: text, html: text.trim() ? formattedText() : "", media: text.trim() ? mediaInUse() : [], loop: false }
    }
    // A kept draft back in the box, as it was typed ({text, html, media};
    // a draft from before formatting was kept has only text).
    function setDraftState(d) {
        input.clear()
        media = d && d.media ? d.media : []
        root.loop = null
        // One taken from another device (Teams' roamed draft) is in a sent
        // message's form, so it loads as editing one does.
        if (d && d.editHtml) { setMessage({ edit_html: d.editHtml, edit_media: d.editMedia || [] }); refreshRichState(); return }
        if (d && d.html) { rich.importHtml(d.html, String(theme.brandForeground1)); input.cursorPosition = input.length; refreshRichState() }
        else if (d && d.text) input.insert(0, escapeHtml(d.text))
    }
    // One of your messages to edit: its edit form keeps the emoticons,
    // custom emoji and pictures (as Teams' edit does); else its text.
    function setMessage(m) {
        media = m.edit_media || []
        if (root.editing) {
            root.importance = m.importance === "high" || m.importance === "urgent" ? m.importance : ""
            root.editFiles = (m.files || []).filter(f => !!f.object_url)
                .map(f => ({ key: f.object_url, name: f.name || "", kind: f.file_type || "", existing: true }))
            root.editFilesAtStart = root.editFiles.map(f => f.key)
            root.editClip = (m.videos || []).length ? m.videos[0] : null
            root.removedClips = []
            const lc = (m.cards || []).find(c => c.content_type === "application/vnd.microsoft.card.fluidEmbedCard" && c.content && c.content.componentUrl)
            root.editLoop = lc ? { url: String(lc.content.componentUrl), name: "", description: "" } : null
            root.removedLoops = []
            if (root.editLoop) backend.loopHostRequest("editLoopInfo", "editloop:" + root.editorDoc, JSON.stringify({ url: root.editLoop.url }))
            if (root.post) {
                root.subject = m.subject || ""
                root.replyPermission = m.reply_permission === "AuthorAndOwners" ? "AuthorAndOwners" : ""
                root.replyPermissionAtStart = root.replyPermission
                root.crossPostId = m.cross_post_id || ""
                root.crossPost = !!root.crossPostId
                root.crossChannels = []
                root.crossChannelsAtStart = root.crossPostId ? null : []
                if (root.crossPostId) backend.channelAction("cross-post-channels", "", root.postChannelId, root.crossPostId)
            }
        }
        // Mention tokens in Teams' colour; a shared contact's icon.
        const tokens = String(m.edit_html || "").replace(/<a href="(mention[^"]*)">/g, '<a href="$1" style="color:' + theme.brandForeground1 + '; text-decoration:none">')
        setHtml(m.edit_html ? theme.messageHtml(tokens) : (m.html || escapeHtml(m.text || "")))
    }
    function insertText(t) { input.insert(input.cursorPosition, t); input.forceActiveFocus() }
    // What the fun picker put in: [{src, kind, id, title, unicode, url, width,
    // height}], each shown as an <img> with that src and sent in Teams' form.
    property var media: []
    function insertMedia(m) {
        media = media.concat([m])
        // As the compose box shows them: emoticons in the line (20), GIFs
        // fitted to 444 x 250 (as sent), stickers at 180.
        let w = 20, h = 20
        if (m.kind === "gif") {
            const s = Math.min(1, 444 / Math.max(1, m.width), 250 / Math.max(1, m.height))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        } else if (m.kind === "sticker") { w = 180; h = 180 }
        else if (m.kind === "image") {
            const s = Math.min(1, 240 / Math.max(1, m.width), 180 / Math.max(1, m.height))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        } else if (m.kind === "pasted") {
            // A pasted picture at its own size, at most as wide as the box
            // (Teams' max-width 100%).
            const s = Math.min(1, Math.max(40, input.width - 4) / Math.max(1, m.width))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        }
        input.insert(input.cursorPosition, "<img src=\"" + m.src + "\" width=\"" + w + "\" height=\"" + h + "\">")
        input.forceActiveFocus()
    }
    // The picked items still in the text.
    function mediaInUse() {
        const html = input.getFormattedText(0, input.length)
        return media.filter(m => html.indexOf(m.src) >= 0)
    }
    function focusEditor() { input.forceActiveFocus() }
    // Teams opens the post composer in its subject.
    function focusSubject() { if (post) subjectField.forceActiveFocus(); else input.forceActiveFocus() }
    function wrapSelection(tag) {
        format({ b: "bold", i: "italic", u: "underline", s: "strike", ul: "ul", ol: "ol" }[tag] || tag, "")
    }
    function requestCancel() { discardDialog.open() }

    // The compose banner.
    Rectangle {
        id: hcFill2
        visible: !!root.bannerText || root.draftConflict
        width: parent.width; height: root.noticeH + 4; radius: 4
        color: root.bannerDanger ? theme.pick("#FCF4F6", "#3E1F25", "#000000") : theme.pick("#E6E6E6", "#3D3D3D", "#000000")
        border.color: root.bannerDanger ? theme.pick("#F3D6D8", "#4F222B", "#FFFFFF") : theme.divider; border.width: 0.67
        Text {
            x: 16.7; y: root.noticeH === 28 ? 4 : 4.7; width: parent.width - 16.7 - (root.bannerDismissible && root.bannerText ? 36 : 16.7)
            elide: Text.ElideRight
            // Teams' RoamingDraftConflictBanner: its text and a "View draft" link.
            textFormat: root.bannerText ? Text.PlainText : Text.StyledText
            text: root.bannerText ? root.bannerText
                : qsTr("There's a draft saved from another platform") + "&nbsp;&nbsp;<a href=\"view\">" + qsTr("View draft") + "</a>"
            linkColor: theme.brandForeground1
            onLinkActivated: root.viewConflict()
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.onFill(hcFill2, root.bannerDanger && root.bannerText ? theme.pick("#C4314B", "#E73550", "#FFFFFF") : theme.textStrong)
            HoverHandler { enabled: !root.bannerText; cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Item {
            visible: root.bannerDismissible && !!root.bannerText
            x: parent.width - 28.7; y: 0.7; width: 28; height: 28
            FluentIcon { x: 3.5; y: 7.25; size: 16; name: "dismiss-16"; color: theme.onFill(hcFill2, closeBannerHover.hovered ? theme.brand : (root.bannerDanger ? theme.pick("#C4314B", "#E73550", "#FFFFFF") : theme.textStrong)) }
            HoverHandler { id: closeBannerHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.bannerText = "" }
            ToolTip.visible: closeBannerHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Close this notification")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close notification")
        }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.bannerText || qsTr("There's a draft saved from another platform")
    }
    Rectangle {
        visible: !!root.noteText
        y: root.bannerText || root.draftConflict ? root.noticeH : 0
        width: parent.width; height: root.noteH + 6; radius: 6
        color: theme.pick("#F0F0F0", "#2E2E2E", "#000000")
        Rectangle { width: parent.width; height: 0.67; color: theme.divider; radius: 6 }
        Text {
            id: noteLabel
            x: 16; y: 8; width: parent.width - 32
            wrapMode: Text.Wrap
            text: root.noteText
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.noteMuted ? theme.textSecondary : theme.textStrong
        }
        Accessible.role: Accessible.StaticText
        Accessible.name: root.noteText
    }
    // The post composer's elevation (Fluent shadow 8).
    FluentSurface { visible: root.post; y: box.y; width: box.width; height: box.height; depth: 8; radius: 6; color: theme.surface }
    Rectangle {
        id: box
        y: root.bannerShownH
        width: parent.width; height: root.boxHeight
        radius: 6
        color: theme.surface
        border.color: theme.divider
        border.width: 0.67
        clip: true

        // The post composer's author row, subject or banner and subheading.
        Item {
            id: postHead
            visible: root.post
            width: parent.width; height: root.post ? root.headerH : 0
            Item {
                x: 16.7; y: 0.7; width: parent.width - 33.3; height: 56.7
                Avatar { x: 0; y: 12; size: 32; name: backend.userName; photoId: backend.userMri || "" }
                Text {
                    x: 42; y: 18; text: backend.userName
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
                }
                Rectangle {
                    id: hcFill3
                    x: parent.width - 32; y: 12.3; width: 32; height: 31.3; radius: 4
                    color: postCloseHover.hovered ? theme.hover : "transparent"
                    // (Editing a post: Close.)
                    readonly property bool closes: root.postEmpty || root.editing
                    FluentIcon { anchors.centerIn: parent; size: 20; name: parent.closes ? "dismiss-20" : "delete-20"; color: theme.onFill(hcFill3, postCloseHover.hovered ? theme.brand : theme.textStrong) }
                    HoverHandler { id: postCloseHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.editing ? root.requestCancel() : root.postEmpty ? root.closeRequested() : root.requestCancel() }
                    Accessible.role: Accessible.Button
                    Accessible.name: closes ? qsTr("Close") : qsTr("Discard")
                }
                Rectangle { y: Math.round(parent.height - 1); width: parent.width; height: 1; color: theme.divider }
            }
            // Post in other channels: "+" and the channels.
            Item {
                id: crossRow
                visible: root.crossRowH > 0
                x: 16.7; y: 67.7; width: parent.width - 33.3; height: 26
                Rectangle {
                    id: crossAdd
                    y: 1; width: 24; height: 24; radius: 4
                    color: crossAddHover.hovered ? theme.hover : theme.surface
                    border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    FluentIcon { anchors.centerIn: parent; size: 12; name: "add-16"; color: theme.onFill(crossAdd, theme.text) }
                    HoverHandler { id: crossAddHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openChooseChannels() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Select cross post channels")
                }
                Row {
                    x: 33; y: 0; spacing: 3
                    Repeater {
                        model: root.crossChips
                        Item {
                            id: chip
                            required property string modelData
                            readonly property var info: root.channelInfo(modelData)
                            readonly property bool own: modelData === root.postChannelId
                            width: 97; height: 26
                            Rectangle {
                                x: 1; y: 1; width: 95; height: 24; radius: 4
                                color: theme.pick("#F5F5F5", "#333333", "#000000")
                                Avatar {
                                    size: 24; square: true; squareRadius: 4
                                    name: chip.info.team ? chip.info.team.name : ""
                                    initialsText: chip.info.team ? String(chip.info.team.name).split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
                                    photoId: chip.info.team ? "team:" + chip.info.team.id : ""
                                }
                                Text {
                                    x: 29; y: 2; width: (chip.own ? 95 : 75) - 29
                                    elide: Text.ElideRight
                                    text: chip.info.name
                                    font.family: theme.font; font.pixelSize: 14
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.text
                                }
                                Rectangle {
                                    id: chipRemove
                                    visible: !chip.own
                                    x: 75; y: 2; width: 20; height: 20; radius: 4
                                    color: chipRemoveHover.hovered ? theme.hover : "transparent"
                                    FluentIcon { anchors.centerIn: parent; size: 12; name: "dismiss-12"; color: theme.onFill(chipRemove, theme.textStrong) }
                                    HoverHandler { id: chipRemoveHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.crossChannels = root.crossChannels.filter(c => c !== chip.modelData) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: qsTr("Remove %1").arg(chip.info.name)
                                }
                                HoverHandler { id: chipHover }
                                ToolTip.visible: chipHover.hovered; ToolTip.delay: 500
                                ToolTip.text: (chip.info.team ? chip.info.team.name + " - " : "") + chip.info.name
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: (chip.info.team ? chip.info.team.name + " - " : "") + chip.info.name
                        }
                    }
                }
            }
            // Announcement: the banner.
            Rectangle {
                id: bannerEdit
                visible: root.announcement
                x: 12.7; y: 69.3 + root.crossRowH; width: parent.width - 25.3; height: root.bannerH; radius: 4
                // With a picture the headline is white over it.
                readonly property var colors: root.bannerImage ? [theme.banner(root.bannerTheme)[0], "#FFFFFF"] : theme.banner(root.bannerTheme)
                color: colors[0]
                clip: true
                Image {
                    visible: !!root.bannerImage
                    anchors.fill: parent
                    source: root.bannerImage
                    fillMode: Image.PreserveAspectCrop
                    smooth: true; mipmap: true
                }
                // Delete background image (32 x 33.3, 80% white, radius 6,
                // 12.7 from the top right).
                Rectangle {
                    id: hcFill4
                    visible: !!root.bannerImage
                    x: parent.width - 12.7 - width; y: 12.7; width: 32; height: 33.3; radius: 6
                    color: delImgHover.hovered ? theme.hc(theme.surface, theme.hcHighlight) : Qt.rgba(1, 1, 1, 0.8)
                    border.color: theme.stroke; border.width: 0.67
                    FluentIcon { anchors.centerIn: parent; size: 20; name: "delete-20"; color: theme.onFill(hcFill4, delImgHover.hovered ? theme.brand : theme.textStrong) }
                    HoverHandler { id: delImgHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.bannerImage = ""; root.bannerImageW = 0; root.bannerImageH = 0 } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Delete background image")
                }
                border.width: 0.67
                border.color: parseInt(root.bannerTheme, 10) >= 6 ? Qt.rgba(1, 1, 1, theme.dark ? 0.1 : 0.2) : Qt.rgba(0, 0, 0, theme.dark ? 0.1 : 0.05)
                TextEdit {
                    id: headlineEdit
                    x: 1.3 + 12; width: parent.width - 2.7 - 24
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: TextEdit.AlignHCenter
                    wrapMode: TextEdit.Wrap
                    text: root.headline
                    onTextChanged: {
                        if (text.length > 44) { const c = cursorPosition; text = text.slice(0, 44); cursorPosition = Math.min(c, 44) }
                        if (text !== root.headline) root.headline = text
                    }
                    font.family: theme.font; font.pixelSize: 40; font.weight: Font.DemiBold
                    color: theme.onFill(bannerEdit, bannerEdit.colors[1])
                    selectionColor: theme.selectionFill
                    Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) root.trySubmit(); else subjectField.forceActiveFocus() }
                    Text {
                        visible: !headlineEdit.text && !headlineEdit.preeditText
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Type a headline"); font: headlineEdit.font; color: theme.onFill(bannerEdit, bannerEdit.colors[1])
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Type a headline")
                }
                Rectangle {
                    x: parent.width - 12.8 - width; y: parent.height - 12.6 - height
                    width: 65.3; height: 32.7; radius: 4
                    color: theme.surface
                    Rectangle {
                        id: schemeButton
                        x: 0.7; y: 0.7; width: 32; height: 31.3; radius: 4
                        color: schemeHover.hovered ? theme.hover : "transparent"
                        Rectangle {
                            anchors.centerIn: parent; width: 16; height: 16; radius: 4
                            color: bannerEdit.colors[0]
                            border.width: 0.67; border.color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.2)
                        }
                        HoverHandler { id: schemeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: schemes.opened ? schemes.close() : schemes.open() }
                        ToolTip.visible: schemeHover.hovered && !schemes.opened; ToolTip.delay: 500; ToolTip.text: qsTr("Color scheme")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Color scheme") + ", " + theme.bannerNames[parseInt(root.bannerTheme, 10) || 0]
                        // Teams' scheme picker: 12 swatches (16, radius 4) in
                        // two rows of six, 28 apart, above the button with its
                        // right edge on the button's.
                        Popup {
                            id: schemes
                            x: parent.width - width; y: -height - 0.7
                            width: 181.3; height: 69.3; padding: 0
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            Repeater {
                                model: 12
                                Rectangle {
                                    required property int index
                                    x: 12.6 + 28 * (index % 6); y: 12.7 + 28 * Math.floor(index / 6)
                                    width: 16; height: 16; radius: 4
                                    color: theme.banner(String(index))[0]
                                    border.width: 0.67; border.color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.2)
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { root.bannerTheme = String(parent.index); schemes.close() } }
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.checked: root.bannerTheme === String(index)
                                    Accessible.name: theme.bannerNames[index]
                                }
                            }
                        }
                    }
                    Rectangle {
                        id: hcFill5
                        x: 32.7; y: 0.7; width: 32; height: 31.3; radius: 4
                        color: uploadHover.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; size: 20; name: "image-add-20"; color: theme.onFill(hcFill5, uploadHover.hovered ? theme.brand : theme.textStrong) }
                        HoverHandler { id: uploadHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: bannerImageDialog.start() }
                        ToolTip.visible: uploadHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Upload an image")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Upload an image")
                    }
                }
            }
            // Add a subject / Add a subheading.
            Item {
                x: 10.7; y: 57.3 + root.crossRowH + (root.announcement ? 12 + root.bannerH + 12 : 0)
                width: parent.width - 21.3; height: 55.7
                TextInput {
                    id: subjectField
                    x: 12; y: 15; width: parent.width - 24; height: 24
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 250
                    text: root.subject
                    onTextEdited: root.subject = text
                    font.family: theme.font; font.pixelSize: 18
                    color: theme.text
                    selectionColor: theme.selectionFill
                    selectByMouse: true
                    clip: true
                    Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) root.trySubmit(); else input.forceActiveFocus() }
                    Keys.onTabPressed: input.forceActiveFocus()
                    Text {
                        visible: !subjectField.text && !subjectField.preeditText
                        text: root.announcement ? qsTr("Add a subheading") : qsTr("Add a subject")
                        font: subjectField.font; color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: root.announcement ? qsTr("Add a subheading") : qsTr("Add a subject")
                }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width
                    height: subjectField.activeFocus ? 2 : 0.67
                    color: subjectField.activeFocus ? theme.brand : theme.textSecondary
                }
            }
        }

        // The delivery option header (measured): 14/20 bold uppercase,
        // DarkOrange foreground for Important, 16 in, 26 tall.
        Text {
            visible: !!root.importance
            x: 16.7; y: 3; height: 20; verticalAlignment: Text.AlignVCenter
            text: (root.importance === "urgent" ? qsTr("Urgent!") : qsTr("Important!")).toUpperCase()
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
            color: root.importance === "urgent" ? theme.redForeground3 : theme.pick("#DA3B01", "#E9835E", "#FFFFFF")
        }
        // "Send to: thread only ⌄" (measured on winpc 2026-11-10): 12 px
        // brand, "Send to:" bold, a 12 px chevron 4 after; 12 in, 5 down. Its
        // menu (Thread only / Thread and channel) opens above it.
        Item {
            id: sendToRow
            visible: !!root.sendTo
            x: 12; y: 5; height: 20
            width: sendToLabel.implicitWidth + 4 + 12
            Text {
                id: sendToLabel
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: root.sendTo === "channel" ? qsTr("<strong>Send to:</strong> thread and channel") : qsTr("<strong>Send to:</strong> thread only")
                font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
            }
            FluentIcon { x: sendToLabel.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.brandForeground1 }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sendToMenu.open() }
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: sendToLabel.text.replace(/<[^>]+>/g, "")
            MenuPopup {
                id: sendToMenu
                y: -height - 4; x: -35
                items: [{ label: qsTr("Thread only"), checked: root.sendTo !== "channel" }, { label: qsTr("Thread and channel"), checked: root.sendTo === "channel" }]
                onPicked: i => { root.sendTo = i === 1 ? "channel" : "thread"; input.forceActiveFocus() }
            }
        }
        Item {
            visible: root.subjectRowH > 0
            x: 10.7; y: root.headerH + 43
            width: parent.width - 21.3; height: 55.7
            TextInput {
                id: threadSubjectField
                x: 12; y: 15; width: parent.width - 24; height: 24
                verticalAlignment: TextInput.AlignVCenter
                maximumLength: 250
                text: root.subject
                onTextEdited: root.subject = text
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                color: theme.text
                selectionColor: theme.selectionFill
                selectByMouse: true
                clip: true
                Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) root.trySubmit(); else input.forceActiveFocus() }
                Keys.onTabPressed: input.forceActiveFocus()
                Text {
                    visible: !threadSubjectField.text && !threadSubjectField.preeditText
                    text: qsTr("Add a subject")
                    font: threadSubjectField.font; color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Add a subject")
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width
                height: threadSubjectField.activeFocus ? 2 : 0.67
                color: threadSubjectField.activeFocus ? theme.brand : theme.pick("#4D4D4D", "#ADADAD", "#000000")
            }
        }
        // "Select Send to deliver on {day} at {time} ⌄" while the message
        // is scheduled (12 px brand, "Send" — "Post" in a channel's post
        // composer — bold; 12 in, 5 down); it reopens the schedule with
        // "Cancel scheduled time".
        Item {
            id: scheduleRow
            visible: root.scheduleAt > 0 && !root.sendTo
            x: 12; y: 5; height: 20
            width: scheduleLabel.implicitWidth + 4 + 12
            Text {
                id: scheduleLabel
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: root.scheduleText(root.editing ? qsTr("Select <strong>Done</strong> to deliver on %1 at %2") : root.post ? qsTr("Select <strong>Post</strong> to deliver on %1 at %2") : qsTr("Select <strong>Send</strong> to deliver on %1 at %2"), root.scheduleAt)
                font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
            }
            FluentIcon { x: scheduleLabel.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.brandForeground1 }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: schedulePopup.openFor(scheduleRow, !root.editing) }
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: scheduleLabel.text.replace(/<[^>]+>/g, "")
        }
        // The formatting bar (Teams' simplified-formatting-toolbar).
        FormatBar {
            id: formatBar
            tierWidth: root.tierWidth
            visible: root.fmtOn
            post: root.post
            announcementButton: !root.editing
            onAnnouncementToggled: { root.announcement = !root.announcement; if (root.announcement) headlineEdit.forceActiveFocus() }
            x: root.post ? 0.7 : 0; y: root.headerH; width: parent.width
            editing: root.editing
            st: root.richState
            selectedText: input.selectedText
            onCommand: (op, arg) => root.format(op, arg)
            onDiscardRequested: root.requestCancel()
            onUndoRequested: { input.undo(); input.forceActiveFocus() }
            onRedoRequested: { input.redo(); input.forceActiveFocus() }
        }

        // The editor: across the box (multiline) or left of the side toolbar.
        Item {
            id: editorArea
            // Text scrolled out of Teams' viewport is covered (above the
            // text, under the cards and quote).
            Rectangle {
                visible: root.maxTextScroll > 0
                z: 1; width: parent.width; height: Math.max(0, root.inputTop)
                color: box.color
            }
            Rectangle {
                visible: root.maxTextScroll > 0
                z: 1; y: root.textBottom; width: parent.width; height: Math.max(0, input.contentHeight - root.textScroll - root.textH + 8)
                color: box.color
            }
            WheelHandler {
                enabled: root.maxTextScroll > 0
                onWheel: e => { root.textScroll = Math.max(0, Math.min(root.maxTextScroll, root.textScroll - e.angleDelta.y / 2)); e.accepted = true }
            }
            x: root.post ? 11.3 : 0.67
            y: root.headerH + (root.fmtOn ? 43 : 0.67) + root.subjectRowH
            width: root.post ? parent.width - 11.3 : root.multiline ? parent.width - 1.33 : parent.width - 1.33 - sideTools.width
            height: loopCard.visible ? loopCard.y + loopCard.height + 10
                : editLoopCard.visible ? editLoopCard.y + editLoopCard.height + 10
                : cloudCards.visible ? cloudCards.y + cloudCards.height + 13.9
                : previewCard.visible ? previewCard.y + previewCard.height + 6
                : appLinkCard.visible ? appLinkCard.y + appLinkCard.height + 8
                : clipCardBox.visible ? root.textBottom + 8
                : Math.max(root.fmtOn ? 104 : 38, quoteCard.visible ? 14.7 + quoteCard.height + 4 + root.textH + 8 : root.textH + 18)
            // Teams' quote box and code card behind the text's quote and
            // code runs (RichText marks them; their margins make room).
            Repeater {
                model: root.richRegions
                Item {
                    id: region
                    required property var modelData
                    readonly property rect r0: input.positionToRectangle(modelData.start)
                    readonly property rect r1: input.positionToRectangle(modelData.end)
                    readonly property bool code: modelData.kind === "code"
                    x: input.x; width: input.width
                    y: input.y + r0.y - (code ? 40 : 7)
                    height: r1.y + r1.height + (code ? 8 : 7) - (r0.y - (code ? 40 : 7))
                    Rectangle {
                        anchors.fill: parent
                        radius: region.code ? 8 : 4
                        color: theme.surface
                        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    }
                    // The quote's bar.
                    Rectangle { visible: !region.code; x: 3; y: 3; width: 2.67; height: parent.height - 6; radius: 1.5; color: theme.pick("#D1D1D1", "#666666", "#000000") }
                    // The code card's header: icon, language (a menu), and
                    // the line under it; line numbers in the gutter.
                    Item {
                        visible: region.code
                        width: parent.width; height: 32
                        // Teams: the icon, language and chevron #424242
                        // (measured 2026-11-10), More options at the end.
                        FluentIcon { x: 10.7; anchors.verticalCenter: parent.verticalCenter; name: "code-block-20"; size: 20; color: theme.textStrong }
                        Row {
                            x: 36.7; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            Text {
                                text: region.modelData.lang ? root.codeLanguageName(region.modelData.lang) : qsTr("Plain Text")
                                font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                            }
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textStrong }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { langMenu.region = region.modelData; const p = region.mapToItem(Overlay.overlay, 36.7, 32); langMenu.x = p.x; langMenu.y = p.y; langMenu.open() } }
                        }
                        Rectangle { y: 31.3; width: parent.width; height: 0.67; color: theme.pick("#D1D1D1", "#666666", "#000000") }
                        Rectangle {
                            id: hcFill6
                            x: parent.width - 3.7 - 32; y: 0; width: 32; height: 31.3; radius: 4
                            color: codeMoreHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill6, codeMenu.opened && codeMenu.region === region.modelData ? theme.brand : theme.textStrong) }
                            HoverHandler { id: codeMoreHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { codeMenu.region = region.modelData; const p = parent.mapToItem(Overlay.overlay, parent.width - codeMenu.width, parent.height + 4); codeMenu.x = p.x; codeMenu.y = p.y; codeMenu.open() } }
                            Accessible.role: Accessible.ButtonMenu
                            Accessible.name: qsTr("More options")
                        }
                    }
                    Repeater {
                        model: region.code ? region.modelData.lines : 0
                        Text {
                            required property int index
                            x: 12; width: 30; height: 24
                            y: 40 + index * 24
                            horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                            text: index + 1
                            font.family: theme.mono; font.pixelSize: 14; color: theme.pick("#8A8886", "#ADADAD", "#FFFFFF")
                        }
                    }
                }
            }
            QuoteCard {
                id: quoteCard
                z: 2
                visible: !!root.quote
                x: 12.67; y: 14
                quote: root.quote
                dismissable: true
                maxWidth: editorArea.width - 28
                onDismissed: { root.quoteDismissed(); input.forceActiveFocus() }
            }
            // A recorded clip, as Teams' editor shows it: after an empty
            // line, 14 in and 32 down, Teams' clip card ("Processing..."
            // while it is stored; Remove video clip on hover); the text
            // follows 2 under it.
            Loader {
                id: clipCardBox
                z: 2
                // (Editing: the message's own clip, as Teams' edit box shows
                // it over the text, measured 2026-11-24; Remove video clip
                // takes it out of the message.)
                visible: !!root.clip || !!root.editClip
                active: !!root.clip || !!root.editClip
                x: 14; y: quoteCard.visible ? 14 + quoteCard.height + 4 + 22 : 32
                sourceComponent: VideoClipCard {
                    clip: root.clip ? ({ id: "", url: "", duration: root.clip.duration / 1000, width: root.clip.width || 1280, height: root.clip.height || 720, thumb_local: root.clip.thumb || "" })
                        : root.editClip
                    localPath: root.clip ? root.clip.path : ""
                    processing: !!root.clip && !!root.clip.uploading
                    removable: true
                    uploadFailed: !!root.clip && !!root.clip.error
                    background: theme.surface
                    onRemoveRequested: {
                        if (root.clip) { root.clipRemoved(); return }
                        if (root.editClip) { root.removedClips = root.removedClips.concat([root.editClip.id]); root.editClip = null }
                    }
                    onRetryUpload: root.clipRetry()
                }
            }
            Flow {
                id: fileChips
                z: 2
                visible: root.files.length > 0
                x: 12; y: (quoteCard.visible ? 14 + quoteCard.height + 4 : 10); width: parent.width - 28
                spacing: 8
                Repeater {
                    model: root.files
                    Rectangle {
                        required property string modelData
                        height: 40; width: Math.min(300, chipName.implicitWidth + 80)
                        radius: 8
                        color: theme.searchFill
                        border.color: theme.divider
                        FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 24; color: theme.textSecondary }
                        Text {
                            id: chipName
                            x: 40; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 76
                            text: parent.modelData.split("/").pop()
                            elide: Text.ElideMiddle
                            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                            color: theme.text
                        }
                        ToolButton32 {
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            icon: "dismiss-20"; label: qsTr("Remove %1").arg(parent.modelData.split("/").pop())
                            onClicked: root.fileRemoved(parent.modelData)
                        }
                    }
                }
            }
            // Teams' link preview in compose (url-preview-card, measured on
            // winpc 2026-11-15): 11.4 in, 11 under the text.
            UrlPreviewCard {
                id: previewCard
                z: 2
                visible: root.previewShown
                x: 11.4; y: root.textBottom + 11
                preview: root.shownPreview
                removable: true
                // A collapsed app card: Expand preview beside the X.
                expandable: root.appCardCollapsedShown
                onExpandRequested: root.setAppCard({ collapsed: false })
                onRemoveRequested: {
                    if (root.appCardCollapsedShown) { root.setAppCard({ removed: true }); return }
                    const p = Object.assign({}, root.urlPreview); p.enabled = false; root.urlPreview = p
                }
            }
            // The app's link card in compose (app-based-link-preview-card,
            // measured on winpc 2026-11-16): 16.67 in, 16.4 under the text.
            AppLinkCard {
                id: appLinkCard
                z: 2
                visible: root.appCardShown
                x: 16.67; y: root.textBottom + 16.4
                compose: true
                appCard: root.appCard
                onCollapseRequested: root.setAppCard({ collapsed: true })
                onRemoveRequested: root.setAppCard({ removed: true })
                onSettingsRequested: root.appCardSettingsRequested()
                onPermissionsRequested: root.appCardPermissionsRequested(root.appCard ? root.appCard.app_id : "")
                onOpenLink: url => Qt.openUrlExternally(url)
                // Teams' permission card: Show Preview installs the app for
                // you and asks it again; Sign in opens the app's sign-in
                // window, and once its page reports success the app is
                // asked again with the result (value.state). Closing the
                // window keeps the sign-in card (Teams' CancelledByUser).
                onShowPreviewRequested: root.showPreview()
                onSignInRequested: u => {
                    if (u.indexOf("https://") !== 0) { root.showPreview(); return }
                    root.openAppAuth(u, root.appCard.valid_domains || [])
                }
            }
            Component { id: authWindow; AppAuthWindow {} }
            // Teams' attachment card for a cloud file (file-well, measured
            // on winpc 2026-11-13): 320 x 237.3 under the text (13 in, 15
            // under its line), radius 6, 0.67 #E0E0E0 and a soft shadow; a
            // #FAFAFA header 56.7 tall with the type icon (32 at 16, 12),
            // the name (14/600 at 60, 10.3) over the default link's
            // description (12 #424242 at 60, 25) and Remove attachment
            // (32 x 30 at 274.7, 13); then the file's picture (179.3 tall,
            // #F5F5F5 behind it).
            // Teams' Loop component in the box (measured 2026-11-20): under
            // the text (16.7 in, 20.5 under its line), as wide as the box
            // less 33.3; the box ends 10 under it.
            LoopCard {
                id: loopCard
                z: 2
                // (A sent one stays loaded, hidden, until its title is read.)
                readonly property var shown: root.loop || root.loopSending
                visible: !!root.loop
                x: 16.7; y: root.textBottom + 20.5
                width: parent.width - 33.3
                mode: "compose"
                live: !!shown
                loopKey: shown ? shown.key : ""
                conversation: String(root.chatId || backend.currentChatId)
                componentUrl: shown ? shown.url : ""
                name: shown && shown.title ? shown.title : qsTr("Loop paragraph")
                description: shown ? shown.description : ""
                linking: !!shown && shown.linking
                onTitleRead: t => root.loopTitleRead(t)
                // Only one at a time; a new one starts over.
                Component.onCompleted: {}
                onCreated: info => {
                    if (!root.loop) return
                    root.setLoop({ driveId: info.driveId || "", itemId: info.itemId || "", linking: true })
                    backend.loopHostRequest("composeLink", root.loop.key + ":link", JSON.stringify({ driveId: info.driveId, itemId: info.itemId, url: info.componentUrl }))
                }
                onTitleChanged: t => root.setLoop({ title: t })
                onDiscardRequested: { root.discardingEditLoop = false; loopDiscardDialog.open() }
                onLinkSettingsRequested: root.openLoopLinkSettings()
            }
            // The message's own Loop component in its edit box.
            LoopCard {
                id: editLoopCard
                z: 2
                visible: !!root.editLoop && !root.loop
                x: 16.7; y: root.textBottom + 20.5
                width: parent.width - 33.3
                mode: "edit"
                live: visible
                conversation: String(root.chatId || backend.currentChatId)
                componentUrl: root.editLoop ? root.editLoop.url : ""
                name: root.editLoop ? root.editLoop.name || "" : ""
                description: root.editLoop ? root.editLoop.description || "" : ""
                onDiscardRequested: { root.discardingEditLoop = true; loopDiscardDialog.open() }
            }
            Flow {
                id: cloudCards
                z: 2
                visible: root.cloudFiles.length > 0
                x: 13; y: root.textBottom + 15
                width: parent.width - 30
                spacing: 8
                Repeater {
                    model: root.cloudFiles
                    Rectangle {
                        id: cc
                        required property var modelData
                        width: 320; height: 237.3; radius: 6
                        color: theme.surface
                        border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF"); border.width: 0.67
                        FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 6 }
                        Rectangle {
                            x: 0.67; y: 0.67; width: parent.width - 1.33; height: 56.7
                            topLeftRadius: 6; topRightRadius: 6
                            color: theme.pick("#FAFAFA", "#292929", "#000000")
                            FluentIcon { x: 16; y: 12; size: 32; name: root.cloudTypeIcon(cc.modelData.kind) }
                            Text {
                                x: 60; y: 10.3; width: 206.4 - 4 - 60 + 12
                                elide: Text.ElideMiddle
                                text: cc.modelData.name
                                lineHeight: 16; lineHeightMode: Text.FixedHeight
                                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                            }
                            // The link's description: a button that opens
                            // Link settings (Teams' file-permission-trigger;
                            // #4F52B2 and underlined on hover).
                            Text {
                                id: ccLink
                                x: 60; y: 25; width: Math.min(implicitWidth, 206.4)
                                elide: Text.ElideRight
                                text: cc.modelData.linking ? qsTr("Updating link settings...") : cc.modelData.file ? cc.modelData.file.link_description : ""
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                                font.family: theme.font; font.pixelSize: 12; font.underline: ccLinkHover.hovered
                                color: ccLinkHover.hovered ? theme.pick("#4F52B2", "#7F85F5", "#FFFF00") : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                HoverHandler { id: ccLinkHover; enabled: !!cc.modelData.file && !cc.modelData.linking; cursorShape: Qt.PointingHandCursor }
                                TapHandler { enabled: !!cc.modelData.file && !cc.modelData.linking; onTapped: root.cloudLinkRequested(cc.modelData.key) }
                                Accessible.role: Accessible.Button
                                Accessible.name: text
                            }
                            Rectangle {
                                id: hcFill7
                                x: 274.7 - 0.67; y: 13 - 0.67; width: 32; height: 30; radius: 4
                                color: ccRemove.hovered ? theme.menuHover : "transparent"
                                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill7, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                                HoverHandler { id: ccRemove; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.cloudRemoved(cc.modelData.key) }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Remove attachment")
                            }
                        }
                        Rectangle {
                            x: 0.67; y: 57.4; width: parent.width - 1.33; height: 179.3
                            bottomLeftRadius: 6; bottomRightRadius: 6
                            color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                            clip: true
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop; verticalAlignment: Image.AlignTop
                                source: cc.modelData.thumbnail || ""
                                asynchronous: true
                            }
                            BusyIndicator { anchors.centerIn: parent; running: !!cc.modelData.loading; visible: running }
                        }
                        Accessible.role: Accessible.Grouping
                        Accessible.name: modelData.name
                    }
                }
            }
            TextEdit {
                id: input
                x: 12
                y: root.inputTop - root.textScroll
                onCursorRectangleChanged: root.keepCursorInView()
                width: parent.width - 12 - 16
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                selectByMouse: true
                persistentSelection: true
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                selectionColor: theme.selectionFill
                selectedTextColor: theme.text
                Text {
                    // (A clip in the box is content: Teams hides it then.)
                    visible: input.length === 0 && !input.preeditText && !root.clip
                    text: root.placeholder
                    font: input.font; color: theme.textSecondary
                }
                onTextChanged: { if (length > 0) root.typed(); else root.grown = false; if (root.pastedPictures === "failed") root.pastedPictures = ""; root.checkMention(); root.refreshRichState(); root.checkSpelling(); linkWatch.restart() }
                onCursorPositionChanged: { root.checkMention(); root.refreshRichState() }
                // The formatting bar's commands act on this text's document.
                RichText { id: rich }
                // Teams' spelling squiggles: a wavy #EB0000 underline under each
                // misspelt word (#FDE5E5 behind it while its card is open).
                Repeater {
                    model: root.critiques
                    Item {
                        id: sq
                        required property var modelData
                        readonly property rect a: { input.text; input.width; return input.positionToRectangle(modelData.start) }
                        readonly property rect b: { input.text; input.width; return input.positionToRectangle(modelData.start + modelData.length) }
                        readonly property bool open: root.openCritique !== null && root.openCritique.id === modelData.id
                        // Behind the text (a negative z draws under the editor's own
                        // text). A word broken over two lines underlines to the
                        // line's end.
                        z: -1
                        x: a.x; y: a.y
                        width: Math.max(1, (b.y === a.y ? b.x : input.width) - a.x); height: a.height
                        Rectangle { anchors.fill: parent; visible: sq.open; color: theme.pick("#FDE5E5", "#3E1F25", "#000000") }
                        // Chromium's wavy underline as Teams shows it (measured): a
                        // 7.3 px period, 2.7 px high, in the line's last 4 px.
                        Canvas {
                            y: parent.height - 4; width: parent.width; height: 4
                            onWidthChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                ctx.strokeStyle = "#EB0000"
                                ctx.lineWidth = 1
                                ctx.beginPath()
                                for (let x = 0; x <= width; x += 0.5) {
                                    const y = 2 + 1.35 * Math.sin(2 * Math.PI * x / 7.3)
                                    if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                }
                                ctx.stroke()
                            }
                        }
                    }
                }
                // Clicking a squiggled word opens its card (the click still
                // places the cursor).
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: ev => {
                        const pos = input.positionAt(ev.position.x, ev.position.y)
                        const c = root.critiques.find(c => pos >= c.start && pos <= c.start + c.length)
                        if (c && input.selectedText.length === 0) root.openEditorCard(c)
                    }
                }
                onLineCountChanged: if (lineCount > 1) root.grown = true
                onActiveFocusChanged: if (activeFocus) root.enterKey = backend.setting("enterKey") || "send"
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Space && !(event.modifiers & Qt.ControlModifier)) { root.autoLinkBeforeCursor(); return }
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                        // A picture (and no text) on the clipboard goes in
                        // as a picture, as Teams' box takes it.
                        if (!root.textOnly && !root.editing && root.pastePicture()) { event.accepted = true; return }
                        root.pasteFrom = input.selectionStart; Qt.callLater(root.autoLinkPaste); return
                    }
                    if (!(event.modifiers & Qt.ControlModifier)) return
                    const shift = event.modifiers & Qt.ShiftModifier
                    const alt = event.modifiers & Qt.AltModifier
                    // Teams: Ctrl+Shift+X the bar, Ctrl+Shift+C inline code,
                    // Ctrl+Shift+B code block, Ctrl+Alt+X strikethrough,
                    // Ctrl+Shift+I Important.
                    if (shift && event.key === Qt.Key_X) root.formatting = !root.formatting
                    else if (shift && event.key === Qt.Key_C) root.format("code", "")
                    else if (shift && event.key === Qt.Key_B) root.format("codeblock", "")
                    // Teams' Slack-style shortcuts (Settings ▸ General ▸
                    // Keyboard shortcuts): Ctrl+E Insert link, Ctrl+Alt+
                    // Shift+C code block, Ctrl+Shift+9 quote.
                    else if (window.slackShortcuts && alt && shift && event.key === Qt.Key_C) root.format("codeblock", "")
                    else if (window.slackShortcuts && shift && (event.key === Qt.Key_9 || event.key === Qt.Key_ParenLeft)) root.format("quote", "")
                    else if (window.slackShortcuts && !shift && !alt && event.key === Qt.Key_E) formatBar.showLink(input)
                    else if (shift && event.key === Qt.Key_I && root.deliveryOptions) root.importance = root.importance === "high" ? "" : "high"
                    else if (alt && event.key === Qt.Key_X) root.format("strike", "")
                    else if (!shift && !alt && event.key === Qt.Key_B) root.wrapSelection("b")
                    else if (!shift && !alt && event.key === Qt.Key_I) root.wrapSelection("i")
                    else if (!shift && !alt && event.key === Qt.Key_U) root.wrapSelection("u")
                    else return
                    event.accepted = true
                }
                Keys.onReturnPressed: event => {
                    if (mentionPicker.opened) { mentionPicker.pick(); return }
                    // Teams: Enter on an empty quote line leaves the quote.
                    if (root.richState.quote && root.richState.empty && !(event.modifiers & Qt.ControlModifier)) { root.format("quote", ""); return }
                    root.autoLinkBeforeCursor()
                    root.enterPressed(event)
                }
                Keys.onEnterPressed: event => { if (mentionPicker.opened) { mentionPicker.pick(); return } root.enterPressed(event) }
                // In a table Tab goes to the next cell (from the last one it
                // adds a row, as Teams' editor does) and Shift+Tab back.
                Keys.onTabPressed: event => {
                    if (mentionPicker.opened) { mentionPicker.pick(); return }
                    if (root.richState.table) {
                        if (root.richState.nextCell < 0) { rich.apply(input.cursorPosition, input.cursorPosition, "table-row-below", ""); root.refreshRichState() }
                        if (root.richState.nextCell >= 0) input.cursorPosition = root.richState.nextCell
                        return
                    }
                    event.accepted = false
                }
                Keys.onBacktabPressed: event => {
                    if (root.richState.table && root.richState.prevCell >= 0) { input.cursorPosition = root.richState.prevCell; return }
                    event.accepted = false
                }
                Keys.onUpPressed: event => { if (mentionPicker.opened) mentionPicker.move(-1); else event.accepted = false }
                Keys.onDownPressed: event => { if (mentionPicker.opened) mentionPicker.move(1); else event.accepted = false }
                Keys.onEscapePressed: event => { if (mentionPicker.opened) mentionPicker.close(); else event.accepted = false }
                Accessible.role: Accessible.EditableText
                Accessible.name: root.placeholder
            }
            TapHandler { onTapped: input.forceActiveFocus() }
        }

        // The toolbar buttons (side in single-line, bottom in multiline).
        Row {
            id: sideTools
            visible: !root.multiline
            x: parent.width - width - 6.7; y: root.headerH + 6.7
            Repeater { model: root.toolModel; delegate: toolDelegate }
            Item {
                width: 8.7 - 4 + 4; height: 32
                Rectangle { x: 4; y: 4; width: 1; height: 24; color: theme.stroke }
            }
            Repeater { model: root.endModel; delegate: toolDelegate }
        }
        // The post composer's tools (from 8.7) and Post.
        Item {
            visible: root.post
            x: 0; y: parent.height - 17.4 - 31.3 - 0.35; width: parent.width; height: 32
            Row {
                x: 8.7
                Repeater { model: root.postTools; delegate: toolDelegate }
            }
            Rectangle {
                id: hcFill8
                x: parent.width - 16.7 - width; y: 0
                width: 96; height: 31.3; radius: 4
                color: postHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Post"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill8, "white") }
                HoverHandler { id: postHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.trySubmit() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Post")
            }
        }
        Item {
            id: bottomBar
            visible: root.multiline && !root.post
            x: 0; y: parent.height - 44.7; width: parent.width; height: 44.7
            Row {
                x: parent.width - width - 6.7; y: 6
                Repeater { model: root.toolModel; delegate: toolDelegate }
                Item {
                    width: 8.7; height: 32
                    Rectangle { x: 4; y: 4; width: 1; height: 24; color: theme.stroke }
                }
                Repeater { model: root.endModel; delegate: toolDelegate }
            }
        }

        // Focused: Fluent's 2 px brand line along the bottom.
        Rectangle {
            visible: input.activeFocus && !root.post
            x: 0; y: parent.height - 2; width: parent.width; height: 2
            color: theme.brand
        }
    }

    // The hint under the box (the post composer's too, measured).
    Row {
        visible: !root.empty
        anchors.right: parent.right; anchors.rightMargin: root.post ? 0 : 17
        y: root.bannerShownH + root.boxHeight + 2
        spacing: 4
        Text {
            text: root.fmtOn || root.enterKey === "newline" ? qsTr("Enter") : qsTr("Shift+Enter")
            font.family: theme.font; font.pixelSize: theme.small; color: theme.brandForeground1
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            HoverHandler { id: hintHover; cursorShape: Qt.PointingHandCursor }
            font.underline: hintHover.hovered
            TapHandler { onTapped: root.settingsRequested() }
            Accessible.role: Accessible.Link
            Accessible.name: root.fmtOn || root.enterKey === "newline" ? qsTr("Select Enter to open settings") : qsTr("Select Shift+Enter to open settings")
        }
        Text {
            text: qsTr("starts a new line.")
            font.family: theme.font; font.pixelSize: theme.small; color: theme.text
            lineHeight: 16; lineHeightMode: Text.FixedHeight
        }
    }

    // Toolbar items, in Teams' order (§15). Loop components and Actions and
    // apps are not built yet.
    /// Only Format and Send (Teams' lobby chat compose).
    property bool textOnly: false
    readonly property var toolModel: [
        { id: "expand-compose", icon: "format-20", label: root.formatting ? qsTr("Hide Formatting options") : qsTr("Show Formatting options"), pressed: root.formatting },
        { id: "UnifiedFunPicker", icon: "emoji-20", label: qsTr("Emoji, GIFs and Stickers"), hidden: root.textOnly },
        { id: "FilePicker", icon: "attach-20", label: qsTr("Attach files") + " (Alt+Shift+O)", hidden: root.textOnly },
        // (Also while editing a sent message: Teams' edit box keeps Write
        // with Copilot, its popover over the edit box, measured 2026-11-23.)
        { id: "open-compose-copilot", icon: "pen-sparkle-20", label: qsTr("Write with Copilot") + " (Alt+A)", hidden: root.textOnly || !root.copilotAllowed, pressed: copilotPopover.opened },
        { id: "popup-semo", icon: "loop-page-20", label: qsTr("Loop components"), hidden: root.editing || root.textOnly || !root.loopAllowed, pressed: !!root.loop },
        { id: "message-extension-flyout-command", icon: "add-20", label: qsTr("Actions and apps"), hidden: root.textOnly }
    ].filter(t => !t.hidden)
    /// This box can send a Loop component (the main compose box).
    property bool loopHost: true
    // Teams' Loop components (measured on winpc 2026-11-20): the toolbar's
    // 5th button puts Loop's paragraph in the box at once (Loop's own
    // insert row offers Table, Bulleted list, Checklist, Task list and
    // more); Teams makes it in your OneDrive's chat files (a channel's
    // folder in a channel) and gives it the organization edit link. Where
    // messaging's fluid settings allow compose (composeEnabledComponents;
    // composeInChannelEnabled in channels), not in a new chat or an edit.
    readonly property bool loopAllowed: {
        if (root.newConversation || !root.loopHost) return false
        // (Read again once the chat list has come: Teams' settings are in
        // by then.)
        if (!backend.chatsJson) return false
        let f = {}
        try { f = JSON.parse(backend.ecsSetting("messaging", "fluid") || "{}") } catch (e) {}
        if ((f.composeEnabledComponents || []).indexOf("paragraph") < 0) return false
        return String(root.chatId || backend.currentChatId).indexOf("@thread.tacv2") < 0 || f.composeInChannelEnabled === true
    }
    /// The compose Loop component: {key, url (its link once made), driveId,
    /// itemId, description, title, linking}.
    property var loop: null
    function setLoop(changes) { root.loop = root.loop ? Object.assign({}, root.loop, changes) : null }
    function insertLoop() {
        if (root.loop || !root.loopAllowed) return
        // The card's id: a random UUID, as Teams' cardClientId.
        const hex = n => Array.from({ length: n }, () => Math.floor(Math.random() * 16).toString(16)).join("")
        const cardId = hex(8) + "-" + hex(4) + "-4" + hex(3) + "-" + "89ab"[Math.floor(Math.random() * 4)] + hex(3) + "-" + hex(12)
        root.loop = { key: "loop" + Date.now().toString(36), cardId: cardId, url: "", driveId: "", itemId: "", description: "", title: "", linking: false }
    }
    /// What the message carries ("" without a made component).
    function loopForSend() {
        if (!root.loop || !root.loop.url) return ""
        return JSON.stringify({ component_url: root.loop.url, card_client_id: root.loop.cardId })
    }
    /// The chat's title, which names a sent component without one.
    property string chatTitle: ""
    /// A sent component whose title is being read (its card kept loaded).
    property var loopSending: null
    /// After the message went: Teams reads the component's title
    /// (ComponentWithTitle) and names the file after it, or after the chat
    /// ("{chat} Loop paragraph") when it has none.
    function loopSent() {
        const l = root.loop
        if (root.loopSending) root.loopTitleRead("")
        if (!l || !l.itemId) { root.loop = null; return }
        // (Kept before the box lets go of it, so its page stays loaded.)
        root.loopSending = Object.assign({}, l, { chatTitle: root.chatTitle })
        root.loop = null
        loopTitleWait.restart()
        loopCard.requestTitle()
    }
    function loopTitleRead(title) {
        const l = root.loopSending
        if (!l) return
        loopTitleWait.stop()
        root.loopSending = null
        console.info("LOOPCOMPOSE title", JSON.stringify(title))
        backend.loopHostRequest("composeRename", "compose-rename", JSON.stringify({ driveId: l.driveId, itemId: l.itemId, title: title, chatTitle: l.chatTitle, kindName: qsTr("Loop paragraph") }))
    }
    Timer { id: loopTitleWait; interval: 5000; onTriggered: root.loopTitleRead("") }
    function discardLoop() {
        const l = root.loop
        root.loop = null
        if (l && l.itemId) backend.loopHostRequest("composeDiscard", "compose-discard", JSON.stringify({ driveId: l.driveId, itemId: l.itemId }))
    }
    // The header's link description opens Link settings, as Teams'
    // (fluid compose's file permission button, the attachment card's
    // dialog); the choice becomes the component's link (Teams deletes the
    // old one).
    function openLoopLinkSettings() {
        if (!root.loop || !root.loop.itemId || root.loop.linking) return
        backend.loopHostRequest("composeFileRef", root.loop.key + ":ref", JSON.stringify({ driveId: root.loop.driveId, itemId: root.loop.itemId }))
    }
    function applyLoopLink(scope, edit, expiration, password, line) {
        const l = root.loop
        if (!l || !l.itemId) return
        root.setLoop({ linking: true, wantLine: line, linkScope: scope, linkEdit: edit })
        backend.loopHostRequest("composeRelink", l.key + ":relink", JSON.stringify({ driveId: l.driveId, itemId: l.itemId, url: l.url, shareId: l.shareId || "",
            scope: scope, edit: edit, expiration: expiration || "", password: password || "", chatId: String(root.chatId || backend.currentChatId) }))
    }
    Connections {
        target: backend
        function onLoopHostReply(id, json) {
            if (!root.loop || id.indexOf(root.loop.key + ":") !== 0) return
            let r = {}
            try { r = JSON.parse(json) } catch (e) {}
            const what = id.slice(root.loop.key.length + 1)
            if (what === "link") {
                if (r.componentUrl) root.setLoop({ url: r.componentUrl, description: r.description || "", shareId: r.shareId || "", linking: false })
                else root.setLoop({ linking: false, error: r.error || "error" })
            } else if (what === "ref") {
                if (r.site) root.loopLinkRequested({ site: r.site, list: r.list, item: r.item }, r.name || "", root.loop.linkScope !== undefined ? root.loop.linkScope : 1,
                                                    root.loop.linkEdit !== undefined ? root.loop.linkEdit : true)
            } else if (what === "relink") {
                if (r.componentUrl) root.setLoop({ url: r.componentUrl, shareId: r.shareId || "", description: root.loop.wantLine || root.loop.description, linking: false })
                else { console.warn("LOOPCOMPOSE relink failed", r.error || ""); root.setLoop({ linking: false }) }
            }
        }
    }
    function loopCardForTest() { return loopCard.visible ? loopCard : null }
    function openPlusForTest() { plusFlyout.anchorItem = root.attachButton(); plusFlyout.open() }
    function toolForTest(id) {
        const find = it => {
            for (const c of it.children) {
                if (c.visible && c.modelData && c.modelData.id === id) return c
                const f = find(c)
                if (f) return f
            }
            return null
        }
        return find(root)
    }
    function plusFlyoutForTest() { return plusFlyout }
    function deliveryPopupForTest() { return deliveryPopup }
    function loopDiscardDialogForTest() { return loopDiscardDialog }
    // Teams' "Discard draft message" (measured): 600 wide, the title 20/28
    // 600, "The Loop component will be deleted." 14/20, Close and Discard
    // (brand), 96 x 31.3.
    ConfirmDialog {
        id: loopDiscardDialog
        dialogWidth: 600
        title: qsTr("Discard draft message")
        body: qsTr("The Loop component will be deleted.")
        confirmText: qsTr("Discard")
        cancelText: qsTr("Close")
        onConfirmed: root.discardingEditLoop ? root.discardEditLoop() : root.discardLoop()
    }
    // Change permissions ("Who can reply") and Post in other channels ("Post
    // in"): Teams' radio menus (measured 2026-11-24: 161.2 / 144.8 wide
    // rows, a 12/600 heading row, 16 px checks 6 in), 20 left of "+" with
    // their bottom on its top.
    function openPostMenu(menu, anchor) {
        const a = anchor || root.attachButton()
        menu.parent = a
        menu.x = -20
        menu.y = -menu.implicitHeight
        menu.open()
    }
    MenuPopup {
        id: permissionMenu
        radioColumn: true; radioLabelX: 28; rowSpacing: 0
        items: [{ heading: qsTr("Who can reply") },
                { label: qsTr("Everyone"), checked: root.replyPermission !== "AuthorAndOwners" },
                { label: qsTr("You and moderators"), checked: root.replyPermission === "AuthorAndOwners" }]
        onPicked: i => { root.replyPermission = i === 2 ? "AuthorAndOwners" : (root.replyPermissionAtStart ? "Everyone" : ""); input.forceActiveFocus() }
    }
    MenuPopup {
        id: postInMenu
        radioColumn: true; radioLabelX: 28; rowSpacing: 0
        items: [{ heading: qsTr("Post in") },
                { label: qsTr("This channel"), checked: !root.crossPost },
                { label: qsTr("Multiple channels"), checked: root.crossPost }]
        onPicked: i => {
            root.crossPost = i === 2
            if (!root.crossPost) root.crossChannels = []
            input.forceActiveFocus()
        }
    }
    function openChooseChannels() {
        chooseChannels.source = root.postChannelId
        chooseChannels.selected = root.crossChannels.slice()
        chooseChannels.open()
    }
    CrossPostDialog {
        id: chooseChannels
        onUpdated: channels => root.crossChannels = channels
    }
    function crossPostDialogForTest() { return chooseChannels }
    function permissionMenuForTest() { return permissionMenu }
    function postInMenuForTest() { return postInMenu }
    property bool discardingEditLoop: false
    // The edit's Loop component: its file's name and its link's words.
    Connections {
        target: backend
        enabled: !!root.editLoop
        function onLoopHostReply(id, json) {
            if (id !== "editloop:" + root.editorDoc || !root.editLoop) return
            let r = {}
            try { r = JSON.parse(json) } catch (e) {}
            const l = r.link || {}
            const words = l.description ? l.description
                : l.scope === "organization" ? (l.edit ? qsTr("People in your organization with the link can edit") : qsTr("People in your organization with the link can view"))
                : l.scope === "anonymous" || l.scope === "anyone" ? (l.edit ? qsTr("Anyone with the link can edit") : qsTr("Anyone with the link can view"))
                : l.scope === "users" ? (l.edit ? qsTr("People you choose can edit") : qsTr("People you choose can view")) : ""
            root.editLoop = Object.assign({}, root.editLoop, { name: r.name || "", description: words })
        }
    }
    /// The message's own Loop component discarded in its edit box: gone
    /// from the edit, its file deleted at once (as Teams).
    function discardEditLoop() {
        const l = root.editLoop
        root.discardingEditLoop = false
        if (!l) return
        root.removedLoops = root.removedLoops.concat([l.url])
        root.editLoop = null
        backend.loopHostRequest("composeDiscardUrl", "compose-discard-url", JSON.stringify({ url: l.url }))
    }
    // Write with Copilot (Teams' compose Copilot): for a Microsoft 365
    // Copilot licence where Teams' settings turn it on, between Attach
    // files and Loop components, in chats, channel posts and replies.
    readonly property var copilotState: backend.composeCopilotJson ? JSON.parse(backend.composeCopilotJson) : ({})
    readonly property bool copilotAllowed: !!copilotState.allowed
    function openCopilot(anchor) {
        if (!root.copilotAllowed) return
        if (copilotPopover.opened) { copilotPopover.close(); return }
        copilotPopover.toolbar = anchor || null
        copilotPopover.openFor()
    }
    function copilotForTest() { return copilotPopover }
    CopilotPopover {
        id: copilotPopover
        compose: root
        box: box
        postMode: root.post
        proofread: root.copilotState.proofread !== false
        threadId: root.chatId
        contextType: String(root.chatId || backend.currentChatId).indexOf("@thread.tacv2") >= 0 ? "Channel" : "Chat"
        onReplaced: html => { root.setHtml(html); root.focusEditor() }
    }
    Shortcut {
        sequence: "Alt+A"
        // In a call Alt+A is mute (Main), as in Teams.
        enabled: root.copilotAllowed && input.activeFocus && backend.callState !== "connected"
        onActivated: root.openCopilot(null)
    }
    readonly property var endModel: root.editing
        ? [{ id: "discard-draft", icon: "dismiss-20", label: qsTr("Cancel") }, { id: "send", icon: "checkmark-20", label: qsTr("Done") }]
        : [{ id: "send", icon: "send-20", label: qsTr("Send"), ready: !root.empty }]
    Component {
        id: toolDelegate
        ToolButton32 {
            id: tbd
            required property var modelData
            icon: modelData.id === "send" && !root.editing && modelData.ready ? "send-20-filled" : modelData.icon
            label: modelData.label
            pressedState: !!modelData.pressed
            accent: modelData.id === "send" && !root.editing && !!modelData.ready
            onClicked: root.toolClicked(modelData.id, tbd)
        }
    }
    function toolClicked(id, item) {
        if (id === "expand-compose") { formatting = !formatting; input.forceActiveFocus() }
        else if (id === "UnifiedFunPicker") root.emojiRequested(item)
        else if (id === "FilePicker") { if (root.editing) root.openEditAttach(item); else root.attachRequested(item) }
        else if (id === "open-compose-copilot") root.openCopilot(item)
        else if (id === "popup-semo") root.insertLoop()
        else if (id === "message-extension-flyout-command") { plusFlyout.anchorItem = item; plusFlyout.open() }
        else if (id === "discard-draft") root.requestCancel()
        else if (id === "send") root.trySubmit()
    }
    // The edit's own Attach (the conversation's popover and picker, its
    // files kept for this edit).
    Loader {
        id: editAttachLoader
        active: root.editing
        sourceComponent: Item {
            property alias attach: attachItem
            CloudAttach {
                id: attachItem
                chatId: String(root.chatId || backend.currentChatId)
                channel: chatId.indexOf("@thread.tacv2") >= 0
                teamName: root.editTeamName
                teamId: root.editTeamId
                onUploadRequested: editUpload.open()
                onFailed: text => root.showBanner(text, false, 3000)
            }
            FileDialog {
                id: editUpload
                title: qsTr("Upload from this device")
                fileMode: FileDialog.OpenFiles
                onAccepted: root.editLocalFiles = root.editLocalFiles.concat(selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))))
            }
        }
    }
    function openEditAttach(anchor) {
        if (!root.editAttach) return
        root.editAttach.context = []
        root.editAttach.openMenu(anchor || root.attachButton() || root)
    }
    Connections {
        target: root
        enabled: root.editing
        function onFileRemoved(path) { root.editLocalFiles = root.editLocalFiles.filter(p => p !== path) }
        function onCloudRemoved(key) {
            if (root.editFiles.some(f => f.key === key)) root.editFiles = root.editFiles.filter(f => f.key !== key)
            else if (root.editAttach) root.editAttach.remove(key)
        }
        function onCloudLinkRequested(key) { if (root.editAttach && !root.editFiles.some(f => f.key === key)) root.editAttach.openLink(key) }
        // Cancelling drops what the edit made (Teams deletes a new Loop
        // component's file).
        function onCancelled() { if (root.loop) root.discardLoop(); root.editLocalFiles = []; if (root.editAttach) root.editAttach.clear() }
    }
    /// What Done sends besides the text (backend.editMessageWith).
    function editExtras() {
        const kept = root.editFiles.map(f => f.key)
        const x = {
            importance: root.importance,
            removedFiles: root.editFilesAtStart.filter(k => kept.indexOf(k) < 0),
            keptFiles: kept.length,
            files: root.editLocalFiles.concat(root.editAttach ? root.editAttach.lines() : []).join("\n")
        }
        const l = root.loopForSend()
        if (l) x.loop = JSON.parse(l)
        if (root.clip && root.clip.id) x.clip = { id: root.clip.id, url: root.clip.url, duration: root.clip.duration, width: root.clip.width, height: root.clip.height }
        if (root.removedLoops.length) x.removedLoops = root.removedLoops
        if (root.removedClips.length) x.removedClips = root.removedClips
        // A post (Teams' post composer): its subject, who may reply (sent
        // once set), its other channels when they changed.
        if (root.post) {
            x.post = true
            x.subject = root.subject
            if (root.replyPermission || root.replyPermissionAtStart) x.replyPermission = root.replyPermission || "Everyone"
            const others = root.crossPost ? root.crossChannels : []
            const before = root.crossChannelsAtStart
            if (before === null ? root.crossPostId && !root.crossPost : JSON.stringify(others) !== JSON.stringify(before)) x.crossChannels = others
            x.teamId = root.postTeamThread
        }
        return JSON.stringify(x)
    }
    /// A recorded clip still being stored holds Done back.
    readonly property bool editWaiting: !!root.clip && !root.clip.id
    /// After Done: a Loop component made in the edit takes its title as
    /// its name (as a sent one does).
    function editSent() {
        const l = root.loop
        if (l && l.itemId) backend.loopHostRequest("composeRename", "compose-rename", JSON.stringify({ driveId: l.driveId, itemId: l.itemId, title: l.title || "", chatTitle: root.chatTitle, kindName: qsTr("Loop paragraph") }))
        root.loop = null
        root.editLocalFiles = []
        if (root.editAttach) root.editAttach.clear()
    }
    /// The Attach button on show (Alt+Shift+O opens the popover over it).
    function attachButton() {
        const find = it => {
            for (const c of it.children) {
                if (c.visible && c.modelData && c.modelData.id === "FilePicker") return c
                const f = find(c)
                if (f) return f
            }
            return null
        }
        return find(root) || root
    }
    function cloudTypeIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }
    function trySubmit() {
        // Teams runs its checks even on an empty box (Send and Enter both
        // show "Please type a message to continue.", measured 2026-11-16).
        const blocked = root.preSendCheck()
        if (blocked) {
            // Teams' DefaultBanner: no Close, gone after 3 s; the text stays.
            root.showBanner(blocked, false, 3000, false)
            console.warn("PRESEND blocked:", blocked)
            return
        }
        if (root.dryRun) { console.warn("PRESEND would send"); return }
        root.submit()
    }
    /// Harness: run the checks but never send.
    property bool dryRun: false
    // Teams' checks before a message goes (its draft validation, module
    // 198077, run in this order; the first that fails names the problem in
    // a compose banner and the message stays in the box). Teams for life
    // invitations (11) don't apply in OST.
    /// Teams' maxMessageContentSize (live 90112 bytes of the sent HTML).
    property var sizeCheck: html => backend.composeTooLarge(html, JSON.stringify(root.mediaInUse()))
    /// The new chat form's checks (Teams' 6, 7 and 12): "" when the
    /// recipients are fine, else the problem, in Teams' order.
    property var recipientCheck: null
    /// Pictures pasted into the box still loading or failed (Teams' 4):
    /// "loading", "initializing", "failed" or "".
    property string pastedPictures: ""
    /// A pasted picture is in the box (Teams' box goes to its tall form).
    readonly property bool hasPastedPicture: media.some(m => m.kind === "pasted") && input.length > 0
    // Ctrl+V with a picture: Teams' states while it is read
    // ("initializing"), then the picture in the box; one that can't be
    // read stays "failed" until the box changes.
    function pastePicture() {
        root.pastedPictures = "initializing"
        const r = backend.pasteComposePicture()
        if (!r) { root.pastedPictures = ""; return false }
        const p = JSON.parse(r)
        if (p.failed) { root.pastedPictures = "failed"; return true }
        root.pastedPictures = ""
        root.insertMedia({ kind: "pasted", src: p.path, path: p.path, title: "image", width: p.width, height: p.height })
        return true
    }
    function pictureForTest(path, w, h) { root.insertMedia({ kind: "pasted", src: path, path: path, title: "image", width: w, height: h }) }
    function preSendCheck() {
        const text = root.plainText().replace(/[\u00a0\ufffc\ufdd0\ufdd1]/g, " ")
        const html = root.formattedText()
        // 1 FileEvaluator: files still uploading.
        if (root.cloudFiles.some(c => c.loading || c.linking)) return qsTr("Uploading... Please wait.")
        // 2 fluidComponentSyncingEvaluator: a Loop component not made yet.
        if (root.loop && !root.loop.itemId && !root.loop.error) return qsTr("Syncing... Please wait.")
        // 3 EmptyContentEvaluator: nothing but spaces (files, a Loop
        // component and cards count).
        if (!text.trim() && root.mediaInUse().length === 0 && root.files.length === 0 && root.cloudFiles.length === 0 && !root.clip && !root.appCard && !root.loop)
            return qsTr("Please type a message to continue.")
        // 4 InlineImageContentEvaluator: pasted pictures.
        if (root.pastedPictures === "loading") return qsTr("The images are being loaded... Please wait.")
        if (root.pastedPictures === "initializing") return qsTr("The images are being initialized... Please wait.")
        if (root.pastedPictures === "failed") return qsTr("Cannot paste this image. Try different source.")
        // 5 AnnouncementPostEvaluator: an announcement needs its headline.
        if (root.post && root.announcement && !root.headline.trim() && !root.bannerImage) return qsTr("You'll need to add a headline to post your announcement.")
        // 6, 7 noRecipientEvaluator, notEnoughGroupParticipantsEvaluator.
        const who = root.recipientCheck ? root.recipientCheck("before-size") : ""
        if (who) return who
        // 8 exceedsMaxSizeEvaluator.
        if (root.sizeCheck(html)) return qsTr("Message is too large to send.")
        // 9 scheduledSendTimeInThePastEvaluator (10 s of grace).
        if (root.scheduleAt > 0 && Date.now() > root.scheduleAt + 10000) return qsTr("This message was scheduled for a time in the past.")
        // 10 scheduledMessageWithNearbyMentionEvaluator: only with Teams'
        // @Nearby mention (People.enableAtNearbyMention, which this
        // tenant's ECS leaves off, so Teams offers neither); OST's mention
        // picker has no @Nearby, so a draft can't carry one.
        // 12 exceedsMaxChatRosterSizeEvaluator.
        const roster = root.recipientCheck ? root.recipientCheck("roster") : ""
        if (roster) return roster
        // 14 FluidPermissionsEvaluator: the Loop component's link.
        if (root.loop && root.loop.linking) return qsTr("Checking permissions... Please wait.")
        // 15 VideoMessageEvaluator: a clip still uploading; kept 7 days.
        if (root.clip && (root.clip.uploading || (!root.clip.id && !root.newConversation))) return qsTr("Uploading... Please wait.")
        if (root.clip && root.clip.created && Date.now() - root.clip.created > 604800000) return qsTr("The video clip might not exist or is no longer available.")
        // ShareToL1WithBotMentionEvaluator: a reply also sent to the channel
        // can't @mention a bot.
        if (root.sendTo === "channel" && /href="mention:28:/.test(html)) return qsTr("Remove the bot mention or switch to thread only to proceed.")
        return ""
    }
    // The post composer's tools under the editor (Teams: Emoji, GIFs and
    // Stickers, Attach files, Actions and apps).
    readonly property var postTools: [
        { id: "UnifiedFunPicker", icon: "emoji-20", label: qsTr("Emoji, GIFs and Stickers") },
        { id: "FilePicker", icon: "attach-20", label: qsTr("Attach files") },
        { id: "open-compose-copilot", icon: "pen-sparkle-20", label: qsTr("Write with Copilot") + " (Alt+A)", hidden: !root.copilotAllowed, pressed: copilotPopover.opened },
        // (Loop components in posts and their edits too: measured
        // 2026-11-24 at 580.7, after Write with Copilot.)
        { id: "popup-semo", icon: "loop-page-20", label: qsTr("Loop components"), hidden: !root.loopAllowed || !!root.editLoop, pressed: !!root.loop },
        { id: "message-extension-flyout-command", icon: "add-20", label: qsTr("Actions and apps") }
    ].filter(t => !t.hidden)
    /// Back to an empty post composer.
    function resetPost() {
        subject = ""; headline = ""; bannerTheme = "0"; announcement = false; bannerImage = ""; bannerImageW = 0; bannerImageH = 0
        replyPermission = ""; crossPost = false; crossChannels = []
    }
    /// The next post's fields for backend.setNextPost.
    function postFields() {
        return JSON.stringify({ subject: subject, title: headline, theme: announcement ? bannerTheme : "",
            image: announcement ? bannerImage.replace(/^file:\/\//, "") : "", imageWidth: bannerImageW, imageHeight: bannerImageH,
            replyPermission: replyPermission, crossPost: crossPost ? crossChannels : [] })
    }
    BannerImageDialog {
        id: bannerImageDialog
        onPicked: (path, w, h) => { root.bannerImage = path; root.bannerImageW = w; root.bannerImageH = h }
    }
    function enterPressed(event) {
        const ctrl = event.modifiers & Qt.ControlModifier
        const shift = event.modifiers & Qt.ShiftModifier
        if (ctrl) { root.trySubmit(); return }
        // In a table Enter starts a new line in the cell, as in Teams.
        if (shift || root.enterKey === "newline" || root.fmtOn || root.richState.table) { event.accepted = false; return }
        root.trySubmit()
    }

    // A 32 px Fluent subtle icon button: #424242, hover shows the filled
    // glyph in brand.
    component ToolButton32: Item {
        id: tb
        property string icon
        property string label
        property bool pressedState: false
        property bool accent: false
        signal clicked()
        width: 32; height: 32
        FluentIcon {
            anchors.centerIn: parent; size: 20
            name: tbHover.hovered || tb.pressedState ? tb.icon.replace(/-filled$/, "") + "-filled" : tb.icon
            color: tbHover.hovered || tb.pressedState || tb.accent ? theme.brand : theme.textStrong
        }
        HoverHandler { id: tbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
        ToolTip {
            visible: tbHover.hovered; delay: 500
            y: -height - 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: tb.label; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // "+" Actions and apps (measured): 341.3 wide, a search box, then Teams'
    // own items as 36 px rows (20 px icon 8 in, the label at 40). Then your
    // installed apps with compose commands (measured 2026-11-20: a line,
    // then 36 px rows, the app's 20 px icon 8 in, most recently used
    // first); the menu is at most 480 tall and scrolls, with "Get more
    // apps" (144.8 x 32, 16 from the right and the bottom) in a 48 px
    // footer.
    // In the new chat form (measured on winpc 2026-11-16) it is a short
    // menu with no search: 234.3 x 133.3 for its three rows, right on top
    // of the button and ending 2.7 before its right edge; rows 218 wide
    // from (7.7, 12.7).
    Popup {
        id: plusFlyout
        property Item anchorItem: null
        readonly property bool plain: root.newConversation || root.editing
        parent: Overlay.overlay
        width: plain ? 234.3 : 341.3; padding: 0
        readonly property real listH: itemsCol.height + (appsCol.visible ? 10.7 + appsCol.height : 0) + (newApps.visible ? newApps.height : 0)
        readonly property real footerH: plain ? 0 : 48
        height: plain ? 12.7 + itemsCol.height + 12.6 : Math.min(480, 62.7 + listH + 14.7 + footerH)
        // (A post's edit: centred over the button, measured 2026-11-24.)
        x: !anchorItem ? 0 : plain && root.post ? anchorItem.mapToItem(Overlay.overlay, 0, 0).x + (anchorItem.width - width) / 2
            : plain ? anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - 2.7 - width
            : Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width)
        y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - (plain ? 0 : 8) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onOpened: { search.text = ""; listFlick.contentY = 0; if (!plain) { search.forceActiveFocus(); root.loadComposeApps() } }
        readonly property var suggested: root.suggestedApps.filter(a => String(a.name || "").toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0)
        readonly property var apps: root.composeApps.filter(a => String(a.name || "").toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0)
        // (Editing: Collaborate with Loop, Set delivery options and Record
        // video clip, measured 2026-11-23.)
        readonly property var items: [
            { key: "loop", label: qsTr("Collaborate with Loop"), icon: "loop-page-20", hidden: !root.editing || !root.loopAllowed || !!root.loop || !!root.editLoop },
            { key: "schedule", label: qsTr("Schedule message"), icon: "send-clock-20", hidden: !root.scheduleAllowed || root.editing },
            { key: "delivery", label: qsTr("Set delivery options"), icon: "important-20", hidden: !root.deliveryOptions },
            { key: "meeting", label: qsTr("Schedule meeting"), icon: "calendar-add-20", hidden: root.editing || root.post },
            { key: "clip", label: qsTr("Record video clip"), icon: "video-clip-20", hidden: !root.canRecordClip },
            // A channel post's (new or edited; Teams' enableCrossPost, not
            // when scheduled).
            { key: "permissions", label: qsTr("Change permissions"), icon: "options-20", hidden: !root.post },
            { key: "crosspost", label: qsTr("Post in other channels"), icon: "channel-share-20", hidden: !root.post || root.scheduleAt > 0 }
        ].filter(i => !i.hidden && i.label.toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0)
        Rectangle {
            visible: !plusFlyout.plain
            x: 14.7; y: 17.3; width: 310; height: 30.7; radius: 4
            color: theme.surface
            border.color: search.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: search.activeFocus ? 2 : 0.67; color: search.activeFocus ? theme.brand : theme.textSecondary }
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
            TextInput {
                id: search
                x: 34.6; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                Text { visible: !search.text; text: qsTr("Search for apps"); font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Search for apps")
            }
        }
        Flickable {
            id: listFlick
            x: 0; y: plusFlyout.plain ? 12.7 : 62.7
            width: parent.width; height: plusFlyout.height - y - (plusFlyout.plain ? 12.6 : 14.7 + plusFlyout.footerH)
            contentHeight: plusFlyout.listH
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: listFlick.contentHeight > listFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        Column {
            id: itemsCol
            x: plusFlyout.plain ? 7.7 : 14.7
            Repeater {
                model: plusFlyout.items
                Rectangle {
                    id: hcFill9
                    required property var modelData
                    width: plusFlyout.plain ? 218 : 310; height: 36; radius: 4
                    color: rowHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 8; y: 8; name: parent.modelData.icon; size: 20; color: theme.onFill(hcFill9, theme.textStrong) }
                    Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill9, theme.text) }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            plusFlyout.close()
                            if (parent.modelData.key === "delivery") { deliveryPopup.anchorItem = plusFlyout.anchorItem; deliveryPopup.open() }
                            else if (parent.modelData.key === "loop") root.insertLoop()
                            else if (parent.modelData.key === "schedule") schedulePopup.openFor(plusFlyout.anchorItem, false)
                            else if (parent.modelData.key === "clip") root.recordClipRequested()
                            else if (parent.modelData.key === "permissions") root.openPostMenu(permissionMenu, plusFlyout.anchorItem)
                            else if (parent.modelData.key === "crosspost") root.openPostMenu(postInMenu, plusFlyout.anchorItem)
                            else root.scheduleMeetingRequested()
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
        }
        Rectangle {
            visible: appsCol.visible
            x: 14.7; y: itemsCol.height + 5; width: 310; height: 0.67
            color: theme.divider
        }
        Column {
            id: appsCol
            visible: !plusFlyout.plain && plusFlyout.apps.length > 0
            x: 14.7; y: itemsCol.height + 10.7
            Repeater {
                model: plusFlyout.apps
                Rectangle {
                    id: appRow
                    required property var modelData
                    width: 310; height: 36; radius: 4
                    color: appHover.hovered ? theme.menuHover : "transparent"
                    Image { x: 8; y: 8; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: appRow.modelData.icon || ""; asynchronous: true; fillMode: Image.PreserveAspectFit }
                    Text { x: 40; width: parent.width - 48; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: appRow.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(appRow, theme.text) }
                    HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const anchor = plusFlyout.anchorItem
                            plusFlyout.close()
                            root.openComposeApp(appRow.modelData, anchor)
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.name || ""
                }
            }
        }
        // "Add a new app" (measured on winpc 2026-11-20): Store apps with
        // compose commands you haven't added, 90 apart: the 36 px round
        // icon (#FAFAFA) at 26, the name 14/600 at 74 (an agent's 16 px
        // mark 4 after it), the description 12 #616161 (194.8 wide), Add
        // (39.2 x 24, radius 4) at 280.8, the rating (a 16 px star:
        // outline #C7C7C7 "No ratings yet", or #5B5FC7 "4.9" bold and
        // " (318 ratings)"), then Privacy | Terms of use | Permissions
        // (10/14 #424242, #D1D1D1 bars); the heading 14 #424242 centred
        // between lines.
        Item {
            id: newApps
            visible: !plusFlyout.plain && plusFlyout.suggested.length > 0
            x: 0; y: itemsCol.height + (appsCol.visible ? 10.7 + appsCol.height : 0)
            width: plusFlyout.width; height: 58 + 90 * plusFlyout.suggested.length
            Rectangle { x: 14.7; y: 10; width: (parent.width - 29.4 - heading.implicitWidth) / 2 - 12; height: 0.67; color: theme.divider }
            Rectangle { x: parent.width - 14.7 - width; y: 10; width: (parent.width - 29.4 - heading.implicitWidth) / 2 - 12; height: 0.67; color: theme.divider }
            Text {
                id: heading
                anchors.horizontalCenter: parent.horizontalCenter; y: 0
                text: qsTr("Add a new app")
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Repeater {
                model: plusFlyout.suggested
                Item {
                    id: sug
                    required property var modelData
                    required property int index
                    x: 0; y: 58 + 90 * index; width: newApps.width; height: 90
                    Rectangle {
                        x: 26; y: 0; width: 36; height: 36; radius: 18; clip: true
                        color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                        Image { anchors.fill: parent; sourceSize: Qt.size(72, 72); source: sug.modelData.icon || ""; asynchronous: true; fillMode: Image.PreserveAspectFit }
                    }
                    Row {
                        x: 74; y: 0; spacing: 4
                        Text {
                            width: Math.min(implicitWidth, 194.8 - (agentMark.visible ? 20 : 0)); elide: Text.ElideRight
                            text: sug.modelData.name || ""
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                        }
                        FluentIcon { id: agentMark; visible: !!sug.modelData.agent; y: 2; name: "sparkle-20"; size: 16; color: theme.textSecondary; Accessible.name: qsTr("Agent") }
                    }
                    Text {
                        x: 74; y: 20; width: 194.8; elide: Text.ElideRight
                        text: sug.modelData.short || ""
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                    Rectangle {
                        x: 280.8; y: 6; width: 39.2; height: 24; radius: 4
                        color: addHover.hovered ? theme.menuHover : theme.surface
                        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                        opacity: root.addingApp === sug.modelData.id ? 0.5 : 1
                        Text { anchors.centerIn: parent; text: qsTr("Add"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.addSuggestedApp(sug.modelData, plusFlyout.anchorItem) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Add") + " " + (sug.modelData.name || "")
                    }
                    Row {
                        x: 74; y: 39.5; spacing: 3
                        FluentIcon { name: sug.modelData.count > 0 ? "star-16-filled" : "star-16"; size: 16; color: sug.modelData.count > 0 ? theme.pick("#5B5FC7", "#7F85F5", "#FFFF00") : theme.pick("#C7C7C7", "#666666", "#FFFFFF") }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.StyledText
                            text: sug.modelData.count > 0 ? "<b>" + sug.modelData.averageText + "</b> " + qsTr("(%1 ratings)").arg(sug.modelData.countText) : qsTr("No ratings yet")
                            lineHeight: 16; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 12; color: theme.text
                        }
                    }
                    Row {
                        x: 74; y: 60; spacing: 4
                        Repeater {
                            model: [{ k: "privacy", t: qsTr("Privacy") }, { k: "terms", t: qsTr("Terms of use") }, { k: "permissions", t: qsTr("Permissions") }]
                            Row {
                                id: lnk
                                required property var modelData
                                required property int index
                                spacing: 4
                                Text { visible: lnk.index > 0; text: "|"; font.family: theme.font; font.pixelSize: 10; color: theme.pick("#D1D1D1", "#666666", "#FFFFFF") }
                                Text {
                                    text: lnk.modelData.t
                                    lineHeight: 14; lineHeightMode: Text.FixedHeight
                                    font.family: theme.font; font.pixelSize: 10; font.underline: lnkHover.hovered
                                    color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                    HoverHandler { id: lnkHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (lnk.modelData.k === "permissions") { plusFlyout.close(); root.appPermissionsRequested(sug.modelData.id) }
                                            else if (sug.modelData[lnk.modelData.k]) Qt.openUrlExternally(sug.modelData[lnk.modelData.k])
                                        }
                                    }
                                    Accessible.role: Accessible.Link; Accessible.name: text
                                }
                            }
                        }
                    }
                }
            }
        }
        }
        // Get more apps: Teams' app store.
        Rectangle {
            visible: !plusFlyout.plain
            anchors { right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 16 }
            width: 144.8; height: 32; radius: 4
            color: moreHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-square-20"; size: 20; color: theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Get more apps"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { plusFlyout.close(); root.getMoreAppsRequested() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Get more apps")
        }
    }
    // Your installed apps' compose commands (backend.composeAppRequest
    // "list"), most recently used first by the apps usage Teams keeps on
    // the server, then by name; and "Add a new app" ("suggested").
    property var composeApps: []
    property var suggestedApps: []
    property bool composeAppsLoading: false
    property string addingApp: ""
    signal getMoreAppsRequested()
    signal appPermissionsRequested(string appId)
    /// An app's compose command was picked: the conversation opens its
    /// task module (action) or Teams' search panel (query).
    signal composeAppCommand(var app, var command, Item anchor)
    function loadComposeApps() {
        if (root.composeAppsLoading) return
        root.composeAppsLoading = true
        const here = JSON.stringify({ conversation: String(root.chatId || backend.currentChatId) })
        backend.composeAppRequest("list", "compose-apps", here)
        backend.composeAppRequest("suggested", "compose-apps-suggested", here)
    }
    // Add (a suggested app): installed for you, then its compose command
    // opens as an installed app's would.
    property var addAnchor: null
    function addSuggestedApp(app, anchor) {
        if (root.addingApp) return
        root.addingApp = app.id
        root.addAnchor = anchor
        backend.composeAppRequest("add", "compose-apps-add", JSON.stringify({ appId: app.id }))
    }
    Connections {
        target: backend
        function onComposeAppReply(id, json) {
            let r = {}
            try { r = JSON.parse(json) } catch (e) {}
            if (id === "compose-apps-suggested") { if (r.apps) root.suggestedApps = r.apps; return }
            if (id === "compose-apps-add") {
                const added = root.addingApp
                root.addingApp = ""
                if (r.error) { root.showBanner(r.error, true, 3000); return }
                root.pendingOpen = added
                root.composeAppsLoading = false
                root.loadComposeApps()
                return
            }
            if (id !== "compose-apps") return
            root.composeAppsLoading = false
            if (r.apps) {
                root.composeApps = r.apps
                const open = root.pendingOpen ? r.apps.find(a => String(a.id).toLowerCase() === String(root.pendingOpen).toLowerCase()) : null
                root.pendingOpen = ""
                if (open) { plusFlyout.close(); root.openComposeApp(open, root.addAnchor) }
            }
        }
    }
    property string pendingOpen: ""
    function openComposeApp(app, anchor) {
        // Teams records the use where its "+" order comes from (the apps
        // usage it shares with this account's other devices).
        backend.composeAppRequest("usage", "compose-apps-usage", JSON.stringify({ appId: app.id }))
        const id = String(app.id).toLowerCase()
        root.composeApps = [app].concat(root.composeApps.filter(a => String(a.id).toLowerCase() !== id))
        const cmds = app.commands || []
        // One command: straight to it; several: Teams' list of them.
        if (cmds.length === 1) root.composeAppCommand(app, cmds[0], anchor)
        else root.composeAppCommand(app, null, anchor)
    }
    // Schedule message (measured on winpc 2026-11-10): 245.3 wide, radius
    // 4, shadow16, padding 16 / 12; "Send this message on" (14 #616161),
    // the date (filled, "Tuesday, November 10") and the time (filled, 48
    // half hours, earlier ones greyed today), 220 wide and 8 apart, then
    // Continue (brand, 31.3) and, for a scheduled message, "Cancel
    // scheduled time". It opens above what opened it, its end 8 past.
    Popup {
        id: schedulePopup
        property bool changing: false
        property date day: new Date()
        property int slot: 16
        parent: Overlay.overlay
        width: 245.3; padding: 0
        height: 186.7 + (changing ? 40.7 : 0)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        function openFor(anchor, changing) {
            const at = new Date(root.scheduleAt > 0 ? root.scheduleAt : root.nextEight())
            day = new Date(at.getFullYear(), at.getMonth(), at.getDate())
            slot = at.getHours() * 2 + (at.getMinutes() >= 30 ? 1 : 0)
            schedulePopup.changing = changing
            const p = anchor.mapToItem(Overlay.overlay, anchor.width, 0)
            x = Math.min(Overlay.overlay.width - width - 8, p.x + 8 - width)
            y = Math.max(8, p.y - height - 4)
            open()
        }
        readonly property bool today: { const n = new Date(); return day.getFullYear() === n.getFullYear() && day.getMonth() === n.getMonth() && day.getDate() === n.getDate() }
        readonly property var slots: {
            const out = [], now = Date.now()
            for (let i = 0; i < 48; i++) {
                const t = new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(i / 2), (i % 2) * 30)
                out.push({ label: theme.time(t), disabled: t.getTime() <= now })
            }
            return out
        }
        readonly property real chosen: new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(slot / 2), (slot % 2) * 30).getTime()
        Text { x: 12; y: 16.7; text: qsTr("Send this message on"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
        DatePickerField {
            x: 12; y: 52; width: 220; height: 31.3
            filled: true; format: "dddd, MMMM d"
            date: schedulePopup.day
            minDate: new Date()
            onPicked: d => schedulePopup.day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        }
        OutlineDropdown {
            x: 12; y: 91.3; width: 220; height: 32
            filled: true
            options: schedulePopup.slots
            current: schedulePopup.slot
            accessibleName: qsTr("Select time")
            onPicked: i => schedulePopup.slot = i
        }
        Rectangle {
            id: scheduleGo
            readonly property bool usable: schedulePopup.chosen > Date.now()
            x: 12; y: 139.3; width: 220; height: 31.3; radius: 4
            color: !usable ? theme.bgDisabled : goHover.hovered ? theme.brandHover : theme.brand
            Text { anchors.centerIn: parent; text: qsTr("Continue"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(scheduleGo, scheduleGo.usable ? "white" : theme.disabled) }
            HoverHandler { id: goHover; cursorShape: scheduleGo.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: scheduleGo.usable; onTapped: { root.scheduleAt = schedulePopup.chosen; schedulePopup.close(); input.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Continue")
        }
        Rectangle {
            id: hcFill10
            visible: schedulePopup.changing
            x: 12; y: 178.7; width: 220; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: qsTr("Cancel scheduled time"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill10, theme.text) }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.scheduleAt = 0; schedulePopup.close(); input.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Cancel scheduled time")
        }
    }
    function openScheduleForTest(anchor) { schedulePopup.openFor(anchor, root.scheduleAt > 0) }
    // Delivery options (measured): 317.3 x 161.3; 48 px options with a 16 px
    // icon at (16, 18.3), the title 14/18.7 and description 12/16 at 40.7,
    // the selected one NeutralBackground1Hover with a checkmark at 284.
    Popup {
        id: deliveryPopup
        property Item anchorItem: null
        parent: Overlay.overlay
        // (In an edit, measured 2026-11-23: Standard and Important only,
        // 217.3 x 113.3, right on top of the button from its left edge,
        // kept 16.7 inside the window.)
        width: root.editing ? 217.3 : 317.3; height: root.editing ? 113.3 : 161.3; padding: 0
        x: !anchorItem ? 0 : root.editing ? Math.min(Overlay.overlay.width - width - 16.7, anchorItem.mapToItem(Overlay.overlay, 0, 0).x)
            : Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width + 50)
        y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - (root.editing ? 0 : 8) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            x: 0.7; y: 8.7
            Repeater {
                model: [
                    { key: "", title: qsTr("Standard"), desc: qsTr("Message will be sent as usual"), icon: "chat-20", color: "", name: qsTr("Standard Message Delivery") },
                    { key: "high", title: qsTr("Important"), desc: qsTr("Message will be marked as important"), icon: "important-20", color: "#C4314B", name: qsTr("Mark message as important") },
                    { key: "urgent", title: qsTr("Urgent"), desc: root.urgentAllowed ? qsTr("Recipients notified every %1 min for %2 min", "", 1).arg(2).arg(20) : qsTr("Unavailable in chats with more than 20 people"), icon: "alert-urgent-20", color: "#C4314B", name: qsTr("Mark message as urgent and repeatedly notify recipients every %1 minutes for %2 minutes", "", 1).arg(2).arg(20) }
                ].filter(o => !root.editing || o.key !== "urgent")
                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool selected: root.importance === modelData.key
                    readonly property bool enabledNow: modelData.key !== "urgent" || root.urgentAllowed
                    width: deliveryPopup.width - 1.3; height: 48
                    color: selected || (optHover.hovered && enabledNow) ? theme.menuHover : "transparent"
                    FluentIcon {
                        x: opt.modelData.key === "urgent" ? 20 : 16; y: 16; size: 16
                        name: opt.modelData.icon
                        color: theme.onFill(opt, !opt.enabledNow ? theme.disabled : opt.modelData.color || theme.text)
                    }
                    Text { x: opt.modelData.key === "urgent" ? 44.7 : 40.7; y: 6.6; text: opt.modelData.title; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(opt, opt.enabledNow ? theme.text : theme.disabled) }
                    Text { x: opt.modelData.key === "urgent" ? 44.7 : 40.7; y: 25.3; text: opt.modelData.desc; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(opt, opt.enabledNow ? theme.text : theme.disabled) }
                    FluentIcon { visible: opt.selected; x: deliveryPopup.width - 33.3; y: 16; name: "checkmark-20"; size: 16; color: theme.onFill(opt, theme.text) }
                    HoverHandler { id: optHover; cursorShape: opt.enabledNow ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: opt.enabledNow; onTapped: { root.importance = opt.modelData.key; deliveryPopup.close(); input.forceActiveFocus() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                    Accessible.selected: selected
                }
            }
        }
    }
    // @mentions (930187, measured): typing "@" at a word start opens Teams'
    // picker over the caret; picking inserts the name, each word its own
    // mention token in BrandForeground1, then a space.
    property int mentionAt: -1
    property string mentionQuery: ""
    function checkMention() {
        const pos = input.cursorPosition
        const before = input.getText(0, pos)
        const at = before.lastIndexOf("@")
        const q = at >= 0 ? before.slice(at + 1) : ""
        const ok = at >= 0 && (at === 0 || /\s/.test(before[at - 1])) && !/[\n\u2029]/.test(q) && q.length <= 40 && (q.match(/ /g) || []).length <= 2
        if (!ok) { mentionAt = -1; if (mentionPicker.opened) mentionPicker.close(); return }
        mentionAt = at; mentionQuery = q
        if (q.trim().length >= 2 && root.mentionDirectory) backend.searchPeople(q.trim())
        if (!mentionPicker.opened) mentionPicker.open()
        mentionPicker.current = 0
    }
    function insertMention(person) {
        if (mentionAt < 0) return
        if (person.kind === "add" || person.kind === "agent") {
            // The "@" and what follows it go; Teams' dialog opens.
            input.remove(mentionAt, Math.max(mentionAt, input.cursorPosition))
            mentionAt = -1; mentionPicker.close()
            if (person.kind === "agent") root.addAgentRequested(); else root.addPeopleRequested()
            return
        }
        if (person.kind === "share") {
            // Teams' "Share someone's contact info": the "@" and what
            // follows it go; the dialog puts the cards in.
            shareAt = mentionAt; shareEnd = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            shareContact.start()
            return
        }
        if (person.kind === "team" || person.kind === "channel" || person.kind === "tag") {
            const at1 = mentionAt, end1 = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            input.remove(at1, end1)
            input.insert(at1, '<a href="mention-' + person.kind + ':' + person.mri + '" style="color:' + theme.brandForeground1 + '; text-decoration:none">' + escapeHtml(person.name) + '</a>&nbsp;')
            input.cursorPosition = at1 + person.name.length + 1
            input.forceActiveFocus()
            return
        }
        if (person.everyone) {
            if (!root.everyoneAllowed) return
            // Teams: past 50 others, "# people will be notified".
            if (root.everyoneOthers > 50)
                root.showBanner(qsTr("%n people will be notified", "", root.everyoneOthers), true, 3000, false)
            const at0 = mentionAt, end0 = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            input.remove(at0, end0)
            input.insert(at0, root.memberCount > 2 ? '<a href="mention-everyone:' + root.everyoneId + '" style="color:' + theme.brandForeground1 + '; text-decoration:none">Everyone</a>&nbsp;' : "Everyone&nbsp;")
            input.cursorPosition = at0 + 9
            input.forceActiveFocus()
            return
        }
        // (A bot's name stays one mention, as a suggested action gives it.)
        const words = person.whole ? [String(person.name || "")] : String(person.name || "").split(/\s+/).filter(w => w)
        const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
        // A bot with its app goes as Teams' bot mention (mentionType "bot"
        // and the app id: a Channel Agent answers only those).
        const target = person.appId && String(person.mri).indexOf("28:") === 0 ? "mention-bot:" + person.mri + "|" + person.appId : "mention:" + person.mri
        const html = words.map(w => '<a href="' + target + '" ' + style + '>' + escapeHtml(w) + '</a>').join("&nbsp;") + "&nbsp;"
        const at = mentionAt, end = input.cursorPosition
        mentionAt = -1
        mentionPicker.close()
        input.remove(at, end)
        input.insert(at, html)
        input.cursorPosition = at + words.join(" ").length + 1
        mentionPicker.close()
        input.forceActiveFocus()
    }
    Popup {
        id: mentionPicker
        parent: Overlay.overlay
        width: 300; padding: 0
        height: Math.min(310.3, 43.2 + rowsCol.height + 8)
        closePolicy: Popup.CloseOnPressOutside
        focus: false
        property int current: 0
        readonly property var people: {
            const q = root.mentionQuery.trim().toLowerCase()
            const fromRoster = root.mentionables.filter(p => !q || (p.name || "").toLowerCase().split(/\s+/).some(w => w.startsWith(q)) || (p.name || "").toLowerCase().startsWith(q) || (p.mail || "").toLowerCase().startsWith(q))
            const found = q.length >= 2 && root.mentionDirectory ? (backend.peopleJson ? JSON.parse(backend.peopleJson) : []).map(p => ({ mri: "8:orgid:" + p.id, name: p.name, mail: p.mail || p.email || "" })) : []
            const out = []
            // A channel's team and the channel itself (Teams' channel
            // picker): by a word of their name, or by "team" / "channel".
            const words = n => (n || "").toLowerCase().split(/\s+/)
            const t = root.teamMention, c = root.channelMention
            if (q && t && (words(t.name).some(w => w.startsWith(q)) || t.name.toLowerCase().startsWith(q) || "team".startsWith(q)))
                out.push({ kind: "team", mri: t.id, name: t.name, mail: qsTr("Team"), photoId: t.groupId })
            if (q && c && (words(c.name).some(w => w.startsWith(q)) || c.name.toLowerCase().startsWith(q) || "channel".startsWith(q)))
                out.push({ kind: "channel", mri: c.id, name: c.name, mail: qsTr("Channel"), photoId: t ? t.groupId : "" })
            // Tags, by a word of their name ("1 person", "N people").
            if (q) for (const g of root.tagMentions || [])
                if (words(g.name).some(w => w.startsWith(q)) || g.name.toLowerCase().startsWith(q))
                    out.push({ kind: "tag", mri: g.id, name: g.name, mail: qsTr("%n people", "", g.count) })
            for (const p of fromRoster) out.push(p)
            for (const p of found) if (!out.some(o => o.mri === p.mri)) out.push(p)
            // Everyone: offered up to Teams' limit, shown disabled past it.
            if (root.everyoneId && (!q || "everyone".startsWith(q)))
                out.push({ everyone: true, name: qsTr("Everyone"), mail: qsTr("Notify everyone in the chat"), disabled: !root.everyoneAllowed })
            const rows = out.slice(0, 20)
            if (root.canAddAgent) rows.push({ kind: "agent", name: root.channelMention ? qsTr("Add agent to the channel") : qsTr("Add agent to the chat"), mail: "" })
            if (root.canAddPeople) rows.push({ kind: "add", name: qsTr("Add someone to the chat"), mail: "" })
            // Always last (Teams): share someone's contact card.
            rows.push({ kind: "share", name: qsTr("Share someone\u2019s contact info"), mail: "" })
            return rows
        }
        function move(d) { if (people.length) current = (current + d + people.length) % people.length }
        function pick() { if (people.length) { const p = people[Math.max(0, Math.min(current, people.length - 1))]; if (!p.disabled) root.insertMention(p) } else close() }
        readonly property rect caret: input.cursorRectangle
        x: { const p = input.mapToItem(Overlay.overlay, input.positionToRectangle(Math.max(0, root.mentionAt)).x, 0); return Math.min(Overlay.overlay.width - width - 8, Math.max(8, p.x)) }
        y: { const p = input.mapToItem(Overlay.overlay, 0, input.positionToRectangle(Math.max(0, root.mentionAt)).y); return Math.max(8, p.y - height - 1) }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Text {
            x: 20.7; y: 10.7; height: 20; verticalAlignment: Text.AlignVCenter
            text: qsTr("Suggestions")
            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
        }
        Column {
            id: rowsCol
            // Rows sit 5 apart (measured on winpc, 2026-11-09).
            x: 0.7; y: 43.2; spacing: 5
            Repeater {
                model: mentionPicker.people
                Rectangle {
                    id: prow
                    required property var modelData
                    required property int index
                    readonly property bool action: modelData.kind === "share" || modelData.kind === "add" || modelData.kind === "agent"
                    width: 298.7; height: modelData.kind === "share" || modelData.kind === "agent" || modelData.everyone ? 49.3 : modelData.kind === "add" ? 48.7 : 47.3
                    color: index === mentionPicker.current ? theme.pick("#E6E6E6", "#3D3D3D", "#1AEBFF") : prowHover.hovered ? theme.menuHover : "transparent"
                    Avatar { visible: !prow.modelData.everyone && !prow.modelData.kind; x: 19.6; y: 7.6; size: 32; name: prow.modelData.name; photoId: prow.modelData.mri || "" }
                    // A team or channel: the team's picture, a 4 px square.
                    Avatar {
                        visible: prow.modelData.kind === "team" || prow.modelData.kind === "channel"
                        x: 19.6; y: 7.6; size: 32; square: true
                        readonly property string team: root.teamMention ? root.teamMention.name : ""
                        name: team
                        initialsText: team.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: prow.modelData.photoId ? "team:" + prow.modelData.photoId : ""
                    }
                    // A tag: the tag icon on a 32 px lavender circle.
                    Rectangle {
                        visible: prow.modelData.kind === "tag"
                        x: 19.6; y: 7.6; width: 32; height: 32; radius: 16
                        color: theme.pick("#C5CBFA", "#3D3E78", "#FFFFFF")
                        FluentIcon { anchors.centerIn: parent; name: "tag-20"; size: 20; color: theme.pick("#444791", "#C5CBFA", "#FFFFFF") }
                    }
                    FluentIcon { visible: !!prow.modelData.everyone; x: 25.6; y: 13.6; name: "people-20"; size: 20; color: theme.onFill(prow, prow.modelData.disabled ? theme.disabled : theme.textStrong) }
                    // Past the limit: Teams' tooltip.
                    ToolTip.visible: !!prow.modelData.disabled && prowHover.hovered; ToolTip.delay: 300
                    ToolTip.text: qsTr("Not available for chats over 1,000 users.")
                    // Share someone's contact info: the contact card icon (20).
                    FluentIcon { visible: prow.modelData.kind === "share"; x: 19.6; y: 14.6; name: "contact-card-20"; size: 20; color: theme.onFill(prow, theme.textStrong) }
                    // Add agent: bot-add (20).
                    FluentIcon { visible: prow.modelData.kind === "agent"; x: 19.6; y: 14.6; name: "bot-add-20"; size: 20; color: theme.onFill(prow, theme.textStrong) }
                    // Add someone to the chat: person-add (20).
                    FluentIcon { visible: prow.modelData.kind === "add"; x: 19.6; y: 14.3; name: "people-add-20"; size: 20; color: theme.onFill(prow, theme.textStrong) }
                    // The typed part in bold (Teams).
                    Text { x: prow.action ? 59 : 59.6; y: prow.action ? 14.5 : 5.6; height: 20; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; textFormat: prow.action ? Text.PlainText : Text.StyledText; text: prow.action ? prow.modelData.name : root.boldMatch(prow.modelData.name, root.mentionQuery.trim()); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, prow.modelData.disabled ? theme.disabled : theme.text) }
                    Text { visible: !!prow.modelData.mail; x: 59.6; y: 25.6; height: 16; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; text: prow.modelData.mail || ""; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(prow, prow.modelData.disabled ? theme.disabled : theme.text) }
                    HoverHandler { id: prowHover; cursorShape: prow.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    TapHandler { enabled: !prow.modelData.disabled; onTapped: root.insertMention(prow.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (modelData.mail ? " " + modelData.mail : "")
                    Accessible.selected: index === mentionPicker.current
                }
            }
        }
    }
    // `name` with the word that starts with `q` bold for its first
    // q.length letters.
    function boldMatch(name, q) {
        const n = String(name || "")
        if (!q) return escapeHtml(n)
        const lower = n.toLowerCase(), ql = q.toLowerCase()
        let i = lower.startsWith(ql) ? 0 : lower.indexOf(" " + ql)
        if (i > 0) i++
        if (i < 0) return escapeHtml(n)
        return escapeHtml(n.slice(0, i)) + "<b>" + escapeHtml(n.slice(i, i + q.length)) + "</b>" + escapeHtml(n.slice(i + q.length))
    }
    // Share someone's contact info: where the "@" was, and the dialog.
    property int shareAt: -1
    property int shareEnd: -1
    ShareContactDialog {
        id: shareContact
        onAccepted: people => {
            const at = root.shareAt, end = root.shareEnd
            if (at < 0) return
            input.remove(at, Math.max(at, Math.min(end, input.length)))
            const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
            const icon = Qt.resolvedUrl("../assets/icons/contact-card-inline-" + (theme.dark ? "dark" : "light") + ".svg")
            const html = people.map(p => '<img src="' + icon + '" width="20" height="20"><a href="mention-contact:' + p.mri + '" ' + style + '>' + escapeHtml(p.name) + '</a>&nbsp;').join("")
            input.insert(at, html)
            input.cursorPosition = at + people.reduce((n, p) => n + 1 + p.name.length + 1, 0)
            root.shareAt = -1
            input.forceActiveFocus()
        }
        onClosed: input.forceActiveFocus()
    }
    function shareContactForTest() { return shareContact }
    function formatBarForTest() { return formatBar }
    // Type a line and format all of it (the formatting bar on a selection).
    function formatLineForTest(text, op, arg) {
        if (input.length > 0) rich.apply(input.length, input.length, "newblock", "")
        const a = input.length
        input.insert(a, escapeHtml(text))
        input.select(a, input.length)
        if (op) format(op, arg)
        input.cursorPosition = input.length
    }
    function pickShareForTest() { insertMention({ kind: "share" }) }
    // Tables: insert one, fill its cells in order (Tab between them), run a
    // row/column/table op, read the export.
    function tableForTest(cols, rows) { root.formatting = true; format("table", cols + "x" + rows) }
    function tableFillForTest(texts) {
        refreshRichState()
        for (let i = 0; i < texts.length; i++) {
            input.insert(input.cursorPosition, escapeHtml(texts[i]))
            refreshRichState()
            if (i < texts.length - 1 && richState.nextCell >= 0) input.cursorPosition = richState.nextCell
        }
        refreshRichState()
    }
    function tableOpForTest(op) { format(op, "") }
    function exportForTest() { return rich.exportHtml() }
    /// Insert a mention at the cursor, as if picked after an "@".
    function insertMentionOf(person) {
        mentionAt = input.cursorPosition
        insertMention(person)
    }
    function clearForTest() { input.clear(); mentionAt = -1; mentionPicker.close() }
    function mentionForTest(text) { input.insert(input.cursorPosition, text); input.cursorPosition = input.length }
    function pickMentionForTest(n) { mentionPicker.current = n || 0; mentionPicker.pick() }

    function deliveryForTest() { deliveryPopup.anchorItem = sideTools; deliveryPopup.open() }
    function plusForTest() {
        const find = it => {
            for (const c of it.children) {
                if (c.visible && c.modelData && c.modelData.id === "message-extension-flyout-command") return c
                const f = find(c)
                if (f) return f
            }
            return null
        }
        plusFlyout.anchorItem = find(root) || sideTools; plusFlyout.open()
    }
    function closePlusForTest() { plusFlyout.close() }

    // Teams' "Discard draft" (messagedraft-discard-dialog): 600 x 156,
    // radius 8; the title 20/28 semibold at 24.7, Close, the text at 62,
    // Cancel and Discard (96 x 31.3) at y 100.
    Popup {
        id: discardDialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 600; height: 156; padding: 0
        anchors.centerIn: Overlay.overlay
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        Text { x: 24.7; y: 24.7; height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("Discard draft"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Rectangle {
            id: hcFill11
            x: 543.3; y: 24.7; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill11, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: discardDialog.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Text { x: 22.7; y: 62; height: 32; verticalAlignment: Text.AlignVCenter; text: qsTr("You can discard your draft or cancel to keep editing"); font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        Row {
            x: 375.3; y: 100; spacing: 8
            Rectangle {
                id: hcFill12
                width: 96; height: 31.3; radius: 4
                color: dCancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill12, theme.text) }
                HoverHandler { id: dCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { discardDialog.close(); input.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Cancel")
            }
            Rectangle {
                id: hcFill13
                width: 96; height: 31.3; radius: 4
                color: discardHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Discard"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill13, "white") }
                HoverHandler { id: discardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { discardDialog.close(); root.formatting = false; input.clear(); if (root.post) root.resetPost(); root.cancelled() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Discard")
            }
        }
    }
    // Teams' RoamingDraftConflictDialog ("View draft" on the conflict
    // banner): "Saved draft" with Close, "Saved on {date}", the other
    // device's draft, then Discard and "Use this version". Teams' code gives
    // its parts and strings; it can't be opened on this tenant (drafts don't
    // roam there), so the frame is the Discard draft dialog's.
    /// {text, editHtml, time} of the other device's draft.
    property var conflictDraft: null
    signal conflictResolved(bool useIt)
    function viewConflict() { if (conflictDraft) conflictDialog.open() }
    Popup {
        id: conflictDialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 600; height: Math.min(480, conflictBody.y + conflictBody.height + 24 + 31.3 + 24); padding: 0
        anchors.centerIn: Overlay.overlay
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        Text { x: 24.7; y: 24.7; height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("Saved draft"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Rectangle {
            id: hcFill14
            x: 543.3; y: 24.7; width: 32; height: 31.3; radius: 4
            color: cdCloseHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill14, theme.textStrong) }
            HoverHandler { id: cdCloseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: conflictDialog.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Row {
            x: 24.7; y: 62; spacing: 4
            Text { text: qsTr("Saved on"); font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
            Text {
                text: root.conflictDraft && root.conflictDraft.time ? theme.date(new Date(root.conflictDraft.time)) + " " + theme.time(new Date(root.conflictDraft.time)) : ""
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary
            }
        }
        Text {
            id: conflictBody
            x: 24.7; y: 90; width: 600 - 49.3
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: root.conflictDraft ? theme.messageHtml(String(root.conflictDraft.editHtml || "").replace(/<a href="(mention[^"]*)">/g, '<a href="$1" style="color:' + theme.brandForeground1 + '; text-decoration:none">') || root.escapeHtml(root.conflictDraft.text || "")) : ""
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            maximumLineCount: 14; elide: Text.ElideRight
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24.7
            y: conflictDialog.height - 24 - 31.3; spacing: 8
            Rectangle {
                id: hcFill15
                width: 96; height: 31.3; radius: 4
                color: cdDiscardHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: qsTr("Discard"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill15, theme.text) }
                HoverHandler { id: cdDiscardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { conflictDialog.close(); root.conflictResolved(false) } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Discard")
            }
            Rectangle {
                id: hcFill16
                width: useLabel.implicitWidth + 32; height: 31.3; radius: 4
                color: cdUseHover.hovered ? theme.brandHover : theme.brandFill
                Text { id: useLabel; anchors.centerIn: parent; text: qsTr("Use this version"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill16, "white") }
                HoverHandler { id: cdUseHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { conflictDialog.close(); root.conflictResolved(true) } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Use this version")
            }
        }
    }
    // Test hooks.
    function conflictDialogForTest() { return conflictDialog }
    function discardForTest() { discardDialog.open() }
    function openSchemesForTest() { schemes.open() }
    function bannerDialogForTest() { return bannerImageDialog }
    function closeSchemesForTest() { schemes.close() }
    function everyoneRowForTest(n, meeting) { memberCount = n; meetingChat = !!meeting; return { allowed: everyoneAllowed, others: everyoneOthers } }
    function confirmDiscardForTest() { discardDialog.close(); root.formatting = false; input.clear(); if (root.post) root.resetPost(); root.cancelled() }
}
