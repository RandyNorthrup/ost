import QtQuick
import QtQuick.Controls

// Teams' "Share with all participants?" before Excel Live (calling-app's
// meeting files consent dialog; measured on winpc 2026-11-18): 400 x 235,
// radius 8, over a 40 % black backdrop. The 20/28 semibold title at 24.67
// with a 32 x 31.33 Close (16 px glyph) at its end; "Everyone invited to
// this meeting will be able to access this file. Learn more" (14/20) at
// 64; the file as a 350.67 x 48 card at 119 (#FAFAFA, radius 6, a soft
// shadow): its 32 px icon 12.67 in, the name (14/20 semibold) and "People
// invited to this meeting can edit" (10/14) 52.67 in; Cancel and Share
// (96 x 31.33, 8 apart) at 179, ending 24.67 from the right.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 400; height: 235
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property string fileName: ""
    property string icon: "ft-xlsx-32"
    property string learnMoreUrl: ""
    signal confirmed()

    Text {
        x: 24.67; y: 24.67; width: 310.67; height: 31.33
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: qsTr("Share with all participants?")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Rectangle {
        id: closeFill
        x: 343.33; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(closeFill, theme.textSecondary) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close")
    }
    Text {
        x: 24.67; y: 64; width: 350.67
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        textFormat: Text.RichText
        text: "<style>a { color: " + theme.brandForeground1 + "; }</style>" + qsTr("Everyone invited to this meeting will be able to access this file.") + " "
              + (root.learnMoreUrl ? "<a href=\"" + root.learnMoreUrl + "\">" + qsTr("Learn more") + "</a>" : qsTr("Learn more"))
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
    FluentSurface {
        x: 24.67; y: 119; width: 350.67; height: 48
        depth: 2; radius: 6
        color: theme.pick("#FAFAFA", "#292929", "#000000")
        FluentIcon { x: 12.67; y: 8; size: 32; name: root.icon; color: "transparent" }
        Text {
            x: 52.67; y: 7; width: 293.33; height: 20
            elide: Text.ElideRight
            text: root.fileName
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.text
        }
        Text {
            x: 52.67; y: 27; width: 293.33; height: 14
            elide: Text.ElideRight
            text: qsTr("People invited to this meeting can edit")
            font.family: theme.font; font.pixelSize: 10
            color: theme.text
        }
    }
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        signal clicked()
        y: 179; width: 96; height: 31.33; radius: 4
        color: primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill) : (dbHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
        Text {
            anchors.centerIn: parent
            text: db.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(db, db.primary ? theme.textOnBrand : theme.text)
        }
        HoverHandler { id: dbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: db.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: db.label
    }
    DialogButton { x: 175.33; label: qsTr("Cancel"); onClicked: root.close() }
    DialogButton { x: 279.33; label: qsTr("Share"); primary: true; onClicked: { root.close(); root.confirmed() } }
}
