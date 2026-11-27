import QtQuick

// Teams' post-call "How was the call quality?" (its CQF questionnaire in
// the ThumbsCombined style; docs/spec/feedback-and-help.md §5), shown in
// the call window once a sampled call ends, for those who opted in
// (Settings ▸ Privacy). Measured live in Teams desktop on winpc
// (2026-11-18, its sampling forced over CDP after a solo Meet now; window
// 1280 x 680, CSS px) and read from its CQF bundle:
// - one page on #F5F5F5 (calling-quality-feedback-screen);
// - "How was the call quality?" (h1) 28/700, line 40, #424242, centred;
//   18.75 under it the thumbs: 61.33 squares (transparent, 0.67 #D1D1D1
//   edge, radius 4; the pressed one's edge 1 px brand #4F52B2), 10.14
//   apart, Teams' 50 px "no" / "yes" emoticons (personal expressions,
//   100_f) 5.67 in, "Had issues" / "Good" (14/20 #252423) right under them;
// - 24 under the labels a 580-wide group, centred: "What could've been
//   better?" (14/20 #242424) and beside it the category tabs (a toolbar 8 in
//   and 4 down, its radios padding 5 12, min 96, 28.67 tall: a 16 px glyph
//   (Call, Share screen, Video), 10 px, the label 12/600 #424242; the
//   selected one underlined 2 px #5B5FC7). The categories and their reasons
//   are shuffled, the first category selected;
// - under it the reasons in two 282-wide columns 16 apart: checkbox rows of
//   32 (52 when the label wraps), a 16 px box (0.67 #616161, radius 2) 8 in,
//   the label (14/20 #616161) at 32, up to 250 wide;
// - 15 under, the privacy line (10/14 #424242, 580 wide) ending in
//   "Privacy statement" (#4F52B2); 16 under it Dismiss (96 x 31.33) and
//   Send feedback (primary), 15 apart, at the right;
// - Good is sent at once and "Thanks for the feedback!" / "We'll keep
//   working on improving your experience." and the 13rem thumbs-up show
//   for 3 s; unanswered, the survey goes after 60 s.
// OST sends the rating nowhere: Send feedback opens Report a problem for
// the feedback repo with the reasons and the call's technical details, so
// the privacy line says that instead of Teams' Microsoft text.
Rectangle {
    id: root
    /// {question, categories: [{id, label, items: [{id, label}]}]}.
    property var survey: ({})
    /// "rate" or "thanks".
    property string page: "rate"
    /// The thumb pressed: 0, 1 (Had issues) or 5 (Good).
    property int rating: 0
    property int category: 0
    property var ticked: ({})
    signal sendFeedback(var reasons)
    signal finished()
    color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
    Accessible.role: Accessible.Pane
    Accessible.name: survey.question || qsTr("How was the call quality?")

    function reset() { page = "rate"; rating = 0; category = 0; ticked = ({}) }
    onSurveyChanged: reset()
    readonly property var categories: survey.categories || []
    readonly property var current: categories.length > category ? categories[category] : null
    readonly property var reasons: Object.keys(ticked).filter(k => ticked[k])

    // Teams dismisses an unanswered survey after 60 s.
    Timer { id: autoDismiss; interval: 60000; running: root.visible && root.page !== "thanks"; onTriggered: root.finished() }
    Timer { id: thanksTimer; interval: 3000; onTriggered: root.finished() }
    function thank() { page = "thanks"; thanksTimer.restart() }
    function rate(r) { rating = r; if (r === 5) thank() }

    // Teams' emoticons, as the chat shows them.
    property int emoticonsVersion: backend.emoticonsVersion
    readonly property string noUrl: { emoticonsVersion; return backend.emoticonUrl("no", 100) }
    readonly property string yesUrl: { emoticonsVersion; return backend.emoticonUrl("yes", 100) }

    Item {
        id: page1
        visible: root.page === "rate"
        width: 580; height: buttons.y + buttons.height
        anchors.centerIn: parent
        Text {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            height: 40; verticalAlignment: Text.AlignVCenter
            text: root.survey.question || qsTr("How was the call quality?")
            font.family: theme.font; font.pixelSize: 28; font.weight: Font.Bold
            color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Row {
            id: thumbs
            anchors.horizontalCenter: parent.horizontalCenter
            y: title.height + 18.75
            spacing: 10.14
            Repeater {
                model: [{ label: qsTr("Had issues"), rating: 1 }, { label: qsTr("Good"), rating: 5 }]
                delegate: Item {
                    required property var modelData
                    width: Math.max(61.33, thumbLabel.implicitWidth); height: 61.33 + 20
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 61.33; height: 61.33; radius: 4
                        color: th.pressed ? theme.menuHover : th2.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : "transparent"
                        border.width: root.rating === modelData.rating ? 1 : 0.67
                        border.color: root.rating === modelData.rating ? theme.brandForeground1 : theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF")
                        Image {
                            x: 5.67; y: 5.67; width: 50; height: 50
                            source: modelData.rating === 1 ? root.noUrl : root.yesUrl
                            sourceSize.width: 100; sourceSize.height: 100
                            smooth: true; mipmap: true
                        }
                        HoverHandler { id: th2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: th; onTapped: root.rate(modelData.rating) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Accessible.checked: root.rating === modelData.rating
                        Accessible.onPressAction: root.rate(modelData.rating)
                    }
                    Text {
                        id: thumbLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 61.33; height: 20; verticalAlignment: Text.AlignVCenter
                        text: modelData.label
                        font.family: theme.font; font.pixelSize: 14; color: theme.pick("#252423", "#D6D6D6", "#FFFFFF")
                    }
                }
            }
        }
        // What could've been better? and the category tabs.
        Item {
            id: issuesHead
            y: thumbs.y + thumbs.height + 24
            width: parent.width; height: 36.67
            Text {
                id: heading
                y: (parent.height - height) / 2; height: 20; verticalAlignment: Text.AlignVCenter
                text: qsTr("What could've been better?")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Row {
                x: heading.implicitWidth + 8; y: 4
                visible: root.categories.length > 1
                Repeater {
                    model: root.categories
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.category
                        width: Math.max(96, tabRow.implicitWidth + 24); height: 28.67
                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 10
                            FluentIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 16
                                name: ({ audio: "nmc-callme", video: "video-20", screenshare: "call-share" })[modelData.id] || ""
                                color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                            }
                        }
                        Rectangle { visible: selected; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.category = index }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.label
                        Accessible.checked: selected
                    }
                }
            }
        }
        // The category's reasons in two columns (the first takes the odd
        // one).
        Row {
            id: reasonRows
            y: issuesHead.y + issuesHead.height
            spacing: 16
            Repeater {
                model: {
                    const items = root.current ? root.current.items : []
                    const half = Math.ceil(items.length / 2)
                    return items.length ? [items.slice(0, half), items.slice(half)] : []
                }
                delegate: Column {
                    required property var modelData
                    width: 282
                    Repeater {
                        model: modelData
                        delegate: Item {
                            id: reason
                            required property var modelData
                            readonly property bool checked: !!root.ticked[modelData.id]
                            width: 282; height: Math.max(32, reasonText.implicitHeight + 12)
                            Rectangle {
                                x: 8; y: 8; width: 16; height: 16; radius: 2
                                color: reason.checked ? theme.brandFill : "transparent"
                                border.width: reason.checked ? 0 : 0.67
                                border.color: rh.hovered ? theme.pick("#575757", "#ADADAD", "#FFFFFF") : theme.pick("#616161", "#ADADAD", "#FFFFFF")
                                FluentIcon { anchors.centerIn: parent; visible: reason.checked; size: 12; name: "checkmark-12"; color: "#FFFFFF" }
                            }
                            Text {
                                id: reasonText
                                x: 32; y: 6; width: 250
                                text: reason.modelData.label
                                wrapMode: Text.Wrap
                                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: rh.hovered ? theme.pick("#424242", "#D6D6D6", "#FFFFFF") : theme.pick("#616161", "#ADADAD", "#FFFFFF")
                            }
                            HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { const t = Object.assign({}, root.ticked); t[reason.modelData.id] = !reason.checked; root.ticked = t } }
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: reason.modelData.label
                            Accessible.checked: reason.checked
                        }
                    }
                }
            }
        }
        Text {
            id: privacy
            y: reasonRows.y + reasonRows.height + 15
            width: parent.width
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            text: qsTr("By pressing \"Send feedback\", Report a problem opens with your answers and the call's technical details, to post as a public issue on GitHub (%1). Nothing is sent before you do.").arg(backend.feedbackRepo())
                  + " <a href=\"privacy\">" + qsTr("Privacy statement") + "</a>"
            linkColor: theme.brandForeground1
            font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
            color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
            onLinkActivated: backend.openExternal(backend.feedbackLink("privacy-feedback"))
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Row {
            id: buttons
            anchors.right: parent.right
            y: privacy.y + privacy.height + 16
            spacing: 15
            SettingsParts.Button { label: qsTr("Dismiss"); onClicked: root.finished() }
            SettingsParts.Button {
                label: qsTr("Send feedback"); primary: true
                onClicked: { root.sendFeedback(root.reasons); root.thank() }
            }
        }
    }

    // ---- Thanks for the feedback! ----
    Column {
        visible: root.page === "thanks"
        anchors.centerIn: parent
        spacing: 24
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Thanks for the feedback!")
                font.family: theme.font; font.pixelSize: 28; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("We'll keep working on improving your experience.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
        }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 130; height: 130
            source: "../assets/illustrations/cqf-thanks.svg"
            sourceSize.width: 260; sourceSize.height: 260
            smooth: true
        }
    }
}
