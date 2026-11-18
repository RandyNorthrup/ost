import QtQuick
import QtQuick.Controls
import com.ost.desktop

// Teams' Content from camera setup dialog (ContentCameraSetupDialog in
// Teams' share-tray-content-camera-setup-dialog bundle, its Griffel CSS;
// 1rem = 10 px), a Fluent alert dialog:
// - 800 wide, padding 32 (a window up to 1000 wide: 520, padding 20);
//   "Content from camera" (20/28 semibold) and a subtle close X — no
//   Cancel; closing resets the effects, the rotation and the scan type.
// - Under a NeutralStroke3 line: "Camera" (padding 6 / 4) over a
//   filled-lighter dropdown (200, 140 in narrow windows) and an info button
//   ("For the best experience, use wireless headphones and a camera with
//   at least 720p resolution."); 20 on, "Content type" (Whiteboard /
//   Document / Video, 200 / 140, 10 to its right; picking one re-applies
//   that type's effects); at the end the content-camera toolbar
//   (transparent 32 px buttons, 16 px glyphs, tooltips below): Overlay
//   presenter / Don't overlay presenter, Detect edges / Don't detect
//   edges, Rotate.
// - 20 under it a 450 tall area (300 in windows up to 1000 tall): for a
//   whiteboard or document first Teams' info ("Share a whiteboard", "Point
//   your camera at a nearby whiteboard to detect it.", Got it, Don't show
//   again), the dropdowns and tools disabled meanwhile; then the preview
//   (420 / 270, the processed camera fitted) with "Preview (only you can
//   see this)" under it (padding-top 10) and Teams' toast over it (top at
//   the dialog's middle, centred; NeutralBackground1, radius 3, padding 6
//   10, 12/14, fading in to 0.75 over 0.8 s).
// - Learn more (aka.ms/AAdu0p9) on the left, Scan Again and Share on the
//   right, both disabled until the preview runs.
// Edge detection as Teams' ContentScanPreviewComponent: when quadEnabled
// turns on, "Looking for a whiteboard" / "Looking for a document"
// (announced "Detecting edges"), a 200 ms poll until the quad is stable
// and not the whole frame ("Edges detected"), or after 11 s edge detection
// turned off (cleanup kept, zoom on) and 800 ms later "Couldn't detect
// edges. …" for 7 s. Share freezes the stable quad (else the whole frame)
// and shares the processed camera on the screen-sharing line.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// "whiteboard", "document" or "video" (the tray's pick).
    property string type: "whiteboard"
    property var devices: []
    property string device: ""
    /// The info view per type this session (Teams' consent map), from
    /// "Don't show again".
    property var showInfo: ({})
    /// Teams' scanVideoEffect as last applied or polled.
    property var fx: ({})
    property bool previewRunning: false
    property bool toast: false
    property string toastText: ""
    property string announced: ""
    property bool detecting: false
    signal share(string device)

    readonly property real winW: Overlay.overlay ? Overlay.overlay.width : 1280
    readonly property real winH: Overlay.overlay ? Overlay.overlay.height : 720
    readonly property bool wide: winW > 1000
    readonly property bool tall: winH > 1000
    readonly property bool stacked: winW <= 720
    readonly property real pad: wide ? 32 : 20
    readonly property real dropW: wide ? 200 : 140
    readonly property real areaH: tall ? 450 : 300
    readonly property bool infoView: type !== "video" && showInfo[type] !== false
    readonly property bool shareEnabled: previewRunning && !infoView
    readonly property var fullFrame: [0, 0, 1, 0, 1, 1, 0, 1]
    readonly property var noQuad: [0, 0, 0, 0, 0, 0, 0, 0]
    function trivial(q) { return !q || JSON.stringify(q) === JSON.stringify(fullFrame) || JSON.stringify(q) === JSON.stringify(noQuad) }
    readonly property bool quadOn: !!fx.quadEnabled || !trivial(fx.quadDetails ? fx.quadDetails.normalizedQuad : null)
    readonly property bool cleanupOn: !!fx.cleanupEnabled
    function typeName(t) { return ({ whiteboard: "Whiteboard", document: "Document", video: "Video" })[t] || "Video" }

    width: wide ? 800 : 520
    height: body.y + body.height + pad

    function openFor(t) {
        type = t
        const d = JSON.parse(backend.videoDevices() || "{}")
        devices = d.devices || []
        device = d.current || (devices[0] ? devices[0].path : "")
        const m = {}
        for (const k of ["whiteboard", "document"]) {
            const v = backend.setting("tmp.dont-show-again-" + k)
            m[k] = v === "" ? true : v === "true"
        }
        showInfo = m
        fx = {}
        previewRunning = false
        hideToast()
        open()
        say("Content from camera")
        if (!infoView) startPreview(true)
    }
    function say(t) { announced = ""; announced = t; console.warn("CCAM announce", t) }

    // The effects (Teams' applyScanVideoEffect); quadEnabled turning on
    // starts the edge detection's watch, as Teams' cache watch does.
    function apply(o) {
        const was = !!fx.quadEnabled
        fx = { quadEnabled: o.quadEnabled, cleanupEnabled: o.cleanupEnabled, zoomEnabled: o.zoomEnabled,
               quadDetails: { normalizedQuad: o.normalizedQuad, quadStable: false } }
        backend.contentCameraApply(JSON.stringify(o))
        console.warn("CCAM apply", JSON.stringify(o))
        if (o.quadEnabled && !was) startDetection()
    }
    function defaults(t) {
        return t === "whiteboard" ? { quadEnabled: true, cleanupEnabled: true, zoomEnabled: true, normalizedQuad: fullFrame }
             : t === "document" ? { quadEnabled: true, cleanupEnabled: false, zoomEnabled: true, normalizedQuad: fullFrame }
             : { quadEnabled: false, cleanupEnabled: false, zoomEnabled: true, normalizedQuad: fullFrame }
    }
    function off() { return { quadEnabled: false, cleanupEnabled: false, zoomEnabled: false, normalizedQuad: fullFrame } }
    // Teams' Nt: everything off, then the type's defaults.
    function applyDefaults(t) { stopDetection(); apply(off()); apply(defaults(t)) }

    function startPreview(withDefaults) {
        previewRunning = false
        if (!backend.contentCameraOpen(device)) { console.warn("CCAM camera failed", device); return }
        console.warn("CCAM preview", device, type)
        if (withDefaults) applyDefaults(type)
    }
    function stopPreview() { stopDetection(); hideToast(); previewRunning = false; backend.contentCameraClose() }

    function state() { const s = backend.contentCameraState(); return s ? JSON.parse(s) : null }
    function stable(s) { return s && !s.pending && s.quadDetails.quadStable && !trivial(s.quadDetails.normalizedQuad) }

    function showToastNow(t) { toastText = t; toast = true }
    function hideToast() { toast = false }
    function lookingText() { return type === "whiteboard" ? "Looking for a whiteboard" : "Looking for a document" }
    function failedText() {
        return type === "whiteboard" ? "Couldn't detect edges. We've turned off edge detection, but you can still share the whiteboard."
                                     : "Couldn't detect edges. We've turned off edge detection, but you can still share the document."
    }
    function startDetection() {
        stopDetection()
        detecting = true
        failTimer.restart()
        pollTimer.restart()
        if (type === "video") { hideToast(); say("Detecting edges"); return }
        showToastNow(lookingText())
        say("Detecting edges")
    }
    function stopDetection() { detecting = false; failTimer.stop(); pollTimer.stop(); errShow.stop(); errHide.stop() }

    // Teams' zt: every 200 ms until the quad is stable.
    Timer {
        id: pollTimer
        interval: 200; repeat: true
        onTriggered: {
            const s = root.state()
            if (s && !s.pending) root.fx = s
            if (root.stable(s)) {
                root.detecting = false; stop(); failTimer.stop(); root.hideToast()
                root.say("Edges detected")
                console.warn("CCAM detected", JSON.stringify(s.quadDetails))
            }
        }
    }
    // Teams' xt: 11 s without a stable quad turns edge detection off.
    Timer {
        id: failTimer
        interval: 11000
        onTriggered: {
            pollTimer.stop(); root.detecting = false
            const s = root.state()
            if (root.stable(s)) return
            console.warn("CCAM no edges", JSON.stringify(s ? s.quadDetails : null))
            root.hideToast()
            root.say(root.type === "video" ? "Couldn't detect edges. We've turned off edge detection, but you can still share the document." : root.failedText())
            if (root.type !== "video") errShow.restart()
            root.apply({ quadEnabled: false, cleanupEnabled: s ? s.cleanupEnabled : false, zoomEnabled: true, normalizedQuad: root.fullFrame })
        }
    }
    Timer { id: errShow; interval: 800; onTriggered: { root.showToastNow(root.failedText()); errHide.restart() } }
    Timer { id: errHide; interval: 7000; onTriggered: root.hideToast() }
    // The preview's state for the tools' icons, and the first frame.
    Timer {
        interval: 200; repeat: true; running: root.visible && !root.infoView
        onTriggered: {
            const s = root.state()
            if (!s) return
            if (!pollTimer.running && !s.pending) root.fx = s
            if (!root.previewRunning && s.frames > 0) { root.previewRunning = true; console.warn("CCAM preview started", JSON.stringify(s)) }
        }
    }

    // Close (Teams: reset the effects, rotation 0, scan type none).
    onClosed: if (!sharing) stopPreview()
    property bool sharing: false
    onAboutToShow: sharing = false

    function scanAgain() {
        // Teams' An: everything off, then edges again (cleanup kept).
        const c = cleanupOn
        stopDetection()
        apply({ quadEnabled: false, cleanupEnabled: false, zoomEnabled: false, normalizedQuad: noQuad })
        apply({ quadEnabled: true, cleanupEnabled: c, zoomEnabled: true, normalizedQuad: noQuad })
        console.warn("CCAM scan again")
    }
    function doShare() {
        // Teams' Ln: detection frozen, the stable quad kept (else the whole
        // frame), then the camera shared.
        const s = state() || fx
        const q = s.quadDetails && s.quadDetails.quadStable ? s.quadDetails.normalizedQuad : fullFrame
        stopDetection(); hideToast()
        backend.contentCameraApply(JSON.stringify({ quadEnabled: false, zoomEnabled: !!s.zoomEnabled, cleanupEnabled: !!s.cleanupEnabled, normalizedQuad: q }))
        console.warn("CCAM share", device, JSON.stringify({ cleanup: !!s.cleanupEnabled, zoom: !!s.zoomEnabled, quad: q, stable: !!(s.quadDetails && s.quadDetails.quadStable) }))
        sharing = true
        close()
        root.share(device)
    }
    function gotIt() {
        const m = Object.assign({}, showInfo); m[type] = false; showInfo = m
        console.warn("CCAM got it", type)
        startPreview(true)
    }
    function pickType(t) {
        if (t === type) return
        stopDetection(); hideToast()
        type = t
        console.warn("CCAM type", t, "info", infoView)
        if (infoView) { previewRunning = false; backend.contentCameraClose(); return }
        if (!backend.contentCameraState()) startPreview(true)
        else applyDefaults(t)
    }
    function pickCamera(path) {
        if (path === device) return
        device = path
        backend.setCameraDevice(path)
        console.warn("CCAM camera", path)
        if (!infoView) startPreview(true)
    }
    function toggleCleanup() {
        const on = !cleanupOn
        const q = fx.quadDetails ? fx.quadDetails.normalizedQuad : fullFrame
        apply({ quadEnabled: quadOn, cleanupEnabled: on, zoomEnabled: quadOn || on || !!fx.zoomEnabled, normalizedQuad: q || fullFrame })
        say(on ? "Overlay presenter turned on" : "Overlay presenter turned off")
    }
    function toggleEdges() {
        const on = !quadOn
        const c = cleanupOn
        if (on) {
            apply(off())
            apply({ quadEnabled: true, cleanupEnabled: c, zoomEnabled: true, normalizedQuad: noQuad })
        } else {
            stopDetection(); hideToast()
            apply({ quadEnabled: false, cleanupEnabled: cleanupOn, zoomEnabled: cleanupOn, normalizedQuad: fullFrame })
            say("Edge detection turned off")
        }
    }
    function rotate() { backend.contentCameraRotate(); console.warn("CCAM rotate") }

    Text {
        visible: false
        text: root.announced
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.announced
    }

    // Fluent's medium buttons (32 tall, at least 96 wide).
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool usable: true
        signal clicked()
        width: Math.max(96, dbText.implicitWidth + 24); height: 32; radius: 4
        color: !usable ? theme.bgDisabled : dbTap.pressed ? theme.pick("#444791", "#444791", "#1AEBFF") : dbHover.hovered ? theme.brandHover : theme.brandFill
        border.color: usable ? "transparent" : theme.hc("#E0E0E0", theme.hcDisabled); border.width: 1
        Text {
            id: dbText
            anchors.centerIn: parent
            text: db.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !db.usable ? theme.disabled : theme.onFill(db, theme.textOnBrand)
        }
        HoverHandler { id: dbHover; enabled: db.usable; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: dbTap; enabled: db.usable; onTapped: db.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: db.label
        Accessible.onPressAction: if (db.usable) db.clicked()
    }
    // Fluent's tooltip (no arrow), 4 below its button.
    component TipBelow: ToolTip {
        id: tb
        property string tipText
        text: tipText
        delay: 300
        x: (parent ? parent.width : 0) / 2 - width / 2
        y: (parent ? parent.height : 0) + 4
        topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
        contentItem: Text {
            text: tb.tipText
            width: Math.min(implicitWidth, 240 - 22)
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
    }
    // A content-camera tool: transparent, 32 px, a 16 px glyph.
    component Tool: Rectangle {
        id: tl
        property string icon
        property string tip
        property bool usable: true
        signal clicked()
        width: 32; height: 32; radius: 4
        color: theme.hc("transparent", tlHover.hovered && tl.usable ? theme.hcHighlight : "transparent")
        FluentIcon {
            anchors.centerIn: parent
            name: tl.icon; size: 16
            color: !tl.usable ? theme.disabled : theme.onFill(tl, tlHover.hovered ? theme.brand : theme.textStrong)
        }
        HoverHandler { id: tlHover; cursorShape: tl.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tl.usable; onTapped: tl.clicked() }
        TipBelow { visible: tlHover.hovered; tipText: tl.tip }
        Accessible.role: Accessible.Button
        Accessible.name: tl.tip
        Accessible.onPressAction: if (tl.usable) tl.clicked()
    }
    // Fluent's filled-lighter dropdown (32 tall; no border on the white
    // dialog), disabled while the info shows.
    component FilledDropdown: Rectangle {
        id: fd
        property string label
        property string placeholder
        property var options: []
        property bool usable: true
        property string accessibleName
        signal picked(string code)
        height: 32; radius: 4
        color: theme.surface
        border.color: !usable ? theme.hc("#E0E0E0", theme.hcDisabled) : theme.transparentStroke; border.width: 1
        Text {
            x: 11; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 44; elide: Text.ElideRight
            text: fd.label || fd.placeholder
            font.family: theme.font; font.pixelSize: 14
            color: !fd.usable ? theme.disabled : fd.label ? theme.text : theme.textSecondary
        }
        FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: fd.usable ? theme.textStrong : theme.disabled }
        HoverHandler { cursorShape: fd.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: fd.usable; onTapped: fdList.visible ? fdList.close() : fdList.open() }
        Accessible.role: Accessible.ComboBox
        Accessible.name: fd.accessibleName
        Popup {
            id: fdList
            parent: Overlay.overlay
            padding: 4
            width: Math.max(fd.width, 160)
            height: fdCol.implicitHeight + 8
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            onAboutToShow: {
                const p = fd.mapToItem(Overlay.overlay, 0, 0)
                x = p.x
                const below = p.y + fd.height + 2
                y = below + height <= Overlay.overlay.height ? below : p.y - height - 2
            }
            Column {
                id: fdCol
                width: parent.width
                Repeater {
                    model: fd.options
                    Rectangle {
                        id: fo
                        required property var modelData
                        width: fdCol.width; height: 32; radius: 4
                        color: foh.hovered ? theme.menuHover : "transparent"
                        Text {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16; elide: Text.ElideRight
                            text: fo.modelData[1]
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.onFill(fo, theme.text)
                        }
                        HoverHandler { id: foh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { fdList.close(); fd.picked(fo.modelData[0]) } }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: fo.modelData[1]
                    }
                }
            }
        }
    }

    Item {
        id: body
        x: root.pad; y: root.pad
        width: root.width - 2 * root.pad
        height: actions.y + actions.height

        // Title and close.
        Text {
            width: parent.width - 40; height: 28
            verticalAlignment: Text.AlignVCenter
            text: "Content from camera"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            id: closeBtn
            x: parent.width - 32; y: 0; width: 32; height: 32; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20-filled"; size: 20; color: theme.onFill(closeBtn, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
            Accessible.onPressAction: root.close()
        }

        Item {
            id: content
            y: 40
            width: parent.width
            height: area.y + area.height
            Rectangle { width: parent.width; height: 1; color: theme.quoteBorder }

            // Camera, Content type and the tools.
            Item {
                id: settingsRow
                width: parent.width
                height: root.stacked ? 124 : 62
                Column {
                    id: camCol
                    Item { width: 1; height: 6 }
                    Text {
                        height: 20; verticalAlignment: Text.AlignVCenter
                        text: "Camera"
                        font.family: theme.font; font.pixelSize: 14
                        color: root.infoView ? theme.disabled : theme.text
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        FilledDropdown {
                            width: root.dropW
                            usable: !root.infoView
                            placeholder: "None"
                            label: (root.devices.find(d => d.path === root.device) || { name: "" }).name
                            options: root.devices.map(d => [d.path, d.name])
                            accessibleName: "Cameras"
                            onPicked: code => root.pickCamera(code)
                        }
                        // Fluent's InfoButton (medium).
                        Rectangle {
                            id: infoBtn
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 4
                            color: theme.hc("transparent", infoHover.hovered ? theme.hcHighlight : "transparent")
                            FluentIcon { anchors.centerIn: parent; name: "info-16-regular"; size: 16; color: theme.onFill(infoBtn, infoHover.hovered ? theme.brand : theme.textStrong) }
                            HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: infoTip.visible = !infoTip.visible }
                            ArrowTip { id: infoTip; visible: infoHover.hovered; tipText: "For the best experience, use wireless headphones and a camera with at least 720p resolution." }
                            Accessible.role: Accessible.Button
                            Accessible.name: "For the best experience, use wireless headphones and a camera with at least 720p resolution."
                        }
                    }
                }
                Column {
                    id: typeCol
                    x: root.stacked ? 0 : camCol.width + 20
                    y: root.stacked ? 62 : 0
                    Item { width: 1; height: 6 }
                    Text {
                        height: 20; verticalAlignment: Text.AlignVCenter
                        text: "Content type"
                        font.family: theme.font; font.pixelSize: 14
                        color: root.infoView ? theme.disabled : theme.text
                    }
                    Item { width: 1; height: 4 }
                    FilledDropdown {
                        width: root.dropW
                        usable: !root.infoView
                        placeholder: "Video"
                        label: root.typeName(root.type)
                        options: [["whiteboard", "Whiteboard"], ["document", "Document"], ["video", "Video"]]
                        accessibleName: "Content type"
                        onPicked: code => root.pickType(code)
                    }
                }
                // Teams' content-camera-toolbar (Fluent Toolbar, padding
                // 4 8), its bottom on the dropdowns'.
                Row {
                    id: tools
                    x: parent.width - width - 8
                    y: typeCol.y + 62 - 4 - 32
                    Tool {
                        icon: root.cleanupOn ? "content-camera-cleanup-on" : "content-camera-cleanup-off"
                        tip: root.cleanupOn ? "Don't overlay presenter" : "Overlay presenter"
                        usable: !root.infoView
                        onClicked: root.toggleCleanup()
                    }
                    Tool {
                        icon: root.quadOn ? "content-camera-edges-on" : "content-camera-edges-off"
                        tip: root.quadOn ? "Don't detect edges" : "Detect edges"
                        usable: !root.infoView
                        onClicked: root.toggleEdges()
                    }
                    Tool {
                        icon: "content-camera-rotate"
                        tip: "Rotate"
                        usable: !root.infoView
                        onClicked: root.rotate()
                    }
                }
            }

            Item {
                id: area
                y: settingsRow.height + 20
                width: parent.width
                height: root.areaH

                // Teams' info for a whiteboard or document.
                Item {
                    anchors.fill: parent
                    visible: root.infoView
                    readonly property bool doc: root.type === "document"
                    Column {
                        id: infoCol
                        width: parent.width
                        y: (parent.height - 36 - height) / 2
                        spacing: 15
                        Item {
                            width: parent.width; height: 10 + illo.height
                            Image {
                                id: illo
                                y: 10
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.type === "document" ? 150 : 221
                                height: root.type === "document" ? 142 : 126
                                sourceSize: Qt.size(width * 2, height * 2)
                                fillMode: Image.PreserveAspectFit
                                source: root.type === "document" ? "../assets/illustrations/empty-sharing-document-camera.svg" : "../assets/illustrations/setup-whiteboard-call-share.svg"
                            }
                        }
                        Column {
                            width: parent.width
                            Text {
                                x: 14; width: parent.width - 28
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: root.type === "document" ? "Share a document" : "Share a whiteboard"
                                font.family: theme.font; font.pixelSize: 20
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: theme.text
                                Accessible.role: Accessible.Heading
                                Accessible.name: text
                            }
                            Text {
                                x: root.wide ? 100 : 14; width: parent.width - 2 * x
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: root.type === "document" ? "Put the document in view of your document camera or webcam." : "Point your camera at a nearby whiteboard to detect it."
                                font.family: theme.font; font.pixelSize: 16  // Teams: 15.6 (pixel sizes are whole here)
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: theme.text
                            }
                        }
                        Item {
                            width: parent.width; height: 42
                            DialogButton {
                                id: gotItBtn
                                anchors.horizontalCenter: parent.horizontalCenter
                                label: "Got it"
                                onClicked: root.gotIt()
                                Accessible.name: root.type === "document" ? "Got it, dismiss document sharing information and start camera preview" : "Got it, dismiss whiteboard sharing information and start camera preview"
                            }
                        }
                    }
                    // Don't show again (Fluent's Checkbox: padding 2, margin
                    // 0 2.5 2.5).
                    Item {
                        id: dontShow
                        property bool checked: false
                        x: 2.5; y: parent.height - 36 - 2.5
                        width: 36 + dsText.implicitWidth + 4; height: 36
                        SettingsParts.Box { x: 10; y: 10; checked: dontShow.checked; hovered: dsHover.hovered }
                        Text {
                            id: dsText
                            x: 34; y: 8; height: 20; verticalAlignment: Text.AlignVCenter
                            text: "Don't show again"
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.text
                        }
                        HoverHandler { id: dsHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                dontShow.checked = !dontShow.checked
                                // Teams writes it at once: whether to show.
                                backend.setSetting("tmp.dont-show-again-" + root.type, dontShow.checked ? "false" : "true")
                                console.warn("CCAM dont-show-again", root.type, dontShow.checked)
                            }
                        }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Don't show again"
                        Accessible.checked: checked
                    }
                }

                // The preview: the processed camera, fitted.
                Item {
                    anchors.fill: parent
                    visible: !root.infoView
                    VideoFrame {
                        id: previewFrame
                        width: parent.width; height: root.areaH - 30
                        source: root.visible && !root.infoView ? "content-camera" : ""
                        fit: true; letterbox: false
                        Timer { interval: 66; repeat: true; running: root.visible && !root.infoView; onTriggered: previewFrame.refresh() }
                    }
                    Text {
                        y: root.areaH - 20
                        height: 20; verticalAlignment: Text.AlignVCenter
                        textFormat: Text.StyledText
                        text: "<b>Preview</b> (only you can see this)"
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                }
            }
        }

        // Learn more, Scan Again, Share.
        Item {
            id: actions
            y: content.y + content.height + 8
            width: parent.width; height: 32
            SettingsParts.Link {
                anchors.verticalCenter: parent.verticalCenter
                text: "Learn more"
                onClicked: Qt.openUrlExternally("https://aka.ms/AAdu0p9")
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                DialogButton { label: "Scan Again"; usable: root.shareEnabled; onClicked: root.scanAgain() }
                DialogButton { id: shareBtn; label: "Share"; usable: root.shareEnabled; onClicked: root.doShare() }
            }
        }
    }

    // Teams' toast over the preview: its top at the dialog's middle.
    Rectangle {
        id: toastBox
        visible: root.toast && !root.infoView
        x: (root.width - width) / 2; y: root.height / 2
        width: Math.min(toastLabel.implicitWidth + 20, root.width - 2 * root.pad)
        height: toastLabel.height + 12
        radius: 3
        color: theme.surface
        border.color: theme.transparentStroke; border.width: theme.highContrast ? 1 : 0
        opacity: 0
        onVisibleChanged: { if (visible) { opacity = 0; fadeIn.restart() } }
        NumberAnimation { id: fadeIn; target: toastBox; property: "opacity"; from: 0; to: 0.75; duration: 800; easing.type: Easing.Bezier; easing.bezierCurve: [0.33, 0, 0.67, 1, 1, 1] }
        Text {
            id: toastLabel
            x: 10; y: 6
            width: Math.min(implicitWidth, root.width - 2 * root.pad - 20)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: root.toastText
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 14; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }
}
