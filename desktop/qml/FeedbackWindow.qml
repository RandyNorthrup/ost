import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Feedback ▸ Report a problem / Give a compliment: Teams' feedback window
// (its "Submit feedback to Microsoft" form, measured on winpc 2026-11-10),
// sent to OST's GitHub repo instead (docs/spec/feedback-and-help.md).
// - 786 x 673, the child-window title row ("Report a problem" / "Give a
//   compliment"); the form 24 in, 58 down.
// - "Submit feedback to OST" (20/600 at 24, 24); "What did you dislike?" /
//   "What did you like?" (14, a #D13438 *) at 26, 62; the text box
//   (669.3 x 112 at 26.7, 88.7), "Do not include any private or sensitive
//   information."; "Add more details" with "Drag and drop files here or
//   paste an image from your clipboard" (12, #616161) and Capture
//   screenshot (173.7) / Attach file (116.1), 31.3 tall, 8 apart at 259.3;
//   "Share relevant content samples and additional log files? Learn more *"
//   at 301.3 with Yes, share / No, don't share (32 px radios, labels 14
//   #616161 at 58); "May we contact you about your feedback? *" at 394.7
//   with Yes, you may contact me / No, don't contact me; the 10 px footer
//   at 492; Submit and Cancel (96 x 31.3) at 510 and 618, 536 down.
// - Submit (once the text and both answers are given) first shows what
//   GitHub gets and when (OST's own step, issue #15: the filled-in form's
//   address carries the title, the text and the contact answer, so GitHub
//   has them as the page opens, even if the issue is never created), in
//   the form's type and buttons. From there Open filled-in form opens the
//   repo's issue form with only those and puts the first picture on the
//   clipboard; Copy text and open a blank form puts the text on the
//   clipboard and opens the empty form. Either way the rest (and the
//   masked logs, when shared) is saved to a file in the report's folder
//   for the reporter to review and attach, and the window says how to
//   finish on GitHub.
Window {
    id: win
    /// "problem" or "compliment".
    property string kind: "problem"
    /// Where it was sent from, and what OST knows about it.
    property string area: "Settings and more"
    property string context: ""
    /// What the form's text starts with (the call quality survey's
    /// reasons).
    property string initialText: ""
    Component.onCompleted: if (initialText) text.text = initialText
    /// What Capture screenshot grabs (the main window).
    property Item captureTarget: null
    readonly property bool compliment: kind === "compliment"
    title: compliment ? qsTr("Give a compliment") : qsTr("Report a problem")
    width: 786; height: 673
    minimumWidth: 480; minimumHeight: 480
    color: theme.surface

    property string dir: ""
    property var files: []
    property int share: -1          // 0 yes, 1 no
    property int contact: -1
    property bool sent: false
    /// Submit was pressed: what GitHub gets is shown before the browser
    /// opens.
    property bool reviewing: false
    /// The blank form was opened (the text is on the clipboard).
    property bool blankSent: false
    readonly property string typed: text.text
    readonly property string issueTitle: reviewing ? backend.feedbackIssueTitle(JSON.stringify({ kind: kind, text: typed })) : ""
    readonly property bool ready: text.text.trim().length > 0 && share >= 0 && contact >= 0
    function folder() { if (!dir) dir = backend.feedbackDir(); return dir }
    function addFile(p) { if (p && files.indexOf(p) < 0) files = files.concat([p]) }
    function capture() {
        if (!captureTarget) return
        const path = folder() + "/Screenshot " + (files.filter(f => /Screenshot/.test(f)).length + 1) + ".png"
        captureTarget.grabToImage(r => { if (r.saveToFile(path)) win.addFile(path) })
    }
    // Submit shows what GitHub gets first; nothing opens yet.
    function submit() { reviewing = true }
    // Opens the issue form, filled in with only what you typed (or blank,
    // your text on the clipboard); the details, and the masked logs if you
    // chose to share them, are saved in the report's folder (which opens)
    // for you to review and drop in.
    function send(blank) {
        const report = { kind: kind, text: text.text, area: area, context: context, share_logs: share === 0, contact: contact === 0, files: files, dir: folder(), blank: blank }
        const url = backend.feedbackIssueUrl(JSON.stringify(report))
        openUrl(url)
        if (dryRun) console.warn("FEEDBACK open", "file://" + folder()); else backend.openLocalPath(folder())
        blankSent = blank
        reviewing = false
        sent = true
    }
    // --feedback-test logs the addresses instead of opening a browser.
    readonly property bool dryRun: Qt.application.arguments.indexOf("--feedback-test") >= 0
    function openUrl(u) {
        if (dryRun) console.warn("FEEDBACK open", u)
        else backend.openExternal(u)
    }

    // The window's buttons (96 x 31.3 at least, 14/600; brand or outline).
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        signal clicked()
        width: Math.max(96, dbText.implicitWidth + 24); height: 31.3; radius: 4
        color: db.primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill)
                          : dbTap.pressed ? theme.pick("#E0E0E0", "#2E2E2E", "#1AEBFF") : dbHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
        border.color: db.primary ? "transparent" : theme.stroke; border.width: db.primary ? 0 : 0.67
        Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 6; color: "transparent"; border.width: 2; border.color: theme.text; visible: db.activeFocus }
        Text { id: dbText; anchors.centerIn: parent; text: db.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(db, db.primary ? theme.textOnBrand : theme.text) }
        HoverHandler { id: dbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: dbTap; onTapped: db.clicked() }
        activeFocusOnTab: true
        Keys.onSpacePressed: db.clicked()
        Keys.onReturnPressed: db.clicked()
        Keys.onEnterPressed: db.clicked()
        Accessible.role: Accessible.Button
        Accessible.name: db.label
        Accessible.onPressAction: db.clicked()
    }

    Rectangle { anchors.fill: parent; color: theme.surface }
    ChildWindowTitleBar { id: titleRow; title: win.title; width: parent.width }

    // The form.
    Item {
        id: form
        visible: !win.sent && !win.reviewing
        x: 24; y: 58; width: parent.width - 48; height: parent.height - y
        Text {
            x: 24; y: 24; height: 28
            text: qsTr("Submit feedback to OST")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        // The questions (they scroll; the footer and buttons stay).
        Flickable {
            id: questions
            x: 0; y: 58; width: parent.width; height: 484.7 - 58
            contentHeight: col.height + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Item {
                id: col
                width: questions.width
                height: contactNo.y + contactNo.height
                Text {
                    x: 26; y: 4; height: 24; verticalAlignment: Text.AlignVCenter
                    textFormat: Text.StyledText
                    text: (win.compliment ? qsTr("What did you like?") : qsTr("What did you dislike?")) + " <font color=\"#D13438\">*</font>"
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Rectangle {
                    id: box
                    x: 26.7; y: 30.7; width: Math.min(669.3, col.width - 40); height: 112; radius: 4
                    color: theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: text.activeFocus ? 2 : 0.67; color: text.activeFocus ? theme.brand : theme.textSecondary }
                    ScrollView {
                        anchors.fill: parent; anchors.margins: 1
                        TextArea {
                            id: text
                            wrapMode: TextArea.Wrap
                            leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            placeholderText: qsTr("Do not include any private or sensitive information.")
                            placeholderTextColor: theme.textSecondary
                            background: null
                            selectByMouse: true
                            // Pasting a picture adds it to the report.
                            Keys.onPressed: e => {
                                if (e.matches(StandardKey.Paste)) {
                                    const p = backend.pasteClipboardImage(win.folder())
                                    if (p) { win.addFile(p); e.accepted = true }
                                }
                            }
                            Accessible.name: win.compliment ? qsTr("What did you like?") : qsTr("What did you dislike?")
                        }
                    }
                }
                // Add more details.
                DropArea {
                    id: drop
                    x: 26; y: 157.3; width: col.width - 40; height: details.y + details.height - y
                    onDropped: d => { for (const u of d.urls) win.addFile(decodeURIComponent(String(u).replace(/^file:\/\//, ""))) }
                    Rectangle { anchors.fill: parent; anchors.margins: -4; radius: 4; visible: drop.containsDrag; color: "transparent"; border.color: theme.brand; border.width: 1 }
                }
                Text { x: 26; y: 157.3; text: qsTr("Add more details"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: 26; y: 181.3; text: qsTr("Drag and drop files here or paste an image from your clipboard"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                component OutlineButton: Rectangle {
                    id: ob
                    property string icon: ""
                    property string label: ""
                    signal clicked()
                    height: 31.3; radius: 4
                    width: (icon ? 12.7 + 20 + 8 : 12) + obText.implicitWidth + 12
                    color: obTap.pressed ? theme.pick("#E0E0E0", "#2E2E2E", "#1AEBFF") : obHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                    border.color: obHover.hovered ? theme.pick("#C7C7C7", "#757575", "#1AEBFF") : theme.stroke; border.width: 0.67
                    FluentIcon { visible: !!ob.icon; x: 12.7; anchors.verticalCenter: parent.verticalCenter; name: ob.icon; size: 20; color: theme.onFill(ob, theme.text) }
                    Text { id: obText; x: ob.icon ? 12.7 + 20 + 8 : 12; anchors.verticalCenter: parent.verticalCenter; text: ob.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(ob, theme.text) }
                    TapHandler { id: obTap; onTapped: ob.clicked() }
                    HoverHandler { id: obHover; cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.Button
                    Accessible.name: ob.label
                }
                Row {
                    x: 26; y: 201.3; spacing: 8
                    OutlineButton { icon: "screenshot-20"; label: qsTr("Capture screenshot"); onClicked: win.capture() }
                    OutlineButton { icon: "attach-20"; label: qsTr("Attach file"); onClicked: picker.open() }
                }
                // What's been added: a 64 px picture (or the file's icon and
                // name) with an × to take it off.
                Flow {
                    id: details
                    x: 26; y: win.files.length ? 242.6 : 232.6; width: col.width - 40; spacing: 8
                    Repeater {
                        model: win.files
                        Rectangle {
                            required property string modelData
                            readonly property bool picture: /\.(png|jpe?g|gif|bmp|webp)$/i.test(modelData)
                            width: picture ? 96 : 200; height: 64; radius: 4
                            color: theme.pick("#F5F5F5", "#2E2E2E", "#000000"); border.color: theme.stroke; border.width: 0.67
                            Image { visible: parent.picture; anchors.fill: parent; anchors.margins: 2; source: parent.picture ? "file://" + parent.modelData : ""; fillMode: Image.PreserveAspectFit; asynchronous: true }
                            FluentIcon { visible: !parent.picture; x: 8; anchors.verticalCenter: parent.verticalCenter; name: "document-20"; size: 20; color: theme.textSecondary }
                            Text { visible: !parent.picture; x: 34; width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.split("/").pop(); elide: Text.ElideMiddle; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                            Rectangle {
                                id: hcFill1
                                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 2
                                width: 20; height: 20; radius: 10; color: xh.hovered ? theme.hover : theme.pick("#FFFFFFCC", "#000000AA", "#000000")
                                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 12; color: theme.onFill(hcFill1, theme.text) }
                                HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: win.files = win.files.filter(f => f !== parent.parent.modelData) }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Remove %1").arg(parent.modelData.split("/").pop())
                            }
                        }
                    }
                }
                // Share relevant content samples and additional log files?
                Text {
                    id: shareQ
                    x: 26; y: details.y + details.height + (win.files.length ? 10 : 10.7); height: 22.7; verticalAlignment: Text.AlignVCenter
                    textFormat: Text.StyledText
                    text: qsTr("Share relevant content samples and additional log files?") + " <a href=\"learn\">" + qsTr("Learn more") + "</a> <font color=\"#D13438\">*</font>"
                    linkColor: theme.brandLink
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    onLinkActivated: backend.openExternal(backend.feedbackLink("privacy-feedback"))
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                component Radio: Item {
                    id: rb
                    property string label
                    property bool checked: false
                    signal picked()
                    width: 58 + rbText.implicitWidth + 8; height: 32
                    Rectangle {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16; radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: rb.checked ? theme.brand : rbHover.hovered ? theme.text : theme.textSecondary
                        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; visible: rb.checked; color: theme.brand }
                    }
                    Text { id: rbText; x: 32; anchors.verticalCenter: parent.verticalCenter; text: rb.label; font.family: theme.font; font.pixelSize: 14; color: rb.checked ? theme.text : theme.textSecondary }
                    HoverHandler { id: rbHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: rb.picked() }
                    activeFocusOnTab: true
                    Keys.onSpacePressed: rb.picked()
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: rb.label
                    Accessible.checked: rb.checked
                }
                Radio { id: shareYes; x: 26; y: shareQ.y + 21.4; label: qsTr("Yes, share"); checked: win.share === 0; onPicked: win.share = 0 }
                Radio { id: shareNo; x: 26; y: shareYes.y + 32; label: qsTr("No, don't share"); checked: win.share === 1; onPicked: win.share = 1 }
                Text {
                    id: contactQ
                    x: 26; y: shareNo.y + 40; height: 24; verticalAlignment: Text.AlignVCenter
                    textFormat: Text.StyledText
                    text: qsTr("May we contact you about your feedback?") + " <font color=\"#D13438\">*</font>"
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Radio { id: contactYes; x: 26; y: contactQ.y + 26; label: qsTr("Yes, you may contact me"); checked: win.contact === 0; onPicked: win.contact = 0 }
                Radio { id: contactNo; x: 26; y: contactYes.y + 32; label: qsTr("No, don't contact me"); checked: win.contact === 1; onPicked: win.contact = 1 }
            }
        }
        Text {
            x: 24; y: 492; width: Math.min(690, parent.width - 48)
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            lineHeight: 13.3; lineHeightMode: Text.FixedHeight
            linkColor: theme.brandLink
            text: (backend.userMail ? qsTr("Signed in as %1.").arg(backend.userMail) + " " : "")
                + "<a href=\"learn\">" + qsTr("Learn more") + "</a>"
                + qsTr(" about how this data is used and your rights. By pressing Submit, you see what goes to GitHub (%1) before your browser opens it as a public issue. Your feedback will be used to improve OST.").arg(backend.feedbackLink("repo").replace("https://github.com/", ""))
                + " <a href=\"privacy\">" + qsTr("Privacy statement") + ".</a>"
            font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary
            onLinkActivated: l => backend.openExternal(backend.feedbackLink(l === "privacy" ? "privacy" : "privacy-feedback"))
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Rectangle {
            id: hcFill2
            x: parent.width - 228; y: 536; width: 96; height: 31.3; radius: 4
            color: win.ready ? (submitHover.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E", "#000000")
            Text { anchors.centerIn: parent; text: qsTr("Submit"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, win.ready ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
            HoverHandler { id: submitHover; cursorShape: win.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: win.ready; onTapped: win.submit() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Submit")
        }
        Rectangle {
            id: hcFill3
            x: parent.width - 120; y: 536; width: 96; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, theme.text) }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Cancel")
        }
    }

    // After Submit: what GitHub gets, and when, before the browser opens.
    Item {
        id: review
        visible: win.reviewing && !win.sent
        x: 24; y: 58; width: parent.width - 48; height: parent.height - y
        Text {
            x: 24; y: 24; height: 28
            text: qsTr("Before your browser opens")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Flickable {
            id: reviewScroll
            x: 0; y: 58; width: parent.width; height: 484.7 - 58
            contentHeight: reviewCol.height + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: reviewCol
                x: 26; y: 4; width: Math.min(669.3, reviewScroll.width - 40)
                spacing: 12
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("Your browser opens a new public issue on GitHub (%1), filled in with your feedback and your answer to “May we contact you about your feedback?” GitHub receives them as soon as the page opens, even if you never select Create.").arg(backend.feedbackRepo())
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Text {
                    text: qsTr("What GitHub receives")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                }
                Rectangle {
                    id: sentBox
                    width: parent.width; height: sentCol.height + 16; radius: 4
                    color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                    border.color: theme.stroke; border.width: 0.67
                    Column {
                        id: sentCol
                        x: 12; y: 8; width: parent.width - 24
                        spacing: 4
                        Text {
                            width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                            text: win.issueTitle
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(sentBox, theme.text)
                        }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                            maximumLineCount: 8; elide: Text.ElideRight
                            text: win.typed.trim()
                            font.family: theme.font; font.pixelSize: 14; color: theme.onFill(sentBox, theme.text)
                        }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: win.contact === 0 ? qsTr("Yes, you may contact me") : qsTr("No, don't contact me")
                            font.family: theme.font; font.pixelSize: 12; color: theme.onFill(sentBox, theme.textSecondary)
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("Your screenshots, files and the report details stay on this device, with OST's log lines if you chose to share them. OST opens their folder so you can review them and attach only what you want.")
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("To send GitHub nothing until you select Create, copy your text and open a blank form instead. Then paste your text into it.")
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
            }
        }
        Row {
            x: Math.max(24, parent.width - 24 - width); y: 536
            spacing: 12
            DialogButton { primary: true; label: qsTr("Open filled-in form"); onClicked: win.send(false) }
            DialogButton { label: qsTr("Copy text and open a blank form"); onClicked: win.send(true) }
            DialogButton { label: qsTr("Back"); onClicked: win.reviewing = false }
        }
    }

    // After Submit: finish on GitHub.
    Item {
        visible: win.sent
        x: 48; y: 82; width: parent.width - 96; height: parent.height - y
        Text {
            id: thanks
            text: qsTr("Thank you for your feedback")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Text {
            y: thanks.height + 16; width: parent.width
            wrapMode: Text.Wrap
            text: win.blankSent
                ? qsTr("Finish on GitHub: your text is on the clipboard. Paste it (Ctrl+V) into the form, add a title and whether we may contact you, review the report details and any other files in the folder that opened, drop in what you want to share, and select Create.")
                : win.files.length
                ? qsTr("Finish on GitHub: paste your screenshot (Ctrl+V), review the report details and any other files in the folder that opened, drop in what you want to share, and select Create.")
                : qsTr("Finish on GitHub: review the report details in the folder that opened, drop the file in if you want to share it, and select Create.")
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        Rectangle {
            id: hcFill4
            x: parent.width - 96 + 24; y: 536 + 58 - 82; width: 96; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: qsTr("Close"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.text) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
    }

    FileDialog {
        id: picker
        title: qsTr("Attach file")
        fileMode: FileDialog.OpenFiles
        onAccepted: { for (const u of selectedFiles) win.addFile(decodeURIComponent(String(u).replace(/^file:\/\//, ""))) }
    }
    Shortcut { sequence: "Escape"; onActivated: if (win.reviewing && !win.sent) win.reviewing = false; else win.close() }

    // Test hooks.
    function fillForTest(t, s, c) { text.text = t; share = s; contact = c }
    function captureForTest() { capture() }
    function reviewForTest() { submit() }
    function sendForTest(blank) { send(blank) }
}
