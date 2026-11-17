import QtQuick
import QtQuick.Controls.Basic

// Teams' share tray (the classic floating tray, share-popup /
// floating-sharetray-wrapper; measured on winpc 2026-11-16 in the test
// meeting, camera and mic off): a 360-wide card under the bar (radius 4,
// Fluent's shadow 2), as tall as the window allows, scrolling below its
// header (the content is 622 tall):
// - "Share content" (16/700) and, at the end, "Include sound" (12 px)
//   with its switch (system-audio-checkbox): the computer's sound goes
//   into the call with the screen;
// - "Presenter mode" (14/600) and its four 32 x 31.3 icon radios —
//   Content only, Standout, Side-by-side, Reporter (the camera modes
//   need your camera) — then Add background (Side-by-side and Reporter's
//   picture: a drill-down "Add a background" of Teams' 13 pictures);
// - "Screen" and "Window" (14/600) over 154 x 90 tiles: Teams' screen
//   thumbnails and window list come from its calling stack; on Linux the
//   desktop's portal shows what to share, so the Screen tile shows Teams'
//   no-preview name ("Screen 1") and the Window tile Teams' window
//   illustration ("Opens list of active windows"). Picking one opens the
//   desktop's picker for screens or for windows;
// - Microsoft Whiteboard ("Start Whiteboard") and Content from camera
//   ("Share a document, a whiteboard, and more"), 312 x 36 rows with a
//   32 px tile;
// - PowerPoint Live and Excel Live (14/600 with a 12 px line under) and
//   their recent files ("No files available" without any), then Browse
//   OneDrive and Browse my computer.
// Esc closes it.
Popup {
    id: tray
    property bool includeSound: false
    property bool cameraOn: false
    /// The presenter mode picked (Teams' names).
    property string mode: "ContentOnly"
    /// Add background's picture id ("" for Teams' default).
    property string backgroundId: ""
    /// Recent PowerPoint and Excel files: [{name, url, driveItemId}].
    property var pptFiles: []
    property var excelFiles: []
    signal share(string kind)
    signal pickMode(string mode)
    signal pickBackground(var background)
    signal whiteboard()
    /// Content from camera ▸ Whiteboard, Document or Video.
    signal contentCamera(string type)
    signal officeFile(string kind, var file)
    signal browse(string where)
    /// The drill-down shown ("" the tray, "backgrounds").
    property string drill: ""
    onClosed: drill = ""
    width: 360
    padding: 0
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    // Teams' Add background pictures (ECS videoBackgroundImages, context
    // BackgroundAPL), default first, with their names.
    readonly property string cdn: "https://statics.teams.cdn.office.net"
    readonly property var backgrounds: [
        { id: "aplBackground_003", name: "Futuristic room", isDefault: true },
        { id: "aplBackground_001", name: "Wavy pink and blue" },
        { id: "aplBackground_002", name: "Paper rectangles" },
        { id: "aplBackground_004", name: "Floating shapes" },
        { id: "aplBackground_005", name: "Glowing light" },
        { id: "aplBackground_006", name: "Pink cubes" },
        { id: "aplBackground_007", name: "Circles and squares" },
        { id: "aplBackground_008", name: "Stacked blocks" },
        { id: "aplBackground_009", name: "Green fabric" },
        { id: "aplBackground_010", name: "Colorful bubbles" },
        { id: "aplBackground_011", name: "Skylight" },
        { id: "aplBackground_012", name: "Garden" },
        { id: "aplBackground_013", name: "Green chalkboard" }
    ]
    function backgroundUrl(id, thumb) {
        return "/evergreen-assets/backgroundimages/" + id + (thumb ? "_thumb" : "") + ".jpg?v=0.1"
    }
    background: Rectangle {
        radius: 4
        color: theme.surface
        border.width: theme.highContrast ? 1 : 0; border.color: "#FFFFFF"
        Rectangle { z: -1; anchors.fill: parent; anchors.topMargin: 0.8; radius: 4; color: Qt.rgba(0, 0, 0, theme.dark ? 0.28 : 0.13) }
    }
    contentItem: Item {
        implicitHeight: Math.min(header.height + (tray.drill === "backgrounds" ? bgBody.implicitHeight + 22 : tray.drill === "camera" ? 218 : body.implicitHeight),
                                 tray.parent ? tray.parent.height - tray.y - 7.3 : 438.7)
        // Header (71 tall); in a drill-down, the back button and its title.
        Item {
            id: header
            width: parent.width; height: tray.drill !== "" ? 49 : 71
            Rectangle {
                id: backButton
                visible: tray.drill !== ""
                x: 21; y: 23; width: 20; height: 20; radius: 4
                color: backHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; size: 20; name: "chevron-left-20"; color: theme.text }
                HoverHandler { id: backHover }
                TapHandler { onTapped: tray.drill = "" }
                Accessible.role: Accessible.Button
                Accessible.name: "Back to share tray main content"
            }
            Text {
                x: tray.drill !== "" ? 55 : 23.7; y: tray.drill !== "" ? 23 : 34.7; height: 20; verticalAlignment: Text.AlignVCenter
                text: tray.drill === "backgrounds" ? "Add a background" : tray.drill === "camera" ? "Content from camera" : "Share content"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Text {
                id: soundLabel
                visible: tray.drill === ""
                x: 198.7; y: 29.7; height: 36; verticalAlignment: Text.AlignVCenter
                text: "Include sound"
                font.family: theme.font; font.pixelSize: 12; color: theme.text
            }
            SettingsParts.Toggle {
                visible: tray.drill === ""
                x: 293.3; y: 37.7
                stateLabel: false
                on: tray.includeSound
                accessibleName: "Include sound"
                onToggled: v => tray.includeSound = v
            }
        }
        Flickable {
            id: flick
            visible: tray.drill === ""
            y: header.height; width: parent.width; height: parent.height - y
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            Item {
                id: body
                width: flick.width
                // Teams' content: 622 (the last row ends at 621.7).
                implicitHeight: 622
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
                            readonly property bool checked: modelData.key === tray.mode
                            readonly property bool usable: !modelData.camera || tray.cameraOn
                            width: 32; height: 31.3; radius: 3
                            color: checked ? theme.pick("#E0E0E0", "#3D3D3D", "#1AEBFF") : !usable ? theme.pick("#F0F0F0", "#141414", "#000000") : mh.hovered ? theme.menuHover : theme.surface
                            border.width: 0.67
                            border.color: checked ? theme.pick("#BDBDBD", "#666666", "#FFFFFF") : theme.pick("#FFFFFF", "#141414", "#000000")
                            FluentIcon { anchors.centerIn: parent; size: 20; name: mode.modelData.icon + (mode.checked ? "-filled" : ""); color: mode.usable ? theme.text : theme.disabled }
                            HoverHandler { id: mh }
                            TapHandler { enabled: mode.usable; onTapped: tray.pickMode(mode.modelData.key) }
                            ToolTip.visible: mh.hovered
                            ToolTip.text: mode.usable ? mode.modelData.label : "Turn on your camera to select this layout"
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label
                            Accessible.description: usable ? "" : "Turn on your camera to select this layout"
                            Accessible.checked: checked
                            Accessible.onPressAction: if (usable) tray.pickMode(modelData.key)
                        }
                    }
                }
                SettingsParts.Button {
                    x: 204.3; y: 42; label: "Add background"
                    onClicked: tray.drill = "backgrounds"
                }
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
                // Microsoft Whiteboard (ms-whiteboard): its logo tile
                // (#0027B4, radius 2) and two lines.
                RowButton {
                    x: 23.7; y: 238.3; height: 36
                    accessibleName: "Share Microsoft Whiteboard Start Whiteboard"
                    title: "Microsoft Whiteboard"
                    subtitle: "Start Whiteboard"
                    subtitleColor: theme.textSecondary
                    onPicked: tray.whiteboard()
                    Rectangle {
                        y: 2; width: 32; height: 32; radius: 2
                        color: "#0027B4"
                        Image { x: 5.5; y: 5.5; width: 21; height: 21; source: "../assets/icons/whiteboard-logo.svg"; sourceSize: Qt.size(42, 42) }
                    }
                }
                // Content from camera (content-camera-button).
                RowButton {
                    x: 23.7; y: 298.3; height: 37.3
                    accessibleName: "Content from camera Share a document, a whiteboard, and more"
                    title: "Content from camera"
                    subtitle: "Share a document, a whiteboard, and more"
                    subtitleColor: theme.text
                    textX: 42.6
                    onPicked: tray.drill = "camera"
                    Rectangle {
                        x: 0.6; y: 2.7; width: 32; height: 32; radius: 4
                        color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
                        FluentIcon { anchors.centerIn: parent; size: 22; name: "share-content-camera"; color: theme.text }
                    }
                }
                // PowerPoint Live and Excel Live.
                OfficeSection {
                    y: 359.7
                    title: "PowerPoint Live"
                    subtitle: "See your notes, slides, and audience while you present."
                    files: tray.pptFiles
                    onPicked: f => tray.officeFile("ppt", f)
                }
                OfficeSection {
                    y: 451.7
                    title: "Excel Live"
                    subtitle: "Share a workbook for everyone to work on together."
                    files: tray.excelFiles
                    onPicked: f => tray.officeFile("excel", f)
                }
                Column {
                    x: 23.7; y: 555.7
                    spacing: 2
                    BrowseRow { icon: "onedrive-color"; colour: true; label: "Browse OneDrive"; onPicked: tray.browse("onedrive") }
                    BrowseRow { icon: "share-browse-computer"; label: "Browse my computer"; onPicked: tray.browse("computer") }
                }
            }
        }
        // Add a background: Teams' pictures in two columns, the default
        // first; the chosen one checked.
        Flickable {
            id: bgFlick
            visible: tray.drill === "backgrounds"
            y: header.height; width: parent.width; height: parent.height - y
            contentHeight: bgBody.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: bgFlick.contentHeight > bgFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            Grid {
                id: bgBody
                x: 24; y: 22
                columns: 2
                columnSpacing: 24; rowSpacing: 24
                Repeater {
                    model: tray.backgrounds
                    Rectangle {
                        id: bgItem
                        required property var modelData
                        readonly property bool chosen: (tray.backgroundId || "aplBackground_003") === modelData.id
                        width: 136.33; height: 77.4; radius: 4
                        color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
                        border.width: chosen ? 1.67 : bgHover.hovered ? 0.67 : 0
                        border.color: chosen ? theme.pick("#000000", "#FFFFFF", "#1AEBFF") : theme.stroke
                        Image {
                            anchors.fill: parent; anchors.margins: 0.67
                            source: tray.cdn + tray.backgroundUrl(bgItem.modelData.id, true)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        FluentIcon {
                            visible: bgItem.chosen
                            x: 109.6; y: 8.7; size: 20
                            name: "apl-check-20"; color: theme.pick("#242424", "#FFFFFF", "#FFFFFF")
                        }
                        HoverHandler { id: bgHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: tray.pickBackground({ id: bgItem.modelData.id, url: tray.backgroundUrl(bgItem.modelData.id, false), name: "" })
                        }
                        ToolTip.visible: bgHover.hovered && bgItem.modelData.name.length > 0
                        ToolTip.text: bgItem.modelData.name
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: bgItem.modelData.name
                        Accessible.checked: bgItem.chosen
                    }
                }
            }
        }
    }
    // Content from camera ▸: Whiteboard, Document, Video (322.7 wide
    // rows 18 in, Teams' 48 px illustrations, the title 14/600 at 64.6
    // and its line 12 px under it).
    Column {
        parent: tray.contentItem
        visible: tray.drill === "camera"
        x: 18; y: 59
        Repeater {
            model: [
                { type: "whiteboard", title: "Whiteboard", text: "Use your device's camera to share a nearby whiteboard.", h: 65.33 },
                { type: "document", title: "Document", text: "Use an external camera to share a document.", h: 61.33 },
                { type: "video", title: "Video", text: "Share live video in real time.", h: 61.33 }
            ]
            Rectangle {
                id: cc
                required property var modelData
                width: 322.67; height: modelData.h; radius: 4
                color: ccHover.hovered ? theme.menuHover : "transparent"
                Image {
                    x: 6.6; y: cc.modelData.type === "whiteboard" ? 8.7 : 6.7; width: 48; height: 48
                    source: "../assets/illustrations/content-camera-" + cc.modelData.type + ".svg"
                    sourceSize: Qt.size(96, 96)
                }
                Text {
                    x: 64.6; y: cc.modelData.type === "whiteboard" ? 6.7 : 12.7; height: 20; verticalAlignment: Text.AlignVCenter
                    text: cc.modelData.title
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                }
                Text {
                    x: 64.6; y: cc.modelData.type === "whiteboard" ? 26.7 : 32.7
                    width: 245.3; wrapMode: Text.Wrap
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    text: cc.modelData.text
                    font.family: theme.font; font.pixelSize: 12; color: theme.text
                }
                HoverHandler { id: ccHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { tray.close(); tray.contentCamera(cc.modelData.type) } }
                Accessible.role: Accessible.MenuItem
                Accessible.name: cc.modelData.title + " " + cc.modelData.text
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
    }
    // A 312-wide row: a 32 px tile, then its title (14/600) and a 12 px
    // line, 42 in.
    component RowButton: Rectangle {
        id: rb
        property string accessibleName
        property string title
        property string subtitle
        property color subtitleColor: theme.textSecondary
        property real textX: 42
        default property alias tileItems: tileHolder.data
        signal picked()
        width: 312; radius: 4
        color: rbHover.hovered ? theme.menuHover : "transparent"
        Item { id: tileHolder; width: 34; height: parent.height }
        Text {
            x: rb.textX; y: 0; height: 20; verticalAlignment: Text.AlignVCenter
            width: parent.width - x; elide: Text.ElideRight
            text: rb.title
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            x: rb.textX; y: 20; height: 16; verticalAlignment: Text.AlignVCenter
            width: parent.width - x; elide: Text.ElideRight
            text: rb.subtitle
            font.family: theme.font; font.pixelSize: 12; color: rb.subtitleColor
        }
        HoverHandler { id: rbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: rb.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.onPressAction: rb.picked()
    }
    component OfficeSection: Item {
        id: os
        property string title
        property string subtitle
        property var files: []
        signal picked(var file)
        x: 23.7; width: 312; height: 82
        Text {
            height: 20; verticalAlignment: Text.AlignVCenter
            text: os.title
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Text {
            y: 20; height: 20; verticalAlignment: Text.AlignVCenter
            width: parent.width; elide: Text.ElideRight
            text: os.subtitle
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
        Text {
            visible: os.files.length === 0
            y: 62; height: 20; verticalAlignment: Text.AlignVCenter
            text: "No files available"
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            Accessible.name: text
        }
        Column {
            visible: os.files.length > 0
            y: 50; width: parent.width
            Repeater {
                model: os.files.slice(0, 2)
                Rectangle {
                    id: fr
                    required property var modelData
                    width: 312; height: 32; radius: 4
                    color: frHover.hovered ? theme.menuHover : "transparent"
                    Image { x: 6; y: 6; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: "../assets/icons/" + (os.title === "Excel Live" ? "ft-xlsx-20" : "ft-pptx-20") + ".svg" }
                    Text {
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 38; elide: Text.ElideRight
                        text: fr.modelData.name || ""
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    HoverHandler { id: frHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: os.picked(fr.modelData) }
                    Accessible.role: Accessible.Button
                    Accessible.name: fr.modelData.name || ""
                }
            }
        }
    }
    component BrowseRow: Rectangle {
        id: br
        property string icon
        property bool colour: false
        property string label
        signal picked()
        width: 290; height: 32; radius: 4
        color: brHover.hovered ? theme.menuHover : theme.surface
        Image {
            visible: br.colour
            x: 7; y: 5; width: 18; height: 18
            source: br.colour ? "../assets/icons/" + br.icon + ".svg" : ""
            sourceSize: Qt.size(36, 36)
        }
        FluentIcon { visible: !br.colour; x: 7; y: 5; size: 18; name: br.colour ? "" : br.icon; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
        Text {
            x: 32; y: 6.7; height: 18.7; verticalAlignment: Text.AlignVCenter
            text: br.label
            font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
        }
        HoverHandler { id: brHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: br.picked() }
        Accessible.role: Accessible.MenuItem
        Accessible.name: br.label
        Accessible.onPressAction: br.picked()
    }
}
