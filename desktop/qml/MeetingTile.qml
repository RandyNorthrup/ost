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
    readonly property string videoKey: !call ? "" : self ? (call.cameraOn ? "self" : "") : (call.videoKeys[person.id] || "")
    readonly property int handAt: call ? call.hands.indexOf(person.id) : -1
    readonly property string reaction: { if (!call) return ""; call.reactions; return call.reactionOf(person.id || "") }

    Rectangle {
        id: surface
        anchors { fill: parent; margins: 2 }
        radius: 6
        color: "#F5F5F5"
        border.width: 0.67; border.color: Qt.rgba(0, 0, 0, 0.1)
        // Yours (camera off): the soft gradient Teams puts behind you.
        Rectangle {
            anchors.fill: parent
            visible: mt.self
            radius: 6
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#F6EEF2" }
                GradientStop { position: 1.0; color: "#EEF0F8" }
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
            visible: !mt.self && !!mt.call && mt.person.id === mt.call.speakerId
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
        // Teams' name tag: 24 tall, 50% black, 8 px in from the corner.
        Rectangle {
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 8 }
            height: 24; radius: 4
            width: tagRow.implicitWidth + 12
            color: Qt.rgba(0, 0, 0, 0.5)
            Row {
                id: tagRow
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: mt.person.name || ""; color: "white"; font.family: theme.font; font.pixelSize: 14 }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: mt.self ? (!!mt.call && (mt.call.muted || !mt.call.hasAudio)) : !!mt.person.server_muted
                    name: "mic-off-20"; size: 16; color: "white"
                }
            }
        }
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: person.name || ""
}
