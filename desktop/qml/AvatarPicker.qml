import QtQuick
import QtQuick.Controls

// Teams' avatar quick picker (module 681758; measured in the pre-join
// picker on winpc 2026-11-17): "Avatars" (12 px) over a row of 74 x 42
// tiles in 82 x 50 cells from 10 in — None, your avatars (at most three)
// and "Create More" while you have fewer than three — then "Backgrounds"
// (12 px, 12 above) and None plus the app's backgrounds to fill the row (6
// columns, 4 in Camera ▾ or a picker under 486 wide), and "More avatar
// settings" (12 px, brand) at the right. Background tiles are disabled
// (half opacity) until an avatar is chosen. The avatars and backgrounds
// are the ones the Avatars app lists (AvatarHost).
Column {
    id: root
    /// Camera ▾'s variant: 77 x 48 tiles 6 apart, 4 columns.
    property bool inFlyout: false
    property bool showMore: true
    readonly property int columns: inFlyout || width < 486 ? 4 : 6
    readonly property real tileW: inFlyout ? 77 : 74
    readonly property real tileH: inFlyout ? 48 : 42
    readonly property real cellW: inFlyout ? 83 : 82
    readonly property real cellH: inFlyout ? 72 : 50
    readonly property real gridX: inFlyout ? 0 : 10
    signal moreSettings()
    signal createMore()

    component Cell: Item { width: root.cellW; height: root.cellH }

    Text {
        x: root.inFlyout ? 0 : 12; height: root.inFlyout ? 12 : 18; verticalAlignment: Text.AlignBottom
        text: qsTr("Avatars")
        font.family: theme.font; font.pixelSize: 12
        color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
    }
    Row {
        x: root.gridX
        Accessible.role: Accessible.MenuBar
        Accessible.name: qsTr("Avatars")
        Cell {
            EffectTile {
                x: root.inFlyout ? 0 : (root.cellW - width) / 2; y: (root.cellH - height) / 2; width: root.tileW; height: root.tileH
                kind: "none"; label: qsTr("None")
                selected: !videoEffects.avatarId
                accessibleName: selected ? qsTr("No avatar selected") : qsTr("No avatar")
                onPicked: videoEffects.selectAvatar("")
            }
        }
        Repeater {
            model: avatarHost.avatars.slice(0, 3)
            Cell {
                required property var modelData
                EffectTile {
                    x: root.inFlyout ? 0 : (root.cellW - width) / 2; y: (root.cellH - height) / 2; width: root.tileW; height: root.tileH
                    thumb: parent.modelData.thumbnail
                    label: parent.modelData.name; accessibleName: parent.modelData.name
                    selected: videoEffects.avatarId === parent.modelData.id
                    onPicked: videoEffects.selectAvatar(parent.modelData.id)
                }
            }
        }
        Cell {
            visible: avatarHost.avatars.length < 3
            Rectangle {
                id: create
                x: root.inFlyout ? 0 : (root.cellW - width) / 2; y: (root.cellH - height) / 2; width: root.tileW; height: root.tileH
                radius: 2
                color: theme.effectTile
                Rectangle {
                    visible: createHover.hovered
                    x: -2; y: -2; width: parent.width + 4; height: parent.height + 4; radius: 4
                    color: "transparent"; border.color: theme.brand; border.width: 2
                }
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: Math.round((parent.height - 35) / 2); name: "person-add-20"; size: 20; color: theme.textStrong }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round((parent.height - 35) / 2) + 23
                    text: qsTr("Create More")
                    font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                    color: theme.text
                }
                HoverHandler { id: createHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.createMore() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Create More")
            }
        }
    }
    Text {
        x: root.inFlyout ? 0 : 12; height: root.inFlyout ? 12 : 30; verticalAlignment: Text.AlignBottom
        text: qsTr("Backgrounds")
        font.family: theme.font; font.pixelSize: 12
        color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
    }
    Row {
        x: root.gridX
        enabled: !!videoEffects.avatarId
        opacity: enabled ? 1 : 0.5
        Accessible.role: Accessible.MenuBar
        Accessible.name: qsTr("Backgrounds")
        Cell {
            EffectTile {
                x: root.inFlyout ? 0 : (root.cellW - width) / 2; y: (root.cellH - height) / 2; width: root.tileW; height: root.tileH
                kind: "none"; label: qsTr("None")
                selected: !videoEffects.avatarBackground || videoEffects.avatarBackground === "microsoft_none"
                accessibleName: selected ? qsTr("No background selected") : qsTr("No background")
                onPicked: videoEffects.selectAvatarBackground("")
            }
        }
        Repeater {
            model: avatarHost.backgrounds.filter(b => b.id !== "microsoft_none").slice(0, root.columns - 1)
            Cell {
                required property var modelData
                EffectTile {
                    x: root.inFlyout ? 0 : (root.cellW - width) / 2; y: (root.cellH - height) / 2; width: root.tileW; height: root.tileH
                    thumb: parent.modelData.thumbnail
                    label: parent.modelData.name; accessibleName: parent.modelData.name + " background"
                    selected: videoEffects.avatarBackground === parent.modelData.id
                    onPicked: videoEffects.selectAvatarBackground(parent.modelData.id)
                }
            }
        }
    }
    Item {
        visible: root.showMore
        width: root.width; height: visible ? 20 : 0
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: qsTr("More avatar settings")
            font.family: theme.font; font.pixelSize: 12
            font.underline: moreHover.hovered
            color: theme.brand
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.moreSettings() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More avatar settings")
        }
    }
}
