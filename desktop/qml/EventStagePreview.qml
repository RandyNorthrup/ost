import QtQuick
import QtMultimedia

// The Events form's stage preview (Set up experience and options, Teams'
// event-stage-preview mini window; measured in Teams desktop 26304 on
// winpc 2026-11-18, CSS px, at 618 wide):
// - the meeting window 598 x 374 at 10, 10: #F5F5F5, a #E0E0E0 hairline,
//   radius 8; the title bar 18 tall ("Van Arsdel Product Demo", 7/600
//   #424242); the command bar 41 tall, white: the shield, the LIVE pill
//   (#D13438, white 6/700) and the running time (8, #242424) on the left;
//   Chat, Q&A (when allowed), Raise, React, a divider, Camera and Mic
//   (brand when attendees may use them, with a chevron) in the middle,
//   their 14 px glyphs over 10 px labels; Leave (red glyph) on the right;
// - the stage: nine 148 x 100 video tiles (#EBEBEB, radius 4, 3 apart; the
//   active speaker's with a 2 px brand border; first names on a dark tag,
//   6 px) playing Teams' sample participant videos, and the chat side
//   panel (140 wide, white, "Chat" 6/600, "Type a message") when chat is on
//   (Q&A's panel when only Q&A is);
// - "Approximate preview. Actual event experience may vary based on your
//   set up." (12, #616161) under it.
// The videos are Teams' own (evergreen-assets/virtual-events/
// event-stage-preview/participant-videos), muted and looping.
Item {
    id: root
    width: 618; height: 418
    property bool mic: true
    property bool camera: true
    property bool react: true
    property bool chat: true
    property bool qna: true
    /// A streaming town hall: attendees only watch.
    property bool broadcast: false
    property int elapsed: 22 * 60 + 6
    readonly property string base: "https://teams.public.onecdn.static.microsoft/evergreen-assets/virtual-events/event-stage-preview/participant-videos/"
    readonly property var people: [["Allan", "participant-active-speaker"], ["Daisy", "participant-01"], ["Elvia", "participant-02"],
                                   ["Henry", "participant-03"], ["Robin", "participant-04"], ["Cameron", "participant-05"],
                                   ["Kat", "participant-06"], ["Tim", "participant-07"], ["Lydia", "participant-09"]]
    readonly property string sidebar: chat ? "Chat" : qna ? "Q&A" : ""
    Timer { interval: 1000; repeat: true; running: root.visible; onTriggered: root.elapsed++ }
    function clock(s) { const m = Math.floor(s / 60), r = s % 60; return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r }

    Rectangle {
        anchors.fill: parent; radius: 12
        color: theme.pick("#F0F0F0", "#1F1F1F", "#000000")
    }
    Rectangle {
        id: win
        x: 10; y: 10; width: 598; height: 374; radius: 8; clip: true
        color: "#F5F5F5"; border.color: "#E0E0E0"; border.width: 1
        Text { x: 1; y: 1; width: parent.width - 2; height: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
               text: qsTr("Van Arsdel Product Demo"); font.family: theme.font; font.pixelSize: 7; font.weight: Font.DemiBold; color: "#424242" }
        Rectangle {
            x: 1; y: 19; width: parent.width - 2; height: 41; color: "#FFFFFF"
            FluentIcon { x: 6; y: 14; name: "shield-20"; size: 12; color: "#616161" }
            Rectangle { x: 21; y: 14; width: 21; height: 12; radius: 6; color: "#D13438"
                Text { anchors.centerIn: parent; text: qsTr("LIVE"); font.family: theme.font; font.pixelSize: 6; font.weight: Font.Bold; color: "white" } }
            Text { x: 45; y: 10; height: 20; verticalAlignment: Text.AlignVCenter; text: root.clock(root.elapsed); font.family: theme.font; font.pixelSize: 8; color: "#242424" }
            Row {
                x: 189; y: 4; spacing: 0
                Repeater {
                    model: [["chat-20", qsTr("Chat"), !root.chat, false, root.sidebar === "Chat", true],
                            ["chat-bubbles-question-20", qsTr("Q&A"), false, false, root.sidebar === "Q&A", root.qna],
                            ["hand", qsTr("Raise"), true, false, false, true],
                            ["emoji-20", qsTr("React"), !root.react, false, false, true]]
                    Item {
                        required property var modelData
                        visible: modelData[5]; width: visible ? 38 : 0; height: 32
                        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 0; name: parent.modelData[0]; size: 14; color: parent.modelData[2] ? "#BDBDBD" : "#242424" }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 15; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 10; color: parent.modelData[2] ? "#BDBDBD" : "#424242"; font.underline: parent.modelData[4] }
                    }
                }
                Item { width: 7; height: 32; Rectangle { x: 3; y: 9; width: 1; height: 14; color: "#E0E0E0" } }
                Repeater {
                    model: [[root.camera && !root.broadcast ? "video-20" : "video-off-20", qsTr("Camera"), root.camera && !root.broadcast],
                            [root.mic && !root.broadcast ? "mic-20" : "mic-off-20", qsTr("Mic"), root.mic && !root.broadcast]]
                    Item {
                        required property var modelData
                        width: 40; height: 32
                        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 0
                            FluentIcon { name: parent.parent.modelData[0]; size: 14; color: parent.parent.modelData[2] ? "#5B5FC7" : "#BDBDBD" }
                            FluentIcon { y: 2; name: "chevron-down-12"; size: 8; color: parent.parent.modelData[2] ? "#5B5FC7" : "#BDBDBD" } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 15; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 10; color: "#424242" }
                    }
                }
            }
            Item {
                x: parent.width - 32; y: 4; width: 30; height: 32
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "call-end-filled"; size: 14; color: "#BC2F32" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 15; text: qsTr("Leave"); font.family: theme.font; font.pixelSize: 10; color: "#242424" }
            }
        }
        // The stage.
        Grid {
            x: 15; y: 73; columns: 3; spacing: 2.5
            readonly property real tileW: root.sidebar ? 148 : 190
            readonly property real tileH: root.sidebar ? 100 : 100
            Repeater {
                model: root.people
                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    width: parent.tileW; height: parent.tileH; radius: 4; clip: true
                    color: "#EBEBEB"
                    border.width: index === 0 ? 2 : 0; border.color: "#5B5FC7"
                    MediaPlayer {
                        id: player
                        source: root.visible ? root.base + tile.modelData[1] + ".mp4" : ""
                        loops: MediaPlayer.Infinite
                        videoOutput: vo
                        audioOutput: null
                        onSourceChanged: if (source != "") play()
                    }
                    VideoOutput { id: vo; anchors.fill: parent; anchors.margins: tile.border.width; fillMode: VideoOutput.PreserveAspectCrop }
                    Rectangle {
                        x: 5; y: parent.height - 12; height: 8; radius: 2; width: nameText.implicitWidth + 6
                        color: Qt.rgba(0, 0, 0, 0.4)
                        Text { id: nameText; anchors.centerIn: parent; text: tile.modelData[0]; font.family: theme.font; font.pixelSize: 6; color: "white" }
                    }
                }
            }
        }
        Rectangle {
            visible: root.sidebar !== ""
            x: 468; y: 69; width: 140; height: 314; color: "#FFFFFF"
            Text { x: 6; width: parent.width - 6; height: 17; verticalAlignment: Text.AlignVCenter; text: root.sidebar === "Chat" ? qsTr("Chat") : root.sidebar === "Q&A" ? qsTr("Q&A") : root.sidebar; font.family: theme.font; font.pixelSize: 6; font.weight: Font.DemiBold; color: "#242424" }
            Rectangle { x: 7; y: parent.height - 30; width: 126; height: 26; radius: 2; color: "transparent"; border.color: "#E0E0E0"; border.width: 1
                Text { x: 5; anchors.verticalCenter: parent.verticalCenter; text: root.sidebar === "Q&A" ? qsTr("Ask a question") : qsTr("Type a message"); font.family: theme.font; font.pixelSize: 5; color: "#616161" } }
        }
    }
    Text {
        x: 10; y: 392; width: 598; height: 16; horizontalAlignment: Text.AlignHCenter
        text: qsTr("Approximate preview. Actual event experience may vary based on your set up.")
        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
    }
}
