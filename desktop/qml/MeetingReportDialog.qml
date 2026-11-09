import QtQuick
import QtQuick.Controls.Basic

// Teams' "Report a security concern" for a meeting (More ▸ Report a
// concern; measured on winpc, 2026-11-09): 600 x 460.67, radius 8,
// padding 24:
// - the title (20/28 semibold) and Close (32 x 31.33);
// - the meeting card, y 64, 550.67 x 76, #E8EBFA with a 6 px #5B5FC7 bar:
//   its title (14/20 semibold), start ("Nov 6, 3:00 PM", 12/20 #424242)
//   and organizer, 18 in;
// - "Enter an explanation (optional)", 4 rows (92 tall) filled #F5F5F5,
//   with "{n}/250 maximum characters" (12/20 #616161) under it;
// - "Report participants (optional)" (14/20 semibold) over a 32 px
//   picker: everyone in the meeting or its chat but you; chosen people
//   show as pills (16 px avatar, 12/16 name) before "Search participants";
// - "This message will be shared for review. The review process is fully
//   determined by your organization." (12/16 #616161);
// - Cancel and Report (96 x 31.33). Sent: "Your report was sent"; failed:
//   "Failed to submit report. Please try again.".
Popup {
    id: root
    /// {title, start, organizer}
    property var meeting: ({})
    /// [{id, name}] who can be reported.
    property var people: []
    signal reported()
    modal: true; focus: true
    width: 600; height: 460.67 + (failed ? 28 : 0)
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }
    readonly property bool sending: backend.reportResult === "sending"
    readonly property bool failed: backend.reportResult === "error" && opened
    property var chosen: []
    function openListForTest() { search.forceActiveFocus(); list.open() }
    function chooseFirstForTest() { if (list.matches.length) { chosen = chosen.concat([list.matches[0]]); list.close() } }
    onOpened: { why.text = ""; chosen = []; search.text = ""; why.forceActiveFocus() }
    Connections {
        target: backend
        function onReportResultChanged() {
            if (root.opened && backend.reportResult === "ok") { root.close(); root.reported() }
        }
    }

    Text { x: 24.67; y: 24.67; height: 31.33; verticalAlignment: Text.AlignVCenter; text: "Report a security concern"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
    Rectangle {
        x: 543.33; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    // The meeting.
    Rectangle {
        x: 24.67; y: 64; width: 550.67; height: 76; radius: 4
        color: theme.pick("#E8EBFA", "#2B2B40")
        clip: true
        Rectangle { width: 6; height: parent.height; color: theme.brandFill }
        Column {
            x: 18; y: 8
            Text { width: 500; elide: Text.ElideRight; height: 20; verticalAlignment: Text.AlignVCenter; text: root.meeting.title || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text { height: 20; verticalAlignment: Text.AlignVCenter; text: root.meeting.start || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
            Text { height: 20; verticalAlignment: Text.AlignVCenter; text: root.meeting.organizer || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        }
    }
    // The explanation.
    Rectangle {
        x: 25.33; y: 156.67; width: 549.33; height: 92; radius: 4
        color: theme.inputFilled
        clip: true
        TextEdit {
            id: why
            x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
            wrapMode: TextEdit.Wrap
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            selectByMouse: true
            onTextChanged: if (length > 250) remove(250, length)
            Text { visible: !why.text; text: "Enter an explanation (optional)"; font: why.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Enter an explanation (optional)"
        }
        Rectangle { visible: why.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
    }
    Text { x: 24.67; y: 259.33; height: 20; verticalAlignment: Text.AlignVCenter; text: why.length + "/250 maximum characters"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
    Text { x: 24.67; y: 295.33; height: 20; verticalAlignment: Text.AlignVCenter; text: "Report participants (optional)"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
    // The participant picker.
    Rectangle {
        id: picker
        x: 24.67; y: 320; width: 550.67; height: 32; radius: 4
        color: theme.surface
        border.color: theme.stroke; border.width: 0.67
        Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 0.67; color: theme.textSecondary }
        Row {
            x: 12.67; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: root.chosen
                Rectangle {
                    required property var modelData
                    height: 20; radius: 10
                    width: pillRow.implicitWidth + 4
                    color: theme.menuHover
                    Row {
                        id: pillRow
                        x: 1.67; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Avatar { size: 16; name: modelData.name; photoId: modelData.id || "" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                    }
                    TapHandler { onTapped: root.chosen = root.chosen.filter(p => p.id !== modelData.id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove " + modelData.name
                }
            }
            TextInput {
                id: search
                width: picker.width - 12.67 - 30 - x
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                clip: true
                onTextChanged: if (activeFocus) list.open()
                onActiveFocusChanged: if (activeFocus) list.open()
                Text { visible: !search.text; text: "Search participants"; font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Search participants"
            }
        }
        FluentIcon { x: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 16; color: theme.textSecondary }
        TapHandler { onTapped: { search.forceActiveFocus(); list.visible ? list.close() : list.open() } }
        Popup {
            id: list
            y: picker.height + 3; x: 0
            width: picker.width; padding: 4
            height: Math.min(300, col.implicitHeight + 8)
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            readonly property var matches: root.people.filter(p => !root.chosen.some(c => c.id === p.id)
                && p.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
            Flickable {
                anchors.fill: parent
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: col
                    width: parent.width
                    Repeater {
                        model: list.matches
                        Rectangle {
                            id: opt
                            required property var modelData
                            width: col.width; height: 32; radius: 4
                            color: oh.hovered ? theme.menuHover : "transparent"
                            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: opt.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                            HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.chosen = root.chosen.concat([opt.modelData]); search.text = ""; list.close() } }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: opt.modelData.name
                        }
                    }
                }
            }
        }
    }
    Text {
        x: 24.67; y: 380.67; width: 550.67
        wrapMode: Text.Wrap
        lineHeight: 16; lineHeightMode: Text.FixedHeight
        text: "This message will be shared for review. The review process is fully determined by your organization."
        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
    }
    Row {
        visible: root.failed
        x: 24.67; y: 404.67; spacing: 6
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "warning-12-filled"; size: 16; color: theme.redForeground1 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Failed to submit report. Please try again."; font.family: theme.font; font.pixelSize: 14; color: theme.redForeground1 }
    }
    Row {
        x: 375.33; y: 404.67 + (root.failed ? 28 : 0); spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered && !root.sending ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.sending ? theme.disabled : theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !root.sending; onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: root.sending ? theme.bgDisabled : reportHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Report"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.sending ? theme.disabled : "white" }
            HoverHandler { id: reportHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !root.sending; onTapped: backend.reportMeeting(why.text, JSON.stringify(root.chosen.map(p => p.id))) }
            Accessible.role: Accessible.Button
            Accessible.name: "Report"
        }
    }
}
