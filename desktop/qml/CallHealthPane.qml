import QtQuick
import QtQuick.Controls.Basic

// Teams' Call health pane (More ▸ Settings ▸ Call health; measured on
// winpc 2026-11-09, behaviour from its calling bundles: scratchpad
// ch/spec.md):
// - Root: "Your call is receiving data. Most metrics refresh every 15
//   seconds." with Learn more, "Last updated at: h:mm:ss AM" (it moves
//   only when a value changed), then the Network, Audio, Video and Screen
//   Sharing cards (#F0F0F0; "Label: value" rows 14/20, 23 apart), each
//   with "View more … data" under it. A card whose media is off carries
//   an ⓘ saying how to get metrics.
// - A detail page per card: back, its title, then one tile per metric
//   (label 12/16 semibold with an ⓘ explaining it, the value 16/22).
// Values are "--" when there's nothing or the media is off.
Rectangle {
    id: root
    /// {values: {data-tid: {value, enabled}}} (backend.callHealthJson).
    property var health: ({})
    /// The page shown: "" (root) or a category.
    property string page: ""
    property string updatedAt: ""
    signal closed()
    signal refresh()
    color: theme.pane
    function pageForTest(p) { page = p }

    onHealthChanged: updatedAt = Qt.formatTime(new Date(), "h:mm:ss AP")
    onVisibleChanged: if (visible) { page = ""; refresh() }
    Timer { interval: 15000; repeat: true; running: root.visible; onTriggered: root.refresh() }

    function val(tid) {
        const v = health && health.values ? health.values[tid] : null
        return v && v.enabled && v.value ? v.value : "--"
    }
    function enabled(tid) {
        const v = health && health.values ? health.values[tid] : null
        return !v || v.enabled
    }

    readonly property string micOff: "Turn on your microphone to get metrics"
    readonly property string camOff: "Turn on your camera to get metrics"
    readonly property string shareOff: "Start screensharing to get metrics"
    readonly property string watchOff: "View metrics when participant starts screensharing"
    readonly property string rttTip: "In group calls, it’s the response time between your system and the Teams Service. In one-on-one calls, it’s the response time between your system and the other participant’s. Lower is better."
    readonly property string lossTip: "The result of a poor network connection. Lower is better."
    readonly property string sentPacketsTip: "Data gets sent over the network in packets. This is the number of data packets during the call."
    readonly property string recvPacketsTip: "The number of packets received."
    readonly property string sendBitrateTip: "The amount of data your device sends. The higher the number, the better the quality."
    readonly property string recvBitrateTip: "Bitrate depends on your network speed. Higher is better."
    readonly property string sentFpsTip: "The number of video frames sent per second. Higher is better."
    readonly property string sentResTip: "Video resolution sent. Higher is better."
    readonly property string processingTip: "Indicates whether CPU or GPU is used for encoding."

    // [label, data-tid, help text, text when off]
    readonly property var categories: [
        { name: "Network", title: "Network", off: "", root: [["Round trip time", "network-send-rtt-avg"], ["Received packet loss", "network-recv-loss-rate-avg"]],
          detail: [["Teams send limit", "network-sent-bw-estimate", "The max limit Teams can send based on the current network conditions and how it’s used. This isn’t your ISP speed limit.", ""],
                   ["Teams receive limit", "network-received-bw-estimate", "The max limit Teams can receive based on the current network conditions and how it’s used. This isn’t your ISP speed limit. For more details, see the admin article https://docs.microsoft.com/en-us/MicrosoftTeams/prepare-network#bandwidth-requirements.", ""],
                   ["Round trip time", "network-send-rtt-avg", rttTip, ""],
                   ["Received packet loss", "network-recv-loss-rate-avg", lossTip, ""]] },
        { name: "Audio", title: "Audio", off: micOff, root: [["Sent bitrate", "audio-send-bps"], ["Received Jitter", "audio-nw-jitter-avg"]],
          detail: [["Sent bitrate", "audio-send-bps", "The amount of audio data sent. Higher is better.", micOff],
                   ["Sent packets", "audio-rtp-packets-sent", sentPacketsTip, micOff],
                   ["Round trip time", "audio-send-rtt-avg", rttTip, micOff],
                   ["Sent codec", "audio-send-codec", "Codec used for encoding audio sent.", micOff],
                   ["Received Jitter", "audio-nw-jitter-avg", "Distortion in audio, caused by inconsistent audio packet arrival times. Lower is better.", ""],
                   ["Received packet loss", "audio-recv-loss-rate-avg", lossTip, ""],
                   ["Received packets", "audio-rtp-packets-received", recvPacketsTip, ""],
                   ["Received codec", "audio-received-codec", "Codec used for encoding audio data received by your system.", ""]] },
        { name: "Video", title: "Video", off: camOff,
          root: [["Sent bitrate", "video-send-current-bitrate"], ["Received bitrate", "video-receive-current-bitrate"], ["Sent frame rate", "video-send-current-frame-rate"],
                 ["Sent resolution", "video-send-resolution"], ["Sent codec", "video-sent-codec-name"], ["Video processing", "video-processing-type"]],
          detail: [["Sent bitrate", "video-send-current-bitrate", sendBitrateTip, camOff],
                   ["Received bitrate", "video-receive-current-bitrate", recvBitrateTip, ""],
                   ["Sent frame rate", "video-send-current-frame-rate", sentFpsTip, camOff],
                   ["Sent resolution", "video-send-resolution", sentResTip, camOff],
                   ["Round trip time", "video-send-rtt-avg", rttTip, camOff],
                   ["Sent packets", "video-rtp-packets-sent", sentPacketsTip, camOff],
                   ["Sent codec", "video-sent-codec-name", "Codec used to encode your video data.", camOff],
                   ["Video processing", "video-processing-type", "Resource used to encode video.", camOff]] },
        { name: "ScreenSharing", title: "Screen Sharing", off: shareOff,
          root: [["Sent bitrate", "screen-sharing-send-current-bitrate"], ["Sent frame rate", "screen-sharing-send-current-frame-rate"], ["Sent resolution", "screen-sharing-send-resolution"],
                 ["Sent codec", "screen-sharing-sent-codec-name"], ["Screen share send processing", "screen-sharing-send-processing-type"],
                 ["Received bitrate", "screen-sharing-receive-current-bitrate"], ["Received frame rate", "screen-sharing-receive-current-frame-rate"],
                 ["Received resolution", "screen-sharing-received-resolution"], ["Received codec", "screen-sharing-received-codec"],
                 ["Screen share received processing", "screen-sharing-received-processing-type"]],
          detail: [["Sent bitrate", "screen-sharing-send-current-bitrate", sendBitrateTip, shareOff],
                   ["Sent frame rate", "screen-sharing-send-current-frame-rate", sentFpsTip, shareOff],
                   ["Sent resolution", "screen-sharing-send-resolution", sentResTip, shareOff],
                   ["Round trip time", "screen-sharing-send-rtt-avg", rttTip, shareOff],
                   ["Sent packets", "screen-sharing-rtp-packets-sent", sentPacketsTip, shareOff],
                   ["Sent codec", "screen-sharing-sent-codec-name", "Used for encoding screen share data.", shareOff],
                   ["Screen share send processing", "screen-sharing-send-processing-type", processingTip, shareOff],
                   ["Received bitrate", "screen-sharing-receive-current-bitrate", recvBitrateTip, watchOff],
                   ["Received frame rate", "screen-sharing-receive-current-frame-rate", "The number of video frames received per second. Higher is better.", watchOff],
                   ["Received resolution", "screen-sharing-received-resolution", "Incoming screensharing resolution received. Higher is better.", watchOff],
                   ["Received packet loss", "screen-sharing-recv-loss-rate-avg", lossTip, watchOff],
                   ["Received packets", "screen-sharing-rtp-packets-received", recvPacketsTip, watchOff],
                   ["Received codec", "screen-sharing-received-codec", "Used for processing and encoding incoming screen sharing.", watchOff],
                   ["Screen share received processing", "screen-sharing-received-processing-type", processingTip, watchOff]] }
    ]
    readonly property var current: categories.find(c => c.name === page) || null
    // A card is off when its first metric (what you send) is.
    function categoryOff(c) { return c.off.length > 0 && !enabled(c.root[0][1]) }

    component IconButton: Rectangle {
        id: ib
        property string icon
        property int glyph: 20
        property string tip
        signal clicked()
        width: 32; height: 31.33; radius: 4
        color: ibh.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: ib.glyph; color: theme.textStrong }
        HoverHandler { id: ibh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        ToolTip.visible: ibh.hovered && ib.tip.length > 0
        ToolTip.delay: 250
        ToolTip.text: ib.tip
        Accessible.role: Accessible.Button
        Accessible.name: ib.tip
    }

    // Header: "Call health", or a page's title after Back.
    Item {
        id: header
        y: 3; width: parent.width; height: 58
        IconButton {
            visible: root.page !== ""
            x: 15.67; y: 13.67; height: 30
            icon: "arrow-left-20"; tip: "Go back to call health root panel"
            onClicked: root.page = ""
        }
        Text {
            x: root.page !== "" ? 47.67 : 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: root.current ? root.current.title : "Call health"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        IconButton {
            x: parent.width - (root.page !== "" ? 47 : 52); y: 13.67; height: 30
            icon: "dismiss-16"; glyph: 16; tip: "Close call health pane"
            onClicked: root.closed()
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    Flickable {
        id: flick
        y: 61; width: parent.width; height: parent.height - y
        clip: true
        contentHeight: (root.page === "" ? rootPage.height : detailPage.height) + 16
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property bool overflows: contentHeight > height
        onContentHeightChanged: if (!overflows) contentY = 0

        // The root page.
        Column {
            id: rootPage
            visible: root.page === ""
            x: 16.67; width: flick.overflows ? 313.33 : 319.33
            Item { width: 1; height: 24 }
            Text {
                x: 5; width: parent.width - 5
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: theme.brandLink
                text: "Your call is receiving data. Most metrics refresh every 15 seconds. <a href=\"https://go.microsoft.com/fwlink/?linkid=2270219\">Learn more</a>"
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.text
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
            Item { width: 1; height: 5 }
            Text {
                x: 5; height: 16
                text: "Last updated at: " + root.updatedAt
                font.family: theme.font; font.pixelSize: 12
                color: theme.text
            }
            Item { width: 1; height: 10 }
            Repeater {
                model: root.categories
                Column {
                    id: cat
                    required property var modelData
                    readonly property bool off: root.categoryOff(modelData)
                    width: parent.width
                    Rectangle {
                        width: parent.width
                        height: (cat.off ? 48.33 : 42) + cat.modelData.root.length * 23 + 8
                        color: theme.pick("#F0F0F0", "#3D3D3D")
                        Row {
                            x: 10; y: 14
                            Text {
                                id: catTitle
                                height: 20; verticalAlignment: Text.AlignVCenter
                                text: cat.modelData.title
                                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                color: theme.text
                            }
                        }
                        IconButton {
                            visible: cat.off
                            x: 10 + catTitle.implicitWidth; y: 9
                            icon: "info-20"; tip: cat.modelData.off
                        }
                        Column {
                            x: 10; y: cat.off ? 48.33 : 42
                            Repeater {
                                model: cat.modelData.root
                                Text {
                                    required property var modelData
                                    height: 23
                                    text: modelData[0] + ": " + root.val(modelData[1])
                                    font.family: theme.font; font.pixelSize: 14
                                    color: theme.text
                                }
                            }
                        }
                        Accessible.role: Accessible.Grouping
                        Accessible.name: cat.modelData.title
                    }
                    Item { width: 1; height: 2 }
                    Rectangle {
                        width: parent.width; height: 41.33
                        color: theme.pick("#F0F0F0", "#3D3D3D")
                        Rectangle {
                            x: 10; y: 5; width: parent.width - 20; height: 31.33; radius: 4
                            color: vmh.hovered ? theme.menuHover : "transparent"
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "View more " + cat.modelData.title.toLowerCase() + " data"
                                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                color: theme.textStrong
                            }
                            FluentIcon { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-20"; size: 20; color: theme.textStrong }
                            HoverHandler { id: vmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.page = cat.modelData.name; flick.contentY = 0; root.refresh() } }
                            Accessible.role: Accessible.Button
                            Accessible.name: "View more " + cat.modelData.title.toLowerCase() + " data"
                        }
                    }
                    Item { width: 1; height: 10 }
                }
            }
        }

        // A category's page: a tile per metric.
        Column {
            id: detailPage
            visible: root.page !== ""
            x: 16.67; width: flick.overflows ? 313.33 : 319.33
            spacing: 2
            Item { width: 1; height: 2 }
            Repeater {
                model: root.current ? root.current.detail : []
                Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool on: root.enabled(modelData[1])
                    width: parent.width; height: 73.33
                    color: theme.pick("#F0F0F0", "#3D3D3D")
                    Text {
                        id: tileTitle
                        x: 10; y: 12; height: 23.33 - 8
                        text: tile.modelData[0]
                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    IconButton {
                        x: 10 + tileTitle.implicitWidth; y: 4
                        icon: "info-20"
                        tip: tile.on || !tile.modelData[3] ? tile.modelData[2] : tile.modelData[3]
                    }
                    Text {
                        x: 10; y: 41.33; height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: root.val(tile.modelData[1])
                        font.family: theme.font; font.pixelSize: 16
                        color: theme.text
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: tile.modelData[0] + ": " + root.val(tile.modelData[1])
                }
            }
        }
    }
}
