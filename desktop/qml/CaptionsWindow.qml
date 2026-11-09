import QtQuick
import QtQuick.Controls.Basic

// Teams' live captions window (closed-caption-renderer-wrapper, captions
// v2; measured on winpc, 2026-11-09): a strip 4 px in from the window's
// sides and bottom under the stage (or over it, "At top"), in the caption
// styles' background colour, its height by Panel height (Small / Medium /
// Large: 118 / 132 / 148 px in windows up to 682 px tall, else 22 / 43 /
// 72.5 % of the area under the bar).
// - The captions list is centred, 550 / 620 / 870 / 1000 px wide by Font
//   size (Small / Medium / Large / Extra large), at most 75 px narrower
//   than the strip (then flush left); it scrolls, newest at the bottom.
// - A caption: 2 px above; the speaker's 32 px avatar 8 in and 4 down; the
//   name (10/14, 12/16, 14/20, 16/22 semibold) and a guest's unverified
//   glyph 4 after it; the words (12/16, 16/22, 24/32, 28/36) at 52, 15
//   down; 2 px below (39 / 61 / 83 tall for 1 / 2 / 3 lines at Medium).
//   Every caption carries its speaker, one after another from the same
//   person too (as Teams showed them, sampled for 90 s). The words are in
//   the caption font colour.
// - Before any caption: "Captions will be shown in English (US)."
// - Its buttons, 32 px, 6 down and 8 from the right: caption settings and
//   Hide live captions; when they don't fit beside the list, settings
//   folds into "…".
// - While RTT is on (rtt-*, measured 2026-11-09): only "…"; the list opens
//   on the RTT card (596 wide, 9 in and 7 down, padding 12, radius 4, a
//   card shadow: "RTT" 14/20 bold, then the notice with its privacy link);
//   RTT lines show as captions do, one being typed with a 1.33 px brand
//   line 12 in (40 tall, 8 down), the row 14.67 further in and "RTT
//   Typing" (the name's size, semibold) 12 after the name; the RTT box is
//   under the list (its width, 6 above the bottom; 38 px for it). In the
//   window of its own the box is 23 in and 24 from the right, the list
//   10 above it.
Rectangle {
    id: root
    /// Live captions: [{id, userId, name, text, rawText, isFinal}].
    property var captions: []
    property var roster: []
    property string meId: ""
    property string meName: ""
    /// Show the service's filtered words (Filter profane words).
    property bool filterProfanity: false
    property string languageName: "English (US)"
    /// Caption styles: {fontColor, backgroundColor, fontSize, captionHeight}.
    property var styles: ({})
    /// How tall the window and the area under the bar are (Panel height).
    property real windowHeight: 0
    property real areaHeight: 0
    signal closed()
    signal settingsRequested(Item anchor)
    signal popOut()
    /// In the captions window of its own: no buttons, the list 15 in.
    property bool popout: false
    /// Real-time text is on: the RTT box shows under the list.
    property bool rttOn: false
    /// You turned RTT on (the card says "by you").
    property bool rttInitiator: false
    property string privacyUrl: ""
    /// A meeting rather than a call (the card's wording).
    property bool isMeeting: true
    readonly property Item rttBoxForTest: rttBox
    /// Room under the list: the RTT box (and its message bar), or the
    /// window of its own's bottom margin.
    readonly property real boxSpace: rttOn ? 6 + rttBox.height + (popout ? 10 : 0) : (popout ? 10 : 0)
    readonly property Item settingsAnchorForTest: settingsButton

    readonly property bool lightTheme: theme.pick(true, false)
    readonly property string fontColorName: styles.fontColor || (lightTheme ? "Black" : "White")
    readonly property string backgroundName: styles.backgroundColor || (lightTheme ? "White" : "Black")
    readonly property string fontSize: styles.fontSize || "Medium"
    readonly property string captionHeight: styles.captionHeight || "Medium"
    // Teams' swatch colours.
    function swatch(name) {
        return ({ White: "#FFFFFF", Black: "#000000", Red: "#FE0000", Green: "#00FF00",
                  Blue: "#0000FF", Yellow: "#FFFF00", Aqua: "#00FFFF" })[name] || "#FFFFFF"
    }
    // Light backgrounds (Teams' w0 list) take dark buttons.
    readonly property bool lightBackground: ["White", "Yellow", "Green", "Aqua"].indexOf(backgroundName) >= 0
    color: swatch(backgroundName)
    readonly property color ink: swatch(fontColorName)

    readonly property var sizes: ({
        Small: { text: 12, line: 16, author: 10, authorLine: 14, width: 550 },
        Medium: { text: 16, line: 22, author: 12, authorLine: 16, width: 620 },
        Large: { text: 24, line: 32, author: 14, authorLine: 20, width: 870 },
        Larger: { text: 28, line: 36, author: 16, authorLine: 22, width: 1000 }
    })
    readonly property var size: sizes[fontSize] || sizes.Medium
    implicitHeight: windowHeight <= 682
        ? ({ Small: 118, Medium: 132, Large: 148 })[captionHeight] || 132
        : areaHeight * (({ Small: 0.22, Medium: 0.43, Large: 0.725 })[captionHeight] || 0.43)

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
    function nameOf(e) {
        if (e.name) return e.name
        if (canon(e.userId) === canon(meId)) return meName
        const p = person(e.userId)
        return p ? (p.name || "") : ""
    }
    function isGuest(id) {
        const p = person(id)
        return p ? !!p.guest : (id || "").startsWith("8:teamsvisitor:")
    }
    function wordsOf(e) { return filterProfanity ? (e.text || e.rawText || "") : (e.rawText || e.text || "") }

    readonly property real listWidth: popout ? width - 30 : Math.min(size.width, width - 75)
    readonly property bool listFits: popout || size.width <= width - 75

    ListView {
        id: list
        x: root.popout ? 15 : root.listFits ? (root.width - width) / 2 : 0
        width: root.listWidth; height: parent.height - root.boxSpace
        clip: true
        visible: count > 0
        model: root.captions
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Follow the newest caption unless you scrolled back.
        property bool following: true
        onMovementEnded: following = atYEnd
        onCountChanged: if (following) Qt.callLater(positionViewAtEnd)
        onContentHeightChanged: if (following) Qt.callLater(positionViewAtEnd)
        // The RTT box's message bar takes room from the list.
        onHeightChanged: if (following) Qt.callLater(positionViewAtEnd)
        Accessible.role: Accessible.List
        Accessible.name: "Live captions"
        delegate: Item {
            id: cap
            required property var modelData
            required property int index
            readonly property bool intro: modelData.kind === "realTimeTextIntro"
            readonly property bool typing: modelData.kind === "realTimeText" && !modelData.isFinal
            readonly property bool header: true
            readonly property real wordsTop: 15
            // A line being typed sits in from its brand line.
            readonly property real inset: typing ? 14.67 : 0
            width: list.width - 14
            height: intro ? card.height + 19
                : Math.max(typing ? 48 : 0, header ? 39 : 0, wordsTop + words.implicitHeight + 2)
            Rectangle {
                visible: cap.typing
                x: 12; y: 8; width: 1.33; height: 40
                color: theme.brand
            }
            Item {
                id: card
                visible: cap.intro
                x: 9; y: 7; width: cap.width - 10
                height: visible ? notice.y + notice.height + 12 : 0
                FluentSurface { anchors.fill: parent; depth: 2; radius: 4; color: theme.surface }
                Text {
                    x: 12; y: 12; height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: "RTT"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                    color: theme.text
                }
                Text {
                    id: notice
                    x: 12; y: 44; width: card.width - 24
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    linkColor: theme.brandLink
                    text: "RTT (Real-time text) has been enabled " + (root.rttInitiator ? "by you " : "")
                        + "for all participants throughout this " + (root.isMeeting ? "meeting" : "call")
                        + ". All typed conversations in the RTT text box will be recorded, transcribed, and included in the transcript, in accordance with the <a href=\"" + root.privacyUrl + "\">Microsoft Privacy Statement</a>."
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    onLinkActivated: link => { if (link) Qt.openUrlExternally(link) }
                    HoverHandler { cursorShape: notice.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: "RTT. " + notice.text.replace(/<[^>]*>/g, "")
            }
            Avatar {
                visible: cap.header && !cap.intro
                x: 8 + cap.inset; y: 4; size: 32
                name: root.nameOf(cap.modelData)
                photoId: cap.modelData.userId || ""
            }
            Row {
                visible: cap.header && !cap.intro
                x: 52 + cap.inset; y: cap.wordsTop + 1.33 - height
                height: root.size.authorLine
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.nameOf(cap.modelData)
                    font.family: theme.font; font.pixelSize: root.size.author; font.weight: Font.DemiBold
                    color: root.ink
                }
                FluentIcon {
                    visible: root.isGuest(cap.modelData.userId)
                    anchors.verticalCenter: parent.verticalCenter
                    name: "person-unverified-16-filled"; size: 16; color: root.ink
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Unverified"
                }
                Text {
                    visible: cap.typing
                    leftPadding: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "RTT Typing"
                    font.family: theme.font; font.pixelSize: root.size.author; font.weight: Font.DemiBold
                    color: root.ink
                }
            }
            Text {
                id: words
                visible: !cap.intro
                x: 52 + cap.inset; y: cap.wordsTop; width: cap.width - 52 - cap.inset - 8
                wrapMode: Text.Wrap
                text: cap.intro ? "" : root.wordsOf(cap.modelData)
                font.family: theme.font; font.pixelSize: root.size.text
                lineHeight: root.size.line; lineHeightMode: Text.FixedHeight
                color: root.ink
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: cap.intro ? card.Accessible.name
                : root.nameOf(modelData) + (cap.typing ? ", RTT Typing" : "") + ": " + root.wordsOf(modelData)
        }
    }

    RttBox {
        id: rttBox
        visible: root.rttOn
        x: root.popout ? 23 : list.x
        width: root.popout ? root.width - 47 : list.width
        y: root.height - 6 - height
    }

    Text {
        id: placeholder
        visible: list.count === 0
        anchors.centerIn: parent
        text: "Captions will be shown in " + root.languageName + "."
        font.family: theme.font; font.pixelSize: 16
        color: root.ink
    }

    // Settings, Open captions in new window and close; the first two fold
    // into "…" when the buttons don't fit beside the list.
    readonly property bool overflow: root.rttOn || (root.width - list.x - list.width) < 8 + 3 * 32
    component CapButton: Rectangle {
        id: b
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 32; radius: 4
        color: bh.hovered ? (root.lightBackground ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.12)) : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: b.icon; color: root.lightBackground ? theme.pick("#424242", "#424242") : "#FFFFFF" }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: b.clicked() }
        ToolTip.visible: bh.hovered
        ToolTip.delay: 250
        ToolTip.text: b.tip
        Accessible.role: Accessible.Button
        Accessible.name: b.tip
    }
    Row {
        visible: !root.popout
        anchors.right: parent.right; anchors.rightMargin: 8; y: 6
        CapButton {
            id: settingsButton
            icon: root.overflow ? "more-horizontal-20" : "settings-20"
            tip: root.overflow ? "Closed captions overflow menu" : "Open caption settings"
            onClicked: root.settingsRequested(settingsButton)
        }
        CapButton { visible: !root.overflow; icon: "captions-pop-out-20"; tip: "Open captions in new window"; onClicked: root.popOut() }
        CapButton { visible: !root.rttOn; icon: "dismiss-20"; tip: "Hide live captions"; onClicked: root.closed() }
    }
}
