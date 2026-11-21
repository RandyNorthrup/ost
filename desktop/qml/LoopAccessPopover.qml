import QtQuick
import QtQuick.Controls.Basic

// "See who has access" on a Loop page or component (Loop's header
// PermissionsPanel, which Teams bundles, with Teams' ShareService; read
// from Teams 26304, modules 698099 / 154570 and Loop's host strings):
// a popover below the button with "People who have access", a facepile
// of 32 px pictures (at most 6, then "+n" for the rest; a person's tooltip
// "{name} <{email}>"), the groups count, a line, and what the widest link
// allows ("Anyone with the link can also access this Loop component", …).
// While loading: four 32 px circles and a 16 px row.
Popup {
    id: pop
    property string componentUrl: ""
    property var access: null
    readonly property string tag: "loopaccess" + Math.floor(Math.random() * 1e9) + ":"
    padding: 16
    width: 320
    background: FluentSurface { depth: 16; radius: 8; color: theme.surface }
    function openFor(item, url) {
        componentUrl = url; access = null
        parent = item
        x = item.width - width; y = item.height + 4
        open()
        backend.eventsRequest("loopAccess", tag + "a", JSON.stringify({ url: url }))
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id.indexOf(pop.tag) !== 0) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            pop.access = v.error ? { personas: [], groups: [], scope: "" } : v
        }
    }
    readonly property var people: access ? access.personas : []
    contentItem: Column {
        spacing: 12
        Text {
            text: qsTr("People who have access")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        // Loading.
        Row {
            visible: pop.access === null
            spacing: 4
            Repeater { model: 4; Rectangle { width: 32; height: 32; radius: 16; color: theme.pick("#F0F0F0", "#333333", "#000000") } }
        }
        Row {
            visible: pop.access !== null && pop.people.length > 0
            spacing: 4
            Accessible.role: Accessible.List
            Accessible.name: qsTr("List of people who have access")
            Repeater {
                model: pop.people.slice(0, 6)
                Avatar {
                    required property var modelData
                    size: 32
                    name: modelData.name || modelData.email
                    HoverHandler { id: avHover }
                    ToolTip.visible: avHover.hovered
                    ToolTip.text: (modelData.name || "") + " <" + (modelData.email || "") + ">"
                    ToolTip.delay: 300
                }
            }
            Rectangle {
                visible: pop.people.length > 6
                width: 32; height: 32; radius: 16
                color: theme.pick("#F0F0F0", "#333333", "#000000")
                Text { anchors.centerIn: parent; text: "+" + (pop.people.length - 6); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Additional people: %1").arg(pop.people.length - 6)
            }
        }
        Text {
            visible: !!pop.access && pop.access.groups.length > 0
            text: qsTr("%n groups giving access", "", pop.access ? pop.access.groups.length : 0)
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
        Rectangle { width: pop.availableWidth; height: 0.67; color: theme.divider }
        Text {
            width: pop.availableWidth; wrapMode: Text.Wrap
            visible: pop.access !== null
            text: !pop.access ? "" : pop.access.scope === "anyone" || pop.access.scope === "anonymous" ? qsTr("Anyone with the link can also access this Loop component")
                : pop.access.scope === "organization" ? qsTr("People in your organization with the link can also access this Loop component")
                : pop.access.scope === "users" ? qsTr("Only specified people with the link can access this Loop component")
                : qsTr("Only people with existing access can access this Loop component")
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
        Rectangle { visible: pop.access === null; width: pop.availableWidth; height: 16; radius: 4; color: theme.pick("#F0F0F0", "#333333", "#000000") }
    }
}
