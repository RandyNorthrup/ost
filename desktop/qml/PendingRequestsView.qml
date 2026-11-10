import QtQuick
import QtQuick.Controls.Basic

// Manage team ▸ Pending requests (Teams' tab, measured on winpc
// 2026-11-09; docs/spec/chat-list-and-header.md §5.6.5).
// - None: Teams' illustration (245 x 228.4) centred 70.3 down and "No
//   requests right now. When people ask to join your team, they'll show up
//   here." (18/25.7 semibold, centred) 343.7 down.
// - Requests: "Search for members" (filled-darker) with Accept all
//   (primary) and Deny all; then Name, Title, Location, Requested by and
//   each request's Accept (primary) / Deny, replaced by "You accepted the
//   request." / "You denied the request." once answered. Deny all asks
//   "Deny all join requests" first.
// Requests are read with findJoinRequests and answered with Teams'
// joinRequestAdminAction / bulkJoinRequestAdminAction.
Item {
    id: view
    property string teamId: ""
    property string teamThread: ""
    property string teamName: ""
    property var requests: []
    property bool loaded: false
    property var answered: ({})
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var shown: requests.filter(r => !query || (r.name || "").toLowerCase().indexOf(query) >= 0)
    readonly property bool allAnswered: requests.every(r => answered[r.mri] !== undefined)

    function load() { if (teamThread) { loaded = false; backend.channelAction("join-requests", teamId, teamThread, "") } }
    function answer(mris, accept) { backend.channelAction("join-answer", teamId, teamThread, JSON.stringify({ mris: mris, accept: accept })) }
    onTeamThreadChanged: { requests = []; answered = ({}); search.text = ""; load() }
    Component.onCompleted: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== view.teamThread) return
            if (r.op === "join-requests") { view.loaded = true; if (r.ok) view.requests = r.data.requests || [] }
            else if (r.op === "join-answer") {
                if (!r.ok) { backend.toast("We couldn't update pending member status, please try again later.", "error"); return }
                const a = Object.assign({}, view.answered)
                r.data.mris.forEach(m => a[m] = r.data.accept)
                view.answered = a
                if (r.data.mris.length > 1) backend.toast(r.data.accept ? "You have accepted all pending requests." : "You have denied all pending requests.", "success")
            }
        }
    }

    // None.
    Item {
        visible: view.loaded && view.requests.length === 0
        anchors.fill: parent
        Image {
            x: (parent.width - width) / 2; y: 70.3
            width: 245; height: 228.4
            source: "../assets/illustrations/pending-requests.svg"
            sourceSize: Qt.size(490, 457)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            x: 20; width: parent.width - 40; y: 343.7
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "No requests right now. When people ask to join your team, they'll show up here."
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
    }

    // Requests.
    Item {
        visible: view.requests.length > 0
        anchors.fill: parent
        Rectangle {
            x: 40; y: 20.6; width: 278.7; height: 32; radius: 4
            color: theme.inputFilled
            Rectangle { visible: search.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
            TextInput {
                id: search
                x: 12; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                selectByMouse: true
                Text { visible: !search.text; anchors.verticalCenter: parent.verticalCenter; text: "Search for members"; font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search for members"
            }
            FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
        }
        Row {
            x: 40 + 278.7 + 16; y: 20.6
            spacing: 8
            Btn { text: "Accept all"; primary: true; enabled: !view.allAnswered; onClicked: view.answer(view.requests.filter(r => view.answered[r.mri] === undefined).map(r => r.mri), true) }
            Btn { text: "Deny all"; enabled: !view.allAnswered; onClicked: denyAll.start("denyAll", view.teamName) }
        }
        Flickable {
            x: 40; y: 72; width: parent.width - 80; height: parent.height - y
            contentHeight: 40.7 + view.shown.length * 44.7
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property real col: (width - 220) / 4
            Repeater {
                model: ["Name", "Title", "Location", "Requested by"]
                Text {
                    required property string modelData
                    required property int index
                    x: 8 + index * parent.parent.col; y: 12
                    text: modelData
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.text
                }
            }
            Column {
                y: 40.7; width: parent.width
                Repeater {
                    model: view.shown
                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property real col: (width - 220) / 4
                        readonly property var state_: view.answered[modelData.mri]
                        width: parent.width; height: 44.7
                        color: rowHover.hovered ? theme.menuHover : "transparent"
                        HoverHandler { id: rowHover }
                        Avatar { x: 8; y: 6; size: 32; name: row.modelData.name || "?"; photoId: row.modelData.mri }
                        Repeater {
                            model: [row.modelData.name, row.modelData.title, row.modelData.location, (row.modelData.requested_by || []).length > 1 ? row.modelData.requested_by[0] + ", +" + (row.modelData.requested_by.length - 1) : (row.modelData.requested_by || [""])[0] || ""]
                            Text {
                                required property string modelData
                                required property int index
                                x: 8 + index * row.col + (index === 0 ? 42 : 0)
                                width: row.col - 16 - (index === 0 ? 42 : 0); elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                font.family: theme.font; font.pixelSize: index === 0 ? 14 : 12
                                color: theme.text
                            }
                        }
                        Row {
                            visible: row.state_ === undefined
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Btn { text: "Accept"; primary: true; onClicked: view.answer([row.modelData.mri], true) }
                            Btn { text: "Deny"; onClicked: view.answer([row.modelData.mri], false) }
                        }
                        Text {
                            visible: row.state_ !== undefined
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            text: row.state_ ? "You accepted the request." : "You denied the request."
                            font.family: theme.font; font.pixelSize: 12
                            color: theme.text
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#EBEBEB", "#333333") }
                    }
                }
            }
        }
    }

    TeamActionDialog {
        id: denyAll
        onConfirmed: view.answer(view.requests.filter(r => view.answered[r.mri] === undefined).map(r => r.mri), false)
    }

    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, btnText.implicitWidth + 24); height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !btn.enabled ? theme.disabled : btn.primary ? theme.textOnBrand : theme.text
        }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
}
