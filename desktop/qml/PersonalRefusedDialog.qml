import QtQuick
import QtQuick.Controls

// Teams desktop's answer to a second personal account (measured on
// testpc2, Teams 26304, 2026-11-27): after the account has signed in, a
// 600 x 600 white dialog over the window: the account's 120 px grey
// picture with its initials, its name (18) and address (14), then
// "Multiple personal accounts aren't supported in Teams yet." (20/600),
// "To use another personal account, open Teams on the web." (14), a
// 296 x 40 brand "Open Teams on the web" and Cancel under it. Either
// answer drops the sign-in; Teams adds no account.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 600
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    /// The refused account: {name, upn}.
    property var account: ({})
    signal answered(bool openWeb)
    property bool done: false
    onAboutToShow: done = false
    function answer(openWeb) { if (done) return; done = true; root.close(); root.answered(openWeb) }
    onClosed: answer(false)
    // Teams' initials: the first letters of the first and last words.
    function initials(n) {
        const w = (n || "").trim().split(/\s+/).filter(Boolean)
        if (w.length === 0) return ""
        return (w[0][0] + (w.length > 1 ? w[w.length - 1][0] : "")).toUpperCase()
    }

    Rectangle {
        x: (parent.width - width) / 2; y: 123
        width: 120; height: 120; radius: 60
        color: theme.pick("#E0E0E0", "#3D3D3D", "#000000")
        border.color: theme.highContrast ? "#FFFFFF" : "transparent"
        Text {
            anchors.centerIn: parent
            text: root.initials(root.account.name || root.account.upn)
            font.family: theme.font; font.pixelSize: 14
            color: theme.textStrong
        }
        Accessible.ignored: true
    }
    Text {
        y: 254; width: parent.width; horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.account.name || ""
        font.family: theme.font; font.pixelSize: 18; lineHeight: 24; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Text {
        y: 276; width: parent.width; horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        text: root.account.upn || ""
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Text {
        id: title
        y: 352; x: 24; width: parent.width - 48; horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: qsTr("Multiple personal accounts aren't supported in Teams yet.")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Text {
        y: 395; x: 24; width: parent.width - 48; horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: qsTr("To use another personal account, open Teams on the web.")
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Rectangle {
        id: openWeb
        x: (parent.width - width) / 2; y: 439
        width: 296; height: 40; radius: 4
        color: webHover.hovered ? theme.brandHover : theme.brandFill
        activeFocusOnTab: true
        Component.onCompleted: forceActiveFocus()
        Text {
            anchors.centerIn: parent
            text: qsTr("Open Teams on the web")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(openWeb, theme.textOnBrand)
        }
        HoverHandler { id: webHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.answer(true) }
        Keys.onReturnPressed: root.answer(true)
        Keys.onSpacePressed: root.answer(true)
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Open Teams on the web")
        Accessible.onPressAction: root.answer(true)
    }
    Rectangle {
        id: cancel
        x: (parent.width - width) / 2; y: 490
        width: cancelText.implicitWidth + 24; height: 32; radius: 4
        color: cancelHover.hovered ? theme.menuHover : "transparent"
        activeFocusOnTab: true
        Text {
            id: cancelText
            anchors.centerIn: parent
            text: qsTr("Cancel")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(cancel, theme.text)
        }
        HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.answer(false) }
        Keys.onReturnPressed: root.answer(false)
        Keys.onSpacePressed: root.answer(false)
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Cancel")
        Accessible.onPressAction: root.answer(false)
    }
}
