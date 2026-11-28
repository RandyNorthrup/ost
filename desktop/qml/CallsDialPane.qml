import QtQuick
import QtQuick.Controls.Basic

// The Calls app's left pane, as Teams 26304 draws it for ost-test1 (its
// DialpadContainer, calls-main-app's forwarding and device menus; its DOM
// measured over CDP on winpc 2026-11-27, y from the header's bottom):
// - "Type a name or number" (16 in, 18 down, 347.3 x 33.3, filled
//   #F0F0F0, radius 4, padding 12, the placeholder #424242) when PSTN
//   calling is allowed (Teams' isPstnCallingAllowed), else "Type a name";
// - with PSTN calling, the 12-key dial pad (Teams' keypad with "+" under
//   0): 60 x 60 keys from 63.7,66.3, 96 and 70 apart; digits 22.5/600
//   #4F52B2 6.8 in, letters 10/600 at 38.9; a key types into the box;
//   holding 0 for a second types "+";
// - Call (351.3 down, 347.3 x 32): enabled once someone is picked or
//   anything is typed; with no one picked it calls what's typed as a
//   phone number;
// - the dial pad's #F0F0F0 bottom border at 401.3, then "Parked calls"
//   (426 down, centred, 31.3 tall, padding 20, a #D1D1D1 edge) for an
//   Enterprise Voice user with a call park policy: Pick up a parked call;
// - at the bottom, 85.2 and 51.8 above the pane's end: the forwarding
//   menu ("Don't forward ▾", 33.3 tall) and the audio device menu
//   ("Custom Setup ▾", 35.8 tall): padding 6.7, 20 px glyph, #424242.
Item {
    id: root
    /// People search results ([{id, name, mail, job_title}]).
    property var people: []
    /// Teams' calling settings (SettingsView's mt): callingPolicy, voice,
    /// delegation, attendant.
    property var mt: ({})
    /// Intelligent call delegation is on (Teams hides forwarding then).
    property bool attendantOn: false
    signal callPerson(string oid, string name)
    signal searchPeople(string query)
    signal openSettings(string id)
    signal unpark()

    readonly property var policy: mt.callingPolicy || {}
    readonly property bool pstn: policy.pstn === true
    property var chosen: null
    readonly property bool canCall: chosen !== null || nameField.text.trim().length > 0

    function startCall() {
        if (!canCall) return
        if (chosen) root.callPerson(chosen.id, chosen.name)
        else backend.callPhoneNumber(nameField.text)
        chosen = null
        nameField.text = ""
    }
    function press(k) {
        nameField.insert(nameField.cursorPosition, k)
        nameField.forceActiveFocus()
        chosen = null
    }
    function typeForTest(t) { nameField.text = t; chosen = null }
    function pressForTest(k) { press(k) }
    function callForTest() { startCall() }
    function openForwardingForTest() { forwardRow.openMenu() }
    function openDevicesForTest() { deviceRow.openMenu() }
    function closeMenusForTest() { forwardMenu.close(); deviceMenu.close() }
    function pickForwardingForTest(i) { forwardMenu.picked(i) }
    function pickDeviceForTest(i) { deviceMenu.picked(i) }
    readonly property var forwardItemsForTest: forwardMenu.items
    readonly property var deviceItemsForTest: deviceMenu.items

    Component.onCompleted: backend.prepareDialPad()

    Rectangle {
        id: nameBox
        x: 16; y: 18; width: 347.3; height: 33.3; radius: 4
        color: theme.hc(theme.dark ? "#2E2E2E" : "#F0F0F0", "#000000")
        border.color: theme.highContrast ? theme.stroke : "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand; visible: nameField.activeFocus }
        TextInput {
            id: nameField
            x: 12; width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            clip: true
            onTextEdited: { root.chosen = null; if (text.trim().length > 1) searchDelay.restart() }
            Keys.onReturnPressed: root.startCall()
            Keys.onEnterPressed: root.startCall()
            Text { visible: !nameField.text; text: root.pstn ? qsTr("Type a name or number") : qsTr("Type a name"); color: theme.textStrong; font: nameField.font }
            Accessible.name: root.pstn ? qsTr("Type a name or number") : qsTr("Type a name")
        }
        Timer { id: searchDelay; interval: 300; onTriggered: root.searchPeople(nameField.text.trim()) }
    }
    // Matches while typing.
    Rectangle {
        visible: nameField.activeFocus && nameField.text.trim().length > 1 && !root.chosen && root.people.length > 0
        z: 10
        x: 16; y: nameBox.y + nameBox.height + 2; width: nameBox.width
        height: Math.min(240, pplCol.implicitHeight + 8); radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        Column {
            id: pplCol
            x: 4; y: 4; width: parent.width - 8
            Repeater {
                model: root.people.slice(0, 5)
                Rectangle {
                    id: hcPerson
                    required property var modelData
                    width: pplCol.width; height: 44; radius: theme.radius
                    color: ph.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name; photoId: parent.modelData.id }
                    Column {
                        x: 46; anchors.verticalCenter: parent.verticalCenter
                        Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcPerson, theme.text) }
                        Text { text: parent.parent.modelData.mail || parent.parent.modelData.job_title || ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcPerson, theme.textSecondary) }
                    }
                    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.chosen = parent.modelData; nameField.text = parent.modelData.name } }
                }
            }
        }
    }

    // The dial pad (Teams' 12 keys with "+" under 0).
    Item {
        id: keypad
        visible: root.pstn
        x: 0; y: 66.3; width: 379; height: 270
        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("Use arrow keys to navigate between numbers and press Enter or Space to select a number.")
        Repeater {
            id: keyRep
            model: [["1", ""], ["2", "ABC"], ["3", "DEF"], ["4", "GHI"], ["5", "JKL"], ["6", "MNO"], ["7", "PQRS"], ["8", "TUV"], ["9", "WXYZ"], ["*", ""], ["0", "+"], ["#", ""]]
            Rectangle {
                id: key
                required property var modelData
                required property int index
                readonly property bool longPressed: hold.fired
                x: 63.7 + (index % 3) * 96; y: Math.floor(index / 3) * 70
                width: 60; height: 60; radius: 4
                color: keyTap.pressed ? theme.selected : kh.hovered ? theme.rowHover : "transparent"
                activeFocusOnTab: true
                Text {
                    id: digit
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6.8
                    text: key.modelData[0]
                    // Teams' 22.5 px digits (pixel sizes are whole numbers
                    // here): 45 px drawn at half size.
                    font.family: theme.font; font.pixelSize: 45; font.weight: Font.DemiBold
                    scale: 0.5; transformOrigin: Item.Top
                    color: theme.onFill(key, theme.pick("#4F52B2", "#7F85F5", "#FFFFFF"))
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 38.9
                    text: key.modelData[1]
                    font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                    color: theme.onFill(key, theme.pick("#4F52B2", "#7F85F5", "#FFFFFF"))
                }
                HoverHandler { id: kh; cursorShape: Qt.PointingHandCursor }
                // Holding 0 for a second types "+" (Teams' longKeyPressTimer).
                Timer {
                    id: hold
                    property bool fired: false
                    interval: 1000
                    onTriggered: { fired = true; root.press("+") }
                }
                TapHandler {
                    id: keyTap
                    onPressedChanged: {
                        if (key.modelData[0] !== "0") return
                        if (pressed) { hold.fired = false; hold.restart() } else hold.stop()
                    }
                    onTapped: { if (key.modelData[0] === "0" && hold.fired) { hold.fired = false; return } root.press(key.modelData[0]) }
                }
                Keys.onSpacePressed: root.press(key.modelData[0])
                Keys.onReturnPressed: root.press(key.modelData[0])
                Keys.onRightPressed: { const n = keyRep.itemAt(Math.min(11, key.index + 1)); if (n) n.forceActiveFocus() }
                Keys.onLeftPressed: { const n = keyRep.itemAt(Math.max(0, key.index - 1)); if (n) n.forceActiveFocus() }
                Keys.onDownPressed: { const n = keyRep.itemAt(Math.min(11, key.index + 3)); if (n) n.forceActiveFocus() }
                Keys.onUpPressed: { const n = keyRep.itemAt(Math.max(0, key.index - 3)); if (n) n.forceActiveFocus() }
                Accessible.role: Accessible.Button
                Accessible.name: key.modelData[0]
                Accessible.description: key.modelData[1]
            }
        }
    }

    Rectangle {
        id: callButton
        x: 16; y: root.pstn ? 351.3 : 82; width: 347.3; height: 32; radius: 4
        color: root.canCall ? (cbh.hovered ? theme.brandHover : theme.brandFill) : (theme.dark ? theme.hc("#2E2E2E", "#000000") : theme.hc("#F0F0F0", "#000000"))
        Row {
            anchors.centerIn: parent
            spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-20"; size: 20; color: theme.onFill(callButton, root.canCall ? "white" : theme.disabled) }
            Text { text: qsTr("Call", "calling:ka2l734dq"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(callButton, root.canCall ? "white" : theme.disabled) }
        }
        HoverHandler { id: cbh; cursorShape: root.canCall ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: root.canCall; onTapped: root.startCall() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Call", "calling:ka2l734dq")
    }

    // Parked calls (Teams' UnparkCallButtonRenderer: an Enterprise Voice
    // user whose call park policy allows it), under a divider.
    readonly property bool parkShown: policy.park === true && policy.ev === true
    Rectangle { visible: root.parkShown; x: 16; y: callButton.y + 50; width: 347.3; height: 1; color: theme.pick("#F0F0F0", "#2E2E2E", "#FFFFFF") }
    Rectangle {
        id: parkButton
        visible: root.parkShown
        y: callButton.y + 74.7
        anchors.horizontalCenter: callButton.horizontalCenter
        width: parkText.implicitWidth + 40; height: 31.3; radius: 4
        color: pkh.hovered ? theme.rowHover : theme.input
        border.color: theme.stroke
        Text { id: parkText; anchors.centerIn: parent; text: qsTr("Parked calls"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(parkButton, theme.text) }
        HoverHandler { id: pkh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.unpark() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Parked calls")
    }

    // ---- Forwarding (Teams' CallForwardingSettings quick menu) ----
    // Shown to a user who may forward (isForwardingAllowed) unless
    // Intelligent call delegation is on. The label is the current choice;
    // the menu lists Don't forward, Forward to voicemail, the call group
    // and delegates where they apply, then "Forward to <person>" for your
    // favourite targets, and More Settings (Settings ▸ Calls). Picking
    // forwards all calls there at once (Immediate), or stops forwarding.
    readonly property var redir: (mt.voice || {}).callRedirectionSettings || null
    readonly property var cf: (redir || {}).callForwardingSettings || {}
    readonly property bool forwardShown: !!redir && policy.forwarding === true && !root.attendantOn
    readonly property bool vmAllowed: policy.pstn === true && policy.allowVoicemail !== "AlwaysDisabled"
    readonly property string currentKey: cf.isEnabled === true ? ((cf.targetType === "SingleTarget" && cf.target) ? cf.target : (cf.targetType || "DoNothing")) : "DoNothing"
    readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    function targetName(t) {
        if ((t || "").startsWith("4:")) return JSON.parse(backend.phoneNumberCheck(t.slice(2))).display || t.slice(2)
        return names[t] || ""
    }
    readonly property var forwardOptions: {
        const out = [{ key: "DoNothing", label: qsTr("Don't forward") }]
        if (vmAllowed) out.push({ key: "Voicemail", label: qsTr("Forward to voicemail") })
        if (policy.allowCallGroups === true && policy.pstn === true && (((redir || {}).callGroupDetails || {}).targets || []).length > 0)
            out.push({ key: "Group", label: qsTr("Forwarding to call group") })
        const delegates = ((mt.delegation || {}).userDelegates || {}).delegates || []
        if (policy.allowDelegation === true && policy.pstn === true && delegates.some(d => d.isActive && (d.allowedActions || {}).receiveCalls))
            out.push({ key: "MyDelegates", label: qsTr("Forwarding to delegates") })
        // Favourite targets and the current one, without yourself, as your
        // policy allows (phone numbers, people).
        const me = backend.userMri
        const seen = {}
        ;(((redir || {}).favoriteTargets || {}).targets || []).concat(cf.target ? [cf.target] : []).forEach(t => {
            if (!t || seen[t] || t === me) return
            seen[t] = true
            const phone = t.startsWith("4:")
            if ((phone && policy.allowCallForwardingToPhone === true) || (!phone && policy.allowCallForwardingToUser === true))
                out.push({ key: t, target: true, label: qsTr("Forward to %1").arg(root.targetName(t) || t.replace(/^[0-9]+:(orgid:)?/, "")) })
        })
        return out
    }
    readonly property string forwardLabel: (forwardOptions.find(o => o.key === currentKey) || forwardOptions[0]).label
    onForwardOptionsChanged: {
        const want = forwardOptions.filter(o => o.target && !o.key.startsWith("4:") && !names[o.key]).map(o => o.key)
        if (want.length) backend.resolveNames(JSON.stringify(want))
    }
    function pickForward(o) {
        if (o.key === "DoNothing") backend.changeSetting("mt", "forwarding", JSON.stringify({ op: "forwardAllOff" }))
        else if (o.target) backend.changeSetting("mt", "forwarding", JSON.stringify({ op: "forwardAll", targetType: "SingleTarget", target: o.key }))
        else backend.changeSetting("mt", "forwarding", JSON.stringify({ op: "forwardAll", targetType: o.key }))
    }
    Rectangle {
        id: forwardRow
        visible: root.forwardShown
        x: 16; y: parent.height - 85.2; height: 33.3; radius: 4
        width: Math.min(300, forwardText.implicitWidth + 60.7)
        color: frh.hovered ? theme.rowHover : "transparent"
        function openMenu() { forwardMenu.open() }
        FluentIcon { x: 6.7; anchors.verticalCenter: parent.verticalCenter; name: "call-forward-20"; size: 20; color: theme.onFill(forwardRow, theme.textStrong) }
        Text {
            id: forwardText
            x: 36.7; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 230); elide: Text.ElideRight
            text: root.forwardLabel
            font.family: theme.font; font.pixelSize: 14; color: theme.onFill(forwardRow, theme.textStrong)
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(forwardRow, theme.textStrong) }
        HoverHandler { id: frh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: forwardRow.openMenu() }
        Accessible.role: Accessible.Button
        Accessible.name: root.forwardLabel
        MenuPopup {
            id: forwardMenu
            y: -height - 4
            perItemIcons: true
            items: [{ heading: qsTr("Forwarding") }]
                .concat(root.forwardOptions.map(o => ({ label: o.label, endCheck: o.key === root.currentKey })))
                .concat([{ separator: true }, { label: qsTr("More Settings"), icon: "settings-20" }])
            onPicked: i => {
                const o = root.forwardOptions[i - 1]
                if (o) { if (o.key !== root.currentKey) root.pickForward(o) }
                else if (i === root.forwardOptions.length + 2) root.openSettings("calls")
            }
        }
    }

    // ---- Audio device (Teams' AudioDeviceSettings menu) ----
    // Teams' audio devices are cards with a microphone and a speaker; the
    // button names the one both are on, or "Custom Setup" (a gear) when
    // they're on different ones. The menu: "Audio Devices", the devices
    // (picking one sets both), Custom Setup (checked) while custom, and
    // Device settings (Settings ▸ Devices).
    property var audio: ({ inputs: [], outputs: [], groups: [] })
    property int deviceTick: 0
    function refreshDevices() { audio = JSON.parse(backend.audioDevices()) }
    readonly property string micNow: { deviceTick; const m = backend.setting("micDevice"); return m && m !== "default" ? m : (audio.defaultInput || "") }
    readonly property string speakerNow: { deviceTick; const s = backend.setting("speakerDevice"); return s && s !== "default" ? s : (audio.defaultOutput || "") }
    readonly property var groupNow: (audio.groups || []).find(g => g.mic === micNow && g.speaker === speakerNow) || null
    function groupLabel(g) { return g.internal ? qsTr("PC Mic and Speakers") : g.label }
    readonly property string deviceLabel: groupNow ? groupLabel(groupNow) : qsTr("Custom Setup")
    onVisibleChanged: if (visible) refreshDevices()
    Rectangle {
        id: deviceRow
        x: 16; y: parent.height - 51.8; height: 35.8; radius: 4
        width: Math.min(300, deviceText.implicitWidth + 60.7)
        color: dvh.hovered ? theme.rowHover : "transparent"
        function openMenu() { root.refreshDevices(); deviceMenu.open() }
        FluentIcon { x: 6.7; anchors.verticalCenter: parent.verticalCenter; name: root.groupNow ? "headset-20" : "settings-20"; size: 20; color: theme.onFill(deviceRow, theme.textStrong) }
        Text {
            id: deviceText
            x: 36.7; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 230); elide: Text.ElideRight
            text: root.deviceLabel
            font.family: theme.font; font.pixelSize: 14; color: theme.onFill(deviceRow, theme.textStrong)
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(deviceRow, theme.textStrong) }
        HoverHandler { id: dvh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: deviceRow.openMenu() }
        Accessible.role: Accessible.Button
        Accessible.name: root.deviceLabel
        MenuPopup {
            id: deviceMenu
            y: -height - 4
            perItemIcons: true
            readonly property var groups: root.audio.groups || []
            items: [{ heading: qsTr("Audio Devices") }]
                .concat(groups.map(g => ({ label: root.groupLabel(g), endCheck: !!root.groupNow && root.groupNow.id === g.id })))
                .concat(root.groupNow ? [] : [{ label: qsTr("Custom Setup"), endCheck: true }])
                .concat([{ separator: true }, { label: qsTr("Device settings"), icon: "settings-20" }])
            onPicked: i => {
                const g = groups[i - 1]
                if (g) {
                    backend.setSetting("micDevice", g.mic)
                    backend.setSetting("speakerDevice", g.speaker)
                    root.deviceTick++
                } else if (i === items.length - 1) root.openSettings("devices")
            }
        }
    }
}
