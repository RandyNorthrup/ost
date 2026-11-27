import QtQuick
import QtQuick.Controls

// Teams' "Use phone for audio" dialog (pstn-dialog-manager, measured in
// Teams on the web as ost-test1, 2026-11-16): it opens by itself after
// joining with Phone audio, and from More ▸ Call me (Join info ▸ Call me
// with the new controls).
//
// - Over the call window a rgba(37, 36, 36, 0.75) overlay; the card is 400
//   wide, centred, radius 8, shadow 64, padding 27 32 32.
// - "Use phone for audio" 18/25.7 bold, Close (32 x 32, a 14 px dismiss)
//   24 from the right; the line under it 12/16.
// - Call me (when the meeting allows dial-out): "Enter your number and
//   we'll call you.", the number box (336 x 32, #F5F5F5, radius 4, text
//   12 in, focused at once), "Call me" (primary, 336 x 32, enabled once
//   your dial plan takes the number) 20 below, your favourite numbers,
//   then "Dial in manually" (an underlined transparent button).
// - Dial in: "Dial in with one of the following phone numbers.", the toll
//   number (a tel: link) " (Toll)", "Get local numbers", "Conference ID:
//   975 755 048 #", then "Call me back" when dial-out is allowed.
// - Calling: "We are calling your phone" with the number and "Calling...";
//   connected: "Meeting audio" with the number and Disconnect. A failed
//   call goes back to the box with Teams' message in red.
// - Without phone audio: "Phone audio isn't available" / "Unmute your mic
//   for meeting audio."
Item {
    id: root
    /// call_phone_json, parsed.
    property var phone: ({})
    /// "callMe", "dialIn" or "" (Teams' dialogContentState), chosen on open.
    property string view: ""
    property bool showing: false
    visible: showing
    z: 900

    readonly property string state_: phone.state || ""
    readonly property bool calling: state_ === "connecting"
    readonly property bool connected: state_ === "connected"
    readonly property bool failed: state_ === "failed"
    readonly property var dial: phone.dial || null

    /// Teams' openPstnDialog: Calling / connected first, then Call me when
    /// the meeting allows dial-out, else Dial in, else "not available".
    function open() {
        if (calling || connected) view = ""
        else if (phone.available && phone.dialIn) view = phone.dialOut ? "callMe" : "dialIn"
        else view = "none"
        numberBox.text = ""
        showing = true
        if (view === "callMe") numberBox.forceActiveFocus()
    }
    function close() { showing = false }
    // Teams re-chooses the view when the meeting's PSTN state arrives
    // while the dialog shows (its componentDidUpdate).
    onPhoneChanged: if (showing && view === "none" && phone.available && phone.dialIn) {
        view = phone.dialOut ? "callMe" : "dialIn"
        if (view === "callMe") numberBox.forceActiveFocus()
    }
    // --phone-audio-test: type into the number box, then leave it (Teams
    // formats it then); what Call me would do.
    function typeForTest(t) { numberBox.text = t; numberBox.forceActiveFocus() }
    function blurForTest() { numberBox.focus = false; card.forceActiveFocus() }
    function stateForTest() { return JSON.stringify({ view: view, header: header, subheader: subheader, number: numberBox.text, callMe: JSON.parse(backend.phoneNumberCheck(numberBox.text)).enabled, favorites: favorites.length }) }
    function callMe() {
        const check = JSON.parse(backend.phoneNumberCheck(numberBox.text))
        if (!check.enabled) return
        saveFavorite(check.display)
        backend.callMeBack(numberBox.text)
    }
    // Teams keeps up to ten numbers you had it call (pstn_favorite_numbers).
    readonly property var favorites: {
        const v = backend.setting("phoneFavorites")
        return v ? v.split(",").filter(s => s.length > 0).slice(0, 10) : []
    }
    function saveFavorite(n) {
        const list = favorites
        if (!n || list.indexOf(n) >= 0) return
        backend.setSetting("phoneFavorites", list.concat([n]).join(","))
    }

    readonly property string header: calling ? qsTr("We are calling your phone")
        : connected ? qsTr("Meeting audio")
        : view === "none" ? qsTr("Phone audio isn't available") : qsTr("Use phone for audio")
    readonly property string subheader: calling || connected ? ""
        : view === "none" ? qsTr("Unmute your mic for meeting audio.")
        : view === "dialIn" ? qsTr("Dial in with one of the following phone numbers.")
        : failed ? (phone.error || qsTr("We could not complete the call. The user is unavailable at the moment."))
        : qsTr("Enter your number and we'll call you.")

    // The overlay closes the dialog on a click outside (closeOnOutsideClick).
    Rectangle {
        anchors.fill: parent
        color: theme.pick(Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.75), Qt.rgba(0, 0, 0, 0.5), Qt.rgba(0, 0, 0, 0.75))
        TapHandler { onTapped: root.close() }
    }
    FluentSurface {
        id: card
        width: 400
        height: content.implicitHeight + 27 + 32
        anchors.centerIn: parent
        radius: 8
        color: theme.surface
        depth: 64
        TapHandler {}
        Column {
            id: content
            x: 32; y: 27; width: 336
            Item {
                width: parent.width; height: 25.7
                Text {
                    text: root.header
                    font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
                    lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Rectangle {
                    id: hcFill1
                    x: parent.width + 32 - 24 - 32; y: -3; width: 32; height: 32; radius: 4
                    color: closeHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 14; color: theme.onFill(hcFill1, theme.text) }
                    HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.close() }
                    ToolTip.visible: closeHover.hovered
                    ToolTip.delay: 500
                    ToolTip.text: qsTr("Close")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Close")
                }
            }
            Item { width: 1; height: 10; visible: root.subheader.length > 0 }
            Text {
                visible: root.subheader.length > 0
                width: parent.width
                text: root.subheader
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: root.failed && root.view === "callMe" ? theme.redForeground1 : theme.text
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            // Call me.
            Column {
                visible: root.view === "callMe" && !root.calling && !root.connected
                width: parent.width
                spacing: 0
                Item { width: 1; height: 20 }
                Rectangle {
                    width: parent.width; height: 32; radius: 4
                    color: theme.inputFilled
                    border.width: theme.highContrast ? 1 : 0; border.color: theme.stroke
                    TextInput {
                        id: numberBox
                        x: 12; width: parent.width - 24 - (root.failed ? 24 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                        selectByMouse: true
                        clip: true
                        // Teams formats the number once the box loses focus.
                        onActiveFocusChanged: if (!activeFocus && text.length > 0) text = JSON.parse(backend.phoneNumberCheck(text)).display
                        onAccepted: root.callMe()
                        Keys.onEscapePressed: root.close()
                        Text {
                            visible: !parent.text && !parent.preeditText
                            text: qsTr("Enter phone number")
                            font: parent.font
                            color: theme.textSecondary
                        }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Enter phone number")
                    }
                    FluentIcon {
                        visible: root.failed
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "error-circle-20-filled"; size: 16; color: theme.redForeground1
                    }
                    // Fluent's focused input: a 2 px brand line under it.
                    Rectangle {
                        visible: numberBox.activeFocus
                        anchors.bottom: parent.bottom; width: parent.width; height: 2
                        color: theme.brand
                        bottomLeftRadius: 4; bottomRightRadius: 4
                    }
                }
                Item { width: 1; height: 20 }
                Rectangle {
                    id: callMeButton
                    readonly property bool usable: JSON.parse(backend.phoneNumberCheck(numberBox.text)).enabled
                    width: parent.width; height: 32; radius: 4
                    color: !usable ? theme.bgDisabled : cmHover.hovered ? theme.brandHover : theme.brandFill
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Call me")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: callMeButton.usable ? theme.onFill(callMeButton, theme.textOnBrand) : theme.disabled
                    }
                    HoverHandler { id: cmHover; cursorShape: callMeButton.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: callMeButton.usable; onTapped: root.callMe() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Call me")
                }
                // Favourites: numbers Teams called for you before.
                Column {
                    visible: root.favorites.length > 0
                    width: parent.width
                    Item { width: 1; height: 16 }
                    Text {
                        text: qsTr("Favorites")
                        font.family: theme.font; font.pixelSize: 12
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Item { width: 1; height: 8 }
                    Repeater {
                        model: root.favorites
                        Rectangle {
                            required property string modelData
                            width: parent.width; height: 48; radius: 4
                            color: favHover.hovered ? theme.menuHover : "transparent"
                            Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: modelData }
                            Column {
                                x: 52; anchors.verticalCenter: parent.verticalCenter
                                Text { text: modelData; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                Text { text: qsTr("Other"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                            }
                            HoverHandler { id: favHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { numberBox.text = modelData; root.callMe() } }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData
                        }
                    }
                }
                Item { width: 1; height: 15 }
                LinkButton { label: qsTr("Dial in manually"); onClicked: root.view = "dialIn" }
            }

            // Dial in.
            Column {
                visible: root.view === "dialIn" && !root.calling && !root.connected
                width: parent.width
                Item { width: 1; height: 1 }
                Row {
                    visible: !!root.dial
                    Text {
                        text: root.dial ? root.dial.toll : ""
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.underline: tollHover.hovered
                        color: theme.brandLink
                        HoverHandler { id: tollHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.openExternal("tel:" + root.dial.toll) }
                        Accessible.role: Accessible.Link
                        Accessible.name: root.dial ? root.dial.tollAria : ""
                    }
                    Text {
                        text: qsTr(" (Toll)")
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                }
                Row {
                    visible: !!root.dial && root.dial.tollFree.length > 0
                    Text {
                        text: root.dial ? root.dial.tollFree : ""
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.underline: tollFreeHover.hovered
                        color: theme.brandLink
                        HoverHandler { id: tollFreeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.openExternal("tel:" + root.dial.tollFree) }
                        Accessible.role: Accessible.Link
                        Accessible.name: root.dial ? root.dial.tollFreeAria : ""
                    }
                    Text {
                        text: qsTr(" (Toll-Free)")
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                }
                Text {
                    visible: !!root.dial && root.dial.localNumbersUrl.length > 0
                    text: qsTr("Get local numbers")
                    font.family: theme.font; font.pixelSize: 14
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.underline: localHover.hovered
                    color: theme.brandLink
                    HoverHandler { id: localHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.openExternal(root.dial.localNumbersUrl) }
                    Accessible.role: Accessible.Link
                    Accessible.name: text
                }
                Text {
                    visible: !!root.dial
                    text: root.dial ? root.dial.conferenceText : ""
                    font.family: theme.font; font.pixelSize: 14
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                // Teams keeps the dial-in block at least 122 tall
                // (hasDialInMinHeight) with the button 75 in.
                Item { width: 1; height: 15 }
                LinkButton {
                    visible: !!root.phone.dialOut
                    label: qsTr("Call me back")
                    onClicked: { root.view = "callMe"; numberBox.forceActiveFocus() }
                }
                Item { width: 1; height: 15 }
            }

            // Calling or connected: your phone, with "Calling..." or
            // Disconnect (Teams' highlighted list item).
            Column {
                visible: root.calling || root.connected
                width: parent.width
                Item { width: 1; height: 20 }
                Rectangle {
                    width: parent.width; height: 48; radius: 4
                    color: theme.pane
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: root.phone.number || "" }
                    Text {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        text: root.phone.number || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Text {
                        visible: root.calling
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Calling...")
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.text
                    }
                    Rectangle {
                        id: hcFill2
                        visible: root.connected
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: discText.implicitWidth + 24; height: 32; radius: 4
                        color: discHover.hovered ? theme.menuHover : theme.surface
                        border.color: theme.stroke; border.width: 1
                        Text { id: discText; anchors.centerIn: parent; text: qsTr("Disconnect"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
                        HoverHandler { id: discHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { backend.disconnectPhoneAudio(); root.close() } }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Disconnect")
                    }
                }
            }
        }
    }

    // Teams' inline transparent button: 14/20 semibold #424242,
    // underlined, 32 tall.
    component LinkButton: Item {
        id: lb
        property string label
        signal clicked()
        width: lbText.implicitWidth; height: 32
        Text {
            id: lbText
            anchors.verticalCenter: parent.verticalCenter
            text: lb.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            font.underline: true
            color: lbHover.hovered ? theme.text : theme.textStrong
        }
        HoverHandler { id: lbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
