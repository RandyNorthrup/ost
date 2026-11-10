import QtQuick
import QtQuick.Controls.Basic

// Settings ▸ General ▸ Out of office, as Teams lays it out (measured on
// winpc 2026-11-10): one 790-wide card:
// - "Turn on automatic replies" (14/20) and its explanation (12/16
//   #616161) at 57, the On/Off switch at the right;
// - "Out of office message" (14/20, greyed while off) with an info button,
//   and a 649 x 97 text area;
// - "Send replies outside my organization": then "Only to my contacts" /
//   "All external senders" and a second 644 x 97 text area (placeholder
//   "Message");
// - "Send replies only during a time period": Start and End (12/16 labels),
//   each a 177-wide date picker and a 207-wide time dropdown 42 to its right;
// - Cancel and Save (96 x 31.3); Save is off until something changed, and
//   off while on with no message.
// Saving sends Teams' updateAutomaticRepliesSetting (status disabled,
// alwaysEnabled or scheduled; externalAudience none, contactsOnly or all).
Rectangle {
    id: root
    /// The saved setting ({status, internalReplyMessage, …}), or null.
    property var setting: null
    signal save(var value)
    signal cancel()
    height: col.y + col.height + 20
    radius: 8
    color: "transparent"
    border.color: theme.pick("#D1D1D1", "#3D3D3D"); border.width: 0.67

    property bool on: false
    property bool external: false
    property string audience: "all"
    property bool period: false
    property date start: new Date()
    property date end: new Date()
    property string snapshot: ""
    function nextDay(d) { const n = new Date(d); n.setDate(n.getDate() + 1); return n }
    function load() {
        const s = setting || {}
        on = !!s.status && s.status !== "disabled"
        internal.text = s.internalReplyMessage || ""
        externalText.text = s.externalReplyMessage || ""
        audience = s.externalAudience === "contactsOnly" ? "contactsOnly" : "all"
        external = !!s.externalAudience && s.externalAudience !== "none" && (!!s.externalReplyMessage || s.status !== "disabled")
        period = s.status === "scheduled"
        const today = new Date(); today.setHours(0, 0, 0, 0)
        start = s.scheduledStartDateTime ? new Date(s.scheduledStartDateTime) : today
        end = s.scheduledEndDateTime ? new Date(s.scheduledEndDateTime) : nextDay(today)
        snapshot = JSON.stringify(value())
    }
    onVisibleChanged: if (visible) load()
    onSettingChanged: if (visible) load()
    function value() {
        return {
            status: !on ? "disabled" : period ? "scheduled" : "alwaysEnabled",
            internalReplyMessage: internal.text,
            externalReplyMessage: external ? externalText.text : "",
            externalAudience: external ? audience : "none",
            scheduledStartDateTime: start.toISOString(),
            scheduledEndDateTime: end.toISOString(),
        }
    }
    readonly property bool changed: JSON.stringify(value()) !== snapshot
    readonly property bool canSave: changed && (!on || internal.text.trim().length > 0) && (!period || end > start)

    FluentIcon { x: 18.7; y: 26.7; name: "calendar-arrow-right-20"; size: 20; color: theme.text }
    Column {
        id: col
        x: 57; y: 21; width: root.width - 57 - 29
        Item {
            width: parent.width; height: 52
            Column {
                y: 6; width: parent.width - toggle.width - 40
                Text { text: "Turn on automatic replies"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { width: parent.width; wrapMode: Text.Wrap; text: "Set up a message to let others know you're on vacation or not available to reply. Your out of office status will also sync with your Outlook calendar."; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
            }
            SettingsParts.Toggle { id: toggle; anchors.right: parent.right; anchors.rightMargin: 28; y: 14; on: root.on; accessibleName: "Turn on automatic replies"; onToggled: v => root.on = v }
        }
        SettingsParts.Gap { size: 21 }
        Row {
            x: -16; spacing: 13
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Out of office message"; font.family: theme.font; font.pixelSize: 14; color: root.on ? theme.text : theme.disabled }
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "info-20"; size: 20; color: root.on ? theme.textSecondary : theme.disabled
                HoverHandler { id: infoHover }
                ToolTip.visible: infoHover.hovered; ToolTip.text: "Your automatic reply is sent to people who message or mention you." }
        }
        SettingsParts.Gap { size: 7 }
        MessageArea { id: internal; x: -16; width: 649; usable: root.on; label: "Out of office message" }
        SettingsParts.Gap { size: 21 }
        SettingsParts.CheckRow {
            x: -8; rowHeight: 42
            label: "Send replies outside my organization"
            usable: root.on
            checked: root.external
            onToggled: v => root.external = v
        }
        Column {
            visible: root.external && root.on
            x: -6
            SettingsParts.RadioRow { width: 300; label: "Only to my contacts"; checked: root.audience === "contactsOnly"; onPicked: root.audience = "contactsOnly" }
            SettingsParts.RadioRow { width: 300; label: "All external senders"; checked: root.audience === "all"; onPicked: root.audience = "all" }
            SettingsParts.Gap { size: 7 }
            MessageArea { id: externalText; x: -12; width: 644; usable: root.on; label: "Out of office message to people outside my organization"; placeholder: "Message" }
            SettingsParts.Gap { size: 21 }
        }
        SettingsParts.CheckRow {
            x: -8; rowHeight: 42
            label: "Send replies only during a time period"
            usable: root.on
            checked: root.period
            onToggled: v => root.period = v
        }
        Column {
            visible: root.period && root.on
            x: -18; spacing: 4
            Repeater {
                model: ["Start", "End"]
                Column {
                    required property string modelData
                    readonly property bool isStart: modelData === "Start"
                    readonly property date when: isStart ? root.start : root.end
                    function setWhen(d) { if (isStart) root.start = d; else root.end = d }
                    spacing: 1
                    Text { text: modelData; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Row {
                        spacing: 42
                        DatePickerField {
                            width: 177; height: 31.3
                            date: parent.parent.when
                            minDate: new Date()
                            onPicked: d => { const w = parent.parent.when; parent.parent.setWhen(new Date(d.getFullYear(), d.getMonth(), d.getDate(), w.getHours(), w.getMinutes())) }
                        }
                        OutlineDropdown {
                            width: 207; height: 30
                            accessibleName: parent.parent.modelData + " time"
                            readonly property date day: parent.parent.when
                            options: { const out = []; for (let i = 0; i < 48; i++) { const t = new Date(2000, 0, 1, 0, i * 30); out.push({ label: Qt.formatTime(t, "h:mm AP") }) } return out }
                            current: day.getHours() * 2 + Math.floor(day.getMinutes() / 30)
                            onPicked: i => { const w = parent.parent.when; parent.parent.setWhen(new Date(w.getFullYear(), w.getMonth(), w.getDate(), Math.floor(i / 2), (i % 2) * 30)) }
                        }
                    }
                    SettingsParts.Gap { size: 14 }
                }
            }
        }
        SettingsParts.Gap { size: 26 }
        Row {
            x: -16; spacing: 10
            SettingsParts.Button { label: "Cancel"; onClicked: { root.load(); root.cancel() } }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: !root.canSave ? theme.bgDisabled : saveHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.canSave ? "white" : theme.disabled }
                HoverHandler { id: saveHover; cursorShape: root.canSave ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: root.canSave; onTapped: root.save(root.value()) }
                Accessible.role: Accessible.Button
                Accessible.name: "Save"
            }
        }
    }

    // A Fluent Textarea (outline), 97 tall.
    component MessageArea: Rectangle {
        id: ma
        property bool usable: true
        property string label
        property string placeholder
        property alias text: edit.text
        height: 96.7; radius: 4
        color: theme.surface
        border.color: !usable ? theme.pick("#E0E0E0", "#3D3D3D") : edit.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
        Rectangle { visible: ma.usable; anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: edit.activeFocus ? 2 : 0.67; color: edit.activeFocus ? theme.brand : theme.textSecondary }
        Flickable {
            x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
            contentHeight: edit.contentHeight; clip: true
            TextEdit {
                id: edit
                width: parent.width
                enabled: ma.usable
                wrapMode: TextEdit.Wrap
                font.family: theme.font; font.pixelSize: 14
                color: ma.usable ? theme.text : theme.disabled
                Accessible.role: Accessible.EditableText
                Accessible.name: ma.label
                Text { visible: !edit.text; text: ma.placeholder; font: edit.font; color: theme.textSecondary }
            }
        }
    }
    function typeForTest(t) { internal.text = t }
}
