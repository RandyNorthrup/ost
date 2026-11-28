import QtQuick

// Teams' Attach for a compose box: the Attach popover, the cloud file
// picker, the files picked for the next message (each read for its card
// first) and their cards' Link settings. Used by a conversation's compose
// box and a post's thread view (Teams offers the same popover in both,
// measured on winpc 2026-11-16: a thread in a channel also lists Browse
// Teams and Channels).
// - Picked files: [{key, name, kind, loading, file, thumbnail, linking}].
// - Link settings (the card's link description): OneDrive's Link settings
//   with "People currently in this chat"; Apply makes the link at once
//   (ShareLink; for this chat with its members in peoplePickerInput) and
//   the card's line follows. The message then carries that link instead
//   of Teams' default one, and no invite is sent (OST TEST 172).
Item {
    id: ca
    /// Where the files go: the chat, or the channel (and its team).
    property string chatId: ""
    property bool channel: false
    property string teamName: ""
    property string teamId: ""
    /// The conversation's last messages ({id, text, sender, time}) for the
    /// popover's suggestions.
    property var context: []
    /// Upload from this device.
    signal uploadRequested()
    /// Something went wrong (a short sentence for the compose banner).
    signal failed(string text)

    property var pending: []
    readonly property bool hasFiles: pending.some(c => !!c.file)
    readonly property bool busy: pending.some(c => c.loading || c.linking)
    /// What the backend sends: "cloud:" and each read cloud file.
    function lines() { return pending.filter(c => !!c.file).map(c => "cloud:" + JSON.stringify(c.file)) }
    function clear() { pending = [] }
    function remove(key) { pending = pending.filter(c => c.key !== key) }
    readonly property string tag: "cloud-attach-" + Math.floor(Math.random() * 1e9) + ":"

    /// Files from the Attach popover or the cloud file picker into the
    /// compose box (Teams reads each for its card).
    function attach(list) {
        for (const f of list) {
            const key = f.web_url
            if (!key || pending.some(c => c.key === key)) continue
            pending = pending.concat([{ key: key, name: f.name, kind: f.kind || "", loading: true }])
            backend.driveAction(tag + encodeURIComponent(key) + ":attach_prepare",
                JSON.stringify({ name: f.name, web_url: f.web_url, drive_id: f.drive_id || "", id: f.id || "", kind: f.kind || "" }), "{}")
        }
    }
    function update(key, changes) { pending = pending.map(c => c.key === key ? Object.assign({}, c, changes) : c) }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(ca.tag)) return
            const rest = op.slice(ca.tag.length)
            const cut = rest.lastIndexOf(":")
            const key = decodeURIComponent(rest.slice(0, cut))
            const kind = rest.slice(cut + 1)
            if (kind === "attach_prepare") {
                if (error) { ca.remove(key); ca.failed(qsTr("Couldn't attach the file. Please try again.")); return }
                const v = JSON.parse(result)
                ca.update(key, { loading: false, file: v.file, thumbnail: v.thumbnail })
            } else if (kind === "attach_link") {
                const c = ca.pending.find(x => x.key === key)
                if (!c) return
                if (error) { ca.update(key, { linking: false }); ca.failed(qsTr("Couldn't update the link settings. Please try again.")); return }
                const v = JSON.parse(result)
                ca.update(key, { linking: false, file: Object.assign({}, c.file, { share_url: v.url, share_id: v.share_id, scope: v.scope, link_description: c.wantLine }) })
            }
        }
    }

    /// Teams' Attach popover over `anchor` (alignEnd: a suggested reply's
    /// Share a file).
    function openMenu(anchor, alignEnd) {
        attachMenu.anchorItem = anchor
        attachMenu.channel = ca.channel
        attachMenu.chatId = ca.chatId
        attachMenu.context = ca.context
        attachMenu.alignEnd = !!alignEnd
        attachMenu.open()
    }
    function closeMenu() { attachMenu.close() }
    readonly property alias menu: attachMenu
    readonly property alias picker: cloudPicker
    AttachMenu {
        id: attachMenu
        onAttachCloud: { if (backend.personalAccount) { personalPicker.open(); return } cloudPicker.entry = "home"; cloudPicker.open() }
        onBrowseChannels: { cloudPicker.entry = { team: ca.teamName, team_id: ca.teamId, channel_id: ca.chatId }; cloudPicker.open() }
        onUpload: ca.uploadRequested()
        onPicked: f => ca.attach([f])
    }
    CloudPicker {
        id: cloudPicker
        onAttached: files => ca.attach(files)
    }
    // A personal account's OneDrive (Teams free's picker).
    PersonalCloudPicker {
        id: personalPicker
        onAttached: files => ca.attach(files)
    }
    readonly property alias personalPickerView: personalPicker

    // Link settings.
    property string linkKey: ""
    /// The starting choice from the card's line (Teams' default link).
    function choiceFrom(c) {
        const d = String(c.file ? c.file.link_description : "")
        const write = !c.file || c.file.role === "write" || /can edit$/.test(d)
        if (c.link) return c.link
        if (d.startsWith("Anyone with the link")) return { scope: 0, edit: write }
        if (d.startsWith("People in ") && !d.startsWith("People in this chat")) return { scope: 1, edit: write }
        if (d.startsWith("People currently in this chat")) return { scope: 4, edit: write }
        if (d.startsWith("Specific people") || d.startsWith("Only the people")) return { scope: 2, edit: write }
        return { scope: 3, edit: write }
    }
    /// A compose box's Loop component whose Link settings are open.
    property var loopBox: null
    function openLoopLink(box, fileRef, name, scope, edit) {
        loopBox = box
        linkKey = ""
        linkDialog.openLinkSettings(fileRef, name, "loop", scope, edit, "", "", [0, 2])
    }
    function openLink(key) {
        loopBox = null
        const c = pending.find(x => x.key === key)
        if (!c || !c.file) return
        linkKey = key
        const ch = choiceFrom(c)
        linkDialog.openLinkSettings({ site: c.file.site_url, list: c.file.list_id, item: c.file.unique_id }, c.name, c.kind, ch.scope, ch.edit, ch.expiration || "", ch.password || "")
    }
    /// The card's line for a choice, as Teams words it.
    function lineFor(scope, edit) {
        const can = edit ? "edit" : "view"
        if (scope === 3) return "People with existing access can use the link"
        if (scope === 0) return "Anyone with the link can " + can
        if (scope === 1) return "People in " + (linkDialog.info ? linkDialog.info.tenant : "your organization") + " with the link can " + can
        if (scope === 4) return "People currently in this chat with the link can " + can
        return "Specific people with the link can " + can
    }
    OneDriveShare {
        id: linkDialog
        onLinkChosen: (scope, edit, expiration, password) => {
            if (ca.loopBox) {
                const box = ca.loopBox
                ca.loopBox = null
                box.applyLoopLink(scope, edit, expiration, password, ca.lineFor(scope, edit))
                return
            }
            const key = ca.linkKey
            const c = ca.pending.find(x => x.key === key)
            if (!c || !c.file) return
            const line = ca.lineFor(scope, edit)
            if (scope === 3) {
                // Existing access: no link; the file's own address goes.
                ca.update(key, { link: { scope: scope, edit: edit }, file: Object.assign({}, c.file, { share_url: c.file.object_url, share_id: "", scope: "existingAccess", link_description: line }) })
                return
            }
            ca.update(key, { linking: true, wantLine: line, link: { scope: scope, edit: edit, expiration: expiration, password: password } })
            backend.driveAction(ca.tag + encodeURIComponent(key) + ":attach_link", "{}", JSON.stringify({ site: c.file.site_url, list: c.file.list_id, item: c.file.unique_id,
                scope: scope, edit: edit, expiration: expiration, password: password, chat_id: ca.chatId }))
        }
    }
    function linkDialogForTest() { return linkDialog }
    /// Tests: the picked files.
    function stateForTest() {
        return pending.map(c => ({ name: c.name, loading: !!c.loading, linking: !!c.linking, link: c.file ? c.file.link_description : "", thumb: !!c.thumbnail,
                                   share: c.file ? c.file.share_url || "" : "", scope: c.file ? c.file.scope : "" }))
    }
}
