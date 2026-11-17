import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as QC
import com.ost.desktop

// The pre-join window, as Teams desktop shows it before a meeting
// (measured at 1x): "Meeting join | <title>", the logo, title and time;
// the camera panel (off) on the left; the audio choices on the right
// (Computer audio with the mic switch and your devices); Cancel and
// Join now. Choices OST can't offer yet are shown disabled.
Window {
    id: win
    // Teams' "Always use dark theme for calls and meetings" (Settings ▸
    // Appearance): this window's own theme, dark then even in Light.
    Theme {
        id: theme
        dark: window.appTheme.dark || window.callsDark
        classic: window.appTheme.classic
        highContrast: window.appTheme.highContrast
        hoverCard: window.appTheme.hoverCard
    }
    property string subject
    property string joinUrl
    property date startTime
    property date endTime
    /// The scheduled times are known (from the calendar, or once the
    /// meeting tells us, in the lobby); Teams shows no date line before.
    property bool timesKnown: false
    function setTimes(start, end) {
        if (!start || !end) return
        startTime = new Date(start); endTime = new Date(end); timesKnown = true
    }
    property bool micOn: true
    /// Your camera (Teams' pre-join switch): a live preview while on.
    property bool cameraOn: false
    /// Teams' audio choices: "computer", "room" or "none" (Don't use audio).
    property string audio: "computer"
    /// The audio choices fill the preview's height (Teams, measured
    /// 2026-11-15): unselected choices are 41 tall under Computer audio's
    /// devices, else 44.7.
    readonly property real otherCardHeight: audio === "computer" ? 41 : 44.7
    /// Teams' room devices (Backend::room_devices): {devices, select,
    /// suggest}.
    property var rooms: ({ devices: [], select: null, suggest: false })
    /// The room Room audio joins with (a connected room device), or null.
    property var room: null
    /// Teams' "(suggested)": a room device it knows was found.
    readonly property bool roomSuggested: !!rooms.select || rooms.suggest
    /// Teams' BYOD pick: Room audio with that device, its speaker and
    /// microphone (and camera) chosen at once.
    function pickRoom(d) {
        room = d
        audio = "room"
        if (!d) return
        backend.setSetting("speakerDevice", d.speaker)
        backend.setSetting("micDevice", d.microphone)
        if (d.camera) backend.setSetting("cameraDevice", d.camera)
    }
    signal roomPickerOpenForTest()
    function roomPickerForTest() { roomPickerOpenForTest() }
    function findRooms() {
        room = null
        try { rooms = JSON.parse(backend.roomDevices()) } catch (e) { rooms = { devices: [], select: null, suggest: false } }
        if (rooms.select) pickRoom(rooms.select)
    }
    /// Held in the meeting's lobby (Teams' InLobby pre-join state): the
    /// title says someone will let you in, Join now and the audio choices
    /// are disabled; the mic and camera switches still work.
    property bool lobby: false
    /// Someone is in the meeting (else Teams says "when the meeting
    /// starts").
    property bool presenterConnected: true
    property string userName: ""
    // Teams greets you by your first name ("Hi, OST." for OST Test 1).
    readonly property string firstName: userName.trim().split(/\s+/)[0] || userName
    /// Starting a meeting now (a channel's Meet now, measured on winpc
    /// 2026-11-09): Teams heads it "Microsoft Teams meeting" (here, OST's
    /// name) with the title in a field under it (prejoin-title-input:
    /// 270 x 32, 16/20 medium, "Meeting in \"<channel>\"" to start with),
    /// and no time; Join now starts the meeting with that title.
    property bool meetNow: false
    /// The channel a Meet now starts in.
    property string meetChannel: ""
    signal join(bool micOn, bool withAudio, bool cameraOn)
    signal cancelled()
    /// Leave the lobby (Cancel, Escape).
    signal leaveLobby()
    /// The service ended the join (denied from the lobby, or nobody let us
    /// in): Teams turns this window into its retry screen.
    property string retryReason: ""
    signal rejoin()

    // Teams' lobby chat for people waiting (measured on winpc 2026-11-11):
    // once an organizer has written, "Lobby chat" (a secondary button with
    // the chat glyph) follows Join now, and the Lobby pane opens at the
    // right (360 wide: "Lobby" 18/700 in a 58 header with Close, a #F0F0F0
    // banner "Only organizers and people in the lobby can view these
    // messages." 12/17 between 0.67 #E0E0E0 lines, padding 5 16, then the
    // messages from "Meeting Organizer"); the rest centres in what's left.
    readonly property var lobbyMessages: {
        if (!lobby || !backend.callLobbyThread) return []
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return (all["win:" + backend.callLobbyThread] || []).filter(m => m.kind === "message" && !m.mine)
            .map(m => Object.assign({}, m, { sender: "Meeting Organizer", sender_mri: "" }))
    }
    property bool lobbyPaneOpen: false
    readonly property real lobbyPaneW: lobbyPaneOpen && lobby ? 360 : 0
    /// Teams' effects picker under the camera panel ("Video effects"), and
    /// its "More video effects" pane at the right (instead of the lobby's).
    property bool effectsOpen: false
    property bool effectsPaneOpen: false
    onEffectsPaneOpenChanged: if (effectsPaneOpen) lobbyPaneOpen = false
    onLobbyPaneOpenChanged: if (lobbyPaneOpen) effectsPaneOpen = false
    readonly property real sidePaneW: lobbyPaneW > 0 ? lobbyPaneW : effectsPaneOpen ? 360 : 0
    // Teams opens the pane when the first message arrives.
    onLobbyMessagesChanged: if (lobbyMessages.length > 0 && !lobbySeen) { lobbySeen = true; lobbyPaneOpen = true }
    property bool lobbySeen: false
    onLobbyChanged: if (!lobby) { lobbyPaneOpen = false; lobbySeen = false }
    property string lobbyChatOpen: ""
    Connections {
        target: backend
        function onCallLobbyThreadChanged() {
            if (!win.lobby) return
            if (win.lobbyChatOpen) backend.closeChatWindow(win.lobbyChatOpen)
            win.lobbyChatOpen = backend.callLobbyThread
            if (win.lobbyChatOpen) backend.openChatWindow(win.lobbyChatOpen)
        }
    }
    // The pre-join content shrinks to fit beside the pane, as Teams' does.
    readonly property real fit: Math.min(1, (width - sidePaneW - 48) / (508 + 16 + 449))

    width: 1280; height: 680
    minimumWidth: 1000; minimumHeight: 640
    color: theme.pane
    title: "Meeting join | " + subject

    function openMeetNow(channel, subj) {
        meetNow = true; meetChannel = channel; joinUrl = ""; subject = subj
        micOn = true; audio = "computer"; cameraOn = false
        effectsOpen = false; effectsPaneOpen = false
        findRooms()
        // A meeting started now has no dial-in to look up yet.
        backend.checkPrejoinPhone("")
        show(); raise(); requestActivate()
        titleField.forceActiveFocus(); titleField.cursorPosition = titleField.text.length
    }
    function openFor(url, subj, start, end) {
        meetNow = false; meetChannel = ""
        joinUrl = url; subject = subj
        startTime = start ? new Date(start) : new Date()
        endTime = end ? new Date(end) : new Date()
        timesKnown = !!start && !!end
        micOn = true; audio = "computer"; cameraOn = false
        effectsOpen = false; effectsPaneOpen = false
        retryReason = ""
        findRooms()
        backend.checkPrejoinPhone(url)
        show(); raise(); requestActivate()
    }
    /// Teams' PSTN state for this meeting before joining
    /// (Backend::check_prejoin_phone): checked, then available.
    readonly property var phoneState: backend.prejoinPhoneJson ? JSON.parse(backend.prejoinPhoneJson) : ({ checked: false, available: false })
    readonly property bool phoneChecked: !!phoneState.checked
    readonly property bool phoneAvailable: !!phoneState.available
    // Teams keeps your last audio choice (prejoinScreenSelectedAudio):
    // Phone audio comes back once the meeting is known to offer it.
    onPhoneAvailableChanged: if (phoneAvailable && audio === "computer" && backend.setting("prejoinAudio") === "phone") audio = "phone"
    readonly property bool canJoin: !lobby && (audio !== "room" || !!room)
    readonly property string mic: { const v = backend.setting("micDevice"); return v && v !== "default" ? v : "Default microphone" }
    readonly property string speaker: { const v = backend.setting("speakerDevice"); return v && v !== "default" ? v : "Default speaker" }

    Shortcut { sequence: "Escape"; onActivated: win.cancel() }
    function cancel() {
        win.close()
        if (win.lobby) win.leaveLobby(); else win.cancelled()
    }
    onCameraOnChanged: if (cameraOn && !backend.setCameraPreview(true)) cameraOn = false; else if (!cameraOn) backend.setCameraPreview(false)
    // The camera is free again for the call (or for nobody) once we go.
    onVisibleChanged: if (!visible && cameraOn) backend.setCameraPreview(false)
    Rectangle { anchors.fill: parent; color: theme.pane }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -win.sidePaneW / 2
        y: 73
        spacing: 6
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "../assets/logo.png"; width: 40; height: 40
            sourceSize: Qt.size(80, 80); fillMode: Image.PreserveAspectFit; smooth: true
        }
        Item { width: 1; height: 8 }
        // The title, or in the lobby Teams' lobby text in its place.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.meetNow ? Qt.application.name + " meeting" : !win.lobby ? win.subject
                : win.presenterConnected ? "Hi, " + win.firstName + ". Someone will let you in shortly."
                : "Hi, " + win.firstName + ". Someone will let you in when the meeting starts."
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
        }
        // Meet now: the meeting's title, to edit before joining.
        Item {
            visible: win.meetNow
            anchors.horizontalCenter: parent.horizontalCenter
            width: 270; height: visible ? 32 : 0
            TextInput {
                id: titleField
                anchors.fill: parent; leftPadding: 3; rightPadding: 3
                verticalAlignment: TextInput.AlignVCenter
                text: win.subject
                onTextEdited: win.subject = text
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Medium
                color: theme.text
                clip: true
                maximumLength: 256
                Accessible.name: "Meeting title"
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: titleField.activeFocus ? 2 : 1
                color: titleField.activeFocus ? theme.brand : theme.pick("#757575", "#ADADAD", "#000000")
            }
        }
        Text {
            visible: !win.meetNow && win.timesKnown
            anchors.horizontalCenter: parent.horizontalCenter
            // Teams: "Friday, Nov 6 • 3:00 PM – 3:30 PM PST".
            text: Qt.formatDate(win.startTime, "dddd, MMM d") + "  •  " + theme.time(win.startTime) + " – " + theme.time(win.endTime) + " " + Qt.formatDateTime(win.endTime, "t")
            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
            color: theme.textStrong
        }
    }

    Row {
        id: panels
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -win.sidePaneW / 2
        scale: win.fit
        transformOrigin: Item.Top
        y: 211
        spacing: 16
        // Camera: off, or your live preview (Teams' prejoin-v2-video-
        // preview: mirrored, filling the panel above its bar, inside the
        // 1 px edge).
        Rectangle {
            id: cameraPanel
            width: 508; height: 329 + (win.effectsOpen ? picker.height : 0); radius: 4
            color: theme.surface; border.color: theme.dividerSoft
            VideoFrame {
                id: preview
                visible: win.cameraOn && hasFrame
                source: win.cameraOn ? "self" : ""
                x: 1; y: 1; width: parent.width - 2; height: 329 - 45
                radius: 3
                transform: Scale { origin.x: preview.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
                Timer { interval: 33; repeat: true; running: win.visible && win.cameraOn; onTriggered: preview.refresh() }
            }
            Column {
                visible: !preview.visible
                anchors.horizontalCenter: parent.horizontalCenter
                y: (329 - 44 - height) / 2
                spacing: 8
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "video-off"; size: 20; color: theme.textStrong }
                Text { text: win.cameraOn ? "Starting your camera…" : "Your camera is turned off"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            Rectangle { y: 329 - 44; width: parent.width; height: 1; color: theme.dividerSoft }
            Row {
                x: 16; y: 329 - 44; height: 44
                spacing: 12
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: win.cameraOn ? "video-20-filled" : "video-off"; size: 20; color: theme.textStrong }
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    on: win.cameraOn
                    onToggled: v => win.cameraOn = v
                    Accessible.name: "Camera"
                }
                // Teams' divider (18 x 32) and its effects button (14/600,
                // brand while the picker is open). Teams calls it "Effects
                // and avatars"; OST has no avatars (TASK-0140).
                Item {
                    width: 18; height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.centerIn: parent; width: 1; height: 20; color: theme.divider }
                }
                Rectangle {
                    id: hcFill1
                    anchors.verticalCenter: parent.verticalCenter
                    width: fxRow.implicitWidth + 24; height: 31.3; radius: 4
                    color: fxHover.hovered ? theme.rowHover : "transparent"
                    Row {
                        id: fxRow
                        anchors.centerIn: parent
                        spacing: 8
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "video-background-effect-20"; size: 20; color: theme.onFill(hcFill1, win.effectsOpen ? theme.brand : theme.textStrong) }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Video effects"
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: theme.onFill(hcFill1, win.effectsOpen ? theme.brand : theme.textStrong)
                        }
                    }
                    HoverHandler { id: fxHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { win.effectsOpen = !win.effectsOpen; if (win.effectsOpen) videoEffects.load() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: win.effectsOpen ? "Hide video effects" : "Show video effects"
                }
            }
            // Teams' quick picker (video-effects-quick-picker): "Backgrounds"
            // (12 px) over a row of 74 x 42 tiles in 82 x 50 cells from 10
            // in (None, the blur tile, Teams' first four backgrounds),
            // "Filters" and its row (None, Teams' quick-picker filters) and
            // "More video effects" (12 px, brand) at the end; with the
            // camera off, "To enable video effects, turn on camera".
            Rectangle {
                id: picker
                visible: win.effectsOpen
                x: 1; y: 329; width: parent.width - 2; height: win.cameraOn && videoEffects.quickFilters.length > 0 ? 194 : 114
                color: theme.inputFilledDark; border.color: theme.transparentStroke
                radius: 3
                Rectangle { width: parent.width; height: 4; color: parent.color }
                Text {
                    visible: !win.cameraOn
                    anchors.centerIn: parent
                    text: "To enable video effects, turn on camera"
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                Column {
                    visible: win.cameraOn
                    y: 12; width: parent.width
                    Text {
                        x: 12; height: 18; verticalAlignment: Text.AlignVCenter
                        text: "Backgrounds"
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.text
                    }
                    Row {
                        x: 9; height: 53.2
                        Cell {
                            EffectTile {
                                x: 4; y: 4; width: 74; height: 42
                                kind: "none"; label: "None"; accessibleName: "No background effect"
                                selected: videoEffects.background === "none"
                                onPicked: videoEffects.setBackground("none")
                            }
                        }
                        Cell {
                            EffectTile {
                                x: 4; y: 4; width: 74; height: 42
                                kind: "blur"; label: videoEffects.blurLabel
                                blurKind: videoEffects.blurKind
                                selected: videoEffects.background === "blur"
                                onPicked: videoEffects.setBackground("blur")
                                onBlurPicked: kind => videoEffects.setBlur(kind)
                            }
                        }
                        Repeater {
                            model: videoEffects.catalog.slice(0, 4)
                            Cell {
                                required property var modelData
                                EffectTile {
                                    x: 4; y: 4; width: 74; height: 42
                                    thumb: parent.modelData.thumb; animated: parent.modelData.animated
                                    label: parent.modelData.name; accessibleName: parent.modelData.name + " background effect"
                                    selected: videoEffects.background === parent.modelData.id
                                    onPicked: videoEffects.setBackground(parent.modelData.id)
                                }
                            }
                        }
                    }
                    // Teams' Filters row: None and its quick-picker filters.
                    Text {
                        visible: videoEffects.quickFilters.length > 0
                        x: 12; height: visible ? 30 : 0; verticalAlignment: Text.AlignVCenter
                        text: "Filters"
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.text
                    }
                    Row {
                        visible: videoEffects.quickFilters.length > 0
                        x: 9; height: visible ? 50 : 0
                        Cell {
                            EffectTile {
                                x: 4; y: 4; width: 74; height: 42
                                kind: "none"; label: "None"; accessibleName: "No video effect selected"
                                selected: videoEffects.filter === ""
                                onPicked: videoEffects.setFilter("")
                            }
                        }
                        Repeater {
                            model: videoEffects.quickFilters
                            Cell {
                                required property var modelData
                                EffectTile {
                                    x: 4; y: 4; width: 74; height: 42
                                    thumb: parent.modelData.thumb
                                    label: parent.modelData.name; accessibleName: parent.modelData.name
                                    selected: videoEffects.filter === parent.modelData.id
                                    onPicked: videoEffects.setFilter(parent.modelData.id)
                                }
                            }
                        }
                    }
                    Item {
                        width: parent.width; height: 20.8
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "More video effects"
                            font.family: theme.font; font.pixelSize: 12
                            font.underline: mveHover.hovered
                            color: theme.brand
                            HoverHandler { id: mveHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: win.effectsPaneOpen = true }
                            Accessible.role: Accessible.Button
                            Accessible.name: "More video effects"
                        }
                    }
                }
            }
        }
        // Audio
        Column {
            id: audioColumn
            width: 449
            spacing: 6
            Rectangle {
                // Teams shows your devices only under Computer audio.
                width: parent.width; height: win.audio === "computer" ? 189 : win.otherCardHeight; radius: 4
                clip: true
                color: theme.surface; border.color: theme.dividerSoft
                // High contrast: the chosen option's band is #1AEBFF (Teams).
                Rectangle {
                    visible: theme.highContrast && win.audio === "computer"
                    width: parent.width; height: 54; topLeftRadius: 4; topRightRadius: 4
                    color: theme.hcHighlight
                }
                Radio {
                    x: 16; y: 18; on: win.audio === "computer"; label: "Computer audio"
                    highlighted: win.audio === "computer"; unusable: win.lobby
                    opacity: win.lobby && !theme.highContrast ? 0.45 : 1
                    TapHandler { enabled: !win.lobby; onTapped: win.audio = "computer" }
                }
                Rectangle { y: 54; width: parent.width; height: 1; color: theme.dividerSoft }
                Rectangle { y: 55; width: parent.width; height: parent.height - 56; color: theme.pane }
                Row {
                    x: 18; y: 74; spacing: 12
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: win.micOn ? "mic-24" : "mic-off-24"; size: 20; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 300; elide: Text.ElideRight; text: win.mic; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
                Toggle {
                    anchors.right: parent.right; anchors.rightMargin: 18; y: 76
                    on: win.micOn
                    onToggled: v => win.micOn = v
                    Accessible.name: "Microphone"
                }
                Row {
                    x: 18; y: 112; spacing: 12
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 20; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 260; elide: Text.ElideRight; text: win.speaker; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
            }
            // Teams' Phone audio (measured in Teams on the web, 2026-11-16):
            // offered when the meeting has dial-in (Audio Conferencing);
            // selected, its header fills the column as Room audio's does,
            // over "We'll give you a number to call after you join, or we
            // can call you." (14/20 #616161, padding 16 18, on #FAFAFA,
            // 89.3 tall). Disabled: "You don't have access to dial-in
            // information for this meeting".
            Rectangle {
                id: phoneCard
                readonly property bool selected: win.audio === "phone"
                readonly property bool usable: win.phoneAvailable && !win.lobby
                width: 449; radius: 4
                height: selected ? phoneHeader.height + 89.3 : win.otherCardHeight
                color: theme.highContrast && selected ? theme.hcHighlight : theme.surface
                border.color: theme.dividerSoft; border.width: 0.67
                Item {
                    id: phoneHeader
                    width: parent.width
                    height: phoneCard.selected ? Math.max(44.7, 330.2 - 3 * win.otherCardHeight - 3 * audioColumn.spacing - 89.3) : parent.height
                    Radio {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        on: phoneCard.selected; label: "Phone audio"
                        highlighted: phoneCard.selected; unusable: !phoneCard.usable
                        opacity: phoneCard.usable || theme.highContrast ? 1 : 0.45
                    }
                    HoverHandler { id: phoneHover; cursorShape: phoneCard.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: phoneCard.usable; onTapped: win.audio = "phone" }
                    QC.ToolTip.visible: phoneHover.hovered && !phoneCard.usable && win.phoneChecked
                    QC.ToolTip.delay: 500
                    QC.ToolTip.text: "You don't have access to dial-in information for this meeting"
                }
                Rectangle {
                    visible: phoneCard.selected
                    x: 0.67; y: phoneHeader.height; width: parent.width - 1.33; height: 0.67; color: theme.dividerSoft
                }
                Rectangle {
                    visible: phoneCard.selected
                    x: 0.67; y: phoneHeader.height + 0.67; width: parent.width - 1.33; height: 88.6
                    bottomLeftRadius: 4; bottomRightRadius: 4
                    color: theme.quoteFill
                    Text {
                        x: 18; width: parent.width - 36
                        anchors.verticalCenter: parent.verticalCenter
                        text: "We'll give you a number to call after you join, or we can call you."
                        wrapMode: Text.Wrap
                        font.family: theme.font; font.pixelSize: theme.base
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                }
                Accessible.role: Accessible.RadioButton
                Accessible.name: "Phone audio"
                Accessible.description: !win.phoneChecked ? "Checking for dial-in info…"
                    : win.phoneAvailable ? "Dial in from any phone, or we'll call you."
                    : "You don't have access to dial-in information for this meeting"
                Accessible.checked: selected
            }
            // Teams' Room audio (measured on winpc 2026-11-15): selected, its
            // header fills the column (178.7 with the 89.2 pane) over Teams'
            // room picker. A connected room device (a USB speakerphone) is
            // listed under "Connected room devices"; one Teams knows is
            // picked for you ("meeting room mode") or only suggested.
            Rectangle {
                id: roomCard
                readonly property bool selected: win.audio === "room"
                width: 449; radius: 4
                height: selected ? roomHeader.height + 89.2 : win.otherCardHeight
                color: theme.surface; border.color: theme.dividerSoft; border.width: 0.67
                Item {
                    id: roomHeader
                    width: parent.width
                    height: roomCard.selected ? Math.max(44.7, 330.2 - 3 * win.otherCardHeight - 3 * audioColumn.spacing - 89.2) : parent.height
                    Radio {
                        id: roomRadio
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        on: roomCard.selected; label: ""
                        opacity: win.lobby ? 0.45 : 1
                    }
                    Column {
                        x: 48; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 48 - 20
                        Item {
                            width: parent.width; height: 20
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Room audio"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                            // Teams' "(suggested)" tag, at the title row's end.
                            Text {
                                visible: win.roomSuggested
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: "(suggested)"
                                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
                            }
                        }
                        Text {
                            visible: roomCard.selected && win.roomSuggested
                            text: "We've detected a room device."
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                            color: theme.brandForeground1
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: !win.lobby; onTapped: win.audio = "room" }
                }
                Rectangle {
                    visible: roomCard.selected
                    x: 0.67; y: roomHeader.height; width: parent.width - 1.33; height: 0.67; color: theme.dividerSoft
                }
                Rectangle {
                    visible: roomCard.selected
                    x: 0.67; y: roomHeader.height + 0.67; width: parent.width - 1.33; height: 88.5
                    color: theme.pane
                    RoomPicker { x: 32.5 - 0.67; y: 16.6 - 0.67 }
                    // Teams' line under the picker: what Room audio does once
                    // a room is picked; else that OST finds no rooms nearby
                    // (Teams' text where automatic room discovery is missing).
                    Row {
                        x: 40.7 - 0.67; y: 48 - 0.67; spacing: 8
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: win.room ? "info-20-filled" : "bluetooth-20"; size: 14; color: theme.text }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.room ? "We'll add the room's audio system to the meeting after you join." : "Automatic room discovery isn't available on your device yet."
                            font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary
                        }
                        Accessible.role: Accessible.AlertMessage
                    }
                }
                Accessible.role: Accessible.RadioButton
                Accessible.name: "Room audio" + (win.roomSuggested ? " (suggested)" : "")
                Accessible.checked: selected
            }
            OptionCard { key: "none"; label: "Don't use audio"; usable: true }
        }
    }

    Row {
        x: panels.x + panels.width / 2 + panels.width * win.fit / 2 - width
        // Under the audio choices (the effects picker may reach lower).
        y: panels.y + Math.max(329, audioColumn.height) * win.fit + 24
        spacing: 8
        Rectangle {
            id: hcFill2
            width: 96; height: 32; radius: theme.radius
            color: cxh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
            HoverHandler { id: cxh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.cancel() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            id: hcFill3
            width: 96; height: 32; radius: theme.radius
            // Disabled in the lobby (Fluent's disabled primary button).
            color: !win.canJoin ? theme.pick("#F0F0F0", "#141414", "#000000") : jnh.hovered ? theme.brandHover : theme.brandFill
            border.color: !win.canJoin ? theme.pick("#E0E0E0", "#424242", "#FFFFFF") : "transparent"
            Text { anchors.centerIn: parent; text: "Join now"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, !win.canJoin ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : "white") }
            HoverHandler { id: jnh; cursorShape: win.canJoin ? Qt.PointingHandCursor : Qt.ArrowCursor }
            // Room audio waits for a room (Teams disables Join until one is
            // picked); a connected room device joins with its own audio.
            // Phone audio joins without the computer's audio (Teams'
            // isPSTN), then offers Call me or the dial-in numbers. Teams
            // keeps the choice, except Room audio and Don't use audio.
            TapHandler {
                enabled: win.canJoin
                onTapped: {
                    if (win.audio === "computer" || win.audio === "phone") backend.setSetting("prejoinAudio", win.audio)
                    win.close()
                    const computer = win.audio !== "none" && win.audio !== "phone"
                    win.join(computer && win.micOn, computer, win.cameraOn)
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Join now"
        }
        Rectangle {
            id: hcFill4
            visible: win.lobby && win.lobbyMessages.length > 0
            width: lcRow.implicitWidth + 24; height: 32; radius: theme.radius
            color: lch.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
            Row {
                id: lcRow
                anchors.centerIn: parent
                spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: lch.hovered ? "chat-20-filled" : "chat-20"; size: 20; color: theme.onFill(hcFill4, theme.text) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Lobby chat"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.text) }
            }
            HoverHandler { id: lch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.lobbyPaneOpen = !win.lobbyPaneOpen }
            Accessible.role: Accessible.Button
            Accessible.name: "Lobby chat"
        }
    }

    // An audio choice without a body (Phone audio, Don't use audio).
    component OptionCard: Rectangle {
        id: oc
        property string key
        property string label
        property bool usable: true
        width: 449; height: win.otherCardHeight; radius: 4
        color: theme.highContrast && win.audio === oc.key ? theme.hcHighlight : theme.surface; border.color: theme.dividerSoft; border.width: 0.67
        Radio {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            on: win.audio === oc.key; label: oc.label
            highlighted: win.audio === oc.key; unusable: !oc.usable || win.lobby
            opacity: oc.usable && !win.lobby || theme.highContrast ? 1 : 0.45
        }
        HoverHandler { cursorShape: oc.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: oc.usable && !win.lobby; onTapped: win.audio = oc.key }
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: win.audio === key
    }

    // Teams' room picker (room-search-dropdown, measured): an editable
    // 383.8 x 30.7 combobox, "Search for a room", its listbox (radius 4,
    // shadow16, padding 4; options 32 tall 2 apart, the check 6 in and the
    // text at 28). Sections are greyed semibold headers: "Connected room
    // devices" with each device (Teams' USB plug, 20), then "Other
    // Suggestions" (Teams' tenant rooms; "Unable to find any rooms" when
    // there are none). Typing narrows the list.
    component RoomPicker: Item {
        id: rp
        width: 383.8; height: 30.7
        readonly property string query: field.text === (win.room ? win.room.label : "") ? "" : field.text.trim().toLowerCase()
        readonly property var items: {
            const out = []
            const devices = (win.rooms.devices || []).filter(d => !rp.query || d.label.toLowerCase().indexOf(rp.query) >= 0)
            if (devices.length) {
                out.push({ header: "Connected room devices", disabled: true })
                for (const d of devices) out.push({ header: d.label, device: d })
            }
            out.push({ header: "Other Suggestions", disabled: true })
            out.push({ header: "Unable to find any rooms", disabled: true })
            return out
        }
        Connections {
            target: win
            function onRoomChanged() { field.text = win.room ? win.room.label : "" }
        }
        Component.onCompleted: field.text = win.room ? win.room.label : ""
        Connections { target: win; function onRoomPickerOpenForTest() { roomList.open() } }
        Rectangle {
            anchors.fill: parent; radius: 4
            color: theme.surface
            border.color: fieldHover.hovered ? theme.strokeHover : theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: field.activeFocus || roomList.opened ? 2 : 0.67; color: field.activeFocus || roomList.opened ? theme.brand : theme.textSecondary }
            HoverHandler { id: fieldHover }
        }
        TextInput {
            id: field
            x: 12; width: parent.width - 12 - (clearButton.visible ? 52 : 32)
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            selectByMouse: true
            enabled: !win.lobby
            onTextEdited: { if (!roomList.opened) roomList.open() }
            Text {
                visible: !field.text
                text: "Search for a room"
                font: field.font; color: theme.textSecondary
            }
            Accessible.role: Accessible.ComboBox
            Accessible.name: "Search for a room"
        }
        // Fluent's clear button once a room is chosen.
        FluentIcon {
            id: clearButton
            visible: !!win.room && !win.lobby
            anchors.right: chevron.left; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
            name: "dismiss-20"; size: 16; color: theme.textSecondary
            TapHandler { onTapped: { win.room = null; field.text = "" } }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear selection"
        }
        FluentIcon {
            id: chevron
            anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down-20"; size: 20; color: theme.textSecondary
            TapHandler { enabled: !win.lobby; onTapped: roomList.opened ? roomList.close() : roomList.open() }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            Accessible.role: Accessible.Button
            Accessible.name: "Open"
        }
        QC.Popup {
            id: roomList
            y: rp.height + 2; width: rp.width
            padding: 4
            height: roomView.contentHeight + 8
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            contentItem: ListView {
                id: roomView
                interactive: false
                spacing: 2
                model: rp.items
                delegate: Rectangle {
                    id: ro
                    required property var modelData
                    readonly property bool usable: !modelData.disabled
                    readonly property bool chosen: !!modelData.device && !!win.room && win.room.speaker === modelData.device.speaker
                    width: roomView.width; height: 32; radius: 4
                    color: roHover.hovered && usable ? theme.menuHover : "transparent"
                    FluentIcon { visible: ro.chosen; x: 6; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.onFill(ro, theme.text) }
                    Row {
                        x: 28; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        FluentIcon { visible: !!ro.modelData.device; anchors.verticalCenter: parent.verticalCenter; name: "usb-plug-20"; size: 20; color: theme.onFill(ro, theme.text) }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ro.modelData.header
                            font.family: theme.font; font.pixelSize: 14
                            font.weight: ro.usable ? Font.Normal : Font.DemiBold
                            color: theme.onFill(ro, ro.usable ? theme.text : theme.disabled)
                        }
                    }
                    HoverHandler { id: roHover; cursorShape: ro.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: ro.usable; onTapped: { win.pickRoom(ro.modelData.device); roomList.close() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: ro.modelData.header
                }
            }
        }
    }

    // Fluent switch: a 40 x 20 pill.
    component Toggle: Rectangle {
        id: tg
        property bool on
        property bool usable: true
        signal toggled(bool on)
        width: 40; height: 20; radius: 10
        color: on ? theme.checkedFill : "transparent"
        border.color: on ? "transparent" : theme.textStrong
        Rectangle {
            width: 14; height: 14; radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: tg.on ? parent.width - width - 3 : 3
            color: tg.on ? theme.hc("white", "#000000") : theme.textStrong
        }
        TapHandler { enabled: tg.usable; onTapped: tg.toggled(!tg.on) }
        HoverHandler { cursorShape: tg.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
    }

    component Radio: Row {
        id: radio
        property bool on
        property string label
        /// High contrast: on Teams' #1AEBFF selected card (black ring, dot
        /// and label), or unavailable (#3FF23F).
        property bool highlighted: false
        property bool unusable: false
        readonly property string ink: !theme.highContrast ? "" : highlighted ? "#000000" : unusable ? "#3FF23F" : "#FFFFFF"
        spacing: 12
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: "transparent"; border.color: radio.ink.length ? radio.ink : parent.on ? theme.brand : theme.textStrong; border.width: 1
            Rectangle { visible: parent.parent.on; anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: radio.ink.length ? radio.ink : theme.brand }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: radio.ink.length ? radio.ink : theme.text }
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: on
    }
    // Teams' "More video effects" pane before joining.
    VideoEffectsPane {
        visible: win.effectsPaneOpen && win.lobbyPaneW === 0
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 360
        inCall: false
        cameraOn: win.cameraOn
        onClosed: win.effectsPaneOpen = false
        onGreenScreenSettings: win.greenScreenSettings()
    }
    /// The effects pane's "Green screen settings".
    signal greenScreenSettings()
    component Cell: Item { width: 82; height: 50 }
    // The Lobby pane.
    Rectangle {
        visible: win.lobbyPaneW > 0
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 360
        color: theme.surface
        Item {
            width: parent.width; height: 58
            Text {
                x: 20; anchors.verticalCenter: parent.verticalCenter
                text: "Lobby"
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Rectangle {
                id: hcFill5
                x: parent.width - 16 - 32; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 30; radius: 4
                color: lpClose.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill5, theme.textStrong) }
                HoverHandler { id: lpClose; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.lobbyPaneOpen = false }
                Accessible.role: Accessible.Button
                Accessible.name: "Close chat pane"
            }
        }
        Rectangle {
            id: lpBanner
            y: 61; width: parent.width; height: lpBannerText.implicitHeight + 10 + 1.33
            color: theme.pick("#F0F0F0", "#2E2E2E", "#000000")
            Rectangle { width: parent.width; height: 0.67; color: theme.divider }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
            Text {
                id: lpBannerText
                x: 16.7; y: 5.67; width: parent.width - 33.3
                wrapMode: Text.Wrap
                text: "Only organizers and people in the lobby can view these messages."
                font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                color: theme.textStrong
            }
        }
        Conversation {
            anchors { top: lpBanner.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            pane: true; popout: true
            readOnly: true
            noAvatars: true
            chatId: backend.callLobbyThread
            chatName: "Lobby"
            isGroup: true
            messages: win.lobbyMessages
            paneTitle: ""
            hideHeader: true
        }
    }
    RetryScreen {
        anchors.fill: parent
        z: 10
        visible: win.retryReason !== ""
        reason: win.retryReason
        onRetry: { win.retryReason = ""; win.rejoin() }
        onDismiss: { win.retryReason = ""; win.close() }
    }
}
