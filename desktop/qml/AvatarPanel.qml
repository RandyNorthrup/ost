import QtQuick
import QtQuick.Controls
import com.ost.desktop

// Teams' Avatars tab of the Video effects and settings pane (module
// 906550; measured in a call on winpc 2026-11-17), also the pre-join
// "Avatars" pane: the retirement notice, then the Avatars app's own side
// panel — its page with `uiOnly=true&avatarId=…&backgroundId=…` in Teams'
// host (frameContext sidePanel): your avatars, their backgrounds, emotes,
// mood and camera, "Edit my avatar" — filling the pane; in a call, under
// it, your avatar's preview while previewing (330 x 185.6 in a 339.3 x
// 198.6 box), "Others
// won't see your avatar while you preview." (12 px, an info glyph before
// it, 10 in), Preview / Stop preview (white) and "Apply avatars" (brand),
// 339.3 x 32, 10 apart. Without the app, Teams' "create your avatar".
Item {
    id: root
    property bool inCall: false
    property bool cameraOn: false
    /// Teams turns your video on (Apply with an avatar) or off (Apply
    /// with none, or Preview while it's on).
    signal turnOnVideo()
    signal turnOffVideo()
    signal createAvatar()

    readonly property bool shown: visible && !!avatarHost.app.url
    onShownChanged: videoEffects.avatarViews += shown ? 1 : -1
    Component.onDestruction: if (shown) videoEffects.avatarViews--

    property bool previewing: false
    function pageForTest() { return page.item }
    function refreshFrame() { if (page.item) page.item.refreshFrame() }
    function setPreview(on) {
        if (on === previewing) return
        previewing = on
        backend.setCameraPreview(on)
    }
    onVisibleChanged: if (!visible) setPreview(false)

    AvatarNotice { id: notice; width: root.width }

    // The app's own panel.
    Loader {
        id: page
        anchors { top: notice.bottom; left: parent.left; right: parent.right; bottom: controls.top; bottomMargin: root.inCall ? 10 : 0 }
        active: root.shown
        // Teams frames it afresh for the avatar and background chosen.
        property string url: ""
        onActiveChanged: if (active) url = root.panelUrl()
        sourceComponent: WebApp {
            appName: avatarHost.app.name || "Avatars"
            appId: avatarHost.app.appId || ""
            teamsHost: true
            showHeader: false
            frameContext: "sidePanel"
            hostThread: avatarHost.thread
            homeTemplate: page.url
            runtimeSupports: ({ video: { mediaStream: {}, sharedFrame: {} }, meeting: {} })
            onHostEvent: (name, json) => {
                let a = null
                try { a = JSON.parse(json) } catch (e) {}
                if (name === "videoEffectChanged" && a) {
                    // Teams' onLastEffectSelected: [type, avatarId, backgroundId].
                    if (a[0] === "EffectDisabled") videoEffects.selectAvatar("")
                    else {
                        videoEffects.avatarBackground = a[2] || ""
                        videoEffects.selectAvatar(a[1] || "")
                    }
                } else if (name === "openLink" && a && /\/l\/entity\//.test(a.url || "")) {
                    // "Edit my avatar": the app's Customize Avatar tab.
                    const sub = /AvatarStudioNewPersonaCreation/.test(decodeURIComponent(a.url)) ? "AvatarStudioNewPersonaCreation" : ""
                    window.openAvatarBuilder(sub)
                }
            }
        }
    }
    function panelUrl() {
        const u = String(avatarHost.app.url || "")
        if (!u) return ""
        return u + (u.indexOf("?") < 0 ? "?" : "&") + "uiOnly=true&avatarId=" + encodeURIComponent(videoEffects.avatarId) + "&backgroundId=" + encodeURIComponent(videoEffects.avatarBackground)
    }

    Column {
        id: controls
        visible: root.inCall
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 20 }
        height: visible ? implicitHeight : 0
        spacing: 0
        // Your avatar's preview (Teams' calling-avatar-preview-window).
        Rectangle {
            visible: root.previewing
            x: (root.width - width) / 2
            width: 339.3; height: visible ? 198.6 : 0
            color: "transparent"
            Rectangle {
                x: 4.65; width: 330; height: 185.6; radius: 4; clip: true
                color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                VideoFrame {
                    id: preview
                    anchors.fill: parent
                    visible: hasFrame
                    source: root.previewing ? "self" : ""
                    radius: 4
                    Timer { interval: 33; repeat: true; running: root.previewing; onTriggered: preview.refresh() }
                }
                Text {
                    visible: !preview.visible && !videoEffects.avatarId
                    anchors.centerIn: parent
                    text: qsTr("Select an avatar")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                    color: theme.textSecondary
                }
                BusyIndicator { anchors.centerIn: parent; running: !preview.visible && !!videoEffects.avatarId; visible: running }
            }
        }
        Item {
            width: root.width; height: 26
            FluentIcon { x: 10; y: 0; name: "info-16"; size: 16; color: theme.text }
            Text {
                x: 41; y: 0; height: 16; verticalAlignment: Text.AlignVCenter
                text: qsTr("Others won't see your avatar while you preview.")
                font.family: theme.font; font.pixelSize: 12
                color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
            }
        }
        Rectangle {
            id: previewButton
            x: 10; width: root.width - 20; height: 32; radius: 4
            color: pvHover.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: root.previewing ? qsTr("Stop preview") : qsTr("Preview"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(previewButton, theme.text) }
            HoverHandler { id: pvHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    // Teams: the avatar becomes the camera; your video goes
                    // off while you preview.
                    videoEffects.setAvatarCamera(true)
                    if (!root.previewing && root.cameraOn) root.turnOffVideo()
                    root.setPreview(!root.previewing)
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: root.previewing ? qsTr("Stop preview") : qsTr("Preview")
        }
        Item { width: 1; height: 10 }
        Rectangle {
            id: applyButton
            x: 10; width: root.width - 20; height: 32; radius: 4
            color: apHover.hovered ? theme.brandHover : theme.brandFill
            Row {
                anchors.centerIn: parent
                spacing: 8
                BusyIndicator { width: 16; height: 16; running: !!videoEffects.avatarId && videoEffects.avatarCamera && root.applying && !backend.avatarDrawing(); visible: running }
                Text { text: qsTr("Apply avatars"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(applyButton, "white") }
            }
            HoverHandler { id: apHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    videoEffects.setAvatarCamera(true)
                    videoEffects.saveAvatar()
                    if (videoEffects.avatarId) { root.applying = true; if (!root.cameraOn) root.turnOnVideo() }
                    else if (root.cameraOn) root.turnOffVideo()
                    root.setPreview(false)
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Apply avatars")
        }
    }
    property bool applying: false
    onCameraOnChanged: if (cameraOn) applying = false
}
