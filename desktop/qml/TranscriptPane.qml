import QtQuick
import QtQuick.Controls

// Teams' in-meeting Transcript pane (calling-right-side-panel with the
// call-transcript-panel, measured in Teams on winpc, 2026-11-08): #F5F5F5,
// the rail header "Transcript" (16/22 bold, 20.67 in) with Language
// settings and close, then the transcript list (from y 145 under the live
// captions message bar, else under the header), its runway 10 in:
// - "AI-generated content may be incorrect" above the first row: the info
//   glyph (16, at 21.67) and the text (14/20, at 47.67), 12 down;
// - a transcript start or stop: the record glyph (16, #424242, at 21.67,
//   11 down) and "<name> started transcription" (14/20, at 47.67, 9
//   down), 31 tall;
// - someone's speech: their 32 px avatar (10.67 in, 13.19 down), their
//   name (12/600, at 52.67, 12.53 down), a guest's unverified glyph 4
//   after it, the time ("6:22 PM", 12/16 #616161) 8 after, and what they
//   said (14/20, at 52.67, 30.53 down, 259.33 wide); what they say next
//   follows without the header (9.2 down), until someone else speaks or
//   an event comes between; 2 below each.
// Teams lists the recognizer's final results, then each speaker's result
// still being recognized (replaced as it's refined, gone 5 s after it
// stops changing), and stays at the newest row
// unless you scroll up: then "Go to current" (primary, 125 x 28, 20 from
// the right and bottom) brings you back.
Rectangle {
    id: root
    /// [{id, kind, userId, name, text, atMs}], oldest first.
    property var entries: []
    /// The meeting's people ({id, name, guest, suspected}), for avatars and
    /// the names stored rows leave out.
    property var roster: []
    /// You (your MRI and name), for the same.
    property string meId: ""
    property string meName: ""
    /// Live captions are available (the message bar offers them).
    property bool captionsAvailable: false
    /// Show the service's filtered words (Filter profane words): its
    /// `text`, else the unmasked `rawText` where the store has it.
    property bool filterProfanity: false
    /// Language and speech settings are available (the header button).
    property bool languageSettingsAvailable: false
    signal closed()
    signal switchToCaptions()
    signal languageSettings()
    color: theme.pane

    property bool barDismissed: false
    readonly property bool barShown: captionsAvailable && !barDismissed

    // Someone by id: the store names a guest "8:orgid:<guid>" where the
    // meeting has them as "8:teamsvisitor:<guid without dashes>", so ids
    // match on their last part.
    function canon(id) {
        const v = (id || "").toLowerCase()
        return v.slice(v.lastIndexOf(":") + 1).replace(/-/g, "")
    }
    function person(id) {
        const want = canon(id)
        if (!want) return null
        for (const p of roster) if (canon(p.id) === want) return p
        return null
    }
    // A row's name, or (stored without one) the person's as the meeting
    // knows them, as Teams' transcript resolver fills it in.
    function nameOf(e) {
        if (e.name) return e.name
        if ((e.userId || "").toLowerCase() === meId.toLowerCase()) return meName
        const p = person(e.userId)
        return p ? (p.name || "") : ""
    }
    function isGuest(id) {
        const p = person(id)
        return p ? !!p.guest : (id || "").startsWith("8:teamsvisitor:")
    }
    function escaped(t) {
        return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    function timeText(ms) { return Qt.formatTime(new Date(ms), "h:mm AP") }

    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 16.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: "Transcript"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            visible: root.languageSettingsAvailable
            x: parent.width - 84; y: 13; width: 32; height: 31.33; radius: 4
            color: langHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "translate-auto-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: langHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.languageSettings() }
            ToolTip.visible: langHover.hovered
            ToolTip.delay: 250
            ToolTip.text: "Language settings"
            Accessible.role: Accessible.Button
            Accessible.name: "Language settings"
        }
        Rectangle {
            x: parent.width - 52; y: 13; width: 32; height: 31.33; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            ToolTip.visible: closeHover.hovered
            ToolTip.delay: 250
            ToolTip.text: "Close"
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // "Follow the conversation better in real time by using live
    // captions." with Switch to live captions (Teams' captions redirection
    // message bar, 84 tall).
    Item {
        id: bar
        visible: root.barShown
        anchors.top: header.bottom
        width: parent.width; height: visible ? 84 : 0
        FluentIcon { x: 12.67; y: 10; name: "info-20-filled"; size: 20; color: theme.textSecondary }
        Text {
            x: 40.67; y: 10; width: 283.33
            text: "Follow the conversation better in real time by using live captions."
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            x: 324; y: 10.83; width: 24; height: 23.33; radius: 4
            color: dismissHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.barDismissed = true }
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss"
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 12
            y: 55; height: 23.33; width: switchText.implicitWidth + 16; radius: 4
            color: switchHover.hovered ? theme.menuHover : theme.surface
            border.width: 0.67; border.color: switchHover.hovered ? theme.strokeHover : theme.stroke
            Text {
                id: switchText
                anchors.centerIn: parent
                text: "Switch to live captions"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.text
            }
            HoverHandler { id: switchHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.switchToCaptions() }
            Accessible.role: Accessible.Button
            Accessible.name: switchText.text
        }
    }

    ListView {
        id: list
        anchors { top: bar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Accessible.role: Accessible.List
        Accessible.name: "Transcript"

        // Teams follows the newest row while you're at the bottom (rows
        // settle their height after they're added, so follow the content).
        property bool following: true
        onMovementEnded: following = atYEnd
        onCountChanged: if (following) Qt.callLater(positionViewAtEnd)
        onContentHeightChanged: if (following) Qt.callLater(positionViewAtEnd)
        onHeightChanged: if (following) Qt.callLater(positionViewAtEnd)
        Component.onCompleted: positionViewAtEnd()

        header: Item {
            visible: list.count > 0
            width: list.width; height: visible ? 32 : 0
            FluentIcon { x: 21.67; y: 14; name: "info-16-regular"; size: 16; color: theme.textStrong }
            Text {
                x: 47.67; y: 12; height: 20
                verticalAlignment: Text.AlignVCenter
                text: "AI-generated content may be incorrect"
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var prev: index > 0 ? root.entries[index - 1] : null
            readonly property bool speech: modelData.kind === "speech"
            // A partial (still being recognized) always shows who's speaking.
            readonly property bool first: speech && (!modelData.isFinal || !prev || prev.kind !== "speech" || prev.userId !== modelData.userId)
            readonly property real textTop: !speech ? 9 : first ? 30.53 : 9.2
            width: list.width
            height: textTop + (speech ? message.height : 20) + 2

            // A transcript start or stop.
            FluentIcon {
                visible: !row.speech
                x: 21.67; y: 11
                name: "record-20"; size: 16; color: theme.textStrong
            }
            Text {
                visible: !row.speech
                x: 47.67; y: 9; height: 20
                verticalAlignment: Text.AlignVCenter
                text: row.modelData.kind === "started"
                    ? root.nameOf(row.modelData) + " started transcription"
                    : root.nameOf(row.modelData) + " stopped transcription"
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }

            // Speech: avatar and name over a run of what someone said.
            Avatar {
                visible: row.first
                x: 10.67; y: 13.19; size: 32
                name: root.nameOf(row.modelData)
                photoId: row.speech && !root.isGuest(row.modelData.userId) ? row.modelData.userId : ""
            }
            Row {
                visible: row.first
                x: 52.67; y: 12.53; height: 16
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 200)
                    elide: Text.ElideRight
                    text: root.nameOf(row.modelData)
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.text
                }
                Item { visible: guestGlyph.visible; width: 4; height: 1 }
                FluentIcon {
                    id: guestGlyph
                    visible: row.speech && root.isGuest(row.modelData.userId)
                    anchors.verticalCenter: parent.verticalCenter
                    name: "person-unverified-16-filled"; size: 16; color: theme.text
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Unverified"
                }
                Item { width: 8; height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.timeText(row.modelData.atMs)
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.textSecondary
                }
            }
            // Selectable, as Teams' is; 20 px lines.
            TextEdit {
                id: message
                visible: row.speech
                x: 52.67; y: row.textTop; width: 259.33
                height: row.speech ? implicitHeight : 0
                readOnly: true
                selectByMouse: true
                selectionColor: theme.selectionFill
                selectedTextColor: theme.text
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                text: row.speech
                    ? "<style>p { line-height: 20px; -qt-line-height-type: fixed; margin: 0; }</style><p>"
                      + root.escaped(root.filterProfanity ? (row.modelData.text || row.modelData.rawText || "")
                                                          : (row.modelData.rawText || row.modelData.text || "")) + "</p>"
                    : ""
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: speech ? (root.nameOf(modelData) + ", " + root.timeText(modelData.atMs) + ": " + modelData.text) : ""
        }
    }

    /// Scroll to the oldest row, as a reader scrolling up would (tests).
    function scrollToTopForTest() { list.following = false; list.positionViewAtBeginning() }

    // Back to the newest row after scrolling up.
    Rectangle {
        visible: list.contentHeight > list.height && !list.atYEnd
        anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 20 }
        width: goRow.implicitWidth + 13; height: 28; radius: 4
        color: goHover.hovered ? theme.brandHover : theme.brandFill
        Row {
            id: goRow
            x: 5; anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-down-20-filled"; size: 20; color: theme.textOnBrand }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Go to current"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.textOnBrand
            }
        }
        HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                list.following = true
                list.positionViewAtEnd()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Go to current"
    }
}
