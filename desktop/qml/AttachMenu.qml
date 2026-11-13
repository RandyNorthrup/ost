import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

// Teams' Attach popover (916609), measured on winpc 2026-11-13 (OST group
// test; the OST layout test channel): 305 x 437, white, radius 4, centred
// on the Attach button with its bottom at the button's top.
// - "Search cloud files" (285 x 32 at 10, 7; #F5F5F5, radius 4, 2 px brand
//   underline while focused; a 20 px search glyph at 10.7, the text at
//   32.7; Clear search 24 x 23.3 at 250.3 when there is text).
// - Without a query, Teams' recent-file suggestions (substrate
//   recommendations); none yet shows document-clock-l-standard (120 px)
//   over "Your recent files suggestions will show up here soon." (14/20
//   #424242, 200 wide, centred), both centred between the box and the
//   line.
// - A query searches (substrate suggestions); none found shows
//   search-exclamation (120) over "We couldn't find any results" (16/22
//   600) and "Check for spelling or try another search keyword" (12/16
//   #424242), then "Upload from this device" and "Attach cloud files"
//   (12 px, 23.3 tall, 0.67 #D1D1D1, radius 4, a 16 px icon), and no item
//   list.
// - A 0.67 line, then the items (283 x 28, 32 apart, 11 in; the label
//   14/600 #424242 at 35, its glyph at 8): Attach cloud files (Teams'
//   cloud, 14 px), Browse Teams and Channels in a channel (people-team,
//   16), Upload from this device (arrow-upload, 16); the last ends 9.4
//   above the bottom.
// The suggestions' rows weren't measured (ost-test1 has none); OST draws
// each as the picker's Home does: its type icon, name and location.
Popup {
    id: pop
    property Item anchorItem: null
    /// A channel adds Browse Teams and Channels.
    property bool channel: false
    property string chatId: ""
    /// The conversation's last messages ({id, text, sender, time}), for
    /// Teams' suggestions.
    property var context: []
    signal attachCloud()
    signal browseChannels()
    signal upload()
    /// A suggested file (its name, kind and address).
    signal picked(var file)

    parent: Overlay.overlay
    width: 305; height: 437; padding: 0
    x: anchorItem ? Math.max(8, Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width / 2 - width / 2)) : 0
    y: anchorItem ? Math.max(8, anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height) : 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    readonly property string tag: "attachmenu:"
    property int seq: 0
    property string query: ""
    property bool loading: false
    property var hits: []
    readonly property var items: [
        { key: "cloud", label: "Attach cloud files", icon: "teams-attach-cloud-20", size: 14 },
        { key: "browse", label: "Browse Teams and Channels", icon: "people-team-20", size: 16, hidden: !channel },
        { key: "upload", label: "Upload from this device", icon: "arrow-upload-20", size: 16 }
    ].filter(i => !i.hidden)
    readonly property bool noResults: !!query && !loading && hits.length === 0
    readonly property real firstRowY: 399.6 - (items.length - 1) * 32
    readonly property real lineY: firstRowY - 9.3

    function ask() {
        seq++
        loading = true
        backend.driveAction(tag + seq + ":attach_suggest", "{}", JSON.stringify({ query: query, chat_id: chatId, context: context }))
    }
    onOpened: { field.text = ""; query = ""; hits = []; ask(); field.forceActiveFocus() }
    function act(key) {
        close()
        if (key === "cloud") attachCloud()
        else if (key === "browse") browseChannels()
        else upload()
    }
    Timer { id: typing; interval: 300; onTriggered: { pop.query = field.text.trim(); pop.ask() } }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (op !== pop.tag + pop.seq + ":attach_suggest") return
            pop.loading = false
            const v = result ? JSON.parse(result) : null
            pop.hits = v && v.items ? v.items : []
        }
    }

    Rectangle {
        id: box
        x: 10; y: 7; width: 285; height: 32; radius: 4
        color: theme.pick("#F5F5F5", "#1F1F1F")
        Rectangle {
            anchors.bottom: parent.bottom; x: 0.67; width: parent.width - 1.33
            height: field.activeFocus ? 2 : 0.67; radius: 1
            color: field.activeFocus ? theme.brand : theme.textSecondary
        }
        FluentIcon { x: 10.7; y: 6; name: "search-20"; size: 20; color: theme.textSecondary }
        TextInput {
            id: field
            x: 32.7; width: (clear.visible ? clear.x : parent.width - 8) - x
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
            selectByMouse: true
            onTextChanged: typing.restart()
            Text { visible: !field.text; text: "Search cloud files"; font: field.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Search cloud files"
        }
        Rectangle {
            id: clear
            visible: !!field.text
            x: 250.3; y: 4.3; width: 24; height: 23.3; radius: 4
            color: clearHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { x: 2; y: 1.7; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { field.text = ""; field.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear search"
        }
    }

    // Recent-file suggestions or search results.
    ListView {
        id: list
        visible: pop.hits.length > 0
        x: 0; y: 44; width: pop.width; height: (pop.noResults ? pop.height : pop.lineY) - y
        clip: true
        model: pop.hits
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: hit
            required property var modelData
            width: list.width; height: 56
            color: hitHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { x: 16; y: 12; size: 32; name: pop.typeIcon(hit.modelData.kind) }
            Text {
                x: 60; y: 9.8; width: parent.width - x - 16
                text: hit.modelData.name; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Text {
                x: 60; y: 29.5; width: parent.width - x - 16
                text: hit.modelData.location || ""; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
            }
            HoverHandler { id: hitHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { pop.close(); pop.picked(hit.modelData) } }
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name
        }
    }
    function typeIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }

    // No recent suggestions yet.
    Item {
        visible: !pop.query && !pop.loading && pop.hits.length === 0
        y: 44; width: pop.width; height: pop.lineY - 44
        Column {
            anchors.centerIn: parent
            spacing: 8
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120; height: 120; sourceSize: Qt.size(240, 240)
                source: "../assets/illustrations/document-clock-l-standard.svg"
            }
            Text {
                width: 200; anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: "Your recent files suggestions will show up here soon."
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6")
            }
        }
    }

    // Nothing found.
    Item {
        visible: pop.noResults
        anchors.fill: parent
        Image {
            x: 92.3; y: 116.2; width: 120; height: 120; sourceSize: Qt.size(240, 240)
            source: "../assets/illustrations/search-exclamation-l-standard.svg"
        }
        Text {
            y: 244.2; width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "We couldn't find any results"
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            y: 274.2; width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "Check for spelling or try another search keyword"
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 12; color: theme.pick("#424242", "#D6D6D6")
        }
        Column {
            y: 306.2; width: parent.width
            spacing: 12
            Repeater {
                model: [{ key: "upload", label: "Upload from this device", icon: "arrow-upload-16" },
                        { key: "cloud", label: "Attach cloud files", icon: "cloud-16" }]
                Rectangle {
                    id: nb
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: nbLabel.implicitWidth + 16 + 26.7; height: 23.3; radius: 4
                    color: nbHover.hovered ? theme.menuHover : "transparent"
                    border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                    FluentIcon { x: 10.7; anchors.verticalCenter: parent.verticalCenter; name: nb.modelData.icon; size: 16; color: theme.text }
                    Text {
                        id: nbLabel
                        x: 32.7; anchors.verticalCenter: parent.verticalCenter
                        text: nb.modelData.label
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                    }
                    HoverHandler { id: nbHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pop.act(nb.modelData.key) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
        }
    }

    Rectangle {
        visible: !pop.noResults
        y: pop.lineY; width: pop.width; height: Math.max(0.67, 1 / Screen.devicePixelRatio)
        color: theme.divider
    }
    Repeater {
        model: pop.noResults ? [] : pop.items
        Rectangle {
            id: row
            required property var modelData
            required property int index
            x: 11; y: pop.firstRowY + index * 32; width: 283; height: 28; radius: 4
            color: rowHover.hovered ? theme.menuHover : "transparent"
            FluentIcon {
                x: row.modelData.size === 14 ? 8 : 7
                anchors.verticalCenter: parent.verticalCenter
                name: row.modelData.icon; size: row.modelData.size; color: theme.pick("#424242", "#D6D6D6")
            }
            Text {
                x: 35; anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#424242", "#D6D6D6")
            }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pop.act(row.modelData.key) }
            Accessible.role: Accessible.MenuItem
            Accessible.name: modelData.label
        }
    }

    /// Tests: the popover's state.
    function stateForTest() {
        return { query: query, loading: loading, hits: hits.length, noResults: noResults, items: items.map(i => i.label), x: x, y: y, lineY: lineY }
    }
    function searchForTest(q) { field.text = q }
}
