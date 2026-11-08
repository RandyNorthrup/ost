import QtQuick
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
    /// The compact view's tiles: name tags without the name, 4 px in.
    property bool compact: false
    /// Optimize for room shows the videos on the shared display only;
    /// "Turn off other videos" stops theirs.
    property bool forRoom: false
    readonly property string videoKey: !call || (call.roomMode && !forRoom) ? ""
        : self ? (call.cameraOn ? "self" : "")
        : call.incomingVideoOff ? "" : (call.videoKeys[person.id] || "")
    readonly property int handAt: call ? call.hands.indexOf(person.id) : -1
    readonly property string reaction: { if (!call) return ""; call.reactions; return call.reactionOf(person.id || "") }

    Rectangle {
        id: surface
        anchors { fill: parent; margins: 2 }
        radius: 6
        color: "#F5F5F5"
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
            anchors.centerIn: parent
            size: Math.round(parent.height * 0.4975)
            name: mt.person.name || ""
            photoId: mt.self ? "me" : (mt.person.id || "")
            visible: !video.visible
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
        // Speaking: Teams' voice-level outline.
        Rectangle {
            anchors.fill: parent
            visible: !mt.self && !!mt.call && mt.call.speakingIds.indexOf(mt.person.id) >= 0
            radius: 6; color: "transparent"
            border.width: 4; border.color: "#5B5FC7"
            Rectangle {
                anchors { fill: parent; margins: 4 }
                radius: 3; color: "transparent"
                border.width: 0.67; border.color: "#F5F5F5"
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
            visible: mt.handAt >= 0
            anchors { left: parent.left; top: parent.top; margins: 10 }
            width: handRow.implicitWidth + 12; height: 28; radius: 14
            color: "white"; border.color: theme.dividerSoft
            Row {
                id: handRow
                anchors.centerIn: parent; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: mt.handAt + 1; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
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
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: mt.compact ? 4 : 8; bottomMargin: mt.compact ? 4 : 8 }
            height: 24; radius: 4
            width: tagRow.implicitWidth + 12
            color: Qt.rgba(0, 0, 0, 0.5)
            Row {
                id: tagRow
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                readonly property bool micOff: mt.self ? (!!mt.call && (mt.call.muted || !mt.call.hasAudio)) : !!mt.person.muted
                Text {
                    visible: !mt.compact
                    anchors.verticalCenter: parent.verticalCenter
                    height: 16; verticalAlignment: Text.AlignVCenter
                    text: mt.person.name || ""; color: "white"
                    font.family: theme.font; font.pixelSize: 12
                }
                Item { visible: !!mt.person.guest; width: 4; height: 1 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!mt.person.guest
                    name: "person-unverified-16-filled"; size: 16; color: "white"
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Unverified"
                }
                // Compact (no name): Teams' measured gaps are 8 after a
                // guest's glyph and 6 before your own mic.
                Item { visible: tagRow.micOff && (!mt.compact || !!mt.person.guest || mt.self); width: mt.self ? (mt.compact ? 6 : 14) : 8; height: 1 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tagRow.micOff
                    name: "mic-off-20-filled"; size: 16; color: "white"
                }
            }
        }
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: person.name || ""
}
