import QtQuick
import QtQuick.Controls.Basic

// Teams' tab configuration dialog (platform-modal app-configuration
// dialog), for the Website app, measured on winpc 2026-11-16 (CSS px,
// docs/spec/add-a-tab.md):
// - 600 x 593.3, padding 24, radius 8, Teams' dialog shadow;
// - the header (platform-app-config-header) at (24.7, 32.7): the app's
//   36 px round icon on #FAFAFA, its name 14/20 semibold at 72.7, "About"
//   (96 x 31.3, brand 14) and Close (32 x 31.3, dismiss 20 #424242) at the
//   right;
// - the message bar at 91.9: 550.7 x 32.7, #F0F0F0, a 0.67 #D1D1D1 line,
//   radius 4, the 14 px filled info icon at 5.6, "This site will be added
//   as a tab and open in a browser window." (12/16 semibold) at 27.6, and
//   a close button (32 x 31.3);
// - "Tab name" (14/20) at 140.6, its field (550.7 x 32, #F5F5F5, radius
//   4, text at 12, brand focus line) at 160.6 with a 20 px validity icon 10
//   from its end (the filled check in brand, or the filled error circle in
//   red);
// - "URL*" at 222.6, its field at 242.6 (no icon while empty); an invalid
//   URL shows "That isn't a valid URL." (14/20, #D13438) at the label
//   row's end;
// - the hint (12/16, light) at 284.6;
// - the footer at 526.7: the checkbox (checked, brand) and "Post to the
//   chat (channel) about this tab" (14/20) at 60.7; Back (96 x 32,
//   outline) and Save (96 x 32, brand; #F0F0F0 / #BDBDBD while off).
Popup {
    id: root
    /// The app being configured: {id, name, icon}.
    property var app: null
    property bool channel: false
    property string conversationId: ""
    property string teamId: ""
    property bool saving: false
    property string failure: ""
    property bool barShown: true
    /// What another app's configuration page reported (TeamsJS
    /// setValidityState / setSettings).
    property bool appValid: false
    property var appSettings: null
    signal back()
    signal about(var app)
    signal saved(string tabId)
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true
    width: 600; height: 593.3
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }

    readonly property string nameError: {
        const v = nameField.text
        if (v.trim() === "") return "Name is required"
        if (v.length > 128) return "Tab name cannot exceed 128 characters."
        return ""
    }
    readonly property string urlError: backend.websiteUrlError(urlField.text)
    /// The Website app is configured here; any other app's configuration
    /// is its own page, which Teams embeds in this dialog (24.7, 75.9,
    /// 550.7 x 452.8) and which turns Save on through TeamsJS
    /// (pages.config.setValidityState). OST hosts that page in its TeamsJS
    /// host (frameContext settings; docs/spec/app-host.md) and keeps what
    /// it reports; saving another app's tab (settings.save and the tab's
    /// property) isn't built yet, so Save stays off for it.
    readonly property bool website: !!app && app.id === "com.microsoft.teamspace.tab.web"
    readonly property bool valid: website && !nameError && !urlError && urlField.text.length > 0

    function start(a, id, team, isChannel) {
        app = a; conversationId = id; teamId = team || ""; channel = isChannel
        saving = false; failure = ""; barShown = true; appValid = false; appSettings = null
        nameField.text = a && a.name ? a.name : "Website"
        urlField.text = ""
        post.checked = true
        open()
    }
    function save() {
        if (!valid || saving) return
        saving = true; failure = ""
        backend.addWebsiteTab(teamId, conversationId, nameField.text.trim(), urlField.text, post.checked)
    }
    onOpened: urlField.forceActiveFocus()
    Connections {
        target: backend
        enabled: root.opened && root.saving
        function onChannelTabResultChanged() {
            const r = JSON.parse(backend.channelTabResult || "{}")
            if (r.op !== "add" || r.conversation !== root.conversationId) return
            root.saving = false
            if (r.ok) { root.close(); root.saved(r.tab) }
            else root.failure = "Unable to save " + nameField.text.trim() + " tab configuration."
        }
    }

    // A filled field with Fluent's brand focus line.
    component Field: Rectangle {
        id: fld
        property alias input: ti
        property string a11yName: ""
        property string iconName: ""
        property color iconColor: theme.brandFill
        width: 550.7; height: 32; radius: 4
        color: theme.inputFilled; border.width: 0.67; border.color: theme.transparentStroke
        TextInput {
            id: ti
            x: 12; width: parent.width - 12 - (fld.iconName ? 40 : 12); anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
            selectByMouse: true
            Keys.onReturnPressed: root.save()
            Keys.onEnterPressed: root.save()
            Accessible.role: Accessible.EditableText
            Accessible.name: fld.a11yName
        }
        Rectangle { visible: ti.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        FluentIcon {
            visible: !!fld.iconName
            anchors.right: parent.right; anchors.rightMargin: 10.7; anchors.verticalCenter: parent.verticalCenter
            name: fld.iconName || "dismiss-20"; size: 20; color: fld.iconColor
        }
    }
    component Button96: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        width: 96; height: 32; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : (bh.hovered ? theme.menuHover : theme.surface)
        border.width: 0.67; border.color: primary || !enabled ? "transparent" : theme.stroke
        Text { anchors.centerIn: parent; text: b.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(b, !b.enabled ? theme.disabled : b.primary ? theme.textOnBrand : theme.text) }
        HoverHandler { id: bh; cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: b.enabled; onTapped: b.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }

    // Header.
    Item {
        x: 24.7; y: 32.7; width: 550.7; height: 43.2
        Rectangle {
            id: iconBox
            y: 3.6; width: 36; height: 36; radius: 18; color: theme.quoteFill; clip: true
            Image { anchors.fill: parent; source: root.app && root.app.icon ? root.app.icon : ""; sourceSize: Qt.size(72, 72); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true }
            RoundedCorners { anchors.fill: parent; radius: 18; background: theme.surface }
        }
        Text { x: 48; y: 11.6; height: 20; verticalAlignment: Text.AlignVCenter; text: root.app ? root.app.name : ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Rectangle {
            id: aboutBtn
            x: 422.6; y: 5.9; width: 96; height: 31.3; radius: 4
            color: aboutHover.hovered ? theme.menuHover : "transparent"
            Text { anchors.centerIn: parent; text: "About"; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(aboutBtn, theme.brandLink) }
            HoverHandler { id: aboutHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.about(root.app) }
            Accessible.role: Accessible.Button; Accessible.name: "About"
        }
        Rectangle {
            id: closeBtn
            x: 518.6; y: 5.9; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeBtn, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button; Accessible.name: "Close"
        }
    }

    Loader {
        active: root.opened && !root.website && !!root.app && !!root.app.config_url
        x: 24.7; y: 75.9; width: 550.7; height: 452.8
        sourceComponent: WebApp {
            showHeader: false; appName: root.app ? root.app.name : ""; appId: root.app ? root.app.id : ""; home: root.app ? root.app.config_url : ""
            teamsHost: true; frameContext: "settings"; hostThread: root.conversationId
            onHostEvent: (name, json) => { if (name === "validity") root.appValid = JSON.parse(json).valid; else if (name === "settings") root.appSettings = JSON.parse(json) }
        }
    }
    Column {
        visible: root.website
        x: 24.7; y: 91.9; width: 550.7
        // The message bar.
        Rectangle {
            id: bar
            visible: root.barShown
            width: parent.width; height: 32.7; radius: 4
            color: theme.inputFilledDark; border.width: 0.67; border.color: theme.stroke
            FluentIcon { x: 5.6; anchors.verticalCenter: parent.verticalCenter; name: "info-16"; size: 14; color: theme.onFill(bar, theme.text) }
            Text { x: 27.6; anchors.verticalCenter: parent.verticalCenter; text: "This site will be added as a tab and open in a browser window."; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(bar, theme.text) }
            Rectangle {
                id: barClose
                x: parent.width - 37.7; y: 0.7; width: 32; height: 31.3; radius: 4
                color: barCloseHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(barClose, theme.textStrong) }
                HoverHandler { id: barCloseHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.barShown = false }
                Accessible.role: Accessible.Button; Accessible.name: "Close"
            }
            Accessible.role: Accessible.AlertMessage
            Accessible.name: "This site will be added as a tab and open in a browser window."
        }
        Item { width: 1; height: root.barShown ? 16 : 0 }
        Item {
            width: parent.width; height: 20
            Text { text: "Tab name"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { anchors.right: parent.right; text: root.nameError; font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3; Accessible.role: Accessible.AlertMessage; Accessible.name: text }
        }
        Field {
            id: nameBox
            a11yName: "Tab name"
            iconName: root.nameError ? "error-circle-20-filled" : "checkmark-circle-20-filled"
            iconColor: root.nameError ? theme.redForeground1 : theme.brandFill
        }
        Item { width: 1; height: 30 }
        Item {
            width: parent.width; height: 20
            Text { text: "URL*"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { anchors.right: parent.right; text: root.urlError; font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3; Accessible.role: Accessible.AlertMessage; Accessible.name: text }
        }
        Field {
            id: urlBox
            iconName: urlField.text.length === 0 ? "" : root.urlError ? "error-circle-20-filled" : "checkmark-circle-20-filled"
            iconColor: root.urlError ? theme.redForeground1 : theme.brandFill
            a11yName: "URL"
        }
        Item { width: 1; height: 10 }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: "*Make sure you're only linking to sites that start with 'https://' and contain trustworthy web content. That way, you and your team can stay secure."
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.Light; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text
        }
        Item { width: 1; height: 12 }
        Text {
            visible: !!root.failure
            width: parent.width; wrapMode: Text.Wrap
            text: root.failure
            font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3
            Accessible.role: Accessible.AlertMessage; Accessible.name: text
        }
    }
    readonly property TextInput nameField: nameBox.input
    readonly property TextInput urlField: urlBox.input

    // Footer.
    Item {
        x: 24.7; y: 526.7; width: 550.7; height: 42
        Item {
            id: post
            property bool checked: true
            y: 8; width: 56.7 - 24.7 + postLabel.implicitWidth + 12; height: 36
            Rectangle {
                id: box
                x: 8; y: 10; width: 16; height: 16; radius: 2
                color: post.checked ? theme.checkedFill : "transparent"
                border.width: post.checked ? 0 : 1; border.color: theme.textStrong
                FluentIcon { visible: post.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(box, theme.textOnBrand) }
            }
            Text { id: postLabel; x: 36; anchors.verticalCenter: parent.verticalCenter; text: root.channel ? "Post to the channel about this tab" : "Post to the chat about this tab"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: post.checked = !post.checked }
            Accessible.role: Accessible.CheckBox; Accessible.name: postLabel.text; Accessible.checked: checked
        }
        Row {
            anchors.right: parent.right; y: 10; spacing: 10
            Button96 { label: "Back"; onClicked: { root.close(); root.back() } }
            Button96 { label: "Save"; primary: true; enabled: root.valid && !root.saving; onClicked: root.save() }
        }
    }

    function setPost(on) { post.checked = on }
    function fillForTest(name, url) { nameField.text = name; urlField.text = url }
    function stateForTest() { return JSON.stringify({ name: nameField.text, url: urlField.text, nameError: nameError, urlError: urlError, valid: valid, saving: saving, failure: failure, appValid: appValid, appSettings: appSettings }) }
}
