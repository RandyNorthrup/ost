import QtQuick
import QtQuick.Controls
import QtMultimedia

// Teams for personal use's Communities app while Communities is being
// retired (ECS communities.enableCommunitiesDeprecationBanner and
// disableCommunitiesCreation; measured on Teams desktop 26304 and
// teams.live.com, 2026-11-27/28, OST Personal 1 and 2, who have no
// communities): the retirement banner across the top ("Communities is
// retiring soon. Use a group chat to stay connected." with Learn more,
// Start chat and Dismiss); "Build your community" (24/32 bold) with its
// text, "Create your own" and "Create with a template" (School, Business,
// Life) at the left; Teams' looping animation at the right. Creating a
// community is no longer possible: Create your own and the templates open
// Teams' "Create a group chat" dialog (Learn more, Create), whose Create
// starts a new group chat, as Start chat does.
Rectangle {
    id: root
    color: theme.pick("#F5F2FA", "#1F1F1F", "#000000")
    signal startGroupChat()
    signal learnMore()
    readonly property string cdn: "https://tflteams.public.onecdn.static.microsoft/evergreen-assets/"
    property bool bannerShown: true
    function stateForTest() { return { banner: bannerShown, dialog: createDialog.opened } }
    function openCreateForTest() { createDialog.open() }

    // ---- the retirement banner (Teams' info MessageBar, 36 tall) ----
    Rectangle {
        id: banner
        visible: root.bannerShown
        width: parent.width; height: visible ? 36 : 0
        color: theme.pick("#FFFFFF", "#292929", "#000000")
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
        FluentIcon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "info-16"; size: 16; color: theme.textSecondary }
        Row {
            x: 40; anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text { text: qsTr("Communities is retiring soon. Use a group chat to stay connected."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text {
                text: qsTr("Learn more")
                font.family: theme.font; font.pixelSize: 14; font.underline: true
                color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.learnMore() }
                Accessible.role: Accessible.Link
                Accessible.name: qsTr("Learn more about Communities retirement")
            }
        }
        Rectangle {
            id: startChat
            anchors.right: dismiss.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            width: startText.implicitWidth + 16; height: 24; radius: 4
            color: sch.hovered ? theme.rowHover : theme.surface
            border.color: theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 1
            Text { id: startText; anchors.centerIn: parent; text: qsTr("Start chat"); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(startChat, theme.text) }
            HoverHandler { id: sch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.startGroupChat() }
            Accessible.role: Accessible.Button
            Accessible.name: startText.text
        }
        Rectangle {
            id: dismiss
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 4
            color: dh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(dismiss, theme.text) }
            HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.bannerShown = false }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Dismiss")
        }
    }

    Item {
        anchors { top: banner.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        // The animation, right of the text, as tall as Teams' (900 x 652
        // at 1500 wide).
        MediaPlayer {
            id: player
            source: root.cdn + "communities/communities-empty-state-animation-new.webm"
            loops: MediaPlayer.Infinite
            videoOutput: video
            Component.onCompleted: if (root.visible) play()
        }
        Connections { target: root; function onVisibleChanged() { if (root.visible) player.play(); else player.pause() } }
        VideoOutput {
            id: video
            readonly property real w: Math.min(900, parent.width - 420)
            visible: w > 240
            width: w; height: w * 652 / 900
            x: Math.max(420, parent.width - w - 24)
            anchors.verticalCenter: parent.verticalCenter
            fillMode: VideoOutput.PreserveAspectFit
            // The animation's transparent parts decode as black: keyed out
            // again (shaders/black_key.frag).
            layer.enabled: true
            layer.effect: ShaderEffect { fragmentShader: "../shaders/black_key.frag.qsb" }
        }
        Column {
            x: 40
            anchors.verticalCenter: parent.verticalCenter
            width: 300
            Text { width: parent.width; text: qsTr("Build your community"); wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 24; font.bold: true; lineHeight: 32; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
            Item { width: 1; height: 10 }
            Text { width: parent.width; text: qsTr("Bring your community together in one place to plan events, stay organized, and get more done."); wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 16; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 24 }
            Rectangle {
                id: createOwn
                width: createText.implicitWidth + 34; height: 40; radius: 4
                color: coh.hovered ? theme.brandHover : theme.brandFill
                Text { id: createText; anchors.centerIn: parent; text: qsTr("Create your own"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(createOwn, "#FFFFFF") }
                HoverHandler { id: coh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: createDialog.open() }
                Accessible.role: Accessible.Button
                Accessible.name: createText.text
            }
            Item { width: 1; height: 48 }
            Text { text: qsTr("Create with a template"); font.family: theme.font; font.pixelSize: 20; font.bold: true; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 16 }
            Row {
                spacing: 8
                Repeater {
                    model: [{ key: "school", label: qsTr("School"), icon: "hat-graduation-20" },
                            { key: "business", label: qsTr("Business"), icon: "briefcase-20" },
                            { key: "life", label: qsTr("Life"), icon: "trophy-20" }]
                    Rectangle {
                        id: tpl
                        required property var modelData
                        required property int index
                        width: tplRow.implicitWidth + 26; height: 32; radius: 16
                        color: th.hovered ? theme.rowHover : theme.surface
                        border.color: theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 1
                        Row {
                            id: tplRow
                            anchors.centerIn: parent
                            spacing: 8
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: tpl.modelData.icon; size: 20; color: theme.onFill(tpl, theme.text) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: tpl.modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(tpl, theme.text) }
                        }
                        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: createDialog.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("template item %1 of 3 - %2").arg(index + 1).arg(modelData.label)
                    }
                }
            }
        }
    }

    // Teams' "Create a group chat" (600 x 422): its picture (192), title
    // (20/28 semibold), text, Learn more and Create; Close at the top end.
    Popup {
        id: createDialog
        parent: Overlay.overlay
        modal: true; focus: true
        anchors.centerIn: Overlay.overlay
        width: 600; height: 422; padding: 0
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        Rectangle {
            id: closeBtn
            x: parent.width - 24 - 32; y: 16; width: 32; height: 32; radius: 4
            color: clh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeBtn, theme.text) }
            HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: createDialog.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Column {
            x: 24; y: 48; width: parent.width - 48
            Image { anchors.horizontalCenter: parent.horizontalCenter; width: 160; height: 160; sourceSize: Qt.size(192, 192); source: root.cdn + "illustrations/webp/192/chat-people-l-standard-192x192.webp"; asynchronous: true }
            Item { width: 1; height: 24 }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Create a group chat"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 8 }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: qsTr("Communities is retiring soon. Create a group chat to connect, share and collaborate."); font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 24 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                DialogButton { label: qsTr("Learn more"); onPicked: root.learnMore() }
                DialogButton { label: qsTr("Create"); primary: true; onPicked: { createDialog.close(); root.startGroupChat() } }
            }
        }
    }

    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        signal picked()
        width: Math.max(96, dbText.implicitWidth + 24); height: 32; radius: 4
        color: primary ? (dbh.hovered ? theme.brandHover : theme.brandFill) : dbh.hovered ? theme.rowHover : theme.surface
        border.color: primary ? "transparent" : theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 1
        Text { id: dbText; anchors.centerIn: parent; text: db.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(db, db.primary ? "#FFFFFF" : theme.text) }
        HoverHandler { id: dbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: db.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
