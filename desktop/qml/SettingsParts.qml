import QtQuick

// The pieces Teams' Settings pages are built from (measured on winpc
// 2026-11-10, Settings ▸ General / Chats and channels):
// - Card: 0.67 #D1D1D1 border, radius 8, padding 20 x 12; its icon (20)
//   at 18.7, 26.7, its title (14/20) at 57, 27 and subtitle (12/16
//   #616161) under it; a single-setting card puts its control on the
//   title's row at the right. Its rows start 42 under the title (16 under
//   a subtitle), at x 57.
// - SwitchRow: 51 tall; the label (14/20) 8 down; "On"/"Off" (14) and a
//   40 x 20 Fluent switch whose right edge is 45 in from the card's.
// - CheckRow: 47 tall; a 16 px Fluent checkbox 8 down and the label 28 in.
// - RadioRow: 32 tall (48 with a second line, 12/16 #616161); a 16 px
//   Fluent radio and the label 28 in.
// - ImageRadio: a 169.3 x 130.3 (or 132) card, radius 4, #E0E0E0 border
//   and shadow2; its picture (140 wide) at 12.7, 14.7; the label (14,
//   #616161 unless chosen) and the radio glyph (20) along its bottom.
Item {
    id: parts

    component Card: Rectangle {
        id: card
        property string icon
        property string title
        property string subtitle
        /// A control on the title's row (single-setting cards).
        property Component trailing: null
        /// Its top, when it isn't centred on the header row (NaN: centred,
        /// as Teams does).
        property real trailingY: NaN
        /// The control's right margin (57; Teams' Add people box sits 12 in).
        property real trailingRight: 57
        default property alias body: bodyCol.data
        // Teams' layout (measured on winpc 2026-11-14): 20.7 padding top
        // and bottom; a header row at least 32 tall holding the title (and
        // subtitle) and the control, both centred on it (a switch counts as
        // its 36 px hit area); the body 16 under the header.
        readonly property real pad: 20.7
        readonly property real textHeight: titleText.height + (subtitle ? subText.height : 0)
        readonly property real controlHeight: trailingLoader.item ? (trailingLoader.item.height <= 20 ? 36 : trailingLoader.item.height) : 0
        readonly property real headerHeight: Math.max(32, textHeight, isNaN(trailingY) ? controlHeight : 0)
        readonly property real bodyTop: pad + headerHeight + 16
        // The body without its last row's gap (Teams pads 20.6 under the
        // last control itself).
        readonly property real bodyHeight: {
            let h = bodyCol.height
            for (let i = bodyCol.children.length - 1; i >= 0; i--) {
                const c = bodyCol.children[i]
                if (!c.visible || c.height <= 0) continue
                if (c.trailingGap !== undefined) h -= c.trailingGap
                break
            }
            return h
        }
        width: parent ? parent.width : 0
        height: Math.max(bodyCol.children.length ? bodyTop + bodyHeight : pad + headerHeight,
                         trailingLoader.item && !isNaN(trailingY) ? trailingY + trailingLoader.height : 0) + 20.6
        radius: 8
        color: "transparent"
        border.color: theme.pick("#D1D1D1", "#3D3D3D"); border.width: 0.67
        FluentIcon { x: 18.7; y: card.pad + (card.headerHeight - 20) / 2; name: card.icon; size: 20; color: theme.text }
        Text {
            id: titleText
            x: 57; y: card.pad + (card.headerHeight - card.textHeight) / 2
            width: card.width - 57 - (trailingLoader.item ? trailingLoader.width + 57 + 24 : 29)
            text: card.title
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            id: subText
            visible: !!card.subtitle
            x: 57; y: titleText.y + titleText.height; width: titleText.width
            text: card.subtitle
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
            textFormat: Text.StyledText
            linkColor: theme.brandForeground1
            onLinkActivated: l => card.linkActivated(l)
        }
        signal linkActivated(string link)
        Loader {
            id: trailingLoader
            anchors.right: parent.right; anchors.rightMargin: card.trailingRight
            y: isNaN(card.trailingY) ? card.pad + (card.headerHeight - height) / 2 : card.trailingY
            sourceComponent: card.trailing
        }
        Column {
            id: bodyCol
            x: 57; y: card.bodyTop
            width: card.width - 57 - 29
        }
        Accessible.role: Accessible.Grouping
        Accessible.name: title
    }

    component SubHeading: Text {
        property real gapAbove: 0
        width: parent ? parent.width : 0
        topPadding: gapAbove
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }

    // Fluent's Switch with Teams' "On"/"Off" before it.
    component Toggle: Item {
        id: tg
        property bool on
        property bool usable: true
        property string accessibleName
        /// "On" / "Off" before the switch (App permissions' switches have none).
        property bool stateLabel: true
        signal toggled(bool on)
        width: 40 + (stateLabel ? 12 + stateText.implicitWidth : 0); height: 20
        Text {
            id: stateText
            visible: tg.stateLabel
            anchors.verticalCenter: parent.verticalCenter
            text: tg.on ? "On" : "Off"
            font.family: theme.font; font.pixelSize: 14
            color: tg.usable ? theme.text : theme.disabled
        }
        Rectangle {
            anchors.right: parent.right
            width: 40; height: 20; radius: 10
            color: !tg.on ? "transparent" : !tg.usable ? theme.bgDisabled : th.hovered ? theme.brandHover : theme.brandFill
            border.width: tg.on ? 0 : 1
            border.color: !tg.usable ? theme.disabled : th.hovered ? theme.text : theme.textSecondary
            Rectangle {
                width: 14; height: 14; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: tg.on ? parent.width - width - 3 : 3
                color: tg.on ? (tg.usable ? "white" : theme.disabled) : (!tg.usable ? theme.disabled : th.hovered ? theme.text : theme.textSecondary)
                Behavior on x { NumberAnimation { duration: 100 } }
            }
            HoverHandler { id: th; cursorShape: tg.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: tg.usable; onTapped: tg.toggled(!tg.on) }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: accessibleName
        Accessible.checked: on
        Accessible.onToggleAction: if (usable) toggled(!on)
    }

    component SwitchRow: Item {
        id: sr
        property string label
        property string sublabel
        property bool on
        property bool usable: true
        /// The gap under the row's 36 px switch; a card's last row drops it.
        readonly property real trailingGap: 15
        signal toggled(bool on)
        width: parent ? parent.width : 0
        height: Math.max(51, labelCol.height + 15)
        Column {
            id: labelCol
            y: 8; width: parent.width - toggle.width - 24
            Text { width: parent.width; text: sr.label; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: sr.usable ? theme.text : theme.disabled }
            Text { visible: !!sr.sublabel; width: parent.width; text: sr.sublabel; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
        }
        Toggle {
            id: toggle
            anchors.right: parent.right; anchors.rightMargin: 28
            y: 8
            on: sr.on; usable: sr.usable; accessibleName: sr.label
            onToggled: v => sr.toggled(v)
        }
    }

    // Fluent's Checkbox, 16 px.
    component Box: Rectangle {
        id: bx
        property bool checked
        property bool usable: true
        property bool hovered: false
        width: 16; height: 16; radius: 2
        color: !checked ? "transparent" : !usable ? theme.bgDisabled : hovered ? theme.brandHover : theme.brandFill
        border.width: checked ? 0 : 1
        border.color: !usable ? theme.disabled : hovered ? theme.text : theme.textSecondary
        FluentIcon { visible: bx.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: bx.usable ? "white" : theme.disabled }
    }

    component CheckRow: Item {
        id: cr
        property string label
        /// A second line under the label (12 px NeutralForeground2).
        property string sublabel
        property bool checked
        property bool usable: true
        property real rowHeight: 47
        /// The gap under the 32 px checkbox; a card's last row drops it.
        readonly property real trailingGap: rowHeight >= 47 ? 15 : 0
        signal toggled(bool on)
        width: parent ? parent.width : 0
        height: Math.max(rowHeight, labelText.height + (subText.visible ? subText.height : 0) + 27)
        Box { y: 8; checked: cr.checked; usable: cr.usable; hovered: ch.hovered }
        Text { id: labelText; x: 28; y: 6; width: parent.width - 28; text: cr.label; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: cr.usable ? theme.text : theme.disabled }
        Text { id: subText; visible: !!cr.sublabel; x: 28; y: labelText.y + labelText.height; width: parent.width - 28; text: cr.sublabel; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
        HoverHandler { id: ch; cursorShape: cr.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: cr.usable; onTapped: cr.toggled(!cr.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.checked: checked
    }

    // Fluent's Radio, 16 px.
    component Dot: Rectangle {
        property bool checked
        property bool hovered: false
        width: 16; height: 16; radius: 8
        color: "transparent"
        border.width: 1
        border.color: checked ? theme.brandFill : hovered ? theme.text : theme.textSecondary
        Rectangle { visible: parent.checked; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brandFill }
    }

    component RadioRow: Item {
        id: rr
        property string label
        property string sublabel
        property bool checked
        /// Off: Teams' disabled radio (#BDBDBD).
        property bool usable: true
        signal picked()
        width: parent ? parent.width : 0
        height: sublabel ? 48 : 32
        Dot { y: 8; checked: rr.checked; hovered: rh.hovered; opacity: rr.usable ? 1 : 0.4 }
        Column {
            x: 28; y: 6; width: parent.width - 28
            Text { width: parent.width; text: rr.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: !rr.usable ? theme.disabled : rr.checked || rh.hovered ? theme.text : theme.textSecondary }
            Text { visible: !!rr.sublabel; width: parent.width; text: rr.sublabel; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: rr.usable ? theme.textSecondary : theme.disabled }
        }
        HoverHandler { id: rh; enabled: rr.usable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: rr.usable; onTapped: rr.picked() }
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: checked
    }

    component ImageRadio: Rectangle {
        id: ir
        property string label
        property string image
        property bool checked
        property real imageHeight: 77
        signal picked()
        width: 169.3; height: imageHeight + 53.3
        radius: 4
        color: theme.surface
        border.color: ih.hovered ? theme.pick("#C7C7C7", "#5C5C5C") : theme.pick("#E0E0E0", "#3D3D3D"); border.width: 0.67
        FluentSurface { anchors.fill: parent; z: -1; depth: 2; radius: 4; color: theme.surface }
        Image {
            x: 12.7; y: 14.7; width: 140; height: ir.imageHeight
            source: ir.image
            sourceSize: Qt.size(280, ir.imageHeight * 2)
            fillMode: Image.PreserveAspectFit
        }
        Text { x: 12.7; y: ir.imageHeight + 18.7; text: ir.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: ir.checked ? theme.text : theme.textSecondary }
        FluentIcon { x: 132.7; y: ir.imageHeight + 18.7; name: ir.checked ? "radio-button-20-filled" : "circle-20"; size: 20; color: ir.checked ? theme.brand : theme.textSecondary }
        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ir.picked() }
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: checked
    }

    // Fluent's secondary Button (96 x 31.3 at least).
    component Button: Rectangle {
        id: bt
        property string label
        /// Fluent's primary button (brand fill, white text).
        property bool primary: false
        signal clicked()
        width: Math.max(96, btText.implicitWidth + 24); height: 31.3; radius: 4
        color: primary ? (bh.pressed ? theme.pick("#444791", "#444791") : bh2.hovered ? theme.brandHover : theme.brandFill)
            : bh.pressed ? theme.menuHover : bh2.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : theme.surface
        border.color: primary ? "transparent" : theme.pick("#D1D1D1", "#5C5C5C"); border.width: 0.67
        Text { id: btText; anchors.centerIn: parent; text: bt.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: bt.primary ? "#FFFFFF" : theme.text }
        HoverHandler { id: bh2; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bh; onTapped: bt.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // A link-styled button (brand, 12 or 14 px).
    component Link: Text {
        id: lk
        signal clicked()
        font.family: theme.font; font.pixelSize: 14
        color: lh.hovered ? theme.brandHover : theme.brandForeground1
        font.underline: lh.hovered
        HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lk.clicked() }
        Accessible.role: Accessible.Link
        Accessible.name: text
    }

    component Gap: Item { property real size: 0; width: 1; height: size }

    /// Fluent's Divider between a card's rows (NeutralStroke2), as wide as
    /// Teams' (the card less 56.7 each side).
    component Divider: Item {
        width: parent ? parent.width : 0; height: 0.67
        Rectangle { width: parent.width - 27.3; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
    }

    /// A row with a title (14/20), an optional subtitle (12/16) and a
    /// button at its end, centred on the text (Teams' button widget).
    component ButtonRow: Item {
        id: brw
        property string label
        property string sublabel
        property string buttonText
        signal clicked()
        width: parent ? parent.width : 0
        height: Math.max(brCol.height, brBtn.height)
        Column {
            id: brCol
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - brBtn.width - 27.3 - 24
            Text { width: parent.width; text: brw.label; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { visible: !!brw.sublabel; width: parent.width; text: brw.sublabel; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
        }
        Button {
            id: brBtn
            anchors.right: parent.right; anchors.rightMargin: 27.3
            anchors.verticalCenter: parent.verticalCenter
            label: brw.buttonText
            onClicked: brw.clicked()
        }
    }
}
