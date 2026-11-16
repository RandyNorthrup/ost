import QtQuick
import QtQuick.Controls.Basic

// Teams' test call results (the "Post EchoBot Calling Screen",
// post-echo-bot-screen bundle; measured on winpc 2026-11-16 after Settings
// ▸ Devices ▸ Make a test call). It replaces the call window's bar and
// stage once the test call ends:
// - a 500-wide list, centred, of Microphone, Speaker, Camera and Network:
//   each row 48 (padding 0 10) plus 16 under it and a #D1D1D1 hairline,
//   rows 15 apart; the device's filled glyph (20 px) at 10, "Microphone -
//   <device>" (14/20) at 40, then "Connected" or each problem (14 px, red
//   #BC2F32) under it; at the row's end (24 in, 8 down) a 14 px green
//   (#0E700E) check circle, or Teams' red warning triangle (#C4314B);
// - 30 under the list, Close and Show Device Settings (Fluent outlined
//   buttons, 30 apart, centred); the whole block centred in the window;
// - Show Device Settings opens Teams' Device settings pane (350.8 wide)
//   beside the list, or under it when the window is too narrow (the
//   region then scrolls); the button reads Hide Device Settings.
// Close closes the window.
Rectangle {
    id: root
    /// [{kind, title, problems}] (src/calling/echo_report.rs rows()).
    property var rows: []
    property bool showDevices: false
    signal closed()
    color: theme.pane
    Accessible.role: Accessible.Pane
    Accessible.name: "Post EchoBot Calling Screen"

    readonly property real listWidth: 500
    readonly property real paneWidth: 350.8
    // Side by side when both fit in the region (16 padding each side).
    readonly property bool besides: showDevices && width - 32 >= listWidth + paneWidth
    readonly property real blockHeight: list.height + 30 + 31.3

    function glyph(kind) {
        return { microphone: "echo-mic-speaking", speaker: "echo-speaker-20", camera: "echo-video-20", network: "echo-wifi-20" }[kind] || ""
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.showDevices && !root.besides ? Math.max(height, block.y + root.blockHeight + 0.7 + devicePane.height) : height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Item {
            id: block
            width: root.listWidth; height: root.blockHeight
            // Centred in what the pane leaves; at the top when the pane
            // wraps under it.
            x: 16 + ((root.besides ? root.width - 32 - root.paneWidth : root.width - 32) - width) / 2
            y: root.showDevices && !root.besides ? 0 : Math.max(16, (root.height - height) / 2)

            Column {
                id: list
                width: parent.width
                spacing: 15
                Repeater {
                    model: root.rows
                    delegate: Item {
                        id: row
                        required property var modelData
                        readonly property var problems: modelData.problems || []
                        width: list.width
                        height: Math.max(48, 24.7 + Math.max(1, problems.length) * 18.7 + 4.7) + 16 + 0.67 + 10
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.title + ", " + (problems.length ? problems.join(", ") : "Connected")
                        FluentIcon {
                            x: 10; y: 4.7; size: 20
                            name: root.glyph(row.modelData.kind)
                            color: theme.text
                        }
                        Text {
                            x: 40; y: 4.7; width: row.width - 40 - 44
                            text: row.modelData.title
                            elide: Text.ElideRight
                            font.family: theme.font; font.pixelSize: 14
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        Column {
                            x: 40; y: 24.7
                            Repeater {
                                model: row.problems.length ? row.problems : ["Connected"]
                                delegate: Text {
                                    required property string modelData
                                    height: 18.7
                                    text: modelData
                                    font.family: theme.font; font.pixelSize: 14
                                    color: row.problems.length ? theme.redForeground1 : theme.text
                                }
                            }
                        }
                        FluentIcon {
                            x: row.width - 24; y: 8; size: 14
                            name: row.problems.length ? "echo-error-16" : "echo-check-20"
                            color: row.problems.length ? theme.pick("#C4314B", "#E37D80", "#FFFFFF") : theme.pick("#0E700E", "#54B054", "#3FF23F")
                        }
                        // The row's hairline, 16 under its content.
                        Rectangle {
                            y: row.height - 10 - 0.67
                            width: row.width; height: 0.67
                            color: theme.stroke
                        }
                    }
                }
            }
            Row {
                y: list.height + 30
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 30
                SettingsParts.Button { label: "Close"; onClicked: root.closed() }
                SettingsParts.Button {
                    label: root.showDevices ? "Hide Device Settings" : "Show Device Settings"
                    onClicked: root.showDevices = !root.showDevices
                }
            }
        }

        // Teams' Device settings pane (calling-right-side-panel, 350.8
        // wide): beside the list at the region's end, or under it at its
        // start when there isn't room.
        TestCallDevices {
            id: devicePane
            visible: root.showDevices
            width: root.paneWidth
            x: root.besides ? root.width - 16 - width : 16
            y: root.besides ? 0 : block.y + root.blockHeight + 0.7
            height: root.besides ? root.height : implicitHeight
        }
    }
}
