import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import com.ost.desktop

// Teams' Video effects and settings pane (calling-right-side-panel,
// measured in a call on winpc, 2026-11-14): 360 wide, #F5F5F5. A 58 px
// header ("Video effects and settings", 16/700, 20.7 in; Close 32 x 30),
// then in a call the tabs Video effects | Settings (44 high, 8.7 in, 14 px,
// the chosen one 600 with a brand underline). Before joining Teams titles
// it "Video effects" and has no tabs.
// - Video effects: the "Backgrounds" accordion (32 px, 12 px title) over a
//   grid of 88 x 50 tiles, three to a 109.1 x 58 cell row from 16.7 in:
//   None, the blur tile (its menu picks Standard or Portrait blur), Add
//   new, 14 of Teams' catalog, then "Show all". Show all opens Teams'
//   Backgrounds view: a back button (32 x 25, "Back to all video effects")
//   and "Backgrounds" (14 px), then None, blur, Add new, your uploads and
//   the whole catalog. Add new takes a .png, .jpeg, .jpg or .bmp picture;
//   Teams' info bar over the grid (#EBEBEB, a #D1D1D1 edge, 37.3 high)
//   says "Background added.", "Background removed." or why it couldn't.
// - Settings: accordions Camera (the cameras as radios), Appearance
//   (Adjust brightness, Soft focus) and Advanced settings (Mirror my
//   video), each row a 14 px #424242 label with Teams' info button and a
//   Fluent switch at the row's end.
// With the camera off in a call Teams adds a footer: "Others won't see
// your video while you preview." (12 px, an info glyph before it), Preview
// (white, 339.3 x 32) — which shows your preview (325.3 x 183) above the
// footer and becomes "Stop preview" — and "Apply and turn on video"
// (brand). The Filters accordion holds Teams' Custom Filters app's Frames
// and Styles (the app runs in VideoFilterHost.qml); Teams' Snapchat and
// Maybelline categories are third-party apps and aren't offered.
// "Green screen settings" opens Settings ▸ Devices at Green Screen.
// Avatars (TASK-0140): with Teams' Avatars app the tabs are Video effects
// | Avatars | Settings (AvatarPanel); "More avatar settings" opens the pane
// on Avatars. Before joining, Teams' "More avatar settings" opens the
// "Avatars" pane (avatarsOnly): that tab's content without Preview and
// Apply.
Rectangle {
    id: root
    /// In a call (tabs and the footer) or before joining.
    property bool inCall: true
    property bool cameraOn: false
    signal closed()
    /// Apply and turn on video.
    signal turnOnVideo()
    /// Apply avatars with none, or preview an avatar while your video is on.
    signal turnOffVideo()
    /// Teams' pre-join "Avatars" pane.
    property bool avatarsOnly: false
    readonly property bool avatarsOffered: !!avatarHost.app.url
    /// Teams' "Green screen settings": Settings ▸ Devices at Green Screen.
    signal greenScreenSettings()
    color: theme.pane

    property string tab: "effects"
    /// Teams' Show all view (the Backgrounds list with your uploads).
    property bool showAll: false
    /// The info bar's text ("" hides it).
    property string notice: ""
    property bool previewing: false
    property var cameras: []
    property string currentCamera: ""
    property var expanded: ({ backgrounds: true, filters: true, camera: true, appearance: true, advanced: true })
    /// The Filters category shown (Teams' chips: Frames, Styles).
    property string filterCategory: "Frames"

    function reload() {
        const d = JSON.parse(backend.videoDevices())
        cameras = d.devices || []
        currentCamera = d.current || ""
        videoEffects.load()
    }
    function setPreview(on) {
        if (on === previewing) return
        previewing = on && backend.setCameraPreview(true)
        if (!on) backend.setCameraPreview(false)
    }
    onVisibleChanged: {
        if (visible) { reload(); flick.contentY = 0 }
        else { setPreview(false); showAll = false; notice = "" }
    }
    // Turning the camera on ends the private preview (the call's video
    // shows the effects now).
    onCameraOnChanged: if (cameraOn) setPreview(false)
    Component.onDestruction: if (previewing) backend.setCameraPreview(false)

    readonly property bool footer: inCall && !cameraOn && !avatarPanel.visible

    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: root.avatarsOnly ? "Avatars" : root.inCall ? "Video effects and settings" : "Video effects"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            id: hcFill1
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(hcFill1, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            ToolTip.visible: closeHover.hovered
            ToolTip.delay: 250
            ToolTip.text: "Close video effects and settings pane"
            Accessible.role: Accessible.Button
            Accessible.name: "Close video effects and settings pane"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // Fluent's TabList: 44 px tabs, 10 px padding, the chosen one's text
    // 600 over a 3 px brand bar the text's width.
    Row {
        id: tabs
        visible: root.inCall && !root.avatarsOnly
        x: 8.67; y: header.y + header.height + 2
        height: visible ? 44 : 0
        Repeater {
            model: [{ k: "effects", t: "Video effects" }].concat(root.avatarsOffered ? [{ k: "avatars", t: "Avatars" }] : []).concat([{ k: "settings", t: "Settings" }])
            Item {
                id: tb
                required property var modelData
                readonly property bool chosen: root.tab === modelData.k
                width: tabText.implicitWidth + 20; height: 44
                Text {
                    id: tabText
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    text: tb.modelData.t
                    font.family: theme.font; font.pixelSize: 14; font.weight: tb.chosen ? Font.DemiBold : Font.Normal
                    color: tb.chosen || tbHover.hovered ? theme.text : theme.textStrong
                }
                Rectangle {
                    visible: tb.chosen || tbHover.hovered
                    x: 10; y: 44 - 3 - 4; width: tabText.implicitWidth; height: 3; radius: 1.5
                    color: tb.chosen ? theme.brand : theme.strokeHover
                }
                HoverHandler { id: tbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.tab = tb.modelData.k }
                Accessible.role: Accessible.PageTab
                Accessible.name: tb.modelData.t
                Accessible.selected: tb.chosen
            }
        }
    }

    function avatarPanelForTest() { return avatarPanel }
    function refreshFrames() { if (avatarPanel.visible) avatarPanel.refreshFrame() }
    AvatarPanel {
        id: avatarPanel
        visible: root.visible && (root.avatarsOnly || (root.inCall && root.tab === "avatars"))
        anchors { top: tabs.visible ? tabs.bottom : header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        inCall: root.inCall
        cameraOn: root.cameraOn
        onTurnOnVideo: root.turnOnVideo()
        onTurnOffVideo: root.turnOffVideo()
    }
    Flickable {
        id: flick
        visible: !avatarPanel.visible
        anchors { top: tabs.visible ? tabs.bottom : header.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: foot.top }
        contentHeight: (root.tab === "effects" || !root.inCall ? effectsCol.implicitHeight : settingsCol.implicitHeight) + 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Video effects.
        Column {
            id: effectsCol
            visible: root.tab === "effects" || !root.inCall
            x: 2; width: 341.3
            // Show all: back to the main view.
            Item {
                visible: root.showAll
                width: 341.3; height: visible ? 31 : 0
                Rectangle {
                    id: hcFill2
                    x: 3; width: 32; height: 25; radius: 4
                    color: backHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "arrow-left-20"; size: 20; color: theme.onFill(hcFill2, theme.textStrong) }
                    HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.showAll = false; flick.contentY = 0 } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Back to all video effects"
                }
                Text {
                    x: 35; y: 2.5; height: 20; verticalAlignment: Text.AlignVCenter
                    text: "Backgrounds"
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
            }
            SectionHeader { visible: !root.showAll; key: "backgrounds"; title: "Backgrounds" }
            // Teams' info bar (Fluent MessageBar).
            Item {
                visible: root.notice.length > 0 && (root.expanded.backgrounds || root.showAll)
                width: 341.3; height: visible ? bar.height + 0.7 : 0
                Rectangle {
                    id: bar
                    x: 18.7; y: 0; width: 319.3; height: Math.max(37.3, noticeText.implicitHeight + 17.3); radius: 4
                    color: theme.pick("#EBEBEB", "#2E2E2E", "#000000")
                    border.color: theme.stroke; border.width: 0.67
                    FluentIcon { x: 12; y: 8.67; name: "info-20-filled"; size: 20; color: theme.textSecondary }
                    Text {
                        id: noticeText
                        x: 40; width: parent.width - 76; anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        text: root.notice
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Rectangle {
                        id: hcFill3
                        x: parent.width - 30; y: 8.67
                        width: 20; height: 20; radius: 4
                        color: nxHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(hcFill3, theme.textStrong) }
                        HoverHandler { id: nxHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.notice = "" }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Dismiss"
                    }
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: root.notice
                }
            }
            Grid {
                visible: root.expanded.backgrounds || root.showAll
                x: 14.7; columns: 3
                bottomPadding: 20
                Cell {
                    EffectTile {
                        x: 4; y: 4
                        kind: "none"; label: "None"; accessibleName: "No background effect"
                        selected: videoEffects.background === "none"
                        onPicked: videoEffects.setBackground("none")
                    }
                }
                Cell {
                    EffectTile {
                        x: 4; y: 4
                        kind: "blur"; label: videoEffects.blurLabel
                        blurKind: videoEffects.blurKind
                        selected: videoEffects.background === "blur"
                        onPicked: videoEffects.setBackground("blur")
                        onBlurPicked: kind => videoEffects.setBlur(kind)
                    }
                }
                Cell {
                    EffectTile {
                        x: 4; y: 4
                        kind: "add"; label: "Add new"
                        accessibleName: "Add new background. Image requirements: Minimal size: 360 × 360 pixels; Maximal size: 2048 × 2048 pixels; File type: jpeg, jpg, png, bmp; Aspect ratio: Less than 4."
                        onPicked: chooser.open()
                    }
                }
                // Your uploads (Show all only), as Teams names them.
                Repeater {
                    model: root.showAll ? videoEffects.uploads : []
                    Cell {
                        required property var modelData
                        EffectTile {
                            x: 4; y: 4
                            thumb: parent.modelData.thumb
                            label: parent.modelData.id; accessibleName: parent.modelData.id + " background effect"
                            removable: true
                            selected: videoEffects.background === parent.modelData.id
                            onPicked: videoEffects.setBackground(parent.modelData.id)
                            onRemoveRequested: root.notice = videoEffects.removeUpload(parent.modelData.id)
                        }
                    }
                }
                Repeater {
                    model: root.showAll ? videoEffects.catalog : videoEffects.catalog.slice(0, 14)
                    Cell {
                        required property var modelData
                        EffectTile {
                            x: 4; y: 4
                            thumb: parent.modelData.thumb; animated: parent.modelData.animated
                            label: parent.modelData.name; accessibleName: parent.modelData.name + " background effect"
                            selected: videoEffects.background === parent.modelData.id
                            onPicked: videoEffects.setBackground(parent.modelData.id)
                        }
                    }
                }
                Cell {
                    visible: !root.showAll && videoEffects.catalog.length > 14
                    EffectTile {
                        x: 4; y: 4
                        kind: "showall"; label: "Show all"; accessibleName: "Show all background effects"
                        onPicked: { root.showAll = true; flick.contentY = 0 }
                    }
                }
            }
            // "Green screen settings" (14/500, brand) and Teams' info
            // button, 8 above the grid's bottom padding ends.
            Item {
                visible: !root.showAll && root.expanded.backgrounds
                width: 341.3; height: visible ? 28 : 0
                Row {
                    x: 18.7; y: -8
                    Text {
                        height: 24; verticalAlignment: Text.AlignVCenter
                        text: "Green screen settings"
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.Medium
                        font.underline: gsHover.hovered
                        color: theme.brand
                        HoverHandler { id: gsHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.greenScreenSettings() }
                        Accessible.role: Accessible.Link
                        Accessible.name: text
                    }
                    InfoButton { info: "Turn on Green screen for a better look when you're using a virtual background." }
                }
            }
            // Teams' Filters (its Custom Filters app): None, the category
            // chips (24 px pills, 12 px/500, brand when chosen, #E6E6E6
            // not; 20 in, 13 below) and the category's filters in the
            // same 88 x 50 grid.
            SectionHeader { visible: !root.showAll && (videoEffects.filters.filters || []).length > 0; key: "filters"; title: "Filters" }
            Column {
                visible: !root.showAll && root.expanded.filters && (videoEffects.filters.filters || []).length > 0
                width: 341.3
                Item {
                    width: 341.3; height: 54
                    EffectTile {
                        x: 18.7; y: 4
                        kind: "none"; label: "None"; accessibleName: "No video effect selected"
                        selected: videoEffects.filter === ""
                        onPicked: videoEffects.setFilter("")
                    }
                }
                Row {
                    x: 18.7; spacing: 5
                    bottomPadding: 13; topPadding: 12
                    Repeater {
                        model: ["Frames", "Styles"]
                        Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool chosen: root.filterCategory === modelData
                            width: chipText.implicitWidth + 14; height: 24; radius: 12
                            color: chosen ? theme.brandForeground1 : chipHover.hovered ? theme.hover : theme.effectTile
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: chip.modelData
                                font.family: theme.font; font.pixelSize: 12; font.weight: Font.Medium
                                color: theme.onFill(chip, chip.chosen ? theme.pick("#FAFAFA", "#FFFFFF", "#FFFFFF") : theme.textStrong)
                            }
                            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.filterCategory = chip.modelData }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: chip.modelData
                            Accessible.checked: chip.chosen
                        }
                    }
                }
                Grid {
                    x: 14.7; columns: 3
                    bottomPadding: 20
                    Repeater {
                        model: (videoEffects.filters.filters || []).filter(f => f.category === root.filterCategory)
                        Cell {
                            required property var modelData
                            EffectTile {
                                x: 4; y: 4
                                thumb: parent.modelData.thumb
                                label: parent.modelData.name; accessibleName: parent.modelData.name
                                selected: videoEffects.filter === parent.modelData.id
                                onPicked: videoEffects.setFilter(parent.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // Settings.
        Column {
            id: settingsCol
            visible: root.inCall && root.tab === "settings"
            x: 4; width: 337.3
            SectionHeader { key: "camera"; title: "Camera" }
            Column {
                visible: root.expanded.camera
                x: 16.7; width: 321.3
                Repeater {
                    model: root.cameras
                    Item {
                        id: cam
                        required property var modelData
                        readonly property bool chosen: root.currentCamera === modelData.path
                        width: 321.3; height: 34.3
                        FluentIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; name: cam.chosen ? "radio-on-20" : "radio-off-20"; size: 20; color: cam.chosen ? theme.brand : theme.textSecondary }
                        Text {
                            x: 26; anchors.verticalCenter: parent.verticalCenter; width: 290
                            elide: Text.ElideRight
                            text: cam.modelData.name
                            font.family: theme.font; font.pixelSize: 14
                            color: cam.chosen ? theme.text : theme.textSecondary
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (cam.chosen) return
                                root.currentCamera = cam.modelData.path
                                backend.setCameraDevice(cam.modelData.path)
                                if (root.previewing) { backend.setCameraPreview(false); backend.setCameraPreview(true) }
                            }
                        }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: cam.modelData.name
                        Accessible.checked: cam.chosen
                    }
                }
                Item { width: 1; height: 16 }
            }
            SectionHeader { key: "appearance"; title: "Appearance" }
            Column {
                visible: root.expanded.appearance
                x: 16.7; width: 321.3
                spacing: 8
                SettingSwitch {
                    label: "Adjust brightness"
                    info: "Enhance the quality of your video in low light conditions."
                    checked: videoEffects.brightness
                    onToggled: videoEffects.setBrightness(!checked)
                }
                SettingSwitch {
                    label: "Soft focus"
                    info: "Smoothen your appearance for a polished look."
                    checked: videoEffects.softFocus
                    onToggled: videoEffects.setSoftFocus(!checked)
                }
                Item { width: 1; height: 0 }
            }
            SectionHeader { key: "advanced"; title: "Advanced settings" }
            Column {
                visible: root.expanded.advanced
                x: 16.7; width: 321.3
                SettingSwitch {
                    label: "Mirror my video"
                    info: "Changing this setting will only change the view for you. This setting doesn’t currently work in Together mode."
                    checked: videoEffects.mirror
                    onToggled: videoEffects.setMirror(!checked)
                }
            }
        }
    }

    // The footer while your camera is off in a call.
    Column {
        id: foot
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: root.footer ? 25 : 0 }
        height: root.footer ? implicitHeight : 0
        visible: root.footer
        Item {
            visible: root.previewing
            x: 10.7; width: 325.3; height: visible ? 196 : 0
            Rectangle {
                width: 325.3; height: 183; radius: 4
                color: theme.stage
                clip: true
                VideoFrame {
                    id: preview
                    anchors.fill: parent
                    visible: hasFrame
                    source: root.previewing ? "self" : ""
                    radius: 4
                    transform: Scale { origin.x: preview.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
                    Timer { interval: 33; repeat: true; running: root.previewing; onTriggered: preview.refresh() }
                }
            }
        }
        Item {
            x: 10.7; width: 339.3; height: 26
            FluentIcon { y: 0; name: "info-16-regular"; size: 16; color: theme.text }
            Text {
                x: 24; y: 0; height: 16; verticalAlignment: Text.AlignVCenter
                text: root.previewing && videoEffects.mirror ? "Others will see this image reversed." : "Others won't see your video while you preview."
                font.family: theme.font; font.pixelSize: 12
                color: theme.text
            }
        }
        Rectangle {
            id: hcFill4
            x: 10.7; width: 339.3; height: 32; radius: 4
            color: root.previewing ? theme.pane : pvHover.hovered ? theme.menuHover : theme.surface
            border.color: pvHover.hovered ? theme.strokeHover : theme.stroke; border.width: 0.67
            Text {
                anchors.centerIn: parent
                text: root.previewing ? "Stop preview" : "Preview"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.onFill(hcFill4, theme.text)
            }
            HoverHandler { id: pvHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.setPreview(!root.previewing) }
            Accessible.role: Accessible.Button
            Accessible.name: root.previewing ? "Stop preview" : "Preview"
        }
        Item { width: 1; height: 10 }
        Rectangle {
            id: hcFill5
            x: 10.7; width: 339.3; height: 32; radius: 4
            color: apHover.hovered ? theme.brandHover : theme.brandFill
            Text {
                anchors.centerIn: parent
                text: "Apply and turn on video"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.onFill(hcFill5, theme.textOnBrand)
            }
            HoverHandler { id: apHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.setPreview(false); root.turnOnVideo() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Apply and turn on video"
        }
    }

    // Teams' Add new picker ("Open", its "Custom files" filter).
    FileDialog {
        id: chooser
        title: "Open"
        nameFilters: ["Custom files (*.png *.jpeg *.jpg *.bmp)"]
        onAccepted: root.notice = videoEffects.addUpload(selectedFile)
    }
    /// Test hook: Add new with `path`, as if picked.
    function addForTest(path) { root.notice = videoEffects.addUpload("file://" + path); return root.notice }

    component Cell: Item { width: 109.1; height: 58 }

    // A Fluent accordion header: 32 tall, the caret (down when open) at the
    // start and the 12 px title 16 in.
    component SectionHeader: Item {
        id: sh
        property string key
        property string title
        readonly property bool open: !!root.expanded[key]
        width: 337.3; height: 32
        FluentIcon {
            x: 0; y: 8; name: "accordion-caret"; size: 16; color: theme.text
            rotation: sh.open ? 0 : -90
        }
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: sh.title
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                const e = Object.assign({}, root.expanded)
                e[sh.key] = !sh.open
                root.expanded = e
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: sh.title
        Accessible.checkable: true
        Accessible.checked: sh.open
    }

    // A 14 px #424242 label with Teams' info button after it and a Fluent
    // switch (40 x 20) at the row's end; rows 36 tall.
    component SettingSwitch: Item {
        id: ss
        property string label
        property string info: ""
        property bool checked: false
        signal toggled()
        width: 321.3; height: 36
        Row {
            y: 8.7
            Text {
                height: 18.67
                verticalAlignment: Text.AlignVCenter
                text: ss.label
                font.family: theme.font; font.pixelSize: 14
                color: theme.textStrong
            }
            InfoButton { y: -2.67; visible: ss.info.length > 0; info: ss.info }
        }
        Rectangle {
            x: ss.width - 40; y: 8; width: 40; height: 20; radius: 10
            color: ss.checked ? (swHover.hovered ? theme.brandHover : theme.checkedFill) : "transparent"
            border.color: ss.checked ? "transparent" : theme.textSecondary
            border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: (ss.checked ? 20.67 : 0.67) + 9 - 7.2
                color: ss.checked ? theme.hc("white", "#1AEBFF") : theme.textSecondary
            }
            HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ss.toggled() }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: ss.label
        Accessible.checked: ss.checked
        Accessible.onToggleAction: ss.toggled()
    }

    // Fluent's InfoButton: 24 px with the 16 px info glyph; its popover
    // (241.3 wide here, padding 12, 12 px text) opens above it, inside the
    // pane.
    component InfoButton: Rectangle {
        id: ib
        property string info
        width: 24; height: 24; radius: 4
        color: "transparent"
        FluentIcon { anchors.centerIn: parent; name: ibHover.hovered || pop.visible ? "info-16" : "info-16-regular"; size: 16; color: ibHover.hovered || pop.visible ? theme.brand : theme.textStrong }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pop.visible ? pop.close() : pop.open() }
        Accessible.role: Accessible.Button
        Accessible.name: "information"
        Popup {
            id: pop
            parent: Overlay.overlay
            width: 241.3; padding: 12
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            onAboutToShow: {
                const p = ib.mapToItem(Overlay.overlay, 0, 0)
                const paneRight = root.mapToItem(Overlay.overlay, root.width, 0).x
                x = Math.min(p.x, paneRight - width - 0.67)
                y = p.y - implicitHeight - 6.24
            }
            contentItem: Text {
                text: ib.info
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
        }
    }
}
