import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtCore

// Teams' Add emoji flow (791494, 416188; dialog measured on winpc):
// 1. A file chooser for .png, .jpeg and .gif.
// 2. Anything but a GIF is drawn into a 400 x 400 PNG, scaled by
//    min(398/w, 398/h) and centred.
// 3. "Name your emoji" (custom-emoji-upload-dialog, 600 x 633.3, padding
//    24): the info bar (#F5F5F5, 536.7 x 69.3), "Name" with a red "*", the
//    name field (536.7 x 40, #F5F5F5, 16 px), "Preview" with Teams' mock chat
//    (Clippy at 10:23 AM, a reaction of 3, your reply at 10:25 AM), and
//    Cancel / Add emoji (96 x 31.3).
// The name comes from the file name and must be lowercase letters, digits,
// "-" or "_" (up to 50), and not an emoji name already in use.
Item {
    id: root
    function start() { chooser.open() }
    // Test hooks: skip the chooser; press Add emoji.
    function startWith(path) { prepare(path) }
    function addForTest() { if (addButton.can) addButton.add(); return addButton.can }
    readonly property string nameForTest: nameField.text

    property string picture: ""
    property string sourceName: ""

    FileDialog {
        id: chooser
        title: "Add emoji"
        nameFilters: ["Images (*.png *.jpeg *.gif)"]
        onAccepted: root.prepare(String(selectedFile))
    }

    function prepare(url) {
        const path = url.replace(/^file:\/\//, "")
        sourceName = decodeURIComponent(path.split("/").pop())
        if (/\.gif$/i.test(path)) { picture = "file://" + path; openDialog(); return }
        resizer.source = "file://" + path
    }
    // Teams' resize: a 400 x 400 canvas, the picture scaled to fit 398.
    Item {
        id: canvas
        visible: false
        width: 400; height: 400
        Image {
            id: resizer
            readonly property real s: implicitWidth > 0 ? Math.min(398 / implicitWidth, 398 / implicitHeight) : 1
            width: implicitWidth * s; height: implicitHeight * s
            anchors.centerIn: parent
            smooth: true; mipmap: true
            onStatusChanged: if (status === Image.Ready) {
                canvas.visible = true
                const dir = String(StandardPaths.writableLocation(StandardPaths.CacheLocation)).replace(/^file:\/\//, "")
                const out = dir + "/custom-emoji-" + Date.now() + ".png"
                canvas.grabToImage(r => {
                    canvas.visible = false
                    if (r.saveToFile(out)) { root.picture = "file://" + out; root.openDialog() }
                }, Qt.size(400, 400))
            }
        }
    }

    function openDialog() {
        const base = sourceName.replace(/\.[^.]*$/, "").toLowerCase().replace(/[\W_]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "")
        nameField.text = /^[a-z0-9-_]{1,50}$/.test(base) ? base : ""
        backend.customEmojiResult = ""
        dialog.open()
        nameField.forceActiveFocus()
    }

    readonly property string name: nameField.text.trim()
    readonly property bool badName: name.length > 0 && !/^[a-z0-9-_]{1,50}$/.test(name)
    readonly property bool taken: {
        if (name.length === 0 || badName) return false
        if (["star", "follow", "acks"].indexOf(name) >= 0) return true
        const custom = backend.customEmojiJson ? JSON.parse(backend.customEmojiJson) : []
        if (custom.some(e => e.shortcut === name)) return true
        const cat = backend.emoticonCatalogJson()
        const list = cat ? JSON.parse(cat) : []
        return list.some(c => c.emoticons.some(e => (e.shortcuts || []).indexOf("(" + name + ")") >= 0 || e.id === name))
    }
    readonly property string error: badName ? "Names must be lowercase and can’t contain special characters or spaces."
        : (taken || backend.customEmojiResult === "duplicate") ? "An emoji with that name already exists. Try another name."
        : backend.customEmojiResult === "error" ? "Something went wrong. Please try again." : ""
    readonly property bool adding: backend.customEmojiResult === "adding"

    Connections {
        target: backend
        function onCustomEmojiResultChanged() {
            const r = backend.customEmojiResult
            if (r === "ok") dialog.close()
            else if (r.indexOf("limit:") === 0) { limitDialog.limit = r.slice(6); limitDialog.open() }
        }
    }

    Popup {
        id: dialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 600; height: 633.3; padding: 0
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
        Overlay.modal: Rectangle { color: "#66000000" }

        Text {
            x: 24.7; y: 24.7; height: 28; verticalAlignment: Text.AlignVCenter
            text: "Name your emoji"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Rectangle {
            x: 24.7; y: 60.7; width: 536.7; height: 69.3; radius: 4
            color: theme.pick("#F5F5F5", "#292929")
            FluentIcon { x: 12.6; y: 10.6; name: "info-20"; size: 20; color: theme.textStrong }
            Text {
                x: 40.6; y: 10.6; width: 495.3
                wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight
                text: "Emoji you add will be available to everyone in your org. Your identity is linked to your emoji and visible to everyone."
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
        }
        Row {
            x: 24.7; y: 156.7
            Text { y: 2.6; height: 16; text: "Name"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
            Text { leftPadding: 2; text: "*"; font.family: theme.font; font.pixelSize: 14; color: "#D13438" }
        }
        Rectangle {
            x: 24.7; y: 180; width: 536.7; height: 40; radius: 4
            color: theme.pick("#F5F5F5", "#292929")
            TextInput {
                id: nameField
                x: 18; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 16; color: theme.text
                maximumLength: 60; clip: true; selectByMouse: true
                onTextChanged: if (backend.customEmojiResult === "duplicate" || backend.customEmojiResult === "error") backend.customEmojiResult = ""
                Keys.onReturnPressed: if (addButton.can) addButton.add()
                Text { visible: !nameField.text; text: "(Enter a name for your emoji)"; font: nameField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Name"
            }
            Rectangle {
                visible: nameField.activeFocus || root.error.length > 0
                anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
                color: root.error.length > 0 ? "#C50F1F" : theme.brand
            }
        }
        Text {
            visible: root.error.length > 0
            x: 24.7; y: 224; width: 536.7; wrapMode: Text.Wrap
            text: root.error
            font.family: theme.font; font.pixelSize: 12; color: "#C50F1F"
            Accessible.role: Accessible.AlertMessage
        }
        Text { x: 24.7; y: 273.3; height: 16; text: "Preview"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        // Teams' mock chat with the new emoji.
        Item {
            x: 24.7; y: 292; width: 536.7; height: 185
            Accessible.role: Accessible.Grouping
            Accessible.name: "Emoji preview"
            Rectangle {
                x: 32; y: 42; width: 28; height: 28; radius: 14
                color: theme.pick("#E6E6E6", "#3D3D3D")
                Image { anchors.fill: parent; source: "https://teams.public.onecdn.static.microsoft/evergreen-assets/personal-expressions/v2/assets/emoticons/1f4ce_paperclip/default/50_f.png"; fillMode: Image.PreserveAspectFit; asynchronous: true }
                Rectangle { x: 18; y: 18; width: 10; height: 10; radius: 5; color: "#6BB700"; border.color: theme.surface; border.width: 1.5 }
            }
            Text { x: 72; y: 22; height: 16; text: "Clippy"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Text { x: 113.1; y: 22; height: 16; text: "10:23 AM"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Rectangle {
                x: 72; y: 40; width: msg1.implicitWidth + 24 + 4 + 20; height: 36; radius: 6
                color: theme.pick("#F5F5F5", "#292929")
                Text { id: msg1; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Great choice on the new emoji."; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                Image { x: msg1.x + msg1.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; source: root.picture; fillMode: Image.PreserveAspectFit }
            }
            Rectangle {
                x: 87.6; y: 71.3; width: 41; height: 26; radius: 13
                color: theme.surface; border.color: theme.stroke
                Image { x: 7.3; y: 4; width: 18; height: 18; source: root.picture; fillMode: Image.PreserveAspectFit }
                Text { x: 28.3; anchors.verticalCenter: parent.verticalCenter; text: "3"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
            }
            Text { x: 428.4; y: 109; height: 16; text: "10:25 AM"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 58.6
                y: 127; width: msg2.implicitWidth + 24 + 4 + 20; height: 36; radius: 6
                color: theme.pick("#E8EBFA", "#2F2F4A")
                Text { id: msg2; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Thanks! I thought you’d like it."; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                Image { x: msg2.x + msg2.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; source: root.picture; fillMode: Image.PreserveAspectFit }
            }
        }
        Rectangle {
            x: 375.3; y: 577.3; width: 96; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dialog.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            id: addButton
            readonly property bool can: root.name.length > 0 && !root.badName && !root.taken && !root.adding && root.picture.length > 0
            function add() { backend.addCustomEmoji(root.name, root.picture) }
            x: 479.3; y: 577.3; width: 96; height: 31.3; radius: 4
            color: !can && !root.adding ? theme.bgDisabled : addHover.hovered ? theme.brandHover : theme.brandFill
            Text { visible: !root.adding; anchors.centerIn: parent; text: "Add emoji"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: addButton.can ? "white" : theme.disabledStrong }
            BusyIndicator { visible: root.adding; running: root.adding; anchors.centerIn: parent; width: 16; height: 16 }
            HoverHandler { id: addHover; cursorShape: addButton.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: addButton.can; onTapped: addButton.add() }
            Accessible.role: Accessible.Button
            Accessible.name: "Add emoji"
        }
    }

    // "Your org has hit the {limit} emoji limit." with OK.
    Popup {
        id: limitDialog
        property string limit: ""
        parent: Overlay.overlay
        modal: true; focus: true
        width: 440; padding: 24
        anchors.centerIn: parent
        background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
        contentItem: Column {
            spacing: 24
            Text { width: 392; wrapMode: Text.Wrap; text: "Your org has hit the " + limitDialog.limit + " emoji limit."; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Rectangle {
                anchors.right: parent.right; width: 96; height: 31.3; radius: 4
                color: okHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "OK"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: "white" }
                HoverHandler { id: okHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { limitDialog.close(); dialog.close() } }
                Accessible.role: Accessible.Button
                Accessible.name: "OK"
            }
        }
    }
}
