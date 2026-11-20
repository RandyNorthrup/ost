import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

// Teams' Sharing control bar (presenter toolbar window, module 827897;
// measured on winpc 2026-11-16 sharing Notepad): a window of its own,
// titled "Sharing control bar", while you share. Centred on the screen
// 8 px from its top (5 minimized); it minimizes 4 s after it shows unless
// it's hovered, focused or pinned, and the badge brings it back.
// - Expanded (734 x 56 with Teams' controls): the 45.3 tall #FAFAFA card
//   (radius 8, a #F0F0F0 hairline) 10 in: Dragger (20 x 44), the duration
//   (12 px #424242), Mic and Camera | Give control, Share sound, Optimize,
//   Layout, Annotate | More (Chat, People) | Stop sharing (its glyph
//   #B10E1C) and Pin. 40 x 39.3 buttons (wider for longer labels) with
//   a 20 px glyph over a 10 px label, 15.7 apart; dividers 1 x 24.2.
// - Minimized (298 x 36): the 26 tall card: Dragger (23.7 x 24.7), the
//   badge "You're sharing a window" / "You're sharing your screen"
//   (12/500) and the red "Stop sharing" (87 x 22.7, #D13438, radius 6,
//   12 px white).
// On Wayland it's a layer-shell surface at the top (an app can't place
// its own windows there); dragging moves it within the screen.
Window {
    id: bar
    /// The call window (its state and actions).
    property var call
    /// What we share: "screen" or "window".
    property string kind: "window"
    property bool pinned: false
    property bool expanded: true
    readonly property bool hovering: hoverAll.hovered
    readonly property var control: call && call.presentingState.control ? call.presentingState.control : ({})
    readonly property string mode: call && call.presentingState.mode ? call.presentingState.mode : "ContentOnly"
    // Teams: Give control is unavailable in Side-by-side and Reporter and
    // when nobody can be given control.
    readonly property bool canGive: (control.controllable || []).length > 0 && mode !== "SideBySide" && mode !== "NewsAnchor"
    readonly property bool someoneControls: control.state === "controlled"
    title: qsTr("Sharing control bar")
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    width: expanded ? card.width + 20 : 298
    // Teams grows the window under the bar while a menu is open (230 for
    // Layout, 248 for Give control).
    height: (expanded ? (layoutMenu.visible ? 230 : menus.open ? 248 : 56) : 36) + (alertShown ? 100 : 0)
    // A control request (or "… has control.") while the meeting window is
    // minimized: Teams' alert window shows it; here it hangs under the bar.
    readonly property bool alertShown: !!call && !!call.controlAlert && (call.controlAlert.kind === "request" || call.controlAlert.kind === "has")
    ControlAlert {
        visible: bar.alertShown
        alert: bar.call ? bar.call.controlAlert : null
        x: (bar.width - width) / 2
        y: (bar.expanded ? 56 : 36) + 4
        onGive: { bar.call.screenControl("accept", ""); bar.call.controlAlert = null }
        onDeny: { bar.call.screenControl("deny", ""); bar.call.controlAlert = null }
        onTakeBack: { bar.call.screenControl("takeBack", ""); bar.call.controlAlert = null }
    }
    // Where you dragged it (from the centre, 8 from the top otherwise).
    property real dragX: -1
    property real dragY: -1
    x: screen ? (dragX >= 0 ? dragX : screen.virtualX + (screen.width - width) / 2) : 0
    y: screen ? (dragY >= 0 ? dragY : screen.virtualY + (expanded ? 8 : 5)) : 0
    onWidthChanged: place()
    onExpandedChanged: place()
    function place() {
        if (!visible || !layered) return
        backend.placeSharingBar(dragX >= 0 ? Math.round(dragX) : -1, Math.round(dragY >= 0 ? dragY : (expanded ? 8 : 5)))
    }
    property bool layered: false
    onVisibleChanged: {
        if (visible) {
            expanded = true
            minimizeTimer.restart()
            place()
        }
    }
    // Made a layer-shell surface before it first shows (Wayland), then
    // shown (Teams fades it in after 150 ms).
    Component.onCompleted: { layered = backend.prepareSharingBar(); showTimer.start() }
    Timer { id: showTimer; interval: 150; onTriggered: bar.visible = true }
    // Teams' draggablePresenterToolbarTimeoutInMs.
    Timer {
        id: minimizeTimer
        interval: 4000
        running: bar.visible && bar.expanded && !bar.pinned && !bar.hovering && !menus.open
        onTriggered: bar.expanded = false
    }
    QtObject {
        id: menus
        readonly property bool open: giveMenu.visible || layoutMenu.visible || moreMenu.visible
    }
    HoverHandler { id: hoverAll }
    function openLayoutMenuForTest() { layoutMenu.open() }
    function closeMenusForTest() { layoutMenu.close() }

    // ---- Expanded ----
    Rectangle {
        id: card
        visible: bar.expanded
        x: 10; y: 0
        width: row.x + row.width + pinButton.width + 3.3
        height: 45.33; radius: 8
        color: theme.pick("#FAFAFA", "#292929", "#000000")
        border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
        Dragger { x: 0.67; y: 0.67; width: 20; height: 44; leftRadius: true }
        // The duration (Teams' indicators group).
        Text {
            x: 26.3; y: 14.1
            text: bar.call ? bar.call.clock(bar.call.seconds) : ""
            font.family: theme.font; font.pixelSize: 12
            color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
        }
        Row {
            id: row
            x: 68.6; y: 3
            spacing: 15.7
            Item { width: 0.1; height: 1 }
            BarItem {
                icon: bar.call && (bar.call.muted || !bar.call.hasAudio) ? "nmc-mic-off" : "nmc-mic"
                label: qsTr("Mic")
                tip: bar.call && bar.call.muted ? qsTr("Unmute mic") : qsTr("Mute mic")
                onClicked: bar.call.toggleMute()
            }
            BarItem {
                icon: bar.call && bar.call.cameraOn ? "nmc-camera" : "nmc-camera-off"
                label: qsTr("Camera")
                tip: bar.call && bar.call.cameraOn ? qsTr("Turn camera off") : qsTr("Turn camera on")
                enabled: bar.call ? bar.call.canVideo : false
                onClicked: bar.call.toggleCamera()
            }
            Divider {}
            BarItem {
                id: giveButton
                icon: "scb-give-control"
                label: bar.someoneControls ? qsTr("Take back") : qsTr("Give control")
                enabled: bar.someoneControls || bar.canGive
                tip: bar.someoneControls ? qsTr("Take back", "calling:k4myjqbw1")
                    : (bar.mode === "SideBySide" || bar.mode === "NewsAnchor") ? qsTr("Unavailable with this layout.")
                    : !bar.canGive ? qsTr("Participants are not allowed to control the shared content") : ""
                onClicked: {
                    if (bar.someoneControls) bar.call.screenControl("takeBack", "")
                    else giveMenu.open()
                }
                GiveControlMenu { id: giveMenu; y: parent.height + 5 }
            }
            BarItem {
                icon: "scb-share-sound"
                label: qsTr("Share sound")
                checked: bar.call ? bar.call.shareIncludeSound : false
                tip: checked ? qsTr("Share system sound is on") : qsTr("Share system sound is off")
                onClicked: bar.call.shareIncludeSound = !bar.call.shareIncludeSound
            }
            BarItem {
                icon: "scb-optimize"
                label: qsTr("Optimize")
                checked: bar.call ? !!bar.call.presentingState.optimize : false
                tip: checked ? qsTr("Optimize for video content is on") : qsTr("Optimize for video content is off")
                onClicked: bar.call.setShareOptimize(!checked)
            }
            BarItem {
                // Teams' apl-mode-switcher-button: the current mode's glyph.
                icon: ({ ContentOnly: "scb-layout", Weatherperson: "share-layout-standout", SideBySide: "share-layout-sidebyside", NewsAnchor: "share-layout-reporter" })[bar.mode] || "scb-layout"
                label: qsTr("Layout")
                enabled: bar.call ? bar.call.cameraOn : false
                tip: enabled ? "" : qsTr("Turn on your camera to select this layout")
                onClicked: layoutMenu.open()
                // apl-mode-switcher-button-menu-popover (measured
                // 2026-11-16): 255.3 wide, 5 under the button, 12.7 in;
                // 230 x 32 menuitemcheckbox rows 2 apart, the mode's 20 px
                // glyph 6 in, its name (14 px #424242) at 30, the chosen
                // one's 16 px check 6 from the end.
                Popup {
                    id: layoutMenu
                    y: parent.height + 5
                    padding: 12.67
                    width: 255.33
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Column {
                        spacing: 2
                        Repeater {
                            model: [
                                { key: "ContentOnly", label: qsTr("Content only"), icon: "share-layout-content" },
                                { key: "Weatherperson", label: qsTr("Standout"), icon: "share-layout-standout" },
                                { key: "SideBySide", label: qsTr("Side-by-side"), icon: "share-layout-sidebyside" },
                                { key: "NewsAnchor", label: qsTr("Reporter"), icon: "share-layout-reporter" }
                            ]
                            Rectangle {
                                id: lm
                                required property var modelData
                                width: 230; height: 32; radius: 4
                                color: lmHover.hovered ? theme.menuHover : theme.surface
                                FluentIcon { x: 6; y: 6; size: 20; name: lm.modelData.icon; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                                Text {
                                    x: 30; y: 6; height: 20; verticalAlignment: Text.AlignVCenter
                                    text: lm.modelData.label
                                    font.family: theme.font; font.pixelSize: 14
                                    color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                }
                                FluentIcon {
                                    visible: bar.mode === lm.modelData.key
                                    x: 208; y: 8; size: 16; name: "view-check-16"
                                    color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                }
                                HoverHandler { id: lmHover }
                                TapHandler { onTapped: { bar.call.setPresenterMode(lm.modelData.key); layoutMenu.close() } }
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: lm.modelData.label
                                Accessible.checked: bar.mode === lm.modelData.key
                            }
                        }
                    }
                }
            }
            BarItem {
                // Teams' Annotate (AnnotationPresenterButton): whole-screen
                // shares only; a Microsoft Whiteboard annotation session
                // over the shared screen (docs/spec/content-sharing.md §4).
                readonly property bool on: bar.call.annotating
                icon: "scb-annotate"
                label: qsTr("Annotate")
                checked: on
                enabled: bar.kind === "screen" && !bar.call.annotationBusy
                tip: bar.kind !== "screen" ? qsTr("Annotation is available when you share your screen")
                     : bar.call.annotationBusy ? (on ? qsTr("Annotations is stopping") : qsTr("Annotations is starting"))
                     : on ? qsTr("Stop annotation") : qsTr("Start annotation")
                onClicked: bar.call.toggleAnnotation()
            }
            Divider {}
            BarItem {
                icon: "scb-more"
                label: qsTr("More")
                onClicked: moreMenu.open()
                MenuPopup {
                    id: moreMenu
                    y: parent.height + 6
                    items: [{ label: qsTr("Chat"), icon: "scb-chat" }, { label: qsTr("People"), icon: "scb-people" }]
                    onPicked: i => bar.call.showSidePane(i === 0 ? "chat" : "people")
                }
            }
            Divider {}
            BarItem {
                icon: "scb-stop-sharing"
                iconColor: theme.pick("#B10E1C", "#DC626D", "#FFFFFF")
                labelColor: theme.pick("#242424", "#FFFFFF", "#FFFFFF")
                label: qsTr("Stop sharing")
                tip: qsTr("Stop sharing")
                onClicked: bar.call.toggleShare()
            }
        }
        Rectangle {
            id: pinButton
            x: row.x + row.width + 1.4; y: 0.67
            width: 32; height: 44; radius: 4
            color: pinHover.hovered ? theme.pick("#F0F0F0", "#3D3D3D", "#1AEBFF") : theme.pick("#FAFAFA", "#292929", "#000000")
            FluentIcon { x: 5; y: 12.3; size: 20; name: bar.pinned ? "scb-pin" : "pin-20"; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
            HoverHandler { id: pinHover }
            TapHandler { onTapped: bar.pinned = !bar.pinned }
            Accessible.role: Accessible.Button
            Accessible.name: bar.pinned ? qsTr("Unpin toolbar") : qsTr("Pin toolbar")
        }
    }

    // ---- Minimized ----
    Rectangle {
        visible: !bar.expanded
        x: 10; y: 0
        width: 278; height: 26; radius: 8
        color: theme.pick("#FFFFFF", "#292929", "#000000")
        border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
        Dragger { x: 0.67; y: 0.67; width: 23.67; height: 24.67; leftRadius: true }
        Rectangle {
            x: 24.3; y: 0.67; width: 164; height: 24.67
            color: theme.pick("#FAFAFA", "#292929", "#000000")
            Text {
                anchors.centerIn: parent
                text: bar.kind === "screen" ? qsTr("You're sharing your screen") : qsTr("You're sharing a window")
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.Medium
                color: theme.text
            }
            HoverHandler { onHoveredChanged: if (hovered) bar.expanded = true }
            TapHandler { onTapped: bar.expanded = true }
            Accessible.role: Accessible.Button
            Accessible.name: bar.kind === "screen" ? qsTr("You're sharing your screen") : qsTr("You're sharing a window")
        }
        Rectangle {
            id: hcStop
            x: 189.3; y: 1.67; width: 87; height: 22.67; radius: 6
            color: stopHover.hovered ? theme.pick("#BC2F32", "#BC2F32", "#1AEBFF") : theme.pick("#D13438", "#D13438", "#000000")
            border.width: theme.highContrast ? 1 : 0; border.color: "#FFFFFF"
            Text {
                anchors.centerIn: parent
                text: qsTr("Stop sharing")
                font.family: theme.font; font.pixelSize: 12
                color: theme.onFill(hcStop, "#FFFFFF")
            }
            HoverHandler { id: stopHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: bar.call.toggleShare() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Stop sharing")
        }
    }

    // Ctrl+Shift+Space: back to the bar (Teams' global shortcut, in OST
    // while one of its windows has the keyboard).
    Shortcut {
        sequence: "Ctrl+Shift+Space"
        context: Qt.ApplicationShortcut
        enabled: bar.visible
        onActivated: { bar.expanded = true; minimizeTimer.restart() }
    }

    component Divider: Item {
        width: 1; height: 39.33
        Rectangle { y: 7.56; width: 1; height: 24.2; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
    }
    component Dragger: Rectangle {
        id: dr
        property bool leftRadius: false
        radius: 8
        color: theme.pick("#FAFAFA", "#292929", "#000000")
        // Square on the right (Teams: radius 8px 0 0 8px).
        Rectangle { x: parent.width / 2; width: parent.width / 2; height: parent.height; color: parent.color }
        FluentIcon { anchors.centerIn: parent; size: 12; name: "scb-dragger"; color: theme.text }
        DragHandler {
            target: null
            property point start
            property point origin
            onActiveChanged: if (active) { start = centroid.scenePosition; origin = Qt.point(bar.x - (bar.screen ? bar.screen.virtualX : 0), bar.y - (bar.screen ? bar.screen.virtualY : 0)) }
            onCentroidChanged: {
                if (!active) return
                const sw = bar.screen ? bar.screen.width : 1920, sh = bar.screen ? bar.screen.height : 1080
                const dx = centroid.scenePosition.x - start.x, dy = centroid.scenePosition.y - start.y
                bar.dragX = Math.max(0, Math.min(sw - bar.width, origin.x + dx))
                bar.dragY = Math.max(0, Math.min(sh - bar.height, origin.y + dy))
                bar.place()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Dragger")
    }
    component BarItem: Rectangle {
        id: bi
        property string icon
        property string label
        property string tip
        property bool checked: false
        property color iconColor: !enabled ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
        property color labelColor: iconColor
        signal clicked()
        width: Math.max(40, labelText.implicitWidth + 1.33)
        height: 39.33; radius: 4
        color: !enabled ? "transparent" : (biHover.hovered || bi.checked) ? theme.pick("#F0F0F0", "#3D3D3D", "#1AEBFF") : "transparent"
        border.width: 0.67; border.color: "transparent"
        FluentIcon {
            x: (parent.width - 20) / 2; y: 0.67; size: 20
            name: bi.icon
            color: bi.iconColor
        }
        Text {
            id: labelText
            x: (parent.width - width) / 2; y: 20.67; height: 16
            verticalAlignment: Text.AlignVCenter
            text: bi.label
            font.family: theme.font; font.pixelSize: 10
            color: bi.labelColor
        }
        HoverHandler { id: biHover }
        TapHandler { enabled: bi.enabled; onTapped: bi.clicked() }
        ToolTip.visible: biHover.hovered && bi.tip.length > 0
        ToolTip.text: bi.tip
        Accessible.role: Accessible.Button
        Accessible.name: bi.label
        Accessible.description: bi.tip
        Accessible.checked: bi.checked
        Accessible.onPressAction: if (bi.enabled) bi.clicked()
    }
    // Give control ▸ (give-control-button-popover, measured 2026-11-16): a
    // 305.3 wide white popover 5 under the button, 12.7 in: the search box
    // (256 x 32, #FAFAFA, radius 4, "Give control of your screen to", a
    // 20 px magnifier at its end), then the people who can take it (their
    // viewers answered the handshake): 270 x 48 rows, a 32 px avatar 10 in,
    // the name (14 px) at 50.
    component GiveControlMenu: Popup {
        id: gm
        padding: 12.67
        width: 305.33
        background: FluentSurface { depth: 16; radius: 4 }
        readonly property var people: {
            const ids = bar.control.controllable || []
            const roster = bar.call ? bar.call.roster : []
            return ids.map(id => roster.find(p => p.id === id) || { id: id, name: id }).filter(p => p.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
        }
        contentItem: Column {
            topPadding: 8
            spacing: 8
            Rectangle {
                x: 10; width: 256; height: 32; radius: 4
                color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                TextField {
                    id: search
                    x: 0.67; y: 0.67; width: 222.67; height: 30.67
                    placeholderText: qsTr("Give control of your screen to")
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    background: null
                    Accessible.name: qsTr("Give control of your screen to")
                }
                FluentIcon { x: 225.3; y: 6; size: 20; name: "search-20"; color: theme.textSecondary }
            }
            Repeater {
                model: gm.people
                Rectangle {
                    id: pr
                    required property var modelData
                    x: 5; width: 270; height: 48; radius: 4
                    color: prHover.hovered ? theme.menuHover : "transparent"
                    Avatar { x: 10; y: 8; size: 32; name: pr.modelData.name; photoId: pr.modelData.id || "" }
                    Text {
                        x: 50; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60; elide: Text.ElideRight
                        text: pr.modelData.name
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    HoverHandler { id: prHover }
                    TapHandler { onTapped: { bar.call.screenControl("give", pr.modelData.id); gm.close() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: pr.modelData.name
                }
            }
        }
    }
}
