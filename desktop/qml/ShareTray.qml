import QtQuick
import QtQuick.Controls.Basic

// Teams' share tray (the classic floating tray, share-popup /
// floating-sharetray-wrapper; measured on winpc 2026-11-16 in the test
// meeting, camera and mic off): a 360-wide card under the bar (radius 4,
// Fluent's shadow 2), as tall as the window allows, scrolling below its
// header:
// - "Share content" (16/700) and, at the end, "Include sound" (12 px)
//   with its switch (system-audio-checkbox): the computer's sound goes
//   into the call with the screen;
// - "Presenter mode" (14/600) and its four 32 x 31.3 icon radios —
//   Content only, Standout, Side-by-side, Reporter — then Add background;
// - "Screen" and "Window" (14/600) over 154 x 90 tiles: Teams' screen
//   thumbnails and window list come from its calling stack; on Linux the
//   desktop's portal shows what to share, so the Screen tile shows Teams'
//   no-preview name ("Screen 1") and the Window tile Teams' window
//   illustration ("Opens list of active windows"). Picking one opens the
//   desktop's picker for screens or for windows.
// Esc closes it. (Microsoft Whiteboard, Content from camera, PowerPoint
// Live and Excel Live, which Teams lists under these, aren't offered.)
Popup {
    id: tray
    property bool includeSound: false
    property bool cameraOn: false
    signal share(string kind)
    width: 360
    padding: 0
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
        radius: 4
        color: theme.surface
        border.width: theme.highContrast ? 1 : 0; border.color: "#FFFFFF"
        Rectangle { z: -1; anchors.fill: parent; anchors.topMargin: 0.8; radius: 4; color: Qt.rgba(0, 0, 0, theme.dark ? 0.28 : 0.13) }
    }
    contentItem: Item {
        implicitHeight: Math.min(header.height + body.implicitHeight, tray.parent ? tray.parent.height - tray.y - 7.3 : 438.7)
        // Header (71 tall).
        Item {
            id: header
            width: parent.width; height: 71
            Text {
                x: 23.7; y: 34.7; height: 20; verticalAlignment: Text.AlignVCenter
                text: "Share content"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Text {
                id: soundLabel
                x: 198.7; y: 29.7; height: 36; verticalAlignment: Text.AlignVCenter
                text: "Include sound"
                font.family: theme.font; font.pixelSize: 12; color: theme.text
            }
            SettingsParts.Toggle {
                x: 293.3; y: 37.7
                stateLabel: false
                on: tray.includeSound
                accessibleName: "Include sound"
                onToggled: v => tray.includeSound = v
            }
        }
        Flickable {
            id: flick
            y: header.height; width: parent.width; height: parent.height - y
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            Item {
                id: body
                width: flick.width
                implicitHeight: 306
                Text {
                    x: 23.7; y: 10; height: 20; verticalAlignment: Text.AlignVCenter
                    text: "Presenter mode"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                // The radios: the chosen one #E0E0E0 with a #BDBDBD edge;
                // the camera modes need the camera ("Turn on your camera
                // to select this layout").
                Row {
                    x: 23.7; y: 41
                    spacing: 10
                    Repeater {
                        model: [
                            { key: "ContentOnly", label: "Content only", icon: "share-layout-content", camera: false },
                            { key: "Weatherperson", label: "Standout", icon: "share-layout-standout", camera: true },
                            { key: "SideBySide", label: "Side-by-side", icon: "share-layout-sidebyside", camera: true },
                            { key: "NewsAnchor", label: "Reporter", icon: "share-layout-reporter", camera: true }
                        ]
                        delegate: Rectangle {
                            id: mode
                            required property var modelData
                            readonly property bool checked: modelData.key === "ContentOnly"
                            // OST shares content only: Teams' presenter
                            // modes (its receivers composite your camera
                            // over the screen) aren't built yet.
                            readonly property bool usable: !modelData.camera
                            width: 32; height: 31.3; radius: 3
                            color: checked ? theme.pick("#E0E0E0", "#3D3D3D", "#1AEBFF") : !usable ? theme.pick("#F0F0F0", "#141414", "#000000") : mh.hovered ? theme.menuHover : theme.surface
                            border.width: 0.67
                            border.color: checked ? theme.pick("#BDBDBD", "#666666", "#FFFFFF") : theme.pick("#FFFFFF", "#141414", "#000000")
                            FluentIcon { anchors.centerIn: parent; size: 20; name: mode.modelData.icon; color: mode.usable ? theme.text : theme.disabled }
                            HoverHandler { id: mh }
                            ToolTip.visible: mh.hovered && !mode.usable
                            ToolTip.text: tray.cameraOn ? mode.modelData.label : "Turn on your camera to select this layout"
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label
                            Accessible.checked: checked
                        }
                    }
                }
                SettingsParts.Button { x: 204.3; y: 42; label: "Add background"; enabled: false }
                // Screen and Window.
                Text {
                    x: 23.7; y: 100.3; height: 20; verticalAlignment: Text.AlignVCenter
                    text: "Screen"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                }
                Text {
                    x: 191.7; y: 100.3; height: 20; verticalAlignment: Text.AlignVCenter
                    text: "Window"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                }
                Tile {
                    x: 18.7; y: 124.3
                    accessibleName: "Screen 1"
                    onPicked: tray.share("screen")
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4.67; radius: 4
                        color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                        border.width: 0.67; border.color: theme.stroke
                        Text {
                            anchors.centerIn: parent
                            text: "Screen 1"
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
                        }
                    }
                }
                Tile {
                    x: 186.7; y: 124.3
                    accessibleName: "Opens list of active windows"
                    onPicked: tray.share("window")
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4.67; radius: 4
                        color: theme.pick("#F5F5F5", "#292929", "#000000")
                        Image {
                            x: 10; y: 7; width: 124; height: 75
                            source: "../assets/illustrations/share-window.svg"
                            sourceSize: Qt.size(248, 150)
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                }
            }
        }
    }
    // A 154 x 90 option with Fluent's 4.67 focus/hover ring.
    component Tile: Rectangle {
        id: tile
        property string accessibleName
        signal picked()
        width: 154; height: 90; radius: 4
        color: "transparent"
        border.width: th.hovered ? 2 : 0
        border.color: theme.brand
        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tile.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.onPressAction: tile.picked()
    }
}
