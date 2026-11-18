import QtQuick

// Teams' post-call "How was the call quality?" (its CQF questionnaire in
// the ThumbsCombined style; docs/spec/feedback-and-help.md §5), shown in
// the call window once a sampled call ends, for those who opted in
// (Settings ▸ Privacy). Measured on winpc 2026-11-11 and read from Teams'
// CQF bundle and its Griffel CSS 2026-11-18 (1 rem = 10 px):
// - the page is colorNeutralBackground3 (#F5F5F5), the content box 2.4rem
//   in, at most 58rem wide;
// - "How was the call quality?" 28/700 #424242 (NeutralForeground2),
//   2.4rem over the two thumbs: 61.3 square buttons (0.67 #D1D1D1 edge,
//   radius 4) with Teams' 50 px "no" / "yes" emoticons (personal
//   expressions, 100_f), "Had issues" / "Good" 14 px under them;
// - Good is sent at once and the thank-you shows: "Thanks for the
//   feedback!" (bold), "We'll keep working on improving your experience.",
//   the 13rem thumbs-up illustration; it closes after 3 s;
// - Had issues: "What could've been better?" with the category tabs
//   (shuffled; the first selected; 12/600, padding 5 12, the selected one
//   underlined 2 px in brand), the category's reasons as checkboxes in two
//   columns 1.6rem apart (shuffled), then "Privacy statement" (10/14
//   NeutralForeground2) and Dismiss / Send feedback;
// - unanswered, it goes after 60 s.
// OST sends the rating nowhere: Send feedback opens Report a problem for
// the feedback repo with the reasons and the call's technical details.
Rectangle {
    id: root
    /// {question, categories: [{id, label, items: [{id, label}]}]}.
    property var survey: ({})
    /// "rate", "issues" or "thanks".
    property string page: "rate"
    property int category: 0
    property var ticked: ({})
    signal sendFeedback(var reasons)
    signal finished()
    color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
    Accessible.role: Accessible.Pane
    Accessible.name: survey.question || "How was the call quality?"

    function reset() { page = "rate"; category = 0; ticked = ({}) }
    onSurveyChanged: reset()
    readonly property var categories: survey.categories || []
    readonly property var current: categories.length > category ? categories[category] : null
    readonly property var reasons: Object.keys(ticked).filter(k => ticked[k])

    // Teams dismisses an unanswered survey after 60 s.
    Timer { id: autoDismiss; interval: 60000; running: root.visible && root.page !== "thanks"; onTriggered: root.finished() }
    Timer { id: thanksTimer; interval: 3000; onTriggered: root.finished() }
    function thank() { page = "thanks"; thanksTimer.restart() }

    // Teams' emoticons, as the chat shows them.
    property int emoticonsVersion: backend.emoticonsVersion
    readonly property string noUrl: { emoticonsVersion; return backend.emoticonUrl("no", 100) }
    readonly property string yesUrl: { emoticonsVersion; return backend.emoticonUrl("yes", 100) }

    // ---- How was the call quality? ----
    Column {
        visible: root.page === "rate"
        anchors.centerIn: parent
        spacing: 24
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.survey.question || "How was the call quality?"
            font.family: theme.font; font.pixelSize: 28; font.weight: Font.Bold
            color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: [{ label: "Had issues", rating: 1 }, { label: "Good", rating: 5 }]
                delegate: Column {
                    required property var modelData
                    spacing: 6
                    Rectangle {
                        id: thumb
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 61.3; height: 61.3; radius: 4
                        color: th.pressed ? theme.menuHover : th2.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                        border.width: 0.67; border.color: theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF")
                        Image {
                            anchors.centerIn: parent
                            width: 50; height: 50
                            source: modelData.rating === 1 ? root.noUrl : root.yesUrl
                            sourceSize.width: 100; sourceSize.height: 100
                            smooth: true; mipmap: true
                        }
                        HoverHandler { id: th2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: th; onTapped: modelData.rating === 5 ? root.thank() : (root.page = "issues") }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Accessible.onPressAction: modelData.rating === 5 ? root.thank() : (root.page = "issues")
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                }
            }
        }
    }

    // ---- What could've been better? ----
    Item {
        visible: root.page === "issues"
        anchors { fill: parent; margins: 24 }
        Item {
            id: box
            width: Math.min(parent.width, 580)
            height: issuesCol.height
            anchors.centerIn: parent
            Column {
                id: issuesCol
                width: parent.width
                spacing: 16
                // The title and the category tabs on one row (Teams' flex row
                // from 768 px; a column below).
                Item {
                    width: parent.width
                    height: Math.max(heading.height, tabs.height)
                    Text {
                        id: heading
                        anchors.verticalCenter: parent.verticalCenter
                        text: "What could've been better?"
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }
                    Row {
                        id: tabs
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.categories.length > 1
                        Repeater {
                            model: root.categories
                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.category
                                width: tabRow.implicitWidth + 24; height: 32
                                Row {
                                    id: tabRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    FluentIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 20
                                        name: ({ audio: "speaker-2-20", video: "video-20", screenshare: "share-screen-start-20" })[modelData.id] || ""
                                        color: selected ? theme.brand : theme.text
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                        color: selected ? theme.brand : theme.text
                                    }
                                }
                                Rectangle { visible: selected; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brandForeground1 }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.category = index }
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label
                                Accessible.checked: selected
                            }
                        }
                    }
                }
                // The category's reasons in two columns (the first takes
                // the odd one).
                Row {
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: {
                            const items = root.current ? root.current.items : []
                            const half = Math.ceil(items.length / 2)
                            return items.length ? [items.slice(0, half), items.slice(half)] : []
                        }
                        delegate: Column {
                            required property var modelData
                            width: (box.width - 16) / 2
                            Repeater {
                                model: modelData
                                delegate: SettingsParts.CheckRow {
                                    required property var modelData
                                    width: (box.width - 16) / 2
                                    rowHeight: 32
                                    label: modelData.label
                                    checked: !!root.ticked[modelData.id]
                                    onToggled: on => { const t = Object.assign({}, root.ticked); t[modelData.id] = on; root.ticked = t }
                                }
                            }
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: 31.3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.StyledText
                        text: "<a href=\"privacy\">Privacy statement</a>"
                        linkColor: theme.link
                        font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                        onLinkActivated: Qt.openUrlExternally(backend.feedbackLink("privacy-feedback"))
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        SettingsParts.Button { label: "Dismiss"; onClicked: root.finished() }
                        SettingsParts.Button {
                            label: "Send feedback"; primary: true
                            onClicked: { root.sendFeedback(root.reasons); root.thank() }
                        }
                    }
                }
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
                text: "Thanks for the feedback!"
                font.family: theme.font; font.pixelSize: 28; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "We'll keep working on improving your experience."
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
