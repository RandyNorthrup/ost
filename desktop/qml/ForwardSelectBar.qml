import QtQuick
import QtQuick.Controls.Basic

// Teams' forward-multiselect-footer (828024; measured on Teams on the web
// 2026-11-27, a 1172 wide pane): it takes the compose box's place while
// messages are being picked to forward. A 1 px colorNeutralStrokeAlpha
// line on top; padding 16 24 12, 24 48 20 from 480 px and 32 64 24 from
// 1024; the forward arrow (20) and "{n} selected" (14/20) at the start;
// Cancel (secondary) and Next (primary, off with nothing picked), 32 tall
// and 8 apart, at the end.
Rectangle {
    id: root
    property int count: 0
    signal cancelled()
    signal next()
    readonly property real padX: width >= 1024 ? 64 : width >= 480 ? 48 : 24
    readonly property real padTop: width >= 1024 ? 32 : width >= 480 ? 24 : 16
    readonly property real padBottom: width >= 1024 ? 24 : width >= 480 ? 20 : 12
    height: padTop + 32 + padBottom + 1
    color: theme.surface
    Rectangle { width: parent.width; height: 1; color: theme.pick(Qt.rgba(0, 0, 0, 0.05), Qt.rgba(1, 1, 1, 0.1), "#FFFFFF") }
    Row {
        x: root.padX; y: 1 + root.padTop; height: 32; spacing: 8
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "share-forward-20"; size: 20; color: theme.text }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("%1 selected").arg(root.count)
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
    Row {
        x: root.width - root.padX - width; y: 1 + root.padTop; spacing: 8
        Rectangle {
            id: hcFill1
            width: Math.max(65, cancelText.implicitWidth + 24); height: 32; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { id: cancelText; anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.text) }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.cancelled() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Cancel")
            Accessible.onPressAction: root.cancelled()
        }
        Rectangle {
            id: hcFill2
            readonly property bool on: root.count > 0
            width: Math.max(65, nextText.implicitWidth + 24); height: 32; radius: 4
            color: !on ? theme.hc(theme.bgDisabled, theme.hcHighlight) : nextHover.hovered ? theme.brandHover : theme.checkedFill
            Text { id: nextText; anchors.centerIn: parent; text: qsTr("Next"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, parent.on ? "white" : theme.disabledStrong) }
            HoverHandler { id: nextHover; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: hcFill2.on; onTapped: root.next() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Next")
            Accessible.onPressAction: if (hcFill2.on) root.next()
        }
    }
}
