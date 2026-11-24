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
// - Recent-file suggestions (measured 2026-11-16, when ost-test1 had
//   one): "Recent cloud files" (14/20 600 at 8.2, 44.7), then 52 px rows
//   from 12.2, 74.7 (282.2 wide, radius 4, #F5F5F5 on hover with the name
//   in the brand colour): the 20 px type icon at 4.5, 15, the name (14/17)
//   at 34.5, 7.6 and "Opened {time} ago" (12/18 #616161) at 34.5, 23.6;
//   the time is date-fns' strict distance ("4 days"). Search results use
//   the same rows without the heading (their rows weren't seen yet).
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
    /// Open above the anchor at its end (a suggested reply's Share a file,
    /// Teams' "above-end"), until closed.
    property bool alignEnd: false
    onClosed: alignEnd = false
    x: anchorItem ? Math.max(8, Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + (alignEnd ? anchorItem.width - 4 - width : anchorItem.width / 2 - width / 2))) : 0
    y: anchorItem ? Math.max(8, anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height) : 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    readonly property string tag: "attachmenu:"
    property int seq: 0
    property string query: ""
    property bool loading: false
    property var hits: []
    readonly property var items: [
        { key: "cloud", label: qsTr("Attach cloud files"), icon: "teams-attach-cloud-20", size: 14 },
        { key: "browse", label: qsTr("Browse Teams and Channels"), icon: "people-team-20", size: 16, hidden: !channel },
        { key: "upload", label: qsTr("Upload from this device"), icon: "arrow-upload-20", size: 16 }
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
        color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
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
            Text { visible: !field.text; text: qsTr("Search cloud files"); font: field.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: qsTr("Search cloud files")
        }
        Rectangle {
            id: clear
            visible: !!field.text
            x: 250.3; y: 4.3; width: 24; height: 23.3; radius: 4
            color: clearHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { x: 2; y: 1.7; name: "dismiss-20"; size: 20; color: theme.onFill(clear, theme.textStrong) }
            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { field.text = ""; field.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Clear search")
        }
    }

    // Recent-file suggestions or search results.
    Text {
        visible: pop.hits.length > 0 && !pop.query
        x: 8.2; y: 44.7; height: 25; verticalAlignment: Text.AlignVCenter
        text: qsTr("Recent cloud files")
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    ListView {
        id: list
        visible: pop.hits.length > 0
        x: 12.2; y: pop.query ? 49.7 : 74.7; width: 282.2; height: (pop.noResults ? pop.height : pop.lineY) - y - 8
        clip: true
        model: pop.hits
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: hit
            required property var modelData
            width: list.width; height: 52; radius: 4
            color: hitHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
            FluentIcon { x: 4.5; y: 15; size: 20; name: pop.typeIcon(hit.modelData.kind).replace("-32", "-20") }
            Text {
                x: 34.5; y: 7.6; width: parent.width - x - 8; height: 17
                text: hit.modelData.name; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14
                color: theme.onFill(hit, hitHover.hovered ? theme.pick("#5B5FC7", "#7F85F5", "#000000") : theme.text)
            }
            Text {
                x: 34.5; y: 23.6; width: parent.width - x - 8; height: 18
                text: hit.modelData.opened_ago || hit.modelData.location || ""; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hit, theme.pick("#616161", "#ADADAD", "#000000"))
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
                text: qsTr("Your recent files suggestions will show up here soon.")
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
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
            text: qsTr("We couldn't find any results")
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            y: 274.2; width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: qsTr("Check for spelling or try another search keyword")
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 12; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
        }
        Column {
            y: 306.2; width: parent.width
            spacing: 12
            Repeater {
                model: [{ key: "upload", label: qsTr("Upload from this device"), icon: "arrow-upload-16" },
                        { key: "cloud", label: qsTr("Attach cloud files"), icon: "cloud-16" }]
                Rectangle {
                    id: nb
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: nbLabel.implicitWidth + 16 + 26.7; height: 23.3; radius: 4
                    color: nbHover.hovered ? theme.menuHover : "transparent"
                    border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    FluentIcon { x: 10.7; anchors.verticalCenter: parent.verticalCenter; name: nb.modelData.icon; size: 16; color: theme.onFill(nb, theme.text) }
                    Text {
                        id: nbLabel
                        x: 32.7; anchors.verticalCenter: parent.verticalCenter
                        text: nb.modelData.label
                        font.family: theme.font; font.pixelSize: 12; color: theme.onFill(nb, theme.text)
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
                name: row.modelData.icon; size: row.modelData.size; color: theme.onFill(row, theme.pick("#424242", "#D6D6D6", "#FFFFFF"))
            }
            Text {
                x: 35; anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(row, theme.pick("#424242", "#D6D6D6", "#FFFFFF"))
            }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pop.act(row.modelData.key) }
            Accessible.role: Accessible.MenuItem
            Accessible.name: modelData.label
        }
    }

    /// Tests: the popover's state.
    function stateForTest() {
        return { query: query, loading: loading, hits: hits.length, rows: hits.map(h => h.name + " | " + (h.opened_ago || "")), noResults: noResults, items: items.map(i => i.label), x: x, y: y, lineY: lineY }
    }
    function searchForTest(q) { field.text = q }
}
