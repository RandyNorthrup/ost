import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtMultimedia

// Teams' own notification banners ("custom notifications", its
// notifications-app; measured on winpc 2026-11-15 at Teams' 1x):
//
// - One window, 372 wide, flush with the screen's right (or left) edge and
//   90 px from the bottom (or top) of the work area, in the corner
//   Settings ▸ Notifications ▸ Position on the screen picks. It holds up to
//   three 360-wide cards, 8 apart, 2 in from the window's edge on the
//   screen side and 10 from it on the far side ("BR": the list's right
//   margin 8 plus its 2 padding).
// - Cards are #444791 (colorBrandForegroundOnLightSelected) with white
//   text, radius 8. Comfy cards (Settings ▸ Size) carry a 44 px header (the
//   app's 18 px logo and name in 12 px; More options, React and Dismiss)
//   over the sender's 48 px picture, the title (14/600) and two lines of
//   text; chat messages add a "Send a quick reply" box: 124 tall, 164 with
//   it. Compact cards drop the header: 76 tall, the buttons small on the
//   title's line, a Reply button on hover. A meeting that started is
//   Teams' MSN card: 260 (compact 130) with Join and Message.
// - The queue (Teams' NotificationStateContainer): calls, then meetings,
//   then messages, oldest first; three on screen, the oldest nearest the
//   corner. A card leaves after Settings' "Dismiss notifications after"
//   (meetings 20 s), waiting ones after 30 s. Hovering or focusing a card
//   holds it; leaving resumes its time. Hovering in the first 250 ms (the
//   pointer was there when it appeared) holds it only 2 s.
Window {
    id: root
    title: "OST notifications"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    width: 372
    height: Math.max(1, stack.height + 4)
    visible: false

    /// "BR", "TR", "BL" or "TL" (Settings ▸ Notifications ▸ Position).
    property string corner: "BR"
    /// Settings ▸ Notifications ▸ Size: Compact.
    property bool compact: false
    readonly property bool leftSide: corner.endsWith("L")
    readonly property color fill: "#444791"
    /// The app's icon and name in the header (Teams' own there).
    readonly property string appName: "OST"

    signal openChat(string chatId, string chatName)
    signal joinMeeting(string chatId, string chatName)
    signal openSettings()
    /// The incoming call's buttons (kind "call").
    signal acceptCall(bool video)
    signal declineCall()
    signal ignoreCall()

    // Toasts by id; ids by priority, oldest first; the ids on screen in
    // Teams' order (held ones first).
    property var toasts: ({})
    property var order: ({ call: [], high: [], normal: [] })
    property var active: []
    property int rev: 0
    ListModel { id: shown }

    function priority(t) { return t.kind === "call" ? "call" : t.kind === "msn" ? "high" : "normal" }
    function cardHeight(t) {
        if (!t) return 0
        if (t.kind === "call") return 240
        if (t.kind === "msn") return root.compact ? 130 : 260
        return root.compact ? 76 : (t.quickReply ? 164 : 124)
    }

    /// Show a banner (Backend::banner_requested's JSON).
    function add(json) {
        const t = typeof json === "string" ? JSON.parse(json) : json
        corner = ["BR", "TR", "BL", "TL"].indexOf(backend.setting("notificationCorner")) >= 0 ? backend.setting("notificationCorner") : "BR"
        compact = backend.setting("notificationSize") === "COMPACT"
        const old = toasts[t.id]
        // An update to a card you're holding is dropped, as in Teams.
        if (old && old.pinned) return
        t.pinned = false
        t.duration = t.kind === "call" ? 0 : Math.max(1, t.seconds || 5) * 1000
        t.expires = t.kind === "call" ? 0 : Date.now() + 30000
        t.remaining = t.duration
        t.mounted = Date.now()
        toasts[t.id] = t
        if (!old) order[priority(t)].push(t.id)
        regenerate(t.id)
        if (!t.silent && t.kind !== "call" && sound.source.toString() !== "") { sound.stop(); sound.play() }
    }
    /// Take a banner away (its action ran, it was closed, or it timed out).
    function dismiss(id) {
        forget(id)
        regenerate("")
    }
    function forget(id) {
        delete toasts[id]
        for (const p of ["call", "high", "normal"]) {
            const i = order[p].indexOf(id)
            if (i >= 0) order[p].splice(i, 1)
        }
    }
    function pin(id) {
        const t = toasts[id]
        if (!t || t.pinned) return
        t.pinned = true
        if (t.expires) { t.remaining = Math.max(0, t.expires - Date.now()); t.expires = 0 }
    }
    function unpin(id) {
        const t = toasts[id]
        if (!t || !t.pinned) return
        t.pinned = false
        if (t.kind !== "call") t.expires = Date.now() + t.remaining
        regenerate("")
    }
    // Teams' generateUpdatedActiveState: the held cards up to the last one
    // held stay; the rest of the three slots go by priority, oldest first.
    // A card pushed off screen is gone; one that comes on starts its time.
    function regenerate(updated) {
        const all = order.call.concat(order.high, order.normal)
        let lastHeld = -1
        for (let i = active.length - 1; i >= 0; i--)
            if (toasts[active[i]] && toasts[active[i]].pinned) { lastHeld = i; break }
        const keep = lastHeld < 0 ? [] : active.slice(0, lastHeld + 1).filter(id => toasts[id])
        const rest = all.filter(id => keep.indexOf(id) < 0).slice(0, Math.max(0, 3 - keep.length))
        const next = keep.concat(rest)
        for (const id of active)
            if (next.indexOf(id) < 0 && toasts[id]) forget(id)
        const now = Date.now()
        for (const id of next) {
            const t = toasts[id]
            if ((active.indexOf(id) < 0 || id === updated) && t.kind !== "call") {
                t.expires = now + t.duration; t.remaining = t.duration
            }
        }
        active = next
        // Nearest the corner first: the oldest at the bottom for bottom
        // corners.
        sync(corner.startsWith("B") ? next.slice().reverse() : next)
        rev++
        if (next.length && !visible) reveal()
        else if (!next.length) visible = false
    }
    function sync(ids) {
        for (let i = shown.count - 1; i >= 0; i--)
            if (ids.indexOf(shown.get(i).tid) < 0) shown.remove(i)
        for (let i = 0; i < ids.length; i++) {
            let at = -1
            for (let k = i; k < shown.count; k++) if (shown.get(k).tid === ids[i]) { at = k; break }
            if (at < 0) shown.insert(i, { tid: ids[i] })
            else if (at !== i) shown.move(at, i, 1)
        }
    }
    property bool prepared: false
    function reveal() {
        if (!prepared) { prepared = true; backend.prepareBannerWindow() }
        backend.placeBannerWindow(corner)
        visible = true
        backend.placeBannerWindow(corner)
    }
    onHeightChanged: if (visible) backend.placeBannerWindow(corner)
    onCornerChanged: if (visible) backend.placeBannerWindow(corner)

    Timer {
        interval: 100; repeat: true
        running: { root.rev; return Object.keys(root.toasts).length > 0 }
        onTriggered: {
            const now = Date.now()
            const due = Object.keys(root.toasts).filter(id => {
                const t = root.toasts[id]
                return t && !t.pinned && t.expires && now >= t.expires
            })
            if (due.length) { due.forEach(id => root.forget(id)); root.regenerate("") }
        }
    }

    MediaPlayer {
        id: sound
        source: backend.notificationSound()
        audioOutput: AudioOutput {}
    }

    Column {
        id: stack
        x: root.leftSide ? 10 : 2
        y: 2
        spacing: 8
        bottomPadding: 8
        Repeater {
            model: shown
            delegate: Loader {
                id: slot
                required property string tid
                readonly property var toast: { root.rev; return root.toasts[tid] }
                width: 360
                height: root.cardHeight(toast)
                sourceComponent: !toast ? null : toast.kind === "call" ? callCard : toast.kind === "msn" ? msnCard : standardCard
                onLoaded: item.toast = Qt.binding(() => slot.toast)
            }
        }
    }

    // ── shared parts ───────────────────────────────────────────────────

    // A card: hovering or focusing it holds it; a click opens it.
    component Card: Rectangle {
        id: card
        property var toast
        property bool held: hover.hovered || activeFocus
        signal activated()
        width: 360; height: root.cardHeight(toast)
        radius: 8
        color: root.fill
        clip: true
        onHeldChanged: {
            if (!toast) return
            if (held) {
                root.pin(toast.id)
                // The pointer was already there when it appeared: hold it
                // only briefly (Teams' 250 ms / 2 s rule).
                if (Date.now() - toast.mounted < 250) briefHold.restart()
            } else {
                briefHold.stop()
                root.unpin(toast.id)
            }
        }
        Timer { id: briefHold; interval: 2000; onTriggered: if (card.toast) root.unpin(card.toast.id) }
        HoverHandler { id: hover }
        MouseArea {
            anchors.fill: parent; z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: card.activated()
        }
        Keys.onEscapePressed: if (toast) root.dismiss(toast.id)
        Keys.onReturnPressed: card.activated()
        Accessible.role: Accessible.Grouping
        Accessible.name: toast ? [toast.title, toast.subtitle, toast.text].filter(s => s).join(", ") : ""
    }

    // Teams' header (44 px; 42 compact): the app's icon and name, the
    // urgent badge, then the buttons.
    component Header: Item {
        id: hd
        property bool urgent
        default property alias buttons: buttonRow.data
        width: 360; height: 44
        Image {
            x: 16; y: 13; width: 18; height: 18
            source: "../assets/logo.png"; sourceSize: Qt.size(36, 36)
            smooth: true; fillMode: Image.PreserveAspectFit
        }
        Text {
            id: appTitle
            x: 44; y: 12; height: 20
            verticalAlignment: Text.AlignVCenter
            text: root.appName
            font.family: theme.font; font.pixelSize: 12
            color: "white"
        }
        UrgentBadge { visible: hd.urgent; x: appTitle.x + appTitle.implicitWidth + 8; y: 14 }
        Row { id: buttonRow; anchors.right: parent.right; anchors.rightMargin: 8; y: 6.33 }
    }

    // Teams' urgent badge: a red "!" in a 16 px white circle.
    component UrgentBadge: Rectangle {
        width: 16; height: 16; radius: 8
        color: "white"
        FluentIcon { anchors.centerIn: parent; name: "important-20-filled"; size: 12; color: "#D13438" }
    }

    // A transparent header button (Fluent's medium 32 x 31.3, small 24 x
    // 23.3), its icon filled on hover.
    component HeadButton: Item {
        id: hb
        property string icon
        property string label
        property bool small: false
        property bool open: false
        signal clicked()
        width: small ? 24 : 32; height: small ? 23.33 : 31.33
        FluentIcon {
            anchors.centerIn: parent
            name: hb.icon + ((hbHover.hovered || hb.open) ? "-filled" : "")
            size: 16; color: "white"
        }
        HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: hb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: hb.clicked()
    }

    // More options ▸ Go to Notification settings.
    component MoreButton: HeadButton {
        id: mb
        icon: "more-horizontal-20"; label: "More options"
        open: moreMenu.opened
        onClicked: moreMenu.opened ? moreMenu.close() : moreMenu.open()
        Popup {
            id: moreMenu
            // Teams: before the button, level with its top.
            x: -width - 4; y: 0
            padding: 4
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            contentItem: Rectangle {
                implicitWidth: settingsText.implicitWidth + 46; implicitHeight: 32
                radius: 4
                color: settingsHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "settings-20"; size: 20; color: theme.text }
                Text {
                    id: settingsText
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    text: "Go to Notification settings"
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                HoverHandler { id: settingsHover; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: { moreMenu.close(); root.openSettings() } }
                Accessible.role: Accessible.MenuItem
                Accessible.name: settingsText.text
            }
        }
    }

    // React: your quick reactions, opening on hover; one reacts and the
    // card shows it, then leaves.
    component ReactButton: HeadButton {
        id: rb
        property var toast
        signal reacted(string key)
        icon: "emoji-20"; label: "React"
        open: reactMenu.opened
        onClicked: reactMenu.open()
        HoverHandler { onHoveredChanged: if (hovered) reactMenu.open() }
        Popup {
            id: reactMenu
            // Teams: below the button, its end aligned.
            x: rb.width - width; y: rb.height + 2
            padding: 0
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            contentItem: Row {
                leftPadding: 2; rightPadding: 2; height: 32
                Repeater {
                    // With a skin tone set, Like goes in it (Teams' `oa`).
                    model: {
                        let q = ["yes", "heart", "laugh", "surprised"]
                        try { if (backend.quickReactionsJson) q = JSON.parse(backend.quickReactionsJson) } catch (e) {}
                        return q.map(k => k === "yes" && backend.skinTone > 0 ? "yes-tone" + backend.skinTone : k)
                    }
                    delegate: Rectangle {
                        required property var modelData
                        readonly property string key: typeof modelData === "string" ? modelData : (modelData.key || modelData.id || "")
                        width: 32; height: 32; radius: 4
                        color: emoHover.hovered ? theme.menuHover : "transparent"
                        Emoticon { anchors.centerIn: parent; size: 20; key: parent.key }
                        HoverHandler { id: emoHover; cursorShape: Qt.PointingHandCursor }
                        MouseArea { anchors.fill: parent; onClicked: { reactMenu.close(); rb.reacted(parent.key) } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "React with " + parent.key
                    }
                }
            }
        }
    }

    // The sender's picture (48 px); Teams' bell for the test banner.
    component Picture: Item {
        property var toast
        property int size: 48
        width: size; height: size
        Avatar {
            visible: !!toast && toast.kind !== "test"
            size: parent.size
            name: toast ? (toast.senderName || toast.title || "?") : "?"
            photoId: toast ? (toast.senderMri || "") : ""
        }
        Rectangle {
            visible: !!toast && toast.kind === "test"
            anchors.fill: parent; radius: width / 2
            color: "white"
            FluentIcon { anchors.centerIn: parent; name: "alert-20"; size: Math.round(parent.width / 2); color: theme.brandFill }
        }
    }

    // "Send a quick reply" (Fluent's medium input on #383966; Enter sends).
    component QuickReply: Rectangle {
        id: qr
        property var toast
        property alias input: field
        signal sent()
        height: 32; radius: 4
        color: "#383966"
        TextInput {
            id: field
            x: 12; width: parent.width - 12 - 30; height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            font.family: theme.font; font.pixelSize: 14
            color: "white"; selectionColor: "#7579EB"; selectedTextColor: "white"
            onActiveFocusChanged: if (activeFocus) root.requestActivate()
            Keys.onReturnPressed: event => { if (!(event.modifiers & Qt.ShiftModifier)) qr.send() }
            Keys.onEnterPressed: qr.send()
            Text {
                visible: !field.text.length
                anchors.verticalCenter: parent.verticalCenter
                text: "Send a quick reply"
                font: field.font; color: "white"
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Send a quick reply"
        }
        MouseArea {
            anchors.fill: field; cursorShape: Qt.IBeamCursor
            onPressed: mouse => { root.requestActivate(); field.forceActiveFocus(); mouse.accepted = false }
        }
        HeadButton {
            small: true
            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
            icon: "send-20"; label: "Send"
            onClicked: qr.send()
        }
        function send() {
            if (!toast || !field.text.trim().length) return
            backend.bannerReply(toast.chatId, field.text)
            field.text = ""
            qr.sent()
        }
    }

    // ── standard (messages, the test banner) ──────────────────────────

    Component {
        id: standardCard
        Card {
            id: sc
            readonly property bool quick: !!toast && !!toast.quickReply
            property bool replying: false
            property string reaction: ""
            onActivated: {
                if (!toast) return
                if (toast.chatId) root.openChat(toast.chatId, toast.chatName || "")
                root.dismiss(toast.id)
            }
            function react(key) {
                backend.bannerReact(toast.chatId, toast.messageId, key)
                reaction = key
            }

            // Comfy: the header, the picture, title and text, the reply box.
            Header {
                visible: !root.compact
                urgent: !!sc.toast && !!sc.toast.urgent
                MoreButton {}
                ReactButton { visible: sc.quick && !!sc.toast.messageId; toast: sc.toast; onReacted: key => sc.react(key) }
                HeadButton { icon: "dismiss-20"; label: "Dismiss notification"; onClicked: root.dismiss(sc.toast.id) }
            }
            Picture { visible: !root.compact; x: 16; y: 44; toast: sc.toast }
            Column {
                visible: !root.compact
                x: 76; y: 44; width: 268
                spacing: 0
                Text {
                    width: parent.width; height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: sc.toast ? sc.toast.title : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    visible: !!sc.toast && !!sc.toast.subtitle
                    width: parent.width; height: 22; bottomPadding: 2
                    verticalAlignment: Text.AlignVCenter
                    text: sc.toast ? (sc.toast.subtitle || "") : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14
                    color: "white"
                }
                Text {
                    width: parent.width
                    height: sc.toast && sc.toast.subtitle ? 20 : 40
                    text: sc.toast ? (sc.toast.text || "") : ""
                    wrapMode: sc.toast && sc.toast.subtitle ? Text.NoWrap : Text.Wrap
                    maximumLineCount: sc.toast && sc.toast.subtitle ? 1 : 2
                    elide: Text.ElideRight
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14
                    color: "white"
                }
            }
            QuickReply {
                visible: !root.compact && sc.quick
                x: 16; y: 112; width: 328
                toast: sc.toast
                onSent: root.dismiss(sc.toast.id)
            }

            // Compact: the picture, the title with small buttons, one line.
            Picture { visible: root.compact; x: 16; y: 14; toast: sc.toast }
            Item {
                visible: root.compact
                x: 76; y: 10; width: 272; height: 23.33
                UrgentBadge { id: compactUrgent; visible: !!sc.toast && !!sc.toast.urgent; x: 0; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    x: compactUrgent.visible ? 20 : 0
                    width: compactButtons.x - x - 4; height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: sc.toast ? (sc.replying ? (sc.toast.text || "") : sc.toast.title) : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; font.weight: sc.replying ? Font.Normal : Font.DemiBold
                    color: "white"
                }
                Row {
                    id: compactButtons
                    anchors.right: parent.right; height: parent.height
                    MoreButton { small: true }
                    ReactButton { small: true; visible: sc.quick && !!sc.toast.messageId; toast: sc.toast; onReacted: key => sc.react(key) }
                    HeadButton { small: true; icon: "dismiss-20"; label: "Dismiss notification"; onClicked: root.dismiss(sc.toast.id) }
                }
            }
            Item {
                visible: root.compact && !sc.replying
                x: 76; y: 33.33; width: 272; height: 24
                Text {
                    width: (replyButton.visible ? replyButton.x - 8 : parent.width) - 4; height: 24
                    verticalAlignment: Text.AlignVCenter
                    // Compact shows where it was said, else the text.
                    text: sc.toast ? (sc.toast.subtitle || sc.toast.text || "") : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14
                    color: "white"
                }
                // Teams' Reply (small outline button) while the card is held.
                Rectangle {
                    id: replyButton
                    visible: sc.quick && sc.held
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: replyRow.implicitWidth + 16; height: 24; radius: 4
                    color: "transparent"
                    border.width: 1; border.color: replyHover.hovered ? "white" : Qt.rgba(1, 1, 1, 0.2)
                    Row {
                        id: replyRow
                        anchors.centerIn: parent; spacing: 4
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-reply-20"; size: 16; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Reply"; font.family: theme.font; font.pixelSize: 12; color: "white" }
                    }
                    HoverHandler { id: replyHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea { anchors.fill: parent; onClicked: { sc.replying = true; compactReply.input.forceActiveFocus() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Reply"
                }
            }
            QuickReply {
                id: compactReply
                visible: root.compact && sc.replying
                x: 76; y: 35.33; width: 268
                toast: sc.toast
                onSent: root.dismiss(sc.toast.id)
            }

            // Your reaction, shown on the card before it leaves (Teams'
            // 2 s overlay).
            Rectangle {
                id: overlay
                visible: sc.reaction !== ""
                anchors.fill: parent; radius: 8
                color: Qt.rgba(0, 0, 0, 0.4)
                opacity: 0
                Emoticon { id: bigEmoji; anchors.centerIn: parent; size: 60; key: sc.reaction }
                SequentialAnimation {
                    running: overlay.visible
                    PauseAnimation { duration: 314 }
                    ParallelAnimation {
                        NumberAnimation { target: overlay; property: "opacity"; to: 1; duration: 314 }
                        NumberAnimation { target: bigEmoji; property: "size"; to: 80; duration: 314 }
                    }
                    PauseAnimation { duration: 1000 }
                    NumberAnimation { target: bigEmoji; property: "size"; to: 60; duration: 372 }
                    ScriptAction { script: root.dismiss(sc.toast.id) }
                }
            }
        }
    }

    // ── a meeting started (Teams' MSN card) ───────────────────────────

    Component {
        id: msnCard
        Card {
            id: mc
            onActivated: {
                if (!toast) return
                root.openChat(toast.chatId, toast.chatName || "")
                root.dismiss(toast.id)
            }
            function act(id) {
                const t = toast
                root.dismiss(t.id)
                if (id === "join") root.joinMeeting(t.chatId, t.chatName || "")
                else root.openChat(t.chatId, t.chatName || "")
            }
            Header {
                visible: !root.compact
                MoreButton {}
                HeadButton { icon: "dismiss-20"; label: "Dismiss notification"; onClicked: root.dismiss(mc.toast.id) }
            }
            // Comfy: centred picture (80), title, two lines, the actions.
            Picture { visible: !root.compact; x: 140; y: 46; size: 80; toast: mc.toast }
            Text {
                visible: !root.compact
                x: 16; y: 138; width: 328; height: 20
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: mc.toast ? mc.toast.title : ""
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: "white"
            }
            Text {
                visible: !root.compact
                x: 16; y: 158; width: 328; height: 40
                horizontalAlignment: Text.AlignHCenter
                text: mc.toast ? (mc.toast.text || "") : ""
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14
                color: "white"
            }
            Actions { visible: !root.compact; x: 16; y: 210; width: 328; toast: mc.toast; onPicked: id => mc.act(id) }

            // Compact: the picture, title and small buttons, text, actions.
            Picture { visible: root.compact; x: 16; y: 14; toast: mc.toast }
            Item {
                visible: root.compact
                x: 72; y: 12; width: 276; height: 23.33
                Text {
                    width: msnButtons.x - 4; height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: mc.toast ? mc.toast.title : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: "white"
                }
                Row {
                    id: msnButtons
                    anchors.right: parent.right; height: parent.height
                    MoreButton { small: true }
                    HeadButton { small: true; icon: "dismiss-20"; label: "Dismiss notification"; onClicked: root.dismiss(mc.toast.id) }
                }
            }
            Text {
                visible: root.compact
                x: 72; y: 37.33; width: 276
                text: mc.toast ? (mc.toast.text || "") : ""
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14
                color: "white"
            }
            Actions { visible: root.compact; x: 16; y: 86; width: 332; toast: mc.toast; onPicked: id => mc.act(id) }
        }
    }

    // The MSN card's buttons: the first white, the rest outlined.
    component Actions: Row {
        id: acts
        property var toast
        signal picked(string id)
        spacing: 8
        readonly property var list: toast && toast.actions ? toast.actions : []
        Repeater {
            model: acts.list
            delegate: Rectangle {
                id: ab
                required property var modelData
                required property int index
                readonly property bool primary: index === 0
                width: (acts.width - acts.spacing * (acts.list.length - 1)) / Math.max(1, acts.list.length)
                height: 32; radius: 4
                color: primary ? (abMouse.pressed ? "#C5CBFA" : abHover.hovered ? "#E8EBFA" : "white")
                               : (abMouse.pressed ? Qt.rgba(0, 0, 0, 0.3) : abHover.hovered ? Qt.rgba(0, 0, 0, 0.1) : "transparent")
                border.width: 1; border.color: "white"
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: ab.modelData.id === "join" ? "video-20" : "chat-20"
                        size: 20; color: ab.primary ? "#242424" : "white"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ab.modelData.label
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: ab.primary ? "#242424" : "white"
                    }
                }
                HoverHandler { id: abHover; cursorShape: Qt.PointingHandCursor }
                MouseArea { id: abMouse; anchors.fill: parent; onClicked: acts.picked(ab.modelData.id) }
                Accessible.role: Accessible.Button
                Accessible.name: ab.modelData.label
            }
        }
    }

    // ── an incoming call ──────────────────────────────────────────────

    Component {
        id: callCard
        Card {
            id: cc
            IncomingCall {
                anchors.fill: parent
                peer: cc.toast ? (cc.toast.title || "") : ""
                videoOffered: !!cc.toast && !!cc.toast.video
                onAcceptVideo: root.acceptCall(true)
                onAcceptAudio: root.acceptCall(false)
                onDecline: root.declineCall()
                onIgnore: { root.dismiss(cc.toast.id); root.ignoreCall() }
            }
        }
    }
    /// The call card on screen (for the call harness's picture), or null.
    function callCardItem() {
        for (let i = 0; i < stack.children.length; i++) {
            const c = stack.children[i]
            if (c.toast && c.toast.kind === "call" && c.item) return c.item
        }
        return null
    }
}
