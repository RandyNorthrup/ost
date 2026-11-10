import QtQuick
import QtQuick.Controls.Basic

// Teams' Create a team dialog (measured on winpc 2026-11-09): 600 x 600,
// padding 24, radius 8. Three kinds:
// - scratch (Create team): "Create a team" (18/28 bold); "You're creating
//   a team from scratch." and the "More create team options" link at 37.3;
//   Team name * (12/16) at 71.7 over a filled 550.7 x 32 field ("Give your
//   team a name", a check at its end while the name is good); Description
//   at 142.7 over a 78 tall field ("Let people know what this team is all
//   about"); Team type at 259.7 over a 102.9 x 31.3 button (lock or globe
//   and Private / Public) that opens the team type page; First channel
//   name * with an info button (Teams' tooltip) at 334 over a field with
//   "More naming options" ··· (Set name to General); "What's a team?" (13,
//   brand) at 492; Cancel / Create (96 x 31.3) at 520. Create needs a name
//   and a first channel name.
// - template (Use this template): "Create a team" with a Close button
//   (32 x 31.3); Team name at 40, Description at 111, Team type at 228 and
//   "Customize channels >" (brand, 170.9 x 31.3) at 302.3, which opens the
//   rename page (General fixed, the others editable lines 47 apart; Cancel
//   customizing / Done).
// - clone (From another team): 'You are using "{team}" as a template for a
//   new team' with Close; Team name ("{team} [copy]"), Description,
//   Privacy (14/20) over a dropdown, "Choose what you'd like to include from
//   the original team" (21 bold), Teams' line, and the checkboxes Channels
//   and Apps (always), Tabs, Team settings (on) and Member(s) (off); only
//   Create at the bottom.
// The team type page: "What kind of team will this be?", Privacy, two
// 550.7 x 75 cards (Teams' 48 px tiles; Private "People need permission to
// join", Public "Anyone in your org can join"; the chosen one #F5F5F5) 77
// apart from 86.7, and Back at the bottom left.
// Closing a template or clone asks "Do you want to stop creating this team
// and discard it?" (No, go back / Yes, discard).
Popup {
    id: dlg
    property string kind: "scratch"
    property string page: "form"
    property bool isPublic: false
    property bool creating: false
    /// Opened from the Create team page (Teams adds Close there and asks
    /// before discarding, as for templates).
    property bool fromPage: false
    /// The name was left empty after being visited: Teams' "Required".
    property bool nameTouched: false
    readonly property bool nameError: nameTouched && nameField.text.trim().length === 0
    // template: {id, name, locale, channels: [{id, displayName}], appIds}
    property var template: null
    property var channelNames: []
    // clone: the team {id, name, people}
    property var source: null
    property bool pickTabs: true
    property bool pickSettings: true
    property bool pickMembers: false
    signal moreOptions()
    signal created(string groupId, string threadId)

    readonly property bool nameOk: nameField.text.trim().length > 0 && nameField.text.trim().length <= 256
    readonly property bool canCreate: nameOk && !creating && (kind !== "scratch" || firstField.text.trim().length > 0)

    function reset() {
        page = "form"; isPublic = false; creating = false; nameTouched = false
        nameField.text = ""; descField.text = ""; firstField.text = ""
        pickTabs = true; pickSettings = true; pickMembers = false
    }
    function startScratch(fromPage) { kind = "scratch"; fromPage = !!fromPage; template = null; source = null; reset(); open(); nameField.forceActiveFocus() }
    function startTemplate(t) {
        kind = "template"; source = null; reset()
        template = t
        isPublic = (t.visibility || "Private") === "Public"
        channelNames = (t.channels || []).map(c => c.displayName)
        open(); nameField.forceActiveFocus()
    }
    function startClone(team) {
        kind = "clone"; template = null; reset()
        source = team
        isPublic = !!team["public"]
        nameField.text = (team.name || "") + " [copy]"
        open(); nameField.forceActiveFocus()
    }
    function tryClose() {
        if (kind === "scratch" && !fromPage) close()
        else discard.open()
    }
    function create() {
        if (!canCreate) return
        const a = { mode: kind, name: nameField.text.trim(), description: descField.text, "public": isPublic }
        if (kind === "scratch") a.firstChannel = firstField.text.trim()
        else if (kind === "template") a.template = {
            id: template.id, locale: template.locale || "en-US", appIds: template.app_ids || [],
            channels: (template.channels || []).map((c, i) => ({ id: c.id, displayName: dlg.channelNames[i] || c.displayName }))
        }
        else if (kind === "clone") { a.groupId = source.id; a.pick = { tabs: pickTabs, settings: pickSettings, members: pickMembers } }
        creating = true
        backend.channelAction("create-team", "", "", JSON.stringify(a))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "create-team" || !dlg.creating) return
            dlg.creating = false
            if (r.ok) { dlg.close(); dlg.created(r.data.group_id || "", r.data.thread_id || "") }
            else backend.toast("We couldn't create your team. Please try again.", "error")
        }
    }

    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; height: 600; padding: 24
    closePolicy: Popup.CloseOnEscape
    onAboutToHide: { discard.close(); namingMenu.close() }
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    component Label: Row {
        property string text
        property bool required: false
        spacing: 4
        Text { text: parent.text; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Text { visible: parent.required; text: "*"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.redForeground3 }
    }
    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, btnText.implicitWidth + 24.67); height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text { id: btnText; anchors.centerIn: parent; text: btn.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: !btn.enabled ? theme.disabled : btn.primary ? theme.textOnBrand : theme.text }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
    component CloseButton: Rectangle {
        signal clicked()
        x: 518.7; y: 0; width: 32; height: 31.3; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    component Title: Text {
        width: 510.7; wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
        lineHeight: 28; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    component Link: Text {
        id: link
        property string url
        font.family: theme.font; font.pixelSize: 13; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.brandForeground1
        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        font.underline: linkHover.hovered
        TapHandler { onTapped: Qt.openUrlExternally(link.url) }
        Accessible.role: Accessible.Link
        Accessible.name: text
    }

    // ---- The form ----
    Item {
        id: form
        visible: dlg.page === "form"
        anchors.fill: parent
        readonly property bool scratch: dlg.kind === "scratch"
        readonly property bool clone: dlg.kind === "clone"
        Title {
            y: 0.7
            // One line, as Teams fits it (Selawik runs a little wider).
            wrapMode: Text.NoWrap
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 15
            elide: Text.ElideRight
            text: dlg.kind === "clone" ? "You are using \"" + (dlg.source ? dlg.source.name : "") + "\" as a template for a new team" : "Create a team"
        }
        CloseButton { visible: !form.scratch || dlg.fromPage; onClicked: dlg.tryClose() }
        Row {
            visible: form.scratch
            y: dlg.fromPage ? 40 : 37.3
            Text { text: "You're creating a team from scratch. "; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text {
                text: "More create team options"
                font.family: theme.font; font.pixelSize: 14; font.underline: true
                color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { dlg.close(); dlg.moreOptions() } }
                Accessible.role: Accessible.Link
                Accessible.name: text
            }
        }
        // Scrolls in the clone kind (its checkboxes run past the bottom).
        Flickable {
            id: fields
            y: form.scratch ? (dlg.fromPage ? 75 : 71.7) : 40
            width: form.clone ? 536.7 : 550.7
            height: form.clone ? 520 - 8 - y : 480 - y
            contentHeight: fieldCol.height
            interactive: form.clone
            clip: form.clone
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: form.clone ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; x: 540 }
            Item {
                id: fieldCol
                // Below the name, everything moves down while "Required" shows.
                readonly property real shift: dlg.nameError ? 18 : 0
                width: fields.width
                height: form.clone ? 500 : 420
                Label { text: "Team name"; required: true }
                Rectangle {
                    y: 20; width: parent.width; height: 32; radius: 4
                    color: theme.inputFilled
                    // Teams' Required: a #D13438 outline, its error glyph and
                    // the message (12/16 #BC2F32) 2 under the field; what
                    // follows moves down 18.
                    border.color: dlg.nameError ? theme.pick("#D13438", "#DC626D") : "transparent"; border.width: 0.67
                    FluentIcon { visible: dlg.nameError; x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "error-circle-20-filled"; size: 16; color: theme.pick("#D13438", "#DC626D") }
                    Text { visible: dlg.nameError; y: 34; text: "Required"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.pick("#BC2F32", "#DC626D") }
                    TextInput {
                        id: nameField
                        onActiveFocusChanged: if (!activeFocus) dlg.nameTouched = true
                        x: 12; width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter
                        maximumLength: 256
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        clip: true; selectByMouse: true
                        Text { visible: !nameField.text; anchors.verticalCenter: parent.verticalCenter; text: "Give your team a name"; font: nameField.font; color: theme.textSecondary }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Team name"
                    }
                    FluentIcon { visible: dlg.nameOk && !dlg.nameError; x: parent.width - 32; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-circle-20"; size: 20; color: theme.textSecondary }
                    Rectangle { visible: nameField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
                }
                Label { y: (form.scratch ? 71 : form.clone ? 66 : 71) + fieldCol.shift; text: "Description" }
                Rectangle {
                    y: (form.scratch ? 71 : form.clone ? 66 : 71) + 20 + fieldCol.shift
                    width: parent.width; height: 78; radius: 4
                    color: theme.inputFilled
                    TextEdit {
                        id: descField
                        x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
                        wrapMode: TextEdit.Wrap
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        clip: true; selectByMouse: true
                        Text { visible: !descField.text; text: "Let people know what this team is all about"; font: descField.font; color: theme.textSecondary }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Description"
                    }
                    Rectangle { visible: descField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
                }
                // Team type (scratch, template): a button to the type page.
                Label { visible: !form.clone; y: 188 + fieldCol.shift; text: "Team type" }
                Rectangle {
                    id: typeButton
                    visible: !form.clone
                    y: 216 + fieldCol.shift; width: 102.9; height: 31.3; radius: 4
                    color: typeHover.hovered ? theme.menuHover : theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: dlg.isPublic ? "globe-20" : "lock-closed-20"; size: 20; color: theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: dlg.isPublic ? "Public" : "Private"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    }
                    HoverHandler { id: typeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.page = "type" }
                    ToolTip.visible: typeHover.hovered
                    ToolTip.delay: 600
                    ToolTip.text: "Select the button to change the team type and sensitivity label\nYour current team type is: " + (dlg.isPublic ? "Public\nAnyone in your org can join" : "Private\nPeople need permission to join")
                    Accessible.role: Accessible.Button
                    Accessible.name: "Select the button to change the team type and sensitivity label. Your current team type is: " + (dlg.isPublic ? "Public" : "Private")
                }
                // First channel name (scratch).
                Row {
                    visible: form.scratch
                    y: 262.3 + fieldCol.shift; spacing: 0
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "First channel name"; required: true }
                    Rectangle {
                        width: 20; height: 20; radius: 4
                        color: "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "info-12"; size: 12; color: theme.textStrong }
                        HoverHandler { id: infoHover }
                        ToolTip.visible: infoHover.hovered
                        ToolTip.text: "We create the first channel for you. It'll have basic controls and use the team description, if you added one."
                        Accessible.role: Accessible.Button
                        Accessible.name: "information"
                    }
                }
                Rectangle {
                    visible: form.scratch
                    y: 286.3 + fieldCol.shift; width: parent.width; height: 32; radius: 4
                    color: theme.inputFilled
                    TextInput {
                        id: firstField
                        x: 12; width: 501.3; anchors.verticalCenter: parent.verticalCenter
                        maximumLength: 50
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        clip: true; selectByMouse: true
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "First channel name"
                    }
                    Rectangle {
                        id: namingButton
                        x: 516; y: 4.3; width: 24; height: 23.3; radius: 4
                        color: namingHover.hovered || namingMenu.opened ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 16; color: theme.textStrong }
                        HoverHandler { id: namingHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: namingMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More naming options"
                        MenuPopup {
                            id: namingMenu
                            y: parent.height + 4
                            items: [{ key: "general", label: "Set name to General" }]
                            onPicked: firstField.text = "General"
                        }
                    }
                    Rectangle { visible: firstField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
                }
                // Customize channels > (template).
                Rectangle {
                    visible: dlg.kind === "template"
                    y: 262.3 + fieldCol.shift; width: 170.9; height: 31.3; radius: 4
                    color: customHover.hovered ? theme.menuHover : "transparent"
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Customize channels"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-16"; size: 16; color: theme.brand }
                    }
                    HoverHandler { id: customHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { customRepeater.model = dlg.channelNames.slice(); dlg.page = "customize" } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Customize channels"
                }
                // Clone: privacy and what to copy.
                Text { visible: form.clone; y: 178 + fieldCol.shift; text: "Privacy"; font.family: theme.font; font.pixelSize: 14; lineHeight: 24; lineHeightMode: Text.FixedHeight; color: theme.text }
                Dropdown {
                    visible: form.clone
                    y: 204.7 + fieldCol.shift; width: 536.7; height: 30
                    options: [["private", "Private - People need permission to join"], ["public", "Public - Anyone in your org can join"]]
                    label: dlg.isPublic ? "Public - Anyone in your org can join" : "Private - People need permission to join"
                    accessibleName: "Privacy"
                    onPicked: code => dlg.isPublic = code === "public"
                }
                Text {
                    visible: form.clone
                    y: 262.8 + fieldCol.shift; width: parent.width; wrapMode: Text.Wrap
                    text: "Choose what you'd like to include from the original team"
                    font.family: theme.font; font.pixelSize: 21; font.weight: Font.Bold
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                Text {
                    visible: form.clone
                    y: 330.2 + fieldCol.shift; width: parent.width; wrapMode: Text.Wrap
                    text: "Copy apps, settings, and channels over to your new team. Your existing team won't be changed."
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                Repeater {
                    model: form.clone ? [
                        { label: "Channels", x: 0, y: 380.2, fixed: true },
                        { label: "Tabs", x: 0, y: 412.2, key: "tabs" },
                        { label: "Team settings", x: 0, y: 444.2, key: "settings" },
                        { label: "Apps", x: 268.3, y: 380.2, fixed: true },
                        { label: dlg.source && (dlg.source.people || 0) === 1 ? "Member (1 person)" : "Members (" + (dlg.source ? dlg.source.people || 0 : 0) + " people)", x: 268.3, y: 412.2, key: "members" }
                    ] : []
                    Item {
                        id: cb
                        required property var modelData
                        readonly property bool on: modelData.fixed || (modelData.key === "tabs" ? dlg.pickTabs : modelData.key === "settings" ? dlg.pickSettings : dlg.pickMembers)
                        x: modelData.x; y: modelData.y + fieldCol.shift; width: 32 + cbText.implicitWidth + 12; height: 36
                        Rectangle {
                            x: 8; y: 10; width: 16; height: 16; radius: 2
                            color: cb.on && !cb.modelData.fixed ? theme.brand : "transparent"
                            border.color: cb.modelData.fixed ? theme.disabled : cb.on ? theme.brand : theme.textSecondary; border.width: 0.67
                            FluentIcon { visible: cb.on; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: cb.modelData.fixed ? theme.disabled : "white" }
                        }
                        Text { id: cbText; x: 36; y: 8; text: cb.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: cb.modelData.fixed ? theme.disabled : theme.text }
                        HoverHandler { enabled: !cb.modelData.fixed; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            enabled: !cb.modelData.fixed
                            onTapped: {
                                if (cb.modelData.key === "tabs") dlg.pickTabs = !dlg.pickTabs
                                else if (cb.modelData.key === "settings") dlg.pickSettings = !dlg.pickSettings
                                else dlg.pickMembers = !dlg.pickMembers
                            }
                        }
                        Accessible.role: Accessible.CheckBox
                        Accessible.checked: cb.on
                        Accessible.name: cb.modelData.label
                    }
                }
            }
        }
        Link { visible: !form.clone; y: 492; text: "What's a team?"; url: "https://go.microsoft.com/fwlink/?linkid=2275168" }
        Row {
            anchors.right: parent.right; y: 520
            anchors.rightMargin: form.clone ? 10 : 0
            spacing: 8
            Btn { visible: !form.clone; text: "Cancel"; onClicked: dlg.tryClose() }
            Btn { text: "Create"; primary: true; enabled: dlg.canCreate; onClicked: dlg.create() }
        }
    }

    // ---- The team type page ----
    Item {
        visible: dlg.page === "type"
        anchors.fill: parent
        Title { y: 0.7; text: "What kind of team will this be?" }
        Text { y: 36.7; text: "Privacy"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Repeater {
            model: [[false, "Private", "People need permission to join", "team-type-private.svg"], [true, "Public", "Anyone in your org can join", "team-type-public.svg"]]
            Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property bool chosen: dlg.isPublic === modelData[0]
                y: 62.7 + index * 77; width: 550.7; height: 75; radius: 4
                color: chosen || cardHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Image { x: 12.7; y: 12.7; width: 48; height: 48; source: "../assets/illustrations/" + card.modelData[3]; sourceSize: Qt.size(96, 96) }
                Text { x: 72.7; y: 18.1; text: card.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { x: 72.7; y: 39.1; text: card.modelData[2]; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { dlg.isPublic = card.modelData[0]; dlg.page = "form" } }
                Accessible.role: Accessible.Button
                Accessible.name: card.modelData[1] + ", " + card.modelData[2]
                Accessible.checked: chosen
            }
        }
        Rectangle {
            y: 520; width: 96; height: 31.3; radius: 4
            color: backHover.hovered ? theme.menuHover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-left-20"; size: 20; color: theme.textStrong }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Back"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.page = "form" }
            Accessible.role: Accessible.Button
            Accessible.name: "Back"
        }
    }

    // ---- Customize channels (template) ----
    Item {
        visible: dlg.page === "customize"
        anchors.fill: parent
        Title { y: 0.7; text: "Customize channels" }
        CloseButton { onClicked: dlg.tryClose() }
        Text { y: 40; text: "Rename a channel to customize it for your team."; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
        Repeater {
            id: customRepeater
            model: []
            Item {
                id: chRow
                required property var modelData
                required property int index
                readonly property bool general: index === 0 && (dlg.template && dlg.template.channels && dlg.template.channels[0] && dlg.template.channels[0].id === "General")
                y: 80 + index * 47; width: 550.7; height: 31.3
                TextInput {
                    id: chInput
                    x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                    text: chRow.modelData
                    readOnly: chRow.general
                    font.family: theme.font; font.pixelSize: 14
                    color: chRow.general ? theme.disabled : theme.text
                    clip: true; selectByMouse: true
                    onTextEdited: { const n = customRepeater.model.slice(); n[chRow.index] = text; customRepeater.model = n; chInput.forceActiveFocus(); chInput.cursorPosition = text.length }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: chRow.modelData
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: chInput.activeFocus ? 2 : 0.67; color: chInput.activeFocus ? theme.brand : chRow.general ? theme.divider : theme.textSecondary }
            }
        }
        Row {
            anchors.right: parent.right; y: 520; spacing: 8
            Btn { text: "Cancel customizing"; width: 148; onClicked: dlg.page = "form" }
            Btn { text: "Done"; primary: true; enabled: true; onClicked: { dlg.channelNames = customRepeater.model.slice(); dlg.page = "form" } }
        }
    }

    // Teams' discard question (400 x 154).
    Popup {
        id: discard
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; width: 400; padding: 24
        height: 154
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.2) }
        Text {
            y: 0.7; width: 350.7; wrapMode: Text.Wrap
            text: "Do you want to stop creating this team and discard it?"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            anchors.right: parent.right; y: 74; spacing: 8
            Btn { text: "No, go back"; width: 101.8; onClicked: discard.close() }
            Btn { text: "Yes, discard"; primary: true; width: 98.4; onClicked: { discard.close(); dlg.close() } }
        }
    }

    // Test hooks.
    function setNameForTest(n) { nameField.text = n }
    function setFirstChannelForTest(n) { firstField.text = n }
    function openNamingForTest() { namingMenu.open() }
    function customizeForTest() { customRepeater.model = dlg.channelNames.slice(); dlg.page = "customize" }
    function discardForTest() { discard.open() }
    function bodyForTest() {
        return { mode: kind, name: nameField.text.trim(), description: descField.text, "public": isPublic, firstChannel: firstField.text.trim(), channels: channelNames, pick: { tabs: pickTabs, settings: pickSettings, members: pickMembers } }
    }
}
