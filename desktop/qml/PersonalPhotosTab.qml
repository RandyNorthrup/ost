import QtQuick
import QtQuick.Controls.Basic

// A personal account's chat Photos tab, as Teams free draws it (measured
// on teams.live.com as OST Personal 1, 2026-11-28): the chat's pictures
// from Teams' message search (inline pictures and picture files, 5 at a
// time as the tab scrolls), newest first under day headings ("Today",
// 14/20 semibold, 12 in and 30 down), as 240 x 200 tiles cut to fill
// (the media store's small thumbnails). A tile opens the picture viewer
// (zoom, download, Show message). Empty: Teams' photos illustration
// (256), "No photos shared in the chat" (16/22 semibold) and "Photos
// added to chat automatically show up here." (14/20).
Item {
    id: root
    property string chatId: ""
    property var dayLabel: t => t
    signal openImage(var list, int index, var message)

    property var photos: []
    property bool more: true
    property bool loading: false
    property bool loaded: false
    /// Cached thumbnails and full pictures: url -> file URL.
    property var thumbs: ({})
    property var fulls: ({})
    property string wantFull: ""
    readonly property string tag: "pphotos-" + Math.floor(Math.random() * 1e9) + ":"
    function loadMore() {
        if (!chatId || loading || !more) return
        loading = true
        backend.driveAction(tag + "personal_photos", "{}", JSON.stringify({ chat: chatId, base: pageBase }))
    }
    // Where the next page starts (the search counts messages).
    property int pageBase: 0
    // A picture sent while the tab is open: the newest page again (4 s
    // later, for the search index), its new pictures put first.
    property int messageCount: 0
    onMessageCountChanged: if (loaded) refreshSoon.restart()
    Timer {
        id: refreshSoon; interval: 4000
        onTriggered: { root.incoming = []; root.askNew(0) }
    }
    // The new pictures found so far, page by page, until a page reaches
    // pictures already shown.
    property var incoming: []
    function askNew(base) { backend.driveAction(root.tag + "personal_photos_new", "{}", JSON.stringify({ chat: root.chatId, base: base })) }
    function reset() { photos = []; more = true; loaded = false; pageBase = 0; thumbs = ({}); loadMore() }
    onChatIdChanged: reset()
    Component.onCompleted: loadMore()
    function askThumbs(list) {
        for (const p of list) backend.driveAction(tag + "personal_thumb", "{}", JSON.stringify({ url: p.preview_url, thumb: "1" }))
    }
    function open(p) {
        if (fulls[p.preview_url]) { show(p); return }
        wantFull = p.preview_url
        backend.driveAction(tag + "personal_thumb", "{}", JSON.stringify({ url: p.preview_url, thumb: "0" }))
    }
    // The viewer steps through the pictures of the clicked one's message
    // (its sender, time and Show message are that message's).
    function show(p) {
        const same = photos.filter(x => x.message_id === p.message_id && !!fulls[x.preview_url])
        const list = same.map(x => ({ local_path: fulls[x.preview_url], width: x.width, height: x.height }))
        root.openImage(list, Math.max(0, same.indexOf(p)), { sender: p.sender, time: p.time, id: p.message_id })
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(root.tag)) return
            const kind = op.slice(root.tag.length)
            if (kind === "personal_photos") {
                root.loading = false
                root.loaded = true
                if (error) { console.warn("personal photos:", error); root.more = false; return }
                const v = JSON.parse(result)
                if (v.chat !== root.chatId) return
                const seen = {}
                for (const p of root.photos) seen[p.preview_url] = true
                const fresh = (v.photos || []).filter(p => !seen[p.preview_url])
                root.photos = root.photos.concat(fresh)
                root.askThumbs(fresh)
                root.pageBase = v.base + 5
                root.more = !!v.more
                // Fill the view before waiting for a scroll.
                if (root.more && grid.contentHeight < grid.height) root.loadMore()
            } else if (kind === "personal_photos_new") {
                if (error || !result) return
                const v = JSON.parse(result)
                if (v.chat !== root.chatId) return
                const seen = {}
                for (const p of root.photos.concat(root.incoming)) seen[p.preview_url] = true
                const page = v.photos || []
                const fresh = page.filter(p => !seen[p.preview_url])
                root.incoming = root.incoming.concat(fresh)
                // A whole page of new ones: there may be more before the
                // pictures shown; ask for the next page first.
                if (fresh.length && fresh.length === page.length && v.more) { root.askNew(v.base + 5); return }
                const got = root.incoming
                root.incoming = []
                if (!got.length) return
                root.photos = got.concat(root.photos)
                // (The older pages moved down by as many messages.)
                root.pageBase += new Set(got.map(p => p.message_id)).size
                root.askThumbs(got)
            } else if (kind === "personal_thumb") {
                if (error || !result) return
                const v = JSON.parse(result)
                if (v.thumb) { const m = Object.assign({}, root.thumbs); m[v.url] = v.path; root.thumbs = m }
                else {
                    const m = Object.assign({}, root.fulls); m[v.url] = v.path; root.fulls = m
                    if (root.wantFull === v.url) { root.wantFull = ""; const p = root.photos.find(x => x.preview_url === v.url); if (p) root.show(p) }
                }
            }
        }
    }
    function stateForTest() { return { loaded: loaded, more: more, photos: photos.map(p => ({ name: p.name, day: root.dayLabel(p.time), thumb: !!thumbs[p.preview_url] })) } }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Day groups: [{ day, items }].
    readonly property var groups: {
        const out = []
        for (const p of photos) {
            const d = root.dayLabel(p.time)
            if (!out.length || out[out.length - 1].day !== d) out.push({ day: d, items: [] })
            out[out.length - 1].items.push(p)
        }
        return out
    }
    Flickable {
        id: grid
        anchors.fill: parent
        contentHeight: groupsCol.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: if (contentY + height > contentHeight - 200) root.loadMore()
        Column {
            id: groupsCol
            x: 9; y: 18; width: parent.width - 18
            spacing: 16
            Repeater {
                model: root.groups
                Column {
                    id: group
                    required property var modelData
                    width: groupsCol.width
                    spacing: 12
                    Text { x: 3; text: group.modelData.day; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Flow {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: group.modelData.items
                            Rectangle {
                                id: tile
                                required property var modelData
                                width: 240; height: 200
                                color: theme.pick("#F0F0F0", "#292929", "#000000")
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: root.thumbs[tile.modelData.preview_url] || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.open(tile.modelData) }
                                Accessible.role: Accessible.Button
                                Accessible.name: tile.modelData.name || qsTr("Image")
                            }
                        }
                    }
                }
            }
        }
    }
    Column {
        visible: root.loaded && root.photos.length === 0 && !root.loading
        anchors.centerIn: parent
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 256; height: 256
            source: "https://tflteams.public.onecdn.static.microsoft/evergreen-assets/illustrations/v2/photos-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard.svg"
            sourceSize: Qt.size(256, 256)
            asynchronous: true
        }
        Item { width: 1; height: 12 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("No photos shared in the chat"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Item { width: 1; height: 8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Photos added to chat automatically show up here."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
    }
    BusyIndicator { anchors.centerIn: parent; running: root.loading && !root.loaded; visible: running }
}
