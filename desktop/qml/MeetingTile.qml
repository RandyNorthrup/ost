import QtQuick
import QtQuick.Controls
import com.ost.desktop

// One person's meeting tile, as Teams draws it: a 2 px inset, rounded
// surface; their camera cropped to fill it (yours mirrored), else their
// picture; the name tag; and the outline while they speak.
Item {
    id: mt
    /// The call window (its roster state: videos, hands, speaker, you).
    property var call
    property var person: ({})
    readonly property bool self: !!person.self
    /// A bot in the call (Teams' isBot: the id starts with "28:").
    readonly property bool bot: !self && String(person.id || "").indexOf("28:") === 0
    /// The compact view's tiles: name tags without the name, 4 px in.
    property bool compact: false
    /// Your tile floating over the stage (two people): the name tag
    /// without your name, 8 px in.
    property bool overlay: false
    readonly property bool nameless: compact || overlay
    /// Optimize for room shows the videos on the shared display only;
    /// "Turn off other videos" stops theirs.
    property bool forRoom: false
    readonly property string videoKey: !call || (call.roomMode && !forRoom) ? ""
        : self ? (call.cameraOn ? "self" : "")
        : call.incomingVideoOff ? "" : (call.videoKeys[person.id] || "")
    readonly property int handAt: call ? call.hands.indexOf(person.id) : -1
    /// Sign language mode: they are actively signing (their detection
    /// events), and Teams' badge for it (with a tethered interpreter).
    readonly property bool signing: !!call && call.isSigning(self ? call.selfId : person.id)
    readonly property var tethered: !call || !signing ? [] : call.tetheredOf(self ? call.selfEntry : person)
    readonly property string reaction: { if (!call) return ""; call.reactions; return call.reactionOf(person.id || "") }

    Rectangle {
        id: surface
        anchors { fill: parent; margins: 2 }
        radius: 6
        color: theme.hc("#F5F5F5", "#000000")
        border.width: 0.67; border.color: Qt.rgba(0, 0, 0, 0.1)
        // Teams' camera-off background (#F5F5F5 under four radial
        // gradients, each an ellipse to the farthest corner, CSS-style).
        Canvas {
            id: backdrop
            anchors.fill: parent
            visible: !video.visible
            readonly property var spec: mt.call && mt.person.id !== undefined ? mt.call.tileBackground(mt.person.id || "me") : []
            onSpecChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = width, h = height
                // Round the corners as the surface does.
                ctx.beginPath(); ctx.roundedRect(0, 0, w, h, 6, 6); ctx.clip()
                for (const g of spec) {
                    const cx = w * g.x / 100, cy = h * g.y / 100
                    const rx = Math.max(Math.abs(cx), Math.abs(w - cx)) * Math.SQRT2
                    const ry = Math.max(Math.abs(cy), Math.abs(h - cy)) * Math.SQRT2
                    if (rx <= 0 || ry <= 0) continue
                    ctx.save()
                    ctx.translate(cx, cy)
                    ctx.scale(1, ry / rx)
                    const grad = ctx.createRadialGradient(0, 0, 0, 0, 0, rx)
                    grad.addColorStop(0, g.color)
                    grad.addColorStop(Math.min(1, g.stop / 100), "transparent")
                    ctx.fillStyle = grad
                    ctx.fillRect(-cx, -cy * rx / ry, w, h * rx / ry)
                    ctx.restore()
                }
            }
        }
        Avatar {
            ring: false
            anchors.centerIn: parent
            // Teams' tile avatar: about half the tile's height, at most
            // 200 (a whole-stage tile, measured on winpc 2026-11-10).
            size: Math.min(200, Math.round(parent.height * 0.4975))
            name: mt.person.name || ""
            photoId: mt.self ? "me" : (mt.person.id || "")
            visible: !video.visible && !mt.bot
        }
        // A bot (a 28: participant: the Echo bot in the test call) gets
        // Teams' agent avatar instead, at the same size.
        BotAvatar {
            anchors.centerIn: parent
            size: Math.min(200, Math.round(parent.height * 0.4975))
            visible: !video.visible && mt.bot
        }
        VideoFrame {
            id: video
            source: mt.videoKey
            anchors.fill: parent
            radius: 6
            visible: source !== "" && hasFrame
            transform: Scale { origin.x: video.width / 2; xScale: mt.self ? -1 : 1 }
            Timer {
                interval: 33; repeat: true
                running: mt.visible && video.source !== ""
                onTriggered: video.refresh()
            }
        }
        // Teams' actively signing badge (293537; on video tiles only):
        // the 5-bar waveform in a pill at the tile's top-left indicator
        // slot (10, 10): 3.5 padding, NeutralBackground2 with a 1 px
        // NeutralStroke1 border, radius 20, the bars in brand. Its tooltip
        // names the voice interpreter.
        Rectangle {
            id: signingBadge
            visible: mt.signing && mt.tethered.length > 0 && video.visible
            x: 10; y: 10; z: 2
            width: 18 + 7 + 2; height: 18 + 7 + 2; radius: 20
            color: theme.quoteFill
            border.width: 1; border.color: theme.stroke
            Row {
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: [1.0, 1.4, 1.8, 1.4, 1.0]
                    Rectangle {
                        required property real modelData
                        width: 2; height: 10; radius: 1.5
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        color: theme.brand
                        // Teams' keyframes: scaleY .5 (opacity .8) to the
                        // bar's peak (opacity 1) and back, each bar 0.30 to
                        // 0.55 s, ease-in-out, forever.
                        property real level: 0.5
                        opacity: 0.8 + 0.2 * (level - 0.5) / Math.max(0.01, modelData - 0.5)
                        transform: Scale { origin.y: 5; yScale: level }
                        readonly property int half: Math.round((300 + Math.random() * 250) / 2)
                        SequentialAnimation on level {
                            running: signingBadge.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: modelData; duration: half; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 0.5; duration: half; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }
            HoverHandler { id: badgeHover }
            ToolTip.visible: badgeHover.hovered
            ToolTip.text: mt.call ? mt.call.signingTooltip(mt.tethered) : ""
            Accessible.role: Accessible.Graphic
            Accessible.name: ToolTip.text
        }
        // Speaking: Teams' voice-level outline; a signer actively signing
        // gets it too (Teams' isActivelySigning; on your own tile,
        // signingParticipantStreamOutline, with your video on).
        Rectangle {
            anchors.fill: parent
            visible: !!mt.call && (!mt.self && mt.call.speakingIds.indexOf(mt.person.id) >= 0
                                   || mt.signing && (!mt.self || video.visible))
            radius: 6; color: "transparent"
            border.width: 4; border.color: theme.hc("#5B5FC7", "#FFFFFF")
            Rectangle {
                anchors { fill: parent; margins: 4 }
                radius: 3; color: "transparent"
                border.width: 0.67; border.color: theme.hc("#F5F5F5", "#FFFFFF")
            }
        }
        // A raised hand: Teams' gold outline and "1 ✋" badge.
        Rectangle {
            anchors.fill: parent
            visible: mt.handAt >= 0
            radius: 6; color: "transparent"
            border.width: 3; border.color: theme.handRaised
        }
        Rectangle {
            id: hcFill1
            visible: mt.handAt >= 0
            anchors { left: parent.left; top: parent.top; margins: 10 }
            width: handRow.implicitWidth + 12; height: 28; radius: 14
            color: theme.hc("white", "#000000"); border.color: theme.dividerSoft
            Row {
                id: handRow
                anchors.centerIn: parent; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: mt.handAt + 1; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.text) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u270B"; font.pixelSize: 16 }
            }
            Accessible.role: Accessible.StaticText
            Accessible.name: "Hand raised"
        }
        // A reaction: Teams' 84 px picture, centred, its top at the middle.
        Image {
            visible: mt.reaction.length > 0
            width: 84; height: 84
            x: (parent.width - width) / 2; y: parent.height / 2
            smooth: true
            source: mt.reaction && mt.call ? mt.call.reactionUrl(mt.reaction, true) : ""
            Accessible.role: Accessible.Graphic
            Accessible.name: mt.reaction
        }
        // Teams' name tag (participant-info-nametag): 24 tall, 50% black,
        // radius 4, padding 6, 8 px in from the corner. The name is 12 px
        // white; a guest's person-question glyph follows 4 px on; the
        // mic-off glyph (16 px, filled) 8 px on, after 6 more for you.
        Rectangle {
            id: hcFill2
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: mt.compact ? 4 : 8; bottomMargin: mt.compact ? 4 : 8 }
            height: 24; radius: 4
            width: tagRow.implicitWidth + 12
            color: Qt.rgba(0, 0, 0, 0.5)
            Row {
                id: tagRow
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                readonly property bool pinned: !!mt.call && !mt.self && !!mt.call.pinnedIds && mt.call.pinnedIds.indexOf(mt.person.id) >= 0
                readonly property bool micOff: mt.self ? (!!mt.call && (mt.call.muted || !mt.call.hasAudio)) : !!mt.person.muted
                // Your network strength (Teams' local-nsi): three 2 px bars
                // at 4/8/12 in an 18 px glyph, unlit ones at 30 %, then 3 px.
                Item {
                    id: nsi
                    visible: mt.self && !!mt.call && mt.call.nsiShown
                    width: 21; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property int lit: !mt.call ? 3 : mt.call.networkStrength === "Bad" ? 1 : mt.call.networkStrength === "Poor" ? 2 : 3
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            x: 4 + index * 4; y: 16 - height
                            width: 2; height: [4, 7, 10][index]; radius: 1
                            color: theme.hc("white", "#000000")
                            opacity: index < nsi.lit ? 1 : 0.3
                        }
                    }
                    HoverHandler {
                        onHoveredChanged: if (hovered) mt.call.showNetworkPopover(nsi); else mt.call.leaveNetworkPopover()
                    }
                    Accessible.role: Accessible.Graphic
                    Accessible.name: mt.call ? mt.call.networkHeading : ""
                }
                Text {
                    visible: !mt.nameless
                    anchors.verticalCenter: parent.verticalCenter
                    height: 16; verticalAlignment: Text.AlignVCenter
                    text: mt.person.name || ""; color: theme.onFill(hcFill2, "white")
                    font.family: theme.font; font.pixelSize: 12
                }
                // Sign language mode (Teams' tile icons, 119108 Fa, filled
                // at 16 px): a signer's HandMultipleStack ("sign-language-
                // icon", Teams' own glyph, when they share their status or
                // you're their interpreter) or an interpreter's
                // PersonSupport ("equitable-presence-interpreter-icon"),
                // for people in the mode.
                readonly property string signIcon: !mt.call || !mt.call.signMode || mt.self ? ""
                    : mt.call.signerShown(mt.person) ? "hand-multiple-stack-20-filled"
                    : mt.person.sign_role === "signLanguageInterpreter" ? "person-support-20-filled" : ""
                Item { visible: !!tagRow.signIcon; width: 4; height: 1 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!tagRow.signIcon
                    name: tagRow.signIcon; size: 16; color: theme.onFill(hcFill2, "white")
                    Accessible.role: Accessible.Graphic
                    Accessible.name: mt.person.sign_role === "dhhSigner" ? "Signer participant" : "Sign language interpreter participant"
                }
                Item { visible: !!mt.person.guest; width: 4; height: 1 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!mt.person.guest
                    name: "person-unverified-16-filled"; size: 16; color: theme.onFill(hcFill2, "white")
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Unverified"
                }
                // Compact (no name): Teams' measured gaps are 8 after a
                // guest's glyph and 6 before your own mic.
                Item { visible: tagRow.micOff && (!mt.nameless || !!mt.person.guest || mt.self); width: mt.self ? (mt.nameless ? 6 : 14) : 8; height: 1 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tagRow.micOff
                    name: "mic-off-20-filled"; size: 16; color: theme.onFill(hcFill2, "white")
                }
                // Pinned for you: Teams' 16 px pin, 6 on.
                Item { visible: tagRow.pinned; width: 6; height: 1 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tagRow.pinned
                    name: "pin-20"; size: 16; color: theme.onFill(hcFill2, "white")
                }
            }
        }
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: person.name || ""
}
