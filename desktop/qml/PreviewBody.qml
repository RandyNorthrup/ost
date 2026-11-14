import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Pdf

// A file's preview as OneDrive's viewer draws it (backend driveAction
// "preview": {kind: text | image | pdf | none, text?, path?}).
// - The Preview's dark style (FilePreview): text on a white page 75% wide
//   with a 30 px name strip; pictures fitted; PDF pages (Office files as
//   PDF) with "PAGE n OF m".
// - `embedded`: OneDrive's embed.aspx as Teams shows a message's file
//   (measured on winpc 2026-11-13): #FAF9F8 behind; the name strip (white,
//   30 tall, 20 in from each side, the name 14 px black at 10, 6) over the
//   text editor (#FFFFFE, 1 in from the strip's sides and 21 above the
//   bottom): line numbers right-aligned in 38 (Consolas 14/19; the current
//   line's #0B216F, others #237893), the text at 64 (Consolas 14/19 black)
//   and the current line framed 2 px #EEEEEE.
Item {
    id: root
    property var preview: null
    property string name: ""
    property string kind: ""
    property bool loading: false
    property string error: ""
    property string iconName: ""
    property string appIconName: ""
    property color ink: "#F3F2F1"
    property bool embedded: false
    readonly property int pageCount: pdf.pageCount
    readonly property bool isText: !!preview && preview.kind === "text"

    Rectangle { visible: root.embedded; anchors.fill: parent; color: "#FAF9F8" }

    // Text: the Preview's page
    Rectangle {
        visible: root.isText && !root.embedded
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.75; height: parent.height
        color: "#FFFFFE"
        Text {
            x: 15; height: 30; verticalAlignment: Text.AlignVCenter
            text: root.name
            font.family: theme.font; font.pixelSize: 14; color: "#242424"
        }
        ListView {
            id: lines
            x: 0; y: 30; width: parent.width; height: parent.height - 30
            clip: true
            model: root.isText && !root.embedded ? root.preview.text.split("\n") : []
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                required property string modelData
                required property int index
                width: lines.width; height: Math.max(19, lt.implicitHeight)
                Text { width: 52; horizontalAlignment: Text.AlignRight; text: index + 1; font.family: theme.mono; font.pixelSize: 14; color: "#237893" }
                Text { id: lt; x: 72; width: parent.width - 72 - 16; text: modelData.replace(/\r$/, ""); wrapMode: Text.WrapAnywhere; font.family: theme.mono; font.pixelSize: 14; lineHeight: 19; lineHeightMode: Text.FixedHeight; color: "#000000"; textFormat: Text.PlainText }
            }
        }
    }
    // Text: OneDrive's embedded viewer
    Rectangle {
        visible: root.isText && root.embedded
        x: 20; y: 20; width: parent.width - 40; height: 31
        color: "#FFFFFF"
        Text {
            x: 10; y: 6
            text: root.name
            font.family: theme.font; font.pixelSize: 14; color: "#000000"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
    }
    Rectangle {
        visible: root.isText && root.embedded
        x: 21; y: 51; width: parent.width - 42; height: Math.max(0, parent.height - 72)
        color: "#FFFFFE"
        ListView {
            id: editorLines
            anchors.fill: parent
            clip: true
            model: root.isText && root.embedded ? root.preview.text.split("\n") : []
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            contentWidth: Math.max(width, 64 + widest.advanceWidth + 20)
            flickableDirection: Flickable.AutoFlickIfNeeded
            delegate: Item {
                required property string modelData
                required property int index
                width: editorLines.contentWidth; height: 19
                Rectangle {
                    visible: parent.index === 0
                    x: 64; width: editorLines.width - 64; height: 19
                    color: "transparent"; border.width: 2; border.color: "#EEEEEE"
                }
                Text { width: 38; height: 19; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: parent.index + 1; font.family: theme.mono; font.pixelSize: 14; color: parent.index === 0 ? "#0B216F" : "#237893" }
                Text { x: 64; height: 19; verticalAlignment: Text.AlignVCenter; text: parent.modelData.replace(/\r$/, ""); font.family: theme.mono; font.pixelSize: 14; color: "#000000"; textFormat: Text.PlainText }
            }
            TextMetrics {
                id: widest
                font.family: theme.mono; font.pixelSize: 14
                text: root.isText ? root.preview.text.split("\n").reduce((a, l) => l.length > a.length ? l : a, "") : ""
            }
        }
        Accessible.role: Accessible.EditableText
        Accessible.name: "Editor content"
    }
    // A picture, fitted.
    Image {
        visible: !!root.preview && root.preview.kind === "image"
        anchors.fill: parent; anchors.margins: root.embedded ? 20 : 24
        source: root.preview && root.preview.kind === "image" ? root.preview.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    // PDF pages (and Office files as PDF), with the status line.
    PdfDocument { id: pdf; source: root.preview && root.preview.kind === "pdf" ? root.preview.path : "" }
    ListView {
        id: pages
        visible: !!root.preview && root.preview.kind === "pdf"
        x: 0; y: 10; width: parent.width; height: parent.height - 10 - 22
        clip: true; spacing: 10
        model: visible ? pdf.pageCount : 0
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property real pageWidth: Math.min(818, width - 80)
        delegate: Item {
            required property int index
            width: pages.width
            height: page.height
            PdfPageImage {
                id: page
                anchors.horizontalCenter: parent.horizontalCenter
                document: pdf
                currentFrame: parent.index
                width: pages.pageWidth
                height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : width * 1.294
                sourceSize.width: width * 2
                fillMode: Image.PreserveAspectFit
                Rectangle { anchors.fill: parent; z: -1; color: "white" }
            }
        }
    }
    Rectangle {
        visible: pages.visible
        anchors.bottom: parent.bottom; width: parent.width; height: 22
        color: "#2B2B2B"
        FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 16; name: root.appIconName }
        Text {
            x: 46; anchors.verticalCenter: parent.verticalCenter
            text: "PAGE " + (Math.min(pdf.pageCount, pages.indexAt(10, pages.contentY + 10) + 1) || 1) + " OF " + pdf.pageCount
            font.family: theme.font; font.pixelSize: 11; color: "#FFFFFF"
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 104; anchors.verticalCenter: parent.verticalCenter
            text: "100%"
            font.family: theme.font; font.pixelSize: 11; color: "#FFFFFF"
        }
    }
    // No preview
    Column {
        visible: !root.loading && (!!root.error || (!!root.preview && root.preview.kind === "none"))
        anchors.centerIn: parent; spacing: 12
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 32; name: root.iconName }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.error || "No preview available"; font.family: theme.font; font.pixelSize: 16; color: root.embedded ? "#323130" : root.ink }
    }
    BusyIndicator { anchors.centerIn: parent; running: root.loading; visible: root.loading }
}
