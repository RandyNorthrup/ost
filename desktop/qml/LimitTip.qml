import QtQuick
import QtQuick.Controls.Basic

// Teams' reaction-limit-tooltip.
ToolTip {
    delay: 500
    y: -height - 4; padding: 8
    background: FluentSurface { depth: 16; radius: 4 }
    contentItem: Text { text: qsTr("You’ve reached the %1-reaction limit. Remove one to add another.").arg(20); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
}
