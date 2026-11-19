import QtQuick
import QtQuick.Window
import QtQuick.Controls
import com.ost.desktop

// Teams' Camera ▾ flyout (video-button-configure-popover, measured in a
// call on winpc, 2026-11-14): 359.3 wide, content 326 at 16.7 — your live
// preview (326 x 180, mirrored unless Mirror my video is off) while it's
// open; "Camera" (12 px) with the cameras as radios (34.3 px rows); a
// divider; "Backgrounds" (12 px) over a row of 77 x 48 tiles 6 apart
// (None, the blur tile, Teams' first two catalog backgrounds); a divider;
// Adjust brightness and Soft focus (14 px #424242 labels, Fluent switches,
// 36 px rows); a divider and "More video effects and settings". Picking a
// camera moves a running call's video to it at once.
// Avatars (module 686534, measured 2026-11-17; TASK-0140): with Teams'
// Avatars app the tabs "Effects and settings" | "Avatars" (14 px, 32 high)
// sit under the preview (shown while your video is off); the Avatars tab
// shows the retirement notice, the avatar quick picker ("Avatars" and
// "Backgrounds" 12 px over rows of 77 x 48 tiles 6 apart, 12 above and
// below), a divider, "More avatar settings" and "Turn on avatars" (brand,
// 320 x 32). With your avatar on as your video, the
// flyout is only a 326 x 180 #F0F0F0 box — "Turn off Avatars" (25 high,
// 14/600) over "This removes your avatars from view, and starts video
// preview. Your video preview is only visible to you." (12/600 #616161,
// 240 wide) — and "More avatar settings" (14 px, a 32 px row).
Popup {
    id: root
    /// The call's camera is on (the preview is then the call's own video).
    property bool cameraOn: false
    signal moreVideoSettings()
    /// "More avatar settings": the pane on its Avatars tab.
    signal moreAvatarSettings()
    signal turnOnVideo()
    signal turnOffVideo()
    readonly property bool avatarsOffered: !!avatarHost.app.url
    /// Your avatar is your video (Teams' box instead of the tabs).
    readonly property bool avatarOn: avatarsOffered && cameraOn && videoEffects.avatarCamera && !!videoEffects.avatarId
    /// "effects" or "avatars".
    property string tab: "effects"
    width: 359.3
    height: col.implicitHeight + 27.4
    padding: 0
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    property var cameras: []
    property string current: ""
    property bool previewing: false
    onOpened: {
        const d = JSON.parse(backend.videoDevices())
        // Teams opens on Avatars when your avatar is your video, or when
        // there's no camera to show.
        tab = avatarsOffered && ((videoEffects.avatarCamera && cameraOn) || (d.devices || []).length === 0) ? "avatars" : "effects"
        cameras = d.devices || []
        current = d.current || ""
        videoEffects.load()
        // Teams previews the camera in the flyout while video is off.
        previewing = !cameraOn && (cameras.length > 0 || videoEffects.avatarCamera) && backend.setCameraPreview(true)
        if (tab === "avatars") enterAvatars()
    }
    onClosed: if (previewing) { previewing = false; backend.setCameraPreview(false) }
    readonly property bool avatarsShown: opened && tab === "avatars" && avatarsOffered
    onAvatarsShownChanged: videoEffects.avatarViews += avatarsShown ? 1 : -1
    // Teams: the Avatars tab with your video off makes the avatar the
    // camera (the preview is then your avatar); the Effects tab with your
    // video off brings your camera back.
    function enterAvatars() {
        if (cameraOn || videoEffects.avatarCamera) return
        if (previewing) backend.setCameraPreview(false)
        videoEffects.setAvatarCamera(true)
        previewing = backend.setCameraPreview(true)
    }
    function enterEffects() {
        if (cameraOn || !videoEffects.avatarCamera) return
        if (previewing) backend.setCameraPreview(false)
        videoEffects.setAvatarCamera(false)
        previewing = cameras.length > 0 && backend.setCameraPreview(true)
    }
    onTabChanged: if (opened) { if (tab === "avatars") enterAvatars(); else enterEffects() }

    Column {
        id: col
        x: 16.7; y: 16.7; width: 326
        // Your avatar is your video: Teams' box with Turn off Avatars.
        Rectangle {
            visible: root.avatarOn
            width: 326; height: visible ? 180 : 0; topLeftRadius: 4; topRightRadius: 4
            color: theme.pick("#F0F0F0", "#1F1F1F", "#000000")
            Rectangle {
                id: offButton
                anchors.horizontalCenter: parent.horizontalCenter; y: 42.5
                width: offText.implicitWidth + 24; height: 25; radius: 4
                color: offHover.hovered ? theme.rowHover : parent.color; border.color: theme.stroke
                Text { id: offText; anchors.centerIn: parent; text: qsTr("Turn off Avatars"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(offButton, theme.text) }
                HoverHandler { id: offHover; cursorShape: Qt.PointingHandCursor }
                // Teams: your video off, then your camera back.
                TapHandler { onTapped: { root.turnOffVideo(); videoEffects.setAvatarCamera(false); root.close() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Turn off Avatars")
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: 77.5
                width: 240; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                text: qsTr("This removes your avatars from view, and starts video preview. \u2060Your video preview is only visible to you.")
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                color: theme.textSecondary
            }
        }
        Item {
            visible: root.avatarOn
            width: 326; height: visible ? 40 : 0
            Text {
                y: 8; height: 32; verticalAlignment: Text.AlignVCenter
                text: qsTr("More avatar settings")
                font.family: theme.font; font.pixelSize: 14
                color: masHover.hovered ? theme.text : theme.textStrong
                HoverHandler { id: masHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.close(); root.moreAvatarSettings() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("More avatar settings")
            }
        }
        Rectangle {
            visible: !root.avatarOn
            width: 326; height: visible ? 180 : 0; radius: 4
            color: theme.pane
            clip: true
            VideoFrame {
                id: preview
                anchors.fill: parent
                visible: hasFrame
                source: root.opened && (root.cameraOn || root.previewing) ? "self" : ""
                radius: 4
                transform: Scale { origin.x: preview.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
                Timer { interval: 33; repeat: true; running: root.opened; onTriggered: preview.refresh() }
            }
            Text {
                visible: !preview.visible
                anchors.centerIn: parent
                text: root.tab === "avatars" ? (videoEffects.avatarId ? "" : qsTr("Select an avatar")) : root.cameras.length === 0 ? qsTr("No camera is connected") : qsTr("Starting your camera…")
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
        }
        // Teams' tabs (32 high) when it has avatars.
        Row {
            visible: root.avatarsOffered && !root.avatarOn
            x: -8; height: visible ? 42 : 0
            Repeater {
                model: [{ k: "effects", t: qsTr("Effects and settings") }, { k: "avatars", t: qsTr("Avatars") }]
                Item {
                    id: ftb
                    required property var modelData
                    readonly property bool chosen: root.tab === modelData.k
                    width: ftbText.implicitWidth + 12; height: 42
                    Text {
                        id: ftbText
                        x: 6; y: 6; height: 20; verticalAlignment: Text.AlignVCenter
                        text: ftb.modelData.t
                        font.family: theme.font; font.pixelSize: 14; font.weight: ftb.chosen ? Font.DemiBold : Font.Normal
                        color: ftb.chosen || ftbHover.hovered ? theme.text : theme.textStrong
                    }
                    Rectangle {
                        visible: ftb.chosen || ftbHover.hovered
                        x: 6; y: 28; width: ftbText.implicitWidth; height: 3; radius: 1.5
                        color: ftb.chosen ? theme.brand : theme.strokeHover
                    }
                    HoverHandler { id: ftbHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.tab = ftb.modelData.k }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: ftb.modelData.t
                    Accessible.selected: ftb.chosen
                }
            }
        }
        // Avatars: the quick picker and Turn on avatars.
        Column {
            visible: root.avatarsShown && !root.avatarOn
            width: 326
            AvatarNotice { width: 326 + 32; x: -16; height: visible ? implicitHeight - 6 : 0 }
            AvatarPicker {
                visible: avatarHost.avatars.length > 0
                width: 326
                inFlyout: true
                showMore: false
                onCreateMore: { root.close(); window.openAvatarBuilder("AvatarStudioNewPersonaCreation") }
            }
            AvatarCreate {
                visible: avatarHost.listed && avatarHost.avatars.length === 0
                width: 326; height: visible ? implicitHeight : 0
                onCreate: { root.close(); window.openAvatarBuilder("AvatarStudioNewPersonaCreation") }
            }
            BusyIndicator { visible: !avatarHost.listed; running: visible; anchors.horizontalCenter: parent.horizontalCenter; height: visible ? 40 : 0 }
            Item { width: 326; height: 10 }
            Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
            Item {
                width: 326; height: 32
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("More avatar settings")
                    font.family: theme.font; font.pixelSize: 14
                    color: mas2Hover.hovered ? theme.text : theme.textStrong
                    HoverHandler { id: mas2Hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.close(); root.moreAvatarSettings() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("More avatar settings")
                }
            }
            Item { width: 326; height: 8 }
            Rectangle {
                id: turnOn
                x: 3; width: 320; height: 32; radius: 4
                color: onHover.hovered ? theme.brandHover : theme.brandFill
                opacity: videoEffects.avatarId ? 1 : 0.5
                Text { anchors.centerIn: parent; text: qsTr("Turn on avatars"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(turnOn, "white") }
                HoverHandler { id: onHover; cursorShape: Qt.PointingHandCursor }
                // Teams: the avatar becomes the camera, your video goes on
                // with it, and the flyout closes.
                TapHandler {
                    onTapped: {
                        if (root.previewing) { root.previewing = false; backend.setCameraPreview(false) }
                        videoEffects.setAvatarCamera(true)
                        videoEffects.saveAvatar()
                        if (!root.cameraOn && videoEffects.avatarId) root.turnOnVideo()
                        root.close()
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Turn on avatars")
            }
        }
        Column {
            id: effectsPart
            visible: !root.avatarOn && !root.avatarsShown
            width: 326
        Item { width: 326; height: 10 }
        Text {
            width: 326; height: 16; verticalAlignment: Text.AlignVCenter
            text: qsTr("Camera")
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        Repeater {
            model: root.cameras
            Item {
                id: row
                required property var modelData
                readonly property bool chosen: root.current === modelData.path
                width: 326; height: 34.3
                FluentIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; name: row.chosen ? "radio-on-20" : "radio-off-20"; size: 20; color: row.chosen ? theme.brand : theme.textSecondary }
                Text {
                    x: 26; anchors.verticalCenter: parent.verticalCenter; width: 300
                    elide: Text.ElideRight
                    text: row.modelData.name
                    font.family: theme.font; font.pixelSize: 14
                    color: row.chosen ? theme.text : theme.textSecondary
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (row.chosen) return
                        root.current = row.modelData.path
                        backend.setCameraDevice(row.modelData.path)
                        // The flyout's preview follows the new camera.
                        if (root.previewing) { backend.setCameraPreview(false); backend.setCameraPreview(true) }
                    }
                }
                Accessible.role: Accessible.RadioButton
                Accessible.name: row.modelData.name
                Accessible.checked: row.chosen
            }
        }
        Item { width: 326; height: 10 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 10 }
        Text {
            width: 326; height: 16; verticalAlignment: Text.AlignVCenter
            text: qsTr("Backgrounds")
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        Item { width: 326; height: 10 }
        Row {
            spacing: 6
            height: 50
            EffectTile {
                width: 77; height: 48
                kind: "none"; label: qsTr("None"); accessibleName: qsTr("No background effect")
                selected: videoEffects.background === "none"
                onPicked: videoEffects.setBackground("none")
            }
            EffectTile {
                width: 77; height: 48
                kind: "blur"; label: videoEffects.blurLabel
                blurKind: videoEffects.blurKind
                selected: videoEffects.background === "blur"
                onPicked: videoEffects.setBackground("blur")
                onBlurPicked: kind => videoEffects.setBlur(kind)
            }
            Repeater {
                model: videoEffects.catalog.slice(0, 2)
                EffectTile {
                    required property var modelData
                    width: 77; height: 48
                    thumb: modelData.thumb; animated: modelData.animated
                    label: modelData.name; accessibleName: qsTr("%1 background effect").arg(modelData.name)
                    selected: videoEffects.background === modelData.id
                    onPicked: videoEffects.setBackground(modelData.id)
                }
            }
        }
        Item { width: 326; height: 10 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 10.6 }
        FlyoutSwitch {
            label: qsTr("Adjust brightness")
            checked: videoEffects.brightness
            onToggled: videoEffects.setBrightness(!checked)
        }
        FlyoutSwitch {
            label: qsTr("Soft focus")
            checked: videoEffects.softFocus
            onToggled: videoEffects.setSoftFocus(!checked)
        }
        Item { width: 326; height: 10 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 8.7 }
        Item {
            width: 326; height: 32
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("More video effects and settings")
                font.family: theme.font; font.pixelSize: 14
                color: mvHover.hovered ? theme.text : theme.textStrong
            }
            HoverHandler { id: mvHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.moreVideoSettings() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More video effects and settings")
        }
        }
    }

    // A 14 px #424242 label and a Fluent switch (40 x 20 indicator at the
    // row's end): on, brand with a white thumb; off, a #616161 outline.
    component FlyoutSwitch: Item {
        id: fs
        property string label
        property bool checked: false
        signal toggled()
        width: 326; height: 36
        Text {
            y: 8.7; height: 18.7; verticalAlignment: Text.AlignVCenter
            text: fs.label
            font.family: theme.font; font.pixelSize: 14
            color: theme.textStrong
        }
        Rectangle {
            x: 286; y: 8; width: 40; height: 20; radius: 10
            color: fs.checked ? (swHover.hovered ? theme.brandHover : theme.checkedFill) : "transparent"
            border.color: fs.checked ? "transparent" : theme.textSecondary
            border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: (fs.checked ? 20.67 : 0.67) + 9 - 7.2
                color: fs.checked ? theme.hc("white", "#1AEBFF") : theme.textSecondary
            }
            HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: fs.toggled() }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: fs.label
        Accessible.checked: fs.checked
        Accessible.onToggleAction: fs.toggled()
    }
}
