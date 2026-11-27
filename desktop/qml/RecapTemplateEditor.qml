import QtQuick
import QtQuick.Controls.Basic

// Teams' "Describe your summary format" (the recap's Custom summary ▸
// Create template, and a template's Edit; Teams 26304's customize-notes
// panel, a modal Fluent dialog; 1rem = 10 px):
// - min(window, 1080) wide, 80 % of the window tall up to 704 (a window
//   502 tall or less: 24 from the top, the rest of it), padding 24 32 32
//   32; the 20/28 title and its Close (absolute, 20 from the right);
// - 18 below the title the body: at the left (50 %, 10 apart) the editor
//   box (65 % of the column, growing to 75 %; 1 px NeutralStroke1, radius
//   4, a 2 px brand bottom edge while focused, the danger colour on an
//   error) with the text (padding 6 12) and Preview inside its bottom
//   right (40 tall at least, 12 in), Teams' message under it (12,
//   StatusDangerForeground1, 20 tall at least), then "Suggestions" (a 16
//   px sparkle, 12/16 600) and three pill buttons (radius 16, padding 11 11
//   11 16, two lines at most, 156 wide at most) in 3 or 2 columns by the
//   window's width (1145+: 3, 947–1144: 2, 741–946: 3, less: 2; ‹ › pages
//   in two); a pill replaces the text;
// - at the right (50 %, 14 apart) the preview on NeutralBackground5Selected
//   (radius 4): "When you select Preview, it'll show up here", Teams'
//   loading card (radius 8, shadow 2, 40 tall, 24 4 24 20 around it), the
//   summary (padding 19 10 10 24: "AI-generated content may be incorrect"
//   then its Markdown) or "We couldn't load custom AI summary";
// - 24 below, Discard and Save and Apply at the right, 5 apart (stacked,
//   the full width, Save first, in a window 480 wide or less).
// Windows 947 wide or less put the two halves one under the other and
// scroll. Preview sends Teams' recap prompt with the trimmed text through
// Copilot for the open meeting; Save and Apply asks a new template's name
// (RecapTemplateNameDialog) and saves it to your OneDrive, or saves an
// edited one in place; a failure leaves the dialog open (logged).
Popup {
    id: root
    /// The recap (api::recaps::RecapRef) the preview summarises.
    property var recap: ({})
    /// Your templates ({id, name}), for the name check.
    property var templates: []
    /// Editing one of yours: {id, name}; null for a new one.
    property var editInfo: null
    readonly property string tag: "recaptpl" + Math.floor(Math.random() * 1e9) + ":"
    property string error: ""
    /// The text last previewed ("" before the first Preview).
    property string submitted: ""
    property string previewState: ""
    property string previewText: ""
    property bool saving: false
    property bool loadingContent: false
    /// A new template saved (its item id), or one of yours saved again.
    signal created(string id, string name)
    signal updated(string id, string name, string content)

    function reset() { area.text = ""; error = ""; submitted = ""; previewState = ""; previewText = ""; saving = false; loadingContent = false; sugg.page = 0 }
    function openNew(list) { editInfo = null; templates = list || []; reset(); open(); area.forceActiveFocus() }
    function openEdit(id, name, list) {
        editInfo = { id: id, name: name }; templates = list || []; reset()
        loadingContent = true
        backend.eventsRequest("recapTemplateContent", tag + "content", JSON.stringify({ id: id }))
        open()
    }
    function setText(t) { area.text = t; error = "" }
    function preview() {
        if (!area.text) { error = qsTr("This field cannot be blank", "meetingRecap:k7n7pzpt8"); return }
        const t = area.text.trim()
        if (t === submitted && previewState !== "error") return
        submitted = t; previewState = "generating"; previewText = ""
        console.info("RECAP template preview", t.length)
        backend.eventsRequest("recapSummary", tag + "preview", JSON.stringify({ recap: root.recap, text: t }))
    }
    function saveAndApply() {
        const t = area.text.trim()
        if (!t) { error = qsTr("This field cannot be blank", "meetingRecap:k7n7pzpt8"); return }
        if (saving) return
        if (editInfo) save(editInfo.name, t)
        else nameDialog.openFor("", templates)
    }
    function save(name, content) {
        saving = true
        if (editInfo) {
            const p = { id: editInfo.id, template: content }
            if (name !== editInfo.name) p.name = name
            backend.eventsRequest("recapTemplateUpdate", tag + "update", JSON.stringify(p))
        } else {
            backend.eventsRequest("recapTemplateCreate", tag + "create", JSON.stringify({ name: name, template: content }))
        }
        pending = { name: name, content: content }
    }
    property var pending: null
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id.indexOf(root.tag) !== 0) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            const what = id.slice(root.tag.length)
            if (what === "content") {
                root.loadingContent = false
                if (v.content) area.text = v.content
                console.info("RECAP template content", v.error || "", (v.content || "").length)
            } else if (what === "preview") {
                root.previewText = v.text || ""; root.previewState = v.error ? "error" : "done"
                console.info("RECAP template previewed", v.error || "", (v.text || "").length)
            } else if (what === "create" || what === "update") {
                root.saving = false
                if (v.error) { console.warn("RECAP template save failed", v.error); return }
                console.info("RECAP template saved", what, v.id || root.editInfo.id)
                const p = root.pending
                root.close()
                if (what === "create") root.created(v.id || "", p.name)
                else root.updated(root.editInfo.id, p.name, p.content)
            }
        }
    }

    parent: Overlay.overlay
    modal: true; focus: true
    closePolicy: nameDialog.opened ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    readonly property real winW: parent ? parent.width : 1283
    readonly property real winH: parent ? parent.height : 730
    readonly property bool short_: winH <= 502
    readonly property bool narrow: winW <= 947
    readonly property bool stackButtons: winW <= 480
    width: Math.min(winW, 1080)
    height: short_ ? winH - 24 : Math.min(704, winH * 0.8)
    x: (winW - width) / 2
    y: short_ ? 24 : (winH - height) / 2
    padding: 0
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    onClosed: if (nameDialog.opened) nameDialog.close()

    readonly property color dangerInk: theme.pick("#B10E1C", "#DC626D", "#FFFFFF")   // colorStatusDangerForeground1

    Text {
        x: 32; y: 24; width: root.width - 64 - 40; height: 28
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        text: qsTr("Describe your summary format")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading; Accessible.name: text
    }
    Rectangle {
        id: closeBtn
        x: root.width - 20 - 32; y: 22; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeBtn, theme.textStrong) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
    }

    // The body: 18 below the title (and the dialog's 8 px gaps), down to
    // 24 above the buttons' 40 px row.
    readonly property real footerH: stackButtons ? 32 + 7.5 + 32 : 40
    Flickable {
        id: body
        x: 32; y: 24 + 28 + 8 + 18
        width: root.width - 64; height: root.height - y - 8 - 24 - root.footerH - 32
        clip: root.narrow
        interactive: root.narrow
        contentHeight: root.narrow ? leftCol.height + 32 + rightCol.height : height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: root.narrow ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        // Two 50 % halves with 10 + 14 between them (flex shrinks both).
        Item {
            id: leftCol
            width: root.narrow ? body.width : body.width / 2 - 12
            height: root.narrow ? 398 : body.height - 8
            readonly property real suggH: 8 + 24 + 7.5 + 2.5 + sugg.cardH
            Rectangle {
                id: box
                width: parent.width
                height: Math.max(0, Math.min(parent.height * 0.75, parent.height - 22 - leftCol.suggH))
                radius: 4
                color: theme.surface
                border.width: 1
                border.color: root.error ? root.dangerInk : theme.stroke
                readonly property bool focused: area.activeFocus || previewBtn.activeFocus
                Rectangle { visible: box.focused && !root.error; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brandForeground1 }
                ScrollView {
                    id: scroller
                    visible: !root.loadingContent
                    x: 1; y: 1; width: parent.width - 2; height: parent.height - 2
                    clip: true
                    TextArea {
                        id: area
                        topPadding: 6; bottomPadding: 6; leftPadding: 12; rightPadding: 12
                        wrapMode: TextEdit.Wrap
                        background: null
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.textStrong
                        selectionColor: theme.selectionFill; selectedTextColor: theme.text
                        onTextChanged: if (activeFocus) root.error = ""
                        Accessible.name: hint.text
                        // The placeholder wraps, as a textarea's does.
                        Text {
                            id: hint
                            visible: !area.text && !area.preeditText
                            x: area.leftPadding; y: area.topPadding; width: area.width - area.leftPadding - area.rightPadding
                            wrapMode: Text.Wrap
                            text: qsTr("Describe the format you'd like to create or paste a sample notes for reference if needed")
                            font: area.font; color: theme.textTertiary
                        }
                    }
                }
                // Edit's text loading: Teams' three skeleton lines.
                Column {
                    visible: root.loadingContent
                    x: 12; y: 12; width: parent.width - 24; spacing: 8
                    Repeater {
                        model: [[0.53, 250], [0.66, 316], [0.35, 165]]
                        Rectangle {
                            required property var modelData
                            width: Math.min(parent.width * modelData[0], modelData[1]); height: 16; radius: 4
                            color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
                            SequentialAnimation on opacity { running: root.loadingContent; loops: Animation.Infinite; NumberAnimation { to: 0.4; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
                        }
                    }
                }
                DialogButton {
                    id: previewBtn
                    anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: box.focused ? 11 : 12 }
                    label: qsTr("Preview")
                    enabled: root.previewState !== "generating"
                    onClicked: root.preview()
                }
            }
            Text {
                y: box.height + 2; width: parent.width
                wrapMode: Text.Wrap
                text: root.error
                font.family: theme.font; font.pixelSize: 12; color: root.dangerInk
                Accessible.role: Accessible.AlertMessage; Accessible.name: text
            }
            // Suggestions.
            Item {
                id: sugg
                y: box.height + 22; width: parent.width; height: leftCol.suggH
                readonly property var all: [
                    { label: qsTr("Follow the format in: <0>[sample note]</0>"), insert: qsTr("Follow the format in:") },
                    { label: qsTr("Summarize speaker's key point"), insert: qsTr("Summarize key points made by each speaker:\n\n- Speaker name 1\n- Speaker name 2\n- Speaker name 3") },
                    { label: qsTr("Create an executive report"), insert: qsTr("Create an executive report that includes:\n\n- Overview\n- Key updates") }
                ]
                // Teams' columns by the window's width.
                readonly property int cols: root.winW >= 1145 ? 3 : root.winW >= 947 ? 2 : root.winW >= 741 ? 3 : 2
                property int page: 0
                onColsChanged: page = 0
                readonly property bool paged: cols === 2
                readonly property var shown: paged ? all.slice(page * 2, page * 2 + 2) : all
                readonly property real cardW: Math.min(280, (width - 8 * (cols - 1)) / cols)
                readonly property real textW: Math.min(156, cardW - 27 - 2)
                // The cards are as tall as the tallest (two lines at most).
                readonly property real cardH: 11 + 5 + 20 * Math.max(1, Math.min(2, Math.max(m0.lineCount, m1.lineCount, m2.lineCount))) + 5 + 11 + 2
                // Each label laid out at the pills' text width, unseen.
                component Measure: Text {
                    property int i
                    opacity: 0; enabled: false
                    width: sugg.textW; wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: sugg.all[i].label.replace("<0>", "<font>").replace("</0>", "</font>")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    Accessible.ignored: true
                }
                Measure { id: m0; i: 0 }
                Measure { id: m1; i: 1 }
                Measure { id: m2; i: 2 }
                Row {
                    y: 8; height: 24; spacing: 0
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "sparkle-16"; size: 16; color: theme.text }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Suggestions")
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text
                    }
                }
                Row {
                    visible: sugg.paged
                    anchors.right: parent.right; y: 8; height: 24; spacing: 1.5
                    ArrowButton { icon: "chevron-left-16"; tip: qsTr("Previous suggestions"); enabled: sugg.page > 0; onClicked: sugg.page-- }
                    ArrowButton { icon: "chevron-right-16"; tip: qsTr("Next suggestions"); enabled: sugg.page < Math.ceil(sugg.all.length / 2) - 1; onClicked: sugg.page++ }
                }
                Row {
                    y: 8 + 24 + 7.5 + 2.5; spacing: 8
                    Repeater {
                        model: sugg.shown
                        Rectangle {
                            id: pillBtn
                            required property var modelData
                            width: sugg.cardW; height: sugg.cardH; radius: 16
                            color: pillHover.hovered ? theme.menuHover : theme.surface
                            border.width: 1; border.color: pillHover.hovered ? theme.strokeHover : theme.stroke
                            Text {
                                x: 16; y: 11 + 5; width: sugg.textW
                                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: pillBtn.modelData.label.replace("<0>", "<font color=\"" + theme.brandForeground1 + "\">").replace("</0>", "</font>")
                                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: theme.onFill(pillBtn, theme.text)
                            }
                            HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.setText(pillBtn.modelData.insert) }
                            Accessible.role: Accessible.Button; Accessible.name: pillBtn.modelData.label.replace("<0>", "").replace("</0>", "")
                        }
                    }
                }
            }
        }
        // The preview.
        Rectangle {
            id: rightCol
            x: root.narrow ? 0 : body.width / 2 + 12
            y: root.narrow ? leftCol.height + 32 : 0
            width: root.narrow ? body.width : body.width / 2 - 12
            height: root.narrow ? Math.max(398, previewCol.implicitHeight + 29) : body.height - 8
            radius: 4; clip: true
            color: theme.pick("#FAFAFA", "#1A1A1A")   // colorNeutralBackground5Selected
            // Before a Preview, and an empty or failed one: Teams' status page.
            Column {
                visible: root.submitted === "" || root.previewState === "error" || (root.previewState === "done" && root.previewText === "")
                anchors.centerIn: parent
                width: parent.width - 48
                readonly property bool failed: root.submitted !== ""
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 192; height: 192; sourceSize: Qt.size(384, 384)
                    source: "../assets/illustrations/" + (parent.failed ? "warning" : "meeting-notes") + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                }
                Item { width: 1; height: 24 }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: parent.failed ? qsTr("We couldn't load custom AI summary") : qsTr("When you select Preview, it'll show up here")
                    lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.onFill(rightCol, theme.text)
                }
                Item { visible: parent.failed; width: 1; height: 8 }
                Text {
                    visible: parent.failed
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: qsTr("Something went wrong. Try again.")
                    lineHeight: 28; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill(rightCol, theme.text)
                }
            }
            // Teams' loading card.
            Rectangle {
                id: loadingCard
                visible: root.previewState === "generating"
                x: 20; y: 24; width: parent.width - 24; height: 40; radius: 8
                color: theme.surface; clip: true
                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 8 }
                Text {
                    x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16; elide: Text.ElideRight
                    text: qsTr("Generating your template preview...")
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill(loadingCard, theme.text)
                }
                // Fluent's indeterminate progress bar along the card's foot.
                Rectangle {
                    id: bar
                    y: parent.height - 2; height: 2; width: parent.width * 0.33; radius: 1
                    color: theme.brand
                    NumberAnimation on x { running: loadingCard.visible; loops: Animation.Infinite; from: -bar.width; to: loadingCard.width; duration: 3000 }
                }
                Accessible.role: Accessible.ProgressBar; Accessible.name: qsTr("Generating your template preview...")
            }
            Flickable {
                visible: root.previewState === "done" && root.previewText !== ""
                anchors.fill: parent
                contentHeight: previewCol.implicitHeight + 29
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Column {
                    id: previewCol
                    x: 24; y: 19; width: parent.width - 34
                    Text {
                        topPadding: 5; bottomPadding: 5; width: parent.width; wrapMode: Text.Wrap
                        text: qsTr("AI-generated content may be incorrect")
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(rightCol, theme.textSecondary)
                    }
                    TextEdit {
                        width: parent.width; wrapMode: Text.Wrap; textFormat: TextEdit.MarkdownText
                        readOnly: true; selectByMouse: true
                        text: root.previewText
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(rightCol, theme.text)
                        selectionColor: theme.selectionFill
                        onLinkActivated: link => { if (link.indexOf("https://") === 0) backend.openExternal(link) }
                        Accessible.role: Accessible.StaticText; Accessible.name: text
                    }
                }
            }
        }
    }

    // Discard and Save and Apply.
    Grid {
        id: footer
        x: root.stackButtons ? 32 : root.width - 32 - width
        y: root.height - 32 - root.footerH + (root.stackButtons ? 0 : 4)
        columns: root.stackButtons ? 1 : 2
        spacing: root.stackButtons ? 7.5 : 5
        layoutDirection: Qt.LeftToRight
        DialogButton {
            id: firstBtn
            width: root.stackButtons ? root.width - 64 : implicitWidth
            primary: root.stackButtons
            label: root.stackButtons ? (root.saving ? qsTr("Saving your template...") : qsTr("Save and Apply")) : qsTr("Discard")
            onClicked: root.stackButtons ? root.saveAndApply() : root.close()
        }
        DialogButton {
            width: root.stackButtons ? root.width - 64 : implicitWidth
            primary: !root.stackButtons
            label: root.stackButtons ? qsTr("Discard") : (root.saving ? qsTr("Saving your template...") : qsTr("Save and Apply"))
            onClicked: root.stackButtons ? root.close() : root.saveAndApply()
        }
    }

    RecapTemplateNameDialog {
        id: nameDialog
        onConfirmed: name => root.save(name, area.text.trim())
    }

    // Fluent's medium button (32 tall, at least 96 wide, padding 0 12,
    // 14/600): secondary, or primary; disabled greys.
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        signal clicked()
        implicitWidth: Math.max(96, dbText.implicitWidth + 24)
        width: implicitWidth; height: 32; radius: 4
        activeFocusOnTab: true
        color: !enabled ? theme.bgDisabled : primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill) : (dbHover.hovered ? theme.menuHover : theme.surface)
        border.color: !enabled ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : primary ? "transparent" : theme.stroke; border.width: primary && enabled ? 0 : 1
        Text {
            id: dbText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, db.width - 24); elide: Text.ElideRight
            text: db.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !db.enabled ? theme.disabled : theme.onFill(db, db.primary ? theme.textOnBrand : theme.text)
        }
        HoverHandler { id: dbHover; enabled: db.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: db.enabled; onTapped: db.clicked() }
        Keys.onSpacePressed: if (enabled) clicked()
        Keys.onReturnPressed: if (enabled) clicked()
        Accessible.role: Accessible.Button; Accessible.name: label
    }
    // The suggestions' ‹ › (24 x 24, radius 2, NeutralForeground2).
    component ArrowButton: Rectangle {
        id: ab
        property string icon
        property string tip
        signal clicked()
        width: 24; height: 24; radius: 2
        color: abHover.hovered && enabled ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ab.icon; size: 16; color: !ab.enabled ? theme.disabled : theme.onFill(ab, abHover.hovered ? theme.text : theme.textStrong) }
        HoverHandler { id: abHover; cursorShape: ab.enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor }
        TapHandler { enabled: ab.enabled; onTapped: ab.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: tip
    }

    // The harness's (--recap-window-test=template) steps.
    function typeForTest(t) { area.text = t; error = "" }
    function suggestionForTest(i) { root.setText(sugg.all[i].insert) }
    function nameDialogForTest() { return nameDialog }
    function stateForTest() {
        return { opened: root.opened, edit: root.editInfo, text: area.text, error: root.error, preview: root.previewState, previewLen: root.previewText.length,
                 saving: root.saving, loading: root.loadingContent, cols: sugg.cols, size: [root.width, root.height], box: box.height, cardH: sugg.cardH }
    }
}
