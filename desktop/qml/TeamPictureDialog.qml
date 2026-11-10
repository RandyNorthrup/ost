import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Change team picture (Manage team ▸ Settings ▸ Team details ▸ Change
// picture; Teams' dialog, measured on winpc 2026-11-09): 638 x 504,
// padding 27 32 32, radius 8.
// - "Change team picture" (18/25.7 bold).
// - The picture (196, radius 4) centred 124.7 down; Upload and Remove
//   (transparent, their glyphs) centred under it, 336.7 down.
// - Close and Save (96 x 32) at the bottom left, 432 down; Save once a
//   picture was picked or removed.
// Upload picks a picture file; Remove puts back Teams' initials picture.
// Save sends it as Teams does (POST …/teams/{group}/profilepicture).
Popup {
    id: dlg
    property string teamId: ""
    property string teamThread: ""
    property string teamName: ""
    // "" untouched, "remove", or a file URL.
    property string pending: ""
    property bool saving: false

    function start() { pending = ""; saving = false; open() }
    function save() {
        saving = true
        backend.channelAction("team-picture", teamId, teamThread, JSON.stringify({ path: pending === "remove" ? "" : pending.toString().replace(/^file:\/\//, "") }))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "team-picture" || r.channel !== dlg.teamThread || !dlg.saving) return
            dlg.saving = false
            if (r.ok) dlg.close()
            else backend.toast("Something went wrong on our end. Please try again.", "error")
        }
    }
    FileDialog {
        id: files
        title: "Upload"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.bmp)"]
        onAccepted: dlg.pending = selectedFile.toString()
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 638; height: 504
    topPadding: 27; leftPadding: 32; rightPadding: 32; bottomPadding: 32
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    Item {
        anchors.fill: parent
        Text {
            text: "Change team picture"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        // The picture as it will be.
        Item {
            x: (parent.width - 196) / 2; y: 97.7; width: 196; height: 196
            Avatar {
                visible: dlg.pending === "" || dlg.pending === "remove"
                anchors.fill: parent
                size: 196; square: true; squareRadius: 4
                name: dlg.teamName
                initialsText: dlg.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                photoId: dlg.pending === "remove" || !dlg.teamId ? "" : "team:" + dlg.teamId
            }
            Image {
                visible: dlg.pending !== "" && dlg.pending !== "remove"
                anchors.fill: parent
                source: visible ? dlg.pending : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(392, 392)
                layer.enabled: true
            }
        }
        Row {
            x: (parent.width - width) / 2; y: 309.7
            spacing: 15.3
            Plain { icon: "arrow-upload-20"; text: "Upload"; onClicked: files.open() }
            Plain { icon: "delete-20"; text: "Remove"; onClicked: dlg.pending = "remove" }
        }
        Row {
            x: 20; y: 405
            spacing: 18
            Btn { text: "Close"; onClicked: dlg.close() }
            Btn { text: "Save"; primary: true; enabled: dlg.pending !== "" && !dlg.saving; onClicked: dlg.save() }
        }
    }

    component Plain: Rectangle {
        id: pb
        property string icon
        property string text
        signal clicked()
        width: pbRow.implicitWidth + 24; height: 31.3; radius: 4
        color: pbHover.hovered ? theme.menuHover : "transparent"
        Row {
            id: pbRow
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FluentIcon { name: pb.icon; size: 20; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
        }
        HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: 96; height: 32; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text { anchors.centerIn: parent; text: btn.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: !btn.enabled ? theme.disabledStrong : btn.primary ? theme.textOnBrand : theme.text }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
}
