import QtQuick
import QtQuick.Controls.Basic
import com.ost.desktop

// Teams' simplified compose (266342), measured on winpc. The same box is the
// chat's compose and the in-place editor of a message (Teams edits in place
// with this component).
// - The box: white, a 0.67 px NeutralStroke2 border, radius 6; focused, a
//   2 px brand line along its bottom.
// - Single-line state: the editor (padding 10 16 8 12, 14/20, min 38 tall)
//   with the side toolbar on its right: 32 px buttons 6.7 from the top, then
//   the send group (a 24 px divider 4 in, Send 8.7 in), 6.7 from the end.
// - Multiline state (the formatting bar open, a quote or files, or text over
//   one line): the editor across the box and a 44.7 px bottom toolbar with
//   the same buttons, 6 down, ending 6.7 from the right. While editing, the
//   send group is Cancel and Done.
// - The formatting bar (open with Format): 43 tall, 32 px buttons from
//   (6.7, 9.7) in groups 8.6 apart with a divider between; Discard (Cancel
//   while editing) at the end. The editor is then at least 104 tall.
// - Under the box, when it isn't empty: "Shift+Enter starts a new line."
//   (or "Enter starts a new line." with the bar open or Enter set to a new
//   line), 12/16, right-aligned 17 in; the key is a link to Settings.
// - Enter: Ctrl+Enter sends; Enter sends only with the Enter setting at its
//   default and the bar closed; Shift+Enter is a new line.
// - Cancelling an edit (or Discard) asks first: Teams' "Discard draft".
// - `post`: Teams' channel post composer (Post in channel, measured on
//   winpc 2026-11-09). A card (shadow 0 0 2 / 0 4 8) with the author row
//   (56.7, 16.7 in, a #E0E0E0 line: avatar 32, name 14/20 semibold at 58.7,
//   Close or Discard 48.7 from the right), "Add a subject" (18 px, padding
//   15 0 16, 10.7 in, a #616161 underline, brand when focused; 250
//   characters), the formatting bar always open with Announcement, the
//   editor (at least 104), then 16 under it the tools from 8.7 and Post (96
//   x 31.3) 16.7 from the right, 17.4 above the bottom. Announcement adds
//   the banner (12.7 in, 69.3 down, 244 tall, radius 4, its colour scheme):
//   "Type a headline" (40/52 semibold, centred, 44 characters) and, 12.8
//   from its bottom right, Color scheme and Upload an image; the subject
//   becomes "Add a subheading" 12 under it.
Item {
    id: root
    property bool editing: false
    property string placeholder: "Type a message"
    property var quote: null
    property var files: []
    property bool formatting: false
    // Teams' delivery option for the next message: "", "high" or "urgent";
    // offered outside channels, Urgent only up to 20 members.
    property string importance: ""
    /// A Threads-layout thread's reply target (Teams' "Send to:"): "" (none
    /// shown), "thread" (thread only) or "channel" (thread and channel).
    property string sendTo: ""
    property bool deliveryOptions: true
    property bool urgentAllowed: true
    signal scheduleMeetingRequested()
    // People who can be @mentioned here (the chat's members): [{mri, name, mail}].
    property var mentionables: []
    // Whether the picker also searches the directory (1:1 chats and
    // channels; group chats suggest their members, as Teams does).
    property bool mentionDirectory: true
    // Everyone (group chats): the conversation id, and how many are in it
    // (Teams: up to 250; two or fewer get plain text).
    property string everyoneId: ""
    // In a channel: the channel and its team, mentionable as Teams' channel
    // picker offers them ({id, name}; the team's id is its thread id).
    property var channelMention: null
    // Group chats offer "Add someone to the chat" in the @ picker.
    property bool canAddPeople: false
    signal addPeopleRequested()
    // Group chats and channels offer "Add agent to the chat / channel",
    // which opens Teams' agent Store.
    property bool canAddAgent: false
    signal addAgentRequested()
    property var teamMention: null
    // The team's tags ({id, name, count}), offered after the team and
    // channel as Teams' picker does.
    property var tagMentions: []
    property int memberCount: 0
    /// A meeting's chat (Everyone allows up to 1,000 others there).
    property bool meetingChat: false
    // Teams' Everyone rules (messaging settings, live: group chats 250
    // others, meeting chats 1,000; a banner past 50; module 168932).
    readonly property int everyoneOthers: Math.max(0, memberCount - 1)
    readonly property bool everyoneAllowed: everyoneOthers <= (meetingChat ? 1000 : 250)

    // Teams' compose banner (notificationBanner, measured on winpc
    // 2026-11-09): a 29.3 tall bar on top of the box, the box's width,
    // radius 4 4 0 0, #E6E6E6 with a #E0E0E0 line, its text 14/20 #424242
    // 16.7 in, Close notification (28, a 16 px dismiss) at the end. It goes
    // after 3 s. Danger banners (Everyone past 50) use Teams' alert danger
    // colours (red foreground, background1, border).
    property string bannerText: ""
    property bool bannerDanger: false
    readonly property real bannerShownH: bannerText ? 29.3 : 0
    function showBanner(text, danger, decayMs) {
        bannerText = text; bannerDanger = !!danger
        bannerDecay.interval = decayMs || 3000; bannerDecay.restart()
    }
    Timer { id: bannerDecay; onTriggered: root.bannerText = "" }
    // The Enter setting: "send" (Teams' Default) or "newline".
    property string enterKey: backend.setting("enterKey") || "send"
    readonly property alias editor: input
    readonly property bool empty: input.length === 0 && files.length === 0 && !quote
    // Once the text wraps the box stays multiline until it is empty again
    // (Teams 461103 / 458473).
    property bool grown: false
    // Editing always uses the multiline layout (Teams, measured).
    /// Teams' compact compose (pane under 480 px): the editor across the
    /// box and the tools in the bottom row.
    property bool compact: false
    readonly property bool multiline: !!sendTo || post || editing || compact || formatting || files.length > 0 || !!quote || grown
    // Teams' channel post composer.
    property bool post: false
    property bool announcement: false
    property string subject: ""
    property string headline: ""
    property string bannerTheme: "0"
    // The banner's picture (the cropped PNG) and its size.
    property string bannerImage: ""
    property int bannerImageW: 0
    property int bannerImageH: 0
    readonly property real bannerH: bannerImage ? 200 : 244
    readonly property bool postEmpty: empty && !subject.trim() && !headline.trim() && !bannerImage
    signal closeRequested()
    // The formatting bar shows (always in the post composer).
    readonly property bool fmtOn: formatting || post
    // The delivery header ("IMPORTANT!") is 26 tall above the editor; the
    // post composer's author row and subject (and banner) are above it.
    readonly property real headerH: post ? 57.3 + (announcement ? 12 + bannerH + 12 : 0) + 55.7 : importance ? 26 : sendTo ? 25 : 0
    readonly property real boxHeight: post ? headerH + 43 + editorArea.height + 16 + 31.3 + 17.4
        : headerH + (multiline
        ? (formatting ? 43 : 0) + editorArea.height + 44.7
        : Math.max(45.3, input.contentHeight + 18 + 7.3))
    signal submit()
    signal cancelled()
    signal quoteDismissed()
    signal fileRemoved(string path)
    signal emojiRequested(Item anchor)
    signal attachRequested()
    signal typed()
    signal settingsRequested()
    width: 748
    height: bannerShownH + boxHeight + 2 + (post ? 0 : 16)

    function plainText() { return input.getText(0, input.length) }
    // The text as clean HTML (RichText), for Teams' message HTML.
    function formattedText() { return rich.exportHtml() }
    // What applies at the cursor (the formatting bar's pressed buttons),
    // and where the quotes and code blocks are.
    property var richState: ({})
    property var richRegions: []
    function refreshRichState() {
        try { richState = JSON.parse(rich.state(input.cursorPosition)) } catch (e) { richState = ({}) }
        try { richRegions = JSON.parse(rich.regions()) } catch (e) { richRegions = [] }
    }
    // Teams' code block languages (id, name), as its editor lists them.
    readonly property var codeLanguages: [["plaintext", "Plain Text"], ["bash", "Bash"], ["c", "C"], ["cpp", "C++"], ["csharp", "C#"], ["css", "CSS"],
        ["dart", "Dart"], ["dockerfile", "DockerFile"], ["dos", "DOS"], ["go", "Go"], ["graphql", "GraphQL"], ["html", "HTML"], ["http", "HTTP"],
        ["java", "Java"], ["javascript", "JavaScript"], ["json", "JSON"], ["jsp", "JSP"], ["jsx", "JSX"], ["kotlin", "Kotlin"], ["kql", "KQL"],
        ["latex", "LaTeX"], ["lisp", "Lisp"], ["markdown", "Markdown"], ["objectivec", "Objective-C"], ["octave", "Octave"], ["perl", "Perl"],
        ["php", "PHP"], ["powershell", "PowerShell"], ["python", "Python"], ["r", "R"], ["ruby", "Ruby"], ["rust", "Rust"], ["scala", "Scala"],
        ["scss", "SCSS"], ["shell", "Shell"], ["sql", "SQL"], ["swift", "Swift"], ["typescript", "TypeScript"], ["vbnet", "VB.NET"],
        ["vbscript", "VBScript"], ["verilog", "Verilog"], ["vhdl", "VHDL"], ["xml", "XML"], ["yaml", "YAML"]]
    function codeLanguageName(id) { const l = codeLanguages.find(l => l[0] === id); return l ? l[1] : "Plain Text" }
    MenuPopup {
        id: langMenu
        parent: Overlay.overlay
        property var region: null
        items: root.codeLanguages.map(l => ({ label: l[1], checked: !!langMenu.region && langMenu.region.lang === l[0] }))
        height: Math.min(implicitHeight, 320)
        onPicked: i => { if (region) { rich.apply(region.start, region.start, "lang", root.codeLanguages[i][0]); root.refreshRichState() } }
    }
    // A formatting bar command on the selection (or the word at the cursor).
    function format(op, arg) {
        const a = input.selectionStart, b = input.selectionEnd
        rich.apply(a, b, op, arg || "")
        input.forceActiveFocus()
        refreshRichState()
    }
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function setPlain(t) { input.clear(); if (t) input.insert(0, escapeHtml(t)) }
    function setHtml(h) { input.clear(); if (h) input.insert(0, h); input.cursorPosition = input.length }
    function clear() { input.clear(); media = [] }
    // One of your messages to edit: its edit form keeps the emoticons,
    // custom emoji and pictures (as Teams' edit does); else its text.
    function setMessage(m) {
        media = m.edit_media || []
        // Mention tokens in Teams' colour; a shared contact's icon.
        const tokens = String(m.edit_html || "").replace(/<a href="(mention[^"]*)">/g, '<a href="$1" style="color:' + theme.brandForeground1 + '; text-decoration:none">')
        setHtml(m.edit_html ? theme.messageHtml(tokens) : (m.html || escapeHtml(m.text || "")))
    }
    function insertText(t) { input.insert(input.cursorPosition, t); input.forceActiveFocus() }
    // What the fun picker put in: [{src, kind, id, title, unicode, url, width,
    // height}], each shown as an <img> with that src and sent in Teams' form.
    property var media: []
    function insertMedia(m) {
        media = media.concat([m])
        // As the compose box shows them: emoticons in the line (20), GIFs
        // fitted to 444 x 250 (as sent), stickers at 180.
        let w = 20, h = 20
        if (m.kind === "gif") {
            const s = Math.min(1, 444 / Math.max(1, m.width), 250 / Math.max(1, m.height))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        } else if (m.kind === "sticker") { w = 180; h = 180 }
        else if (m.kind === "image") {
            const s = Math.min(1, 240 / Math.max(1, m.width), 180 / Math.max(1, m.height))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        }
        input.insert(input.cursorPosition, "<img src=\"" + m.src + "\" width=\"" + w + "\" height=\"" + h + "\">")
        input.forceActiveFocus()
    }
    // The picked items still in the text.
    function mediaInUse() {
        const html = input.getFormattedText(0, input.length)
        return media.filter(m => html.indexOf(m.src) >= 0)
    }
    function focusEditor() { input.forceActiveFocus() }
    // Teams opens the post composer in its subject.
    function focusSubject() { if (post) subjectField.forceActiveFocus(); else input.forceActiveFocus() }
    function wrapSelection(tag) {
        format({ b: "bold", i: "italic", u: "underline", s: "strike", ul: "ul", ol: "ol" }[tag] || tag, "")
    }
    function requestCancel() { discardDialog.open() }

    // The compose banner.
    Rectangle {
        visible: !!root.bannerText
        width: parent.width; height: root.bannerShownH + 4; radius: 4
        color: root.bannerDanger ? theme.pick("#FCF4F6", "#3E1F25") : theme.pick("#E6E6E6", "#3D3D3D")
        border.color: root.bannerDanger ? theme.pick("#F3D6D8", "#4F222B") : theme.divider; border.width: 0.67
        Text {
            x: 16.7; y: 4.7; width: parent.width - 16.7 - 36
            elide: Text.ElideRight
            text: root.bannerText
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.bannerDanger ? theme.pick("#C4314B", "#E73550") : theme.textStrong
        }
        Item {
            x: parent.width - 28.7; y: 0.7; width: 28; height: 28
            FluentIcon { x: 3.5; y: 7.25; size: 16; name: "dismiss-16"; color: closeBannerHover.hovered ? theme.brand : (root.bannerDanger ? theme.pick("#C4314B", "#E73550") : theme.textStrong) }
            HoverHandler { id: closeBannerHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.bannerText = "" }
            ToolTip.visible: closeBannerHover.hovered; ToolTip.delay: 500; ToolTip.text: "Close this notification"
            Accessible.role: Accessible.Button
            Accessible.name: "Close notification"
        }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.bannerText
    }
    // The post composer's elevation (Fluent shadow 8).
    FluentSurface { visible: root.post; y: box.y; width: box.width; height: box.height; depth: 8; radius: 6; color: theme.surface }
    Rectangle {
        id: box
        y: root.bannerShownH
        width: parent.width; height: root.boxHeight
        radius: 6
        color: theme.surface
        border.color: theme.divider
        border.width: 0.67
        clip: true

        // The post composer's author row, subject or banner and subheading.
        Item {
            id: postHead
            visible: root.post
            width: parent.width; height: root.post ? root.headerH : 0
            Item {
                x: 16.7; y: 0.7; width: parent.width - 33.3; height: 56.7
                Avatar { x: 0; y: 12; size: 32; name: backend.userName; photoId: backend.userMri || "" }
                Text {
                    x: 42; y: 18; text: backend.userName
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
                }
                Rectangle {
                    x: parent.width - 32; y: 12.3; width: 32; height: 31.3; radius: 4
                    color: postCloseHover.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 20; name: root.postEmpty ? "dismiss-20" : "delete-20"; color: postCloseHover.hovered ? theme.brand : theme.textStrong }
                    HoverHandler { id: postCloseHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.postEmpty ? root.closeRequested() : root.requestCancel() }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.postEmpty ? "Close" : "Discard"
                }
                Rectangle { y: Math.round(parent.height - 1); width: parent.width; height: 1; color: theme.divider }
            }
            // Announcement: the banner.
            Rectangle {
                id: bannerEdit
                visible: root.announcement
                x: 12.7; y: 69.3; width: parent.width - 25.3; height: root.bannerH; radius: 4
                // With a picture the headline is white over it.
                readonly property var colors: root.bannerImage ? [theme.banner(root.bannerTheme)[0], "#FFFFFF"] : theme.banner(root.bannerTheme)
                color: colors[0]
                clip: true
                Image {
                    visible: !!root.bannerImage
                    anchors.fill: parent
                    source: root.bannerImage
                    fillMode: Image.PreserveAspectCrop
                    smooth: true; mipmap: true
                }
                // Delete background image (32 x 33.3, 80% white, radius 6,
                // 12.7 from the top right).
                Rectangle {
                    visible: !!root.bannerImage
                    x: parent.width - 12.7 - width; y: 12.7; width: 32; height: 33.3; radius: 6
                    color: delImgHover.hovered ? theme.surface : Qt.rgba(1, 1, 1, 0.8)
                    border.color: theme.stroke; border.width: 0.67
                    FluentIcon { anchors.centerIn: parent; size: 20; name: "delete-20"; color: delImgHover.hovered ? theme.brand : theme.textStrong }
                    HoverHandler { id: delImgHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.bannerImage = ""; root.bannerImageW = 0; root.bannerImageH = 0 } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Delete background image"
                }
                border.width: 0.67
                border.color: parseInt(root.bannerTheme, 10) >= 6 ? Qt.rgba(1, 1, 1, theme.dark ? 0.1 : 0.2) : Qt.rgba(0, 0, 0, theme.dark ? 0.1 : 0.05)
                TextEdit {
                    id: headlineEdit
                    x: 1.3 + 12; width: parent.width - 2.7 - 24
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: TextEdit.AlignHCenter
                    wrapMode: TextEdit.Wrap
                    text: root.headline
                    onTextChanged: {
                        if (text.length > 44) { const c = cursorPosition; text = text.slice(0, 44); cursorPosition = Math.min(c, 44) }
                        if (text !== root.headline) root.headline = text
                    }
                    font.family: theme.font; font.pixelSize: 40; font.weight: Font.DemiBold
                    color: bannerEdit.colors[1]
                    selectionColor: theme.selectionFill
                    Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) root.trySubmit(); else subjectField.forceActiveFocus() }
                    Text {
                        visible: !headlineEdit.text && !headlineEdit.preeditText
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: "Type a headline"; font: headlineEdit.font; color: bannerEdit.colors[1]
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Type a headline"
                }
                Rectangle {
                    x: parent.width - 12.8 - width; y: parent.height - 12.6 - height
                    width: 65.3; height: 32.7; radius: 4
                    color: theme.surface
                    Rectangle {
                        id: schemeButton
                        x: 0.7; y: 0.7; width: 32; height: 31.3; radius: 4
                        color: schemeHover.hovered ? theme.hover : "transparent"
                        Rectangle {
                            anchors.centerIn: parent; width: 16; height: 16; radius: 4
                            color: bannerEdit.colors[0]
                            border.width: 0.67; border.color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.2)
                        }
                        HoverHandler { id: schemeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: schemes.opened ? schemes.close() : schemes.open() }
                        ToolTip.visible: schemeHover.hovered && !schemes.opened; ToolTip.delay: 500; ToolTip.text: "Color scheme"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Color scheme, " + theme.bannerNames[parseInt(root.bannerTheme, 10) || 0]
                        // Teams' scheme picker: 12 swatches (16, radius 4) in
                        // two rows of six, 28 apart, above the button with its
                        // right edge on the button's.
                        Popup {
                            id: schemes
                            x: parent.width - width; y: -height - 0.7
                            width: 181.3; height: 69.3; padding: 0
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            Repeater {
                                model: 12
                                Rectangle {
                                    required property int index
                                    x: 12.6 + 28 * (index % 6); y: 12.7 + 28 * Math.floor(index / 6)
                                    width: 16; height: 16; radius: 4
                                    color: theme.banner(String(index))[0]
                                    border.width: 0.67; border.color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.2)
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { root.bannerTheme = String(parent.index); schemes.close() } }
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.checked: root.bannerTheme === String(index)
                                    Accessible.name: theme.bannerNames[index]
                                }
                            }
                        }
                    }
                    Rectangle {
                        x: 32.7; y: 0.7; width: 32; height: 31.3; radius: 4
                        color: uploadHover.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; size: 20; name: "image-add-20"; color: uploadHover.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: uploadHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: bannerImageDialog.start() }
                        ToolTip.visible: uploadHover.hovered; ToolTip.delay: 500; ToolTip.text: "Upload an image"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Upload an image"
                    }
                }
            }
            // Add a subject / Add a subheading.
            Item {
                x: 10.7; y: 57.3 + (root.announcement ? 12 + root.bannerH + 12 : 0)
                width: parent.width - 21.3; height: 55.7
                TextInput {
                    id: subjectField
                    x: 12; y: 15; width: parent.width - 24; height: 24
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 250
                    text: root.subject
                    onTextEdited: root.subject = text
                    font.family: theme.font; font.pixelSize: 18
                    color: theme.text
                    selectionColor: theme.selectionFill
                    selectByMouse: true
                    clip: true
                    Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) root.trySubmit(); else input.forceActiveFocus() }
                    Keys.onTabPressed: input.forceActiveFocus()
                    Text {
                        visible: !subjectField.text && !subjectField.preeditText
                        text: root.announcement ? "Add a subheading" : "Add a subject"
                        font: subjectField.font; color: theme.pick("#707070", "#ADADAD")
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: root.announcement ? "Add a subheading" : "Add a subject"
                }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width
                    height: subjectField.activeFocus ? 2 : 0.67
                    color: subjectField.activeFocus ? theme.brand : theme.textSecondary
                }
            }
        }

        // The delivery option header (measured): 14/20 bold uppercase,
        // DarkOrange foreground for Important, 16 in, 26 tall.
        Text {
            visible: !!root.importance
            x: 16.7; y: 3; height: 20; verticalAlignment: Text.AlignVCenter
            text: root.importance === "urgent" ? "URGENT!" : "IMPORTANT!"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
            color: root.importance === "urgent" ? theme.redForeground3 : theme.pick("#DA3B01", "#E9835E")
        }
        // "Send to: thread only ⌄" (measured on winpc 2026-11-10): 12 px
        // brand, "Send to:" bold, a 12 px chevron 4 after; 12 in, 5 down. Its
        // menu (Thread only / Thread and channel) opens above it.
        Item {
            id: sendToRow
            visible: !!root.sendTo
            x: 12; y: 5; height: 20
            width: sendToLabel.implicitWidth + 4 + 12
            Text {
                id: sendToLabel
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: "<b>Send to:</b> " + (root.sendTo === "channel" ? "thread and channel" : "thread only")
                font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
            }
            FluentIcon { x: sendToLabel.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.brandForeground1 }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sendToMenu.open() }
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: sendToLabel.text.replace(/<[^>]+>/g, "")
            MenuPopup {
                id: sendToMenu
                y: -height - 4; x: -35
                items: [{ label: "Thread only", checked: root.sendTo !== "channel" }, { label: "Thread and channel", checked: root.sendTo === "channel" }]
                onPicked: i => { root.sendTo = i === 1 ? "channel" : "thread"; input.forceActiveFocus() }
            }
        }
        // The formatting bar (Teams' simplified-formatting-toolbar).
        FormatBar {
            id: formatBar
            visible: root.fmtOn
            post: root.post
            onAnnouncementToggled: { root.announcement = !root.announcement; if (root.announcement) headlineEdit.forceActiveFocus() }
            x: root.post ? 0.7 : 0; y: root.headerH; width: parent.width
            editing: root.editing
            st: root.richState
            selectedText: input.selectedText
            onCommand: (op, arg) => root.format(op, arg)
            onDiscardRequested: root.requestCancel()
            onUndoRequested: { input.undo(); input.forceActiveFocus() }
            onRedoRequested: { input.redo(); input.forceActiveFocus() }
        }

        // The editor: across the box (multiline) or left of the side toolbar.
        Item {
            id: editorArea
            x: root.post ? 11.3 : 0.67
            y: root.headerH + (root.fmtOn ? 43 : 0.67)
            width: root.post ? parent.width - 11.3 : root.multiline ? parent.width - 1.33 : parent.width - 1.33 - sideTools.width
            height: Math.max(root.fmtOn ? 104 : 38, quoteCard.visible ? 14.7 + quoteCard.height + 4 + input.contentHeight + 8 : input.contentHeight + 18)
            // Teams' quote box and code card behind the text's quote and
            // code runs (RichText marks them; their margins make room).
            Repeater {
                model: root.richRegions
                Item {
                    id: region
                    required property var modelData
                    readonly property rect r0: input.positionToRectangle(modelData.start)
                    readonly property rect r1: input.positionToRectangle(modelData.end)
                    readonly property bool code: modelData.kind === "code"
                    x: input.x; width: input.width
                    y: input.y + r0.y - (code ? 40 : 7)
                    height: r1.y + r1.height + (code ? 8 : 7) - (r0.y - (code ? 40 : 7))
                    Rectangle {
                        anchors.fill: parent
                        radius: region.code ? 8 : 4
                        color: theme.surface
                        border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                    }
                    // The quote's bar.
                    Rectangle { visible: !region.code; x: 3; y: 3; width: 2.67; height: parent.height - 6; radius: 1.5; color: theme.pick("#D1D1D1", "#666666") }
                    // The code card's header: icon, language (a menu), and
                    // the line under it; line numbers in the gutter.
                    Item {
                        visible: region.code
                        width: parent.width; height: 32
                        FluentIcon { x: 10.7; anchors.verticalCenter: parent.verticalCenter; name: "code-block-20"; size: 20; color: theme.textSecondary }
                        Row {
                            x: 36.7; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            Text {
                                text: region.modelData.lang ? root.codeLanguageName(region.modelData.lang) : "Plain Text"
                                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                            }
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { langMenu.region = region.modelData; const p = region.mapToItem(Overlay.overlay, 36.7, 32); langMenu.x = p.x; langMenu.y = p.y; langMenu.open() } }
                        }
                        Rectangle { y: 31.3; width: parent.width; height: 0.67; color: theme.pick("#D1D1D1", "#666666") }
                    }
                    Repeater {
                        model: region.code ? region.modelData.lines : 0
                        Text {
                            required property int index
                            x: 12; width: 30; height: 24
                            y: 40 + index * 24
                            horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                            text: index + 1
                            font.family: theme.mono; font.pixelSize: 14; color: theme.pick("#8A8886", "#ADADAD")
                        }
                    }
                }
            }
            QuoteCard {
                id: quoteCard
                visible: !!root.quote
                x: 12.67; y: 14
                quote: root.quote
                dismissable: true
                maxWidth: editorArea.width - 28
                onDismissed: { root.quoteDismissed(); input.forceActiveFocus() }
            }
            Flow {
                id: fileChips
                visible: root.files.length > 0
                x: 12; y: (quoteCard.visible ? 14 + quoteCard.height + 4 : 10); width: parent.width - 28
                spacing: 8
                Repeater {
                    model: root.files
                    Rectangle {
                        required property string modelData
                        height: 40; width: Math.min(300, chipName.implicitWidth + 80)
                        radius: 8
                        color: theme.searchFill
                        border.color: theme.divider
                        FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 24; color: theme.textSecondary }
                        Text {
                            id: chipName
                            x: 40; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 76
                            text: parent.modelData.split("/").pop()
                            elide: Text.ElideMiddle
                            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                            color: theme.text
                        }
                        ToolButton32 {
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            icon: "dismiss-20"; label: "Remove " + parent.modelData.split("/").pop()
                            onClicked: root.fileRemoved(parent.modelData)
                        }
                    }
                }
            }
            TextEdit {
                id: input
                x: 12
                y: quoteCard.visible ? 14 + quoteCard.height + 4 : fileChips.visible ? fileChips.y + fileChips.height + 8 : 10
                width: parent.width - 12 - 16
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                selectByMouse: true
                persistentSelection: true
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                selectionColor: theme.selectionFill
                selectedTextColor: theme.text
                Text {
                    visible: input.length === 0 && !input.preeditText
                    text: root.placeholder
                    font: input.font; color: theme.textSecondary
                }
                onTextChanged: { if (length > 0) root.typed(); else root.grown = false; root.checkMention(); root.refreshRichState() }
                onCursorPositionChanged: { root.checkMention(); root.refreshRichState() }
                // The formatting bar's commands act on this text's document.
                RichText { id: rich }
                onLineCountChanged: if (lineCount > 1) root.grown = true
                onActiveFocusChanged: if (activeFocus) root.enterKey = backend.setting("enterKey") || "send"
                Keys.onPressed: event => {
                    if (!(event.modifiers & Qt.ControlModifier)) return
                    const shift = event.modifiers & Qt.ShiftModifier
                    const alt = event.modifiers & Qt.AltModifier
                    // Teams: Ctrl+Shift+X the bar, Ctrl+Shift+C inline code,
                    // Ctrl+Shift+B code block, Ctrl+Alt+X strikethrough,
                    // Ctrl+Shift+I Important.
                    if (shift && event.key === Qt.Key_X) root.formatting = !root.formatting
                    else if (shift && event.key === Qt.Key_C) root.format("code", "")
                    else if (shift && event.key === Qt.Key_B) root.format("codeblock", "")
                    else if (shift && event.key === Qt.Key_I && root.deliveryOptions) root.importance = root.importance === "high" ? "" : "high"
                    else if (alt && event.key === Qt.Key_X) root.format("strike", "")
                    else if (!shift && !alt && event.key === Qt.Key_B) root.wrapSelection("b")
                    else if (!shift && !alt && event.key === Qt.Key_I) root.wrapSelection("i")
                    else if (!shift && !alt && event.key === Qt.Key_U) root.wrapSelection("u")
                    else return
                    event.accepted = true
                }
                Keys.onReturnPressed: event => {
                    if (mentionPicker.opened) { mentionPicker.pick(); return }
                    // Teams: Enter on an empty quote line leaves the quote.
                    if (root.richState.quote && root.richState.empty && !(event.modifiers & Qt.ControlModifier)) { root.format("quote", ""); return }
                    root.enterPressed(event)
                }
                Keys.onEnterPressed: event => { if (mentionPicker.opened) { mentionPicker.pick(); return } root.enterPressed(event) }
                Keys.onTabPressed: event => { if (mentionPicker.opened) mentionPicker.pick(); else event.accepted = false }
                Keys.onUpPressed: event => { if (mentionPicker.opened) mentionPicker.move(-1); else event.accepted = false }
                Keys.onDownPressed: event => { if (mentionPicker.opened) mentionPicker.move(1); else event.accepted = false }
                Keys.onEscapePressed: event => { if (mentionPicker.opened) mentionPicker.close(); else event.accepted = false }
                Accessible.role: Accessible.EditableText
                Accessible.name: root.placeholder
            }
            TapHandler { onTapped: input.forceActiveFocus() }
        }

        // The toolbar buttons (side in single-line, bottom in multiline).
        Row {
            id: sideTools
            visible: !root.multiline
            x: parent.width - width - 6.7; y: root.headerH + 6.7
            Repeater { model: root.toolModel; delegate: toolDelegate }
            Item {
                width: 8.7 - 4 + 4; height: 32
                Rectangle { x: 4; y: 4; width: 1; height: 24; color: theme.stroke }
            }
            Repeater { model: root.endModel; delegate: toolDelegate }
        }
        // The post composer's tools (from 8.7) and Post.
        Item {
            visible: root.post
            x: 0; y: parent.height - 17.4 - 31.3 - 0.35; width: parent.width; height: 32
            Row {
                x: 8.7
                Repeater { model: root.postTools; delegate: toolDelegate }
            }
            Rectangle {
                x: parent.width - 16.7 - width; y: 0
                width: 96; height: 31.3; radius: 4
                color: postHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Post"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                HoverHandler { id: postHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.trySubmit() }
                Accessible.role: Accessible.Button
                Accessible.name: "Post"
            }
        }
        Item {
            id: bottomBar
            visible: root.multiline && !root.post
            x: 0; y: parent.height - 44.7; width: parent.width; height: 44.7
            Row {
                x: parent.width - width - 6.7; y: 6
                Repeater { model: root.toolModel; delegate: toolDelegate }
                Item {
                    width: 8.7; height: 32
                    Rectangle { x: 4; y: 4; width: 1; height: 24; color: theme.stroke }
                }
                Repeater { model: root.endModel; delegate: toolDelegate }
            }
        }

        // Focused: Fluent's 2 px brand line along the bottom.
        Rectangle {
            visible: input.activeFocus && !root.post
            x: 0; y: parent.height - 2; width: parent.width; height: 2
            color: theme.brand
        }
    }

    // The hint under the box (the post composer's too, measured).
    Row {
        visible: !root.empty
        anchors.right: parent.right; anchors.rightMargin: root.post ? 0 : 17
        y: root.bannerShownH + root.boxHeight + 2
        spacing: 4
        Text {
            text: root.fmtOn || root.enterKey === "newline" ? "Enter" : "Shift+Enter"
            font.family: theme.font; font.pixelSize: theme.small; color: theme.brandForeground1
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            HoverHandler { id: hintHover; cursorShape: Qt.PointingHandCursor }
            font.underline: hintHover.hovered
            TapHandler { onTapped: root.settingsRequested() }
            Accessible.role: Accessible.Link
            Accessible.name: "Select " + text + " to open settings"
        }
        Text {
            text: "starts a new line."
            font.family: theme.font; font.pixelSize: theme.small; color: theme.text
            lineHeight: 16; lineHeightMode: Text.FixedHeight
        }
    }

    // Toolbar items, in Teams' order (§15). Loop components and Actions and
    // apps are not built yet.
    readonly property var toolModel: [
        { id: "expand-compose", icon: "format-20", label: root.formatting ? "Hide Formatting options" : "Show Formatting options", pressed: root.formatting },
        { id: "UnifiedFunPicker", icon: "emoji-20", label: "Emoji, GIFs and Stickers" },
        { id: "FilePicker", icon: "attach-20", label: "Attach files (Alt+Shift+O)", hidden: root.editing },
        { id: "message-extension-flyout-command", icon: "add-20", label: "Actions and apps", hidden: root.editing }
    ].filter(t => !t.hidden)
    readonly property var endModel: root.editing
        ? [{ id: "discard-draft", icon: "dismiss-20", label: "Cancel" }, { id: "send", icon: "checkmark-20", label: "Done" }]
        : [{ id: "send", icon: "send-20", label: "Send", ready: !root.empty }]
    Component {
        id: toolDelegate
        ToolButton32 {
            id: tbd
            required property var modelData
            icon: modelData.id === "send" && !root.editing && modelData.ready ? "send-20-filled" : modelData.icon
            label: modelData.label
            pressedState: !!modelData.pressed
            accent: modelData.id === "send" && !root.editing && !!modelData.ready
            onClicked: root.toolClicked(modelData.id, tbd)
        }
    }
    function toolClicked(id, item) {
        if (id === "expand-compose") { formatting = !formatting; input.forceActiveFocus() }
        else if (id === "UnifiedFunPicker") root.emojiRequested(item)
        else if (id === "FilePicker") root.attachRequested()
        else if (id === "message-extension-flyout-command") { plusFlyout.anchorItem = item; plusFlyout.open() }
        else if (id === "discard-draft") root.requestCancel()
        else if (id === "send") root.trySubmit()
    }
    function trySubmit() {
        if (root.empty) return
        // Teams: an announcement needs its headline (AnnouncementPostMissingTitle).
        if (root.post && root.announcement && !root.headline.trim()) {
            root.showBanner("You'll need to add a headline to post your announcement.", false, 3000)
            return
        }
        root.submit()
    }
    // The post composer's tools under the editor (Teams: Emoji, GIFs and
    // Stickers, Attach files, Actions and apps).
    readonly property var postTools: [
        { id: "UnifiedFunPicker", icon: "emoji-20", label: "Emoji, GIFs and Stickers" },
        { id: "FilePicker", icon: "attach-20", label: "Attach files" },
        { id: "message-extension-flyout-command", icon: "add-20", label: "Actions and apps" }
    ]
    /// Back to an empty post composer.
    function resetPost() { subject = ""; headline = ""; bannerTheme = "0"; announcement = false; bannerImage = ""; bannerImageW = 0; bannerImageH = 0 }
    /// The next post's fields for backend.setNextPost.
    function postFields() {
        return JSON.stringify({ subject: subject, title: headline, theme: announcement ? bannerTheme : "",
            image: announcement ? bannerImage.replace(/^file:\/\//, "") : "", imageWidth: bannerImageW, imageHeight: bannerImageH })
    }
    BannerImageDialog {
        id: bannerImageDialog
        onPicked: (path, w, h) => { root.bannerImage = path; root.bannerImageW = w; root.bannerImageH = h }
    }
    function enterPressed(event) {
        const ctrl = event.modifiers & Qt.ControlModifier
        const shift = event.modifiers & Qt.ShiftModifier
        if (ctrl) { root.trySubmit(); return }
        if (shift || root.enterKey === "newline" || root.fmtOn) { event.accepted = false; return }
        root.trySubmit()
    }

    // A 32 px Fluent subtle icon button: #424242, hover shows the filled
    // glyph in brand.
    component ToolButton32: Item {
        id: tb
        property string icon
        property string label
        property bool pressedState: false
        property bool accent: false
        signal clicked()
        width: 32; height: 32
        FluentIcon {
            anchors.centerIn: parent; size: 20
            name: tbHover.hovered || tb.pressedState ? tb.icon.replace(/-filled$/, "") + "-filled" : tb.icon
            color: tbHover.hovered || tb.pressedState || tb.accent ? theme.brand : theme.textStrong
        }
        HoverHandler { id: tbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
        ToolTip {
            visible: tbHover.hovered; delay: 500
            y: -height - 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: tb.label; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // "+" Actions and apps (measured): 341.3 wide, a search box, then Teams'
    // own items as 36 px rows (20 px icon 8 in, the label at 40). Installed
    // apps' actions are not built yet.
    Popup {
        id: plusFlyout
        property Item anchorItem: null
        parent: Overlay.overlay
        width: 341.3; padding: 0
        height: 62.7 + itemsCol.height + 14.7
        x: anchorItem ? Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width) : 0
        y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - 8 : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onOpened: { search.text = ""; search.forceActiveFocus() }
        readonly property var items: [
            { key: "delivery", label: "Set delivery options", icon: "important-20", hidden: !root.deliveryOptions },
            { key: "meeting", label: "Schedule meeting", icon: "calendar-add-20" }
        ].filter(i => !i.hidden && i.label.toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0)
        Rectangle {
            x: 14.7; y: 17.3; width: 310; height: 30.7; radius: 4
            color: theme.surface
            border.color: search.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: search.activeFocus ? 2 : 0.67; color: search.activeFocus ? theme.brand : theme.textSecondary }
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
            TextInput {
                id: search
                x: 34.6; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                Text { visible: !search.text; text: "Search for apps"; font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search for apps"
            }
        }
        Column {
            id: itemsCol
            x: 14.7; y: 62.7
            Repeater {
                model: plusFlyout.items
                Rectangle {
                    required property var modelData
                    width: 310; height: 36; radius: 4
                    color: rowHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 8; y: 8; name: parent.modelData.icon; size: 20; color: theme.textStrong }
                    Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            plusFlyout.close()
                            if (parent.modelData.key === "delivery") { deliveryPopup.anchorItem = plusFlyout.anchorItem; deliveryPopup.open() }
                            else root.scheduleMeetingRequested()
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
        }
    }
    // Delivery options (measured): 317.3 x 161.3; 48 px options with a 16 px
    // icon at (16, 18.3), the title 14/18.7 and description 12/16 at 40.7,
    // the selected one NeutralBackground1Hover with a checkmark at 284.
    Popup {
        id: deliveryPopup
        property Item anchorItem: null
        parent: Overlay.overlay
        width: 317.3; height: 161.3; padding: 0
        x: anchorItem ? Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width + 50) : 0
        y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - 8 : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            x: 0.7; y: 8.7
            Repeater {
                model: [
                    { key: "", title: "Standard", desc: "Message will be sent as usual", icon: "chat-20", color: "", name: "Standard Message Delivery" },
                    { key: "high", title: "Important", desc: "Message will be marked as important", icon: "important-20", color: "#C4314B", name: "Mark message as important" },
                    { key: "urgent", title: "Urgent", desc: root.urgentAllowed ? "Recipient notified every 2 min for 20 min" : "Unavailable in chats with more than 20 people", icon: "alert-urgent-20", color: "#C4314B", name: "Mark message as urgent and repeatedly notify recipient every 2 minutes for 20 minutes" }
                ]
                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool selected: root.importance === modelData.key
                    readonly property bool enabledNow: modelData.key !== "urgent" || root.urgentAllowed
                    width: 316; height: 48
                    color: selected || (optHover.hovered && enabledNow) ? theme.menuHover : "transparent"
                    FluentIcon {
                        x: opt.modelData.key === "urgent" ? 20 : 16; y: 16; size: 16
                        name: opt.modelData.icon
                        color: !opt.enabledNow ? theme.disabled : opt.modelData.color || theme.text
                    }
                    Text { x: opt.modelData.key === "urgent" ? 44.7 : 40.7; y: 6.6; text: opt.modelData.title; font.family: theme.font; font.pixelSize: 14; color: opt.enabledNow ? theme.text : theme.disabled }
                    Text { x: opt.modelData.key === "urgent" ? 44.7 : 40.7; y: 25.3; text: opt.modelData.desc; font.family: theme.font; font.pixelSize: 12; color: opt.enabledNow ? theme.text : theme.disabled }
                    FluentIcon { visible: opt.selected; x: 284; y: 16; name: "checkmark-20"; size: 16; color: theme.text }
                    HoverHandler { id: optHover; cursorShape: opt.enabledNow ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: opt.enabledNow; onTapped: { root.importance = opt.modelData.key; deliveryPopup.close(); input.forceActiveFocus() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                    Accessible.selected: selected
                }
            }
        }
    }
    // @mentions (930187, measured): typing "@" at a word start opens Teams'
    // picker over the caret; picking inserts the name, each word its own
    // mention token in BrandForeground1, then a space.
    property int mentionAt: -1
    property string mentionQuery: ""
    function checkMention() {
        const pos = input.cursorPosition
        const before = input.getText(0, pos)
        const at = before.lastIndexOf("@")
        const q = at >= 0 ? before.slice(at + 1) : ""
        const ok = at >= 0 && (at === 0 || /\s/.test(before[at - 1])) && !/[\n\u2029]/.test(q) && q.length <= 40 && (q.match(/ /g) || []).length <= 2
        if (!ok) { mentionAt = -1; if (mentionPicker.opened) mentionPicker.close(); return }
        mentionAt = at; mentionQuery = q
        if (q.trim().length >= 2 && root.mentionDirectory) backend.searchPeople(q.trim())
        if (!mentionPicker.opened) mentionPicker.open()
        mentionPicker.current = 0
    }
    function insertMention(person) {
        if (mentionAt < 0) return
        if (person.kind === "add" || person.kind === "agent") {
            // The "@" and what follows it go; Teams' dialog opens.
            input.remove(mentionAt, Math.max(mentionAt, input.cursorPosition))
            mentionAt = -1; mentionPicker.close()
            if (person.kind === "agent") root.addAgentRequested(); else root.addPeopleRequested()
            return
        }
        if (person.kind === "share") {
            // Teams' "Share someone's contact info": the "@" and what
            // follows it go; the dialog puts the cards in.
            shareAt = mentionAt; shareEnd = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            shareContact.start()
            return
        }
        if (person.kind === "team" || person.kind === "channel" || person.kind === "tag") {
            const at1 = mentionAt, end1 = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            input.remove(at1, end1)
            input.insert(at1, '<a href="mention-' + person.kind + ':' + person.mri + '" style="color:' + theme.brandForeground1 + '; text-decoration:none">' + escapeHtml(person.name) + '</a>&nbsp;')
            input.cursorPosition = at1 + person.name.length + 1
            input.forceActiveFocus()
            return
        }
        if (person.everyone) {
            if (!root.everyoneAllowed) return
            // Teams: past 50 others, "# people will be notified".
            if (root.everyoneOthers > 50)
                root.showBanner(root.everyoneOthers === 1 ? "1 person will be notified" : root.everyoneOthers + " people will be notified", true, 3000)
            const at0 = mentionAt, end0 = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            input.remove(at0, end0)
            input.insert(at0, root.memberCount > 2 ? '<a href="mention-everyone:' + root.everyoneId + '" style="color:' + theme.brandForeground1 + '; text-decoration:none">Everyone</a>&nbsp;' : "Everyone&nbsp;")
            input.cursorPosition = at0 + 9
            input.forceActiveFocus()
            return
        }
        const words = String(person.name || "").split(/\s+/).filter(w => w)
        const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
        const html = words.map(w => '<a href="mention:' + person.mri + '" ' + style + '>' + escapeHtml(w) + '</a>').join("&nbsp;") + "&nbsp;"
        const at = mentionAt, end = input.cursorPosition
        mentionAt = -1
        mentionPicker.close()
        input.remove(at, end)
        input.insert(at, html)
        input.cursorPosition = at + words.join(" ").length + 1
        mentionPicker.close()
        input.forceActiveFocus()
    }
    Popup {
        id: mentionPicker
        parent: Overlay.overlay
        width: 300; padding: 0
        height: Math.min(310.3, 43.2 + rowsCol.height + 8)
        closePolicy: Popup.CloseOnPressOutside
        focus: false
        property int current: 0
        readonly property var people: {
            const q = root.mentionQuery.trim().toLowerCase()
            const fromRoster = root.mentionables.filter(p => !q || (p.name || "").toLowerCase().split(/\s+/).some(w => w.startsWith(q)) || (p.name || "").toLowerCase().startsWith(q) || (p.mail || "").toLowerCase().startsWith(q))
            const found = q.length >= 2 && root.mentionDirectory ? (backend.peopleJson ? JSON.parse(backend.peopleJson) : []).map(p => ({ mri: "8:orgid:" + p.id, name: p.name, mail: p.mail || p.email || "" })) : []
            const out = []
            // A channel's team and the channel itself (Teams' channel
            // picker): by a word of their name, or by "team" / "channel".
            const words = n => (n || "").toLowerCase().split(/\s+/)
            const t = root.teamMention, c = root.channelMention
            if (q && t && (words(t.name).some(w => w.startsWith(q)) || t.name.toLowerCase().startsWith(q) || "team".startsWith(q)))
                out.push({ kind: "team", mri: t.id, name: t.name, mail: "Team", photoId: t.groupId })
            if (q && c && (words(c.name).some(w => w.startsWith(q)) || c.name.toLowerCase().startsWith(q) || "channel".startsWith(q)))
                out.push({ kind: "channel", mri: c.id, name: c.name, mail: "Channel", photoId: t ? t.groupId : "" })
            // Tags, by a word of their name ("1 person", "N people").
            if (q) for (const g of root.tagMentions || [])
                if (words(g.name).some(w => w.startsWith(q)) || g.name.toLowerCase().startsWith(q))
                    out.push({ kind: "tag", mri: g.id, name: g.name, mail: g.count === 1 ? "1 person" : g.count + " people" })
            for (const p of fromRoster) out.push(p)
            for (const p of found) if (!out.some(o => o.mri === p.mri)) out.push(p)
            // Everyone: offered up to Teams' limit, shown disabled past it.
            if (root.everyoneId && (!q || "everyone".startsWith(q)))
                out.push({ everyone: true, name: "Everyone", mail: "Notify everyone in the chat", disabled: !root.everyoneAllowed })
            const rows = out.slice(0, 20)
            if (root.canAddAgent) rows.push({ kind: "agent", name: root.channelMention ? "Add agent to the channel" : "Add agent to the chat", mail: "" })
            if (root.canAddPeople) rows.push({ kind: "add", name: "Add someone to the chat", mail: "" })
            // Always last (Teams): share someone's contact card.
            rows.push({ kind: "share", name: "Share someone\u2019s contact info", mail: "" })
            return rows
        }
        function move(d) { if (people.length) current = (current + d + people.length) % people.length }
        function pick() { if (people.length) { const p = people[Math.max(0, Math.min(current, people.length - 1))]; if (!p.disabled) root.insertMention(p) } else close() }
        readonly property rect caret: input.cursorRectangle
        x: { const p = input.mapToItem(Overlay.overlay, input.positionToRectangle(Math.max(0, root.mentionAt)).x, 0); return Math.min(Overlay.overlay.width - width - 8, Math.max(8, p.x)) }
        y: { const p = input.mapToItem(Overlay.overlay, 0, input.positionToRectangle(Math.max(0, root.mentionAt)).y); return Math.max(8, p.y - height - 1) }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Text {
            x: 20.7; y: 10.7; height: 20; verticalAlignment: Text.AlignVCenter
            text: "Suggestions"
            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
        }
        Column {
            id: rowsCol
            // Rows sit 5 apart (measured on winpc, 2026-11-09).
            x: 0.7; y: 43.2; spacing: 5
            Repeater {
                model: mentionPicker.people
                Rectangle {
                    id: prow
                    required property var modelData
                    required property int index
                    readonly property bool action: modelData.kind === "share" || modelData.kind === "add" || modelData.kind === "agent"
                    width: 298.7; height: modelData.kind === "share" || modelData.kind === "agent" || modelData.everyone ? 49.3 : modelData.kind === "add" ? 48.7 : 47.3
                    color: index === mentionPicker.current ? theme.pick("#E6E6E6", "#3D3D3D") : prowHover.hovered ? theme.menuHover : "transparent"
                    Avatar { visible: !prow.modelData.everyone && !prow.modelData.kind; x: 19.6; y: 7.6; size: 32; name: prow.modelData.name; photoId: prow.modelData.mri || "" }
                    // A team or channel: the team's picture, a 4 px square.
                    Avatar {
                        visible: prow.modelData.kind === "team" || prow.modelData.kind === "channel"
                        x: 19.6; y: 7.6; size: 32; square: true
                        readonly property string team: root.teamMention ? root.teamMention.name : ""
                        name: team
                        initialsText: team.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: prow.modelData.photoId ? "team:" + prow.modelData.photoId : ""
                    }
                    // A tag: the tag icon on a 32 px lavender circle.
                    Rectangle {
                        visible: prow.modelData.kind === "tag"
                        x: 19.6; y: 7.6; width: 32; height: 32; radius: 16
                        color: theme.pick("#C5CBFA", "#3D3E78")
                        FluentIcon { anchors.centerIn: parent; name: "tag-20"; size: 20; color: theme.pick("#444791", "#C5CBFA") }
                    }
                    FluentIcon { visible: !!prow.modelData.everyone; x: 25.6; y: 13.6; name: "people-20"; size: 20; color: prow.modelData.disabled ? theme.disabled : theme.textStrong }
                    // Past the limit: Teams' tooltip.
                    ToolTip.visible: !!prow.modelData.disabled && prowHover.hovered; ToolTip.delay: 300
                    ToolTip.text: "Not available for chats over 1,000 users."
                    // Share someone's contact info: the contact card icon (20).
                    FluentIcon { visible: prow.modelData.kind === "share"; x: 19.6; y: 14.6; name: "contact-card-20"; size: 20; color: theme.textStrong }
                    // Add agent: bot-add (20).
                    FluentIcon { visible: prow.modelData.kind === "agent"; x: 19.6; y: 14.6; name: "bot-add-20"; size: 20; color: theme.textStrong }
                    // Add someone to the chat: person-add (20).
                    FluentIcon { visible: prow.modelData.kind === "add"; x: 19.6; y: 14.3; name: "people-add-20"; size: 20; color: theme.textStrong }
                    // The typed part in bold (Teams).
                    Text { x: prow.action ? 59 : 59.6; y: prow.action ? 14.5 : 5.6; height: 20; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; textFormat: prow.action ? Text.PlainText : Text.StyledText; text: prow.action ? prow.modelData.name : root.boldMatch(prow.modelData.name, root.mentionQuery.trim()); font.family: theme.font; font.pixelSize: 14; color: prow.modelData.disabled ? theme.disabled : theme.text }
                    Text { visible: !!prow.modelData.mail; x: 59.6; y: 25.6; height: 16; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; text: prow.modelData.mail || ""; font.family: theme.font; font.pixelSize: 12; color: prow.modelData.disabled ? theme.disabled : theme.text }
                    HoverHandler { id: prowHover; cursorShape: prow.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    TapHandler { enabled: !prow.modelData.disabled; onTapped: root.insertMention(prow.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (modelData.mail ? " " + modelData.mail : "")
                    Accessible.selected: index === mentionPicker.current
                }
            }
        }
    }
    // `name` with the word that starts with `q` bold for its first
    // q.length letters.
    function boldMatch(name, q) {
        const n = String(name || "")
        if (!q) return escapeHtml(n)
        const lower = n.toLowerCase(), ql = q.toLowerCase()
        let i = lower.startsWith(ql) ? 0 : lower.indexOf(" " + ql)
        if (i > 0) i++
        if (i < 0) return escapeHtml(n)
        return escapeHtml(n.slice(0, i)) + "<b>" + escapeHtml(n.slice(i, i + q.length)) + "</b>" + escapeHtml(n.slice(i + q.length))
    }
    // Share someone's contact info: where the "@" was, and the dialog.
    property int shareAt: -1
    property int shareEnd: -1
    ShareContactDialog {
        id: shareContact
        onAccepted: people => {
            const at = root.shareAt, end = root.shareEnd
            if (at < 0) return
            input.remove(at, Math.max(at, Math.min(end, input.length)))
            const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
            const icon = Qt.resolvedUrl("../assets/icons/contact-card-inline-" + (theme.dark ? "dark" : "light") + ".svg")
            const html = people.map(p => '<img src="' + icon + '" width="20" height="20"><a href="mention-contact:' + p.mri + '" ' + style + '>' + escapeHtml(p.name) + '</a>&nbsp;').join("")
            input.insert(at, html)
            input.cursorPosition = at + people.reduce((n, p) => n + 1 + p.name.length + 1, 0)
            root.shareAt = -1
            input.forceActiveFocus()
        }
        onClosed: input.forceActiveFocus()
    }
    function shareContactForTest() { return shareContact }
    function formatBarForTest() { return formatBar }
    // Type a line and format all of it (the formatting bar on a selection).
    function formatLineForTest(text, op, arg) {
        if (input.length > 0) rich.apply(input.length, input.length, "newblock", "")
        const a = input.length
        input.insert(a, escapeHtml(text))
        input.select(a, input.length)
        if (op) format(op, arg)
        input.cursorPosition = input.length
    }
    function pickShareForTest() { insertMention({ kind: "share" }) }
    /// Insert a mention at the cursor, as if picked after an "@".
    function insertMentionOf(person) {
        mentionAt = input.cursorPosition
        insertMention(person)
    }
    function clearForTest() { input.clear(); mentionAt = -1; mentionPicker.close() }
    function mentionForTest(text) { input.insert(input.cursorPosition, text); input.cursorPosition = input.length }
    function pickMentionForTest(n) { mentionPicker.current = n || 0; mentionPicker.pick() }

    function deliveryForTest() { deliveryPopup.anchorItem = sideTools; deliveryPopup.open() }
    function plusForTest() { plusFlyout.anchorItem = sideTools; plusFlyout.open() }

    // Teams' "Discard draft" (messagedraft-discard-dialog): 600 x 156,
    // radius 8; the title 20/28 semibold at 24.7, Close, the text at 62,
    // Cancel and Discard (96 x 31.3) at y 100.
    Popup {
        id: discardDialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 600; height: 156; padding: 0
        anchors.centerIn: Overlay.overlay
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: "#66000000" }
        Text { x: 24.7; y: 24.7; height: 28; verticalAlignment: Text.AlignVCenter; text: "Discard draft"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Rectangle {
            x: 543.3; y: 24.7; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: discardDialog.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Text { x: 22.7; y: 62; height: 32; verticalAlignment: Text.AlignVCenter; text: "You can discard your draft or cancel to keep editing"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        Row {
            x: 375.3; y: 100; spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: dCancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: dCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { discardDialog.close(); input.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
            }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: discardHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Discard"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: "white" }
                HoverHandler { id: discardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { discardDialog.close(); root.formatting = false; input.clear(); if (root.post) root.resetPost(); root.cancelled() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Discard"
            }
        }
    }
    // Test hooks.
    function discardForTest() { discardDialog.open() }
    function openSchemesForTest() { schemes.open() }
    function bannerDialogForTest() { return bannerImageDialog }
    function closeSchemesForTest() { schemes.close() }
    function everyoneRowForTest(n, meeting) { memberCount = n; meetingChat = !!meeting; return { allowed: everyoneAllowed, others: everyoneOthers } }
    function confirmDiscardForTest() { discardDialog.close(); root.formatting = false; input.clear(); if (root.post) root.resetPost(); root.cancelled() }
}
