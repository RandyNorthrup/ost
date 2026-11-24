import QtQuick
import QtQuick.Controls

// Teams' "Breakout rooms settings" from a meeting chat's Breakout Rooms
// tab (breakout-rooms-settings-dialog, measured on winpc 2026-11-20):
// a 600 x 466.67 dialog, padding 24, radius 8. The title (20/28
// semibold) and Close at 24.67; then label rows 36 tall (14/20, 8 px in)
// with a switch (40 x 20 in a 56 x 36 target at 519.33): "Assign
// presenters to manage rooms" at 84, over "There are no assigned
// presenters to select from in the meeting at the moment." (#616161, to
// the right edge) while there are none; "Set a time limit" with its
// information button at 150, over "0 hours" and "0 minutes" (280 x 31.33
// combo boxes at 295.33, 196 and 237.33; off until the limit is on);
// "Automatically move people to rooms" (on at first) at 278.67, "Let
// people choose their own rooms" at 314.67, "Let people return to the
// main meeting" at 360.67; Save (96, brand) at 479.33, 410.67.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 466.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    /// The rooms' settings: {allow_select, room_duration, allow_return,
    /// auto_move, managers}.
    property var settings: ({})
    /// Presenters who can manage rooms: [{id, name}].
    property var presenters: []
    signal saved(var settings)

    property var managers: []
    property bool managersOn: false
    property bool limitOn: false
    property int hours: 0
    property int minutes: 0
    property bool autoMove: true
    property bool allowSelect: false
    property bool allowReturn: false
    function show() {
        const s = settings || {}
        managers = s.managers || []
        managersOn = managers.length > 0
        limitOn = (s.room_duration || 0) > 0
        hours = Math.floor((s.room_duration || 0) / 60)
        minutes = (s.room_duration || 0) % 60
        autoMove = s.auto_move !== false
        allowSelect = !!s.allow_select
        allowReturn = !!s.allow_return
        open()
    }
    function nameOf(id) { const p = presenters.find(x => x.id === id); return p ? p.name : "" }

    component Switch40: Item {
        id: sw
        property bool checked: false
        property string label
        signal toggled(bool on)
        width: 56; height: 36
        Rectangle {
            x: 8; y: 8; width: 40; height: 20; radius: 10
            color: sw.checked ? (swHover.hovered ? theme.brandHover : theme.checkedFill) : "transparent"
            border.color: sw.checked ? "transparent" : theme.textSecondary; border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: sw.checked ? 22.8 : 2.8
                color: sw.checked ? theme.hc("white", "#1AEBFF") : theme.textSecondary
            }
        }
        HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { sw.checked = !sw.checked; sw.toggled(sw.checked) } }
        Accessible.role: Accessible.CheckBox
        Accessible.name: sw.label
        Accessible.checked: sw.checked
    }
    component Combo: Rectangle {
        id: cb
        property string text
        property string label
        property var items: []
        signal picked(int index)
        width: 280; height: 31.33; radius: 4
        color: theme.surface
        border.color: cb.enabled ? theme.stroke : theme.divider; border.width: 0.67
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; elide: Text.ElideRight
            text: cb.text
            font.family: theme.font; font.pixelSize: 14
            color: theme.onFill(cb, cb.enabled ? theme.text : theme.disabled)
        }
        FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.onFill(cb, cb.enabled ? theme.textSecondary : theme.disabled) }
        HoverHandler { cursorShape: cb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: cb.enabled; onTapped: menu.open() }
        Accessible.role: Accessible.ComboBox
        Accessible.name: cb.label
        MenuPopup {
            id: menu
            y: parent.height + 4
            width: parent.width
            height: Math.min(implicitHeight, 300)
            items: cb.items
            onPicked: i => cb.picked(i)
        }
    }
    component Row36: Text {
        x: 32.67; height: 36; width: 470
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    function unit(v, hoursUnit) {
        return hoursUnit ? (v === 1 ? qsTr("%1 hour").arg(v) : qsTr("%1 hours").arg(v))
                         : (v === 1 ? qsTr("%1 minute").arg(v) : qsTr("%1 minutes").arg(v))
    }

    Text {
        x: 24.67; y: 24.67; width: 510.67; height: 31.33
        verticalAlignment: Text.AlignVCenter
        text: qsTr("Breakout rooms settings")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading; Accessible.name: text
    }
    Rectangle {
        id: hcClose
        x: 543.33; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcClose, theme.textStrong) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close")
    }

    Row36 { y: 84; text: qsTr("Assign presenters to manage rooms") }
    Switch40 {
        x: 519.33; y: 84
        label: qsTr("Assign presenters to manage rooms")
        checked: root.managersOn
        onToggled: on => { root.managersOn = on; if (!on) root.managers = [] }
    }
    Text {
        visible: root.presenters.length === 0
        anchors.right: parent.right; anchors.rightMargin: 24.67; y: 120; height: 20
        text: qsTr("There are no assigned presenters to select from in the meeting at the moment.")
        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
    }
    Combo {
        visible: root.presenters.length > 0
        x: 295.33; y: 118
        enabled: root.managersOn
        label: qsTr("Search for presenters")
        text: root.managers.length ? root.managers.map(m => root.nameOf(m.mri)).join(", ") : qsTr("Search for presenters")
        items: root.presenters.map(p => ({ label: p.name, checked: root.managers.some(m => m.mri === p.id) }))
        onPicked: i => {
            const p = root.presenters[i]
            if (!p) return
            const has = root.managers.some(m => m.mri === p.id)
            root.managers = has ? root.managers.filter(m => m.mri !== p.id) : root.managers.concat([{ mri: p.id, role: "Admin" }])
        }
    }

    Text {
        id: limitLabel
        x: 32.67; y: 157.67; height: 18.67
        verticalAlignment: Text.AlignVCenter
        text: qsTr("Set a time limit")
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    Item {
        x: 125.29; y: 155; width: 24; height: 24
        FluentIcon { anchors.centerIn: parent; name: "info-16"; size: 16; color: theme.textStrong }
        HoverHandler { id: infoHover }
        ToolTip.visible: infoHover.hovered
        ToolTip.text: qsTr("We'll move everyone back to the main meeting when the time expires.")
        Accessible.role: Accessible.Button
        Accessible.name: "information"
    }
    Switch40 {
        x: 519.33; y: 150
        label: qsTr("Set a time limit")
        checked: root.limitOn
        onToggled: on => { root.limitOn = on; if (on && !root.hours && !root.minutes) root.minutes = 30 }
    }
    Combo {
        x: 295.33; y: 196
        enabled: root.limitOn
        label: qsTr("Set hours limit")
        text: root.unit(root.hours, true)
        items: Array.from({ length: 24 }, (_, i) => ({ label: root.unit(i, true) }))
        onPicked: i => root.hours = i
    }
    Combo {
        x: 295.33; y: 237.33
        enabled: root.limitOn
        label: qsTr("Set minutes limit")
        text: root.unit(root.minutes, false)
        items: Array.from({ length: 12 }, (_, i) => ({ label: root.unit(i * 5, false) }))
        onPicked: i => root.minutes = i * 5
    }

    Repeater {
        model: [
            { key: "autoMove", label: qsTr("Automatically move people to rooms"), y: 278.67 },
            { key: "allowSelect", label: qsTr("Let people choose their own rooms"), y: 314.67 },
            { key: "allowReturn", label: qsTr("Let people return to the main meeting"), y: 360.67 }
        ]
        Item {
            required property var modelData
            width: root.width; height: 36; y: modelData.y
            Row36 { text: modelData.label }
            Switch40 {
                x: 519.33
                label: modelData.label
                checked: root[modelData.key]
                onToggled: on => root[modelData.key] = on
            }
        }
    }

    Rectangle {
        id: save
        x: 479.33; y: 410.67; width: 96; height: 31.33; radius: 4
        color: saveHover.hovered ? theme.brandHover : theme.brandFill
        Text {
            anchors.centerIn: parent
            text: qsTr("Save")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(save, theme.textOnBrand)
        }
        HoverHandler { id: saveHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                root.saved({
                    allow_select: root.allowSelect,
                    allow_return: root.allowReturn,
                    auto_move: root.autoMove,
                    room_duration: root.limitOn ? root.hours * 60 + root.minutes : 0,
                    managers: root.managersOn ? root.managers : []
                })
                root.close()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Save")
    }
}
