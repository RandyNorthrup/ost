import QtQuick
import QtQuick.Controls.Basic

// Teams' reaction-limit-tooltip.
ToolTip {
    delay: 500
    y: -height - 4; padding: 8
    background: FluentSurface { depth: 16; radius: 4 }
    contentItem: Text { text: "You\u2019ve reached the 20-reaction limit. Remove one to add another."; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
}
