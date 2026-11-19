import QtQuick
import QtQuick.Controls.Basic

// Teams' voicemail transfer target (settings-app `rg`, measured on winpc
// 2026-11-19): with no target, its people picker ("Type a name or number",
// a 294 x 33.3 filled box, #F0F0F0, radius 4, the text 12 in) whose
// suggestions open right under it (Fluent's surface, padding 4, rows 50
// tall: a 32 px picture at 12, 9, the name 14/20 at 60 with the typed part
// bold, its second line 12/16 #616161); a number typed (letters count as
// a phone keypad's, as Teams' phone parser reads them) is offered first as
// an External phone number. With a target, a 294 x 48 box of the same fill:
// its picture (32, presence) at 12, 8, the name at 52, Delete (32 x 31.3,
// delete-20) at 255, 8.3.
Item {
    id: root
    /// The saved target's MRI ("" for none) and its name, if known.
    property string targetMri: ""
    property string targetName: ""
    property string targetPresence: ""
    /// [{id (object id), name, sub, upn, guest}] for `query`.
    property var people: []
    property string peopleQuery: ""
    /// Teams' other pickers of this kind (Manage interpreters: 600 wide,
    /// "Add someone as an interpreter", people only).
    property string placeholder: "Type a name or number"
    property string accessibleName: placeholder
    property bool phoneSuggestions: true
    /// MRIs left out (already chosen).
    property var exclude: []
    signal search(string query)
    /// mri, object id ("" for a phone number), name.
    signal picked(string mri, string oid, string name)
    signal removed()
    width: 294
    height: targetMri ? 48 : 33.33

    readonly property string query: field.text.trim()
    /// The number Teams offers for the typed text: digits (a keypad's for
    /// letters, once there are 3) of a possible phone number, with the
    /// country code +1.
    readonly property string phone: {
        const q = query
        if (!q) return ""
        const letters = (q.match(/[A-Za-z]/g) || []).length
        const keypad = "22233344455566677778889999"
        let digits = ""
        for (const c of q.toUpperCase()) {
            if (c >= "0" && c <= "9") digits += c
            else if (letters >= 3 && c >= "A" && c <= "Z") digits += keypad[c.charCodeAt(0) - 65]
            else if (!/[\s\-().+]/.test(c)) return ""
        }
        if (digits.length < 7 || digits.length > 15) return ""
        if (q.startsWith("+")) return "+" + digits
        // A whole US number is shown as Teams formats it ("+1 425-555-0100",
        // measured 2026-11-19); a shorter one as typed ("+1 6788378").
        const national = digits.length === 11 && digits[0] === "1" ? digits.slice(1) : digits
        if (national.length === 10) return "+1 " + national.slice(0, 3) + "-" + national.slice(3, 6) + "-" + national.slice(6)
        return "+1 " + digits
    }
    readonly property var rows: {
        const out = []
        if (phone && phoneSuggestions) out.push({ kind: "pstn", name: phone, mri: "4:+" + phone.replace(/[^0-9]/g, ""), oid: "" })
        if (peopleQuery === query)
            for (const p of people.filter(p => exclude.indexOf("8:orgid:" + p.id) < 0).slice(0, 8)) out.push({ kind: "person", name: p.name || "", sub: p.sub || "", mri: "8:orgid:" + p.id, oid: p.id })
        return out
    }
    property int current: 0
    onTargetMriChanged: { list.close(); field.text = "" }
    function typeForTest(q) { field.forceActiveFocus(); field.text = q; root.current = 0; root.search(q.trim()); if (q.trim()) list.open() }
    function rowsForTest() { return { open: list.opened, rows: rows.map(r => [r.kind, r.name, r.sub || "", r.mri]), list: list.opened ? [list.x, list.y, list.width, list.height] : null } }
    function choose(r) {
        root.picked(r.mri, r.oid, r.kind === "pstn" ? r.name : r.name)
        field.text = ""
        list.close()
    }
    // The typed text in bold where it matches the name (Teams' <b>).
    function marked(name) {
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const i = query ? name.toLowerCase().indexOf(query.toLowerCase()) : -1
        if (i < 0) return esc(name)
        return esc(name.slice(0, i)) + "<b>" + esc(name.slice(i, i + query.length)) + "</b>" + esc(name.slice(i + query.length))
    }

    // ---- No target: the picker ----
    Rectangle {
        id: box
        visible: !root.targetMri
        anchors.fill: parent; radius: 4
        color: theme.pick("#F0F0F0", "#0A0A0A", "#000000")
        border.color: theme.highContrast ? "#FFFFFF" : "transparent"; border.width: 0.67
        Rectangle { visible: field.activeFocus; anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; radius: 1; color: theme.brand }
        TextInput {
            id: field
            x: 12; width: parent.width - (text ? 42 : 24); anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
            selectByMouse: true
            onTextEdited: { root.current = 0; searchDelay.restart(); if (text.trim()) list.open(); else list.close() }
            Text { visible: !field.text; text: root.placeholder; font: field.font; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
            Keys.onDownPressed: { if (!list.opened && root.rows.length) list.open(); root.current = Math.min(root.current + 1, root.rows.length - 1) }
            Keys.onUpPressed: root.current = Math.max(root.current - 1, 0)
            Keys.onReturnPressed: if (list.opened && root.rows.length) root.choose(root.rows[root.current])
            Keys.onEnterPressed: if (list.opened && root.rows.length) root.choose(root.rows[root.current])
            Keys.onEscapePressed: { text = ""; list.close() }
            Accessible.role: Accessible.EditableText
            Accessible.name: root.accessibleName
        }
        FluentIcon { visible: !!field.text; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
        Timer { id: searchDelay; interval: 300; onTriggered: if (root.query) root.search(root.query) }
        Popup {
            id: list
            y: box.height; width: box.width; padding: 4
            visible: opened && root.rows.length > 0
            closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            contentItem: Column {
                Repeater {
                    model: root.rows
                    Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width - 8; height: 50; radius: 4
                        color: rowHover.hovered || root.current === index ? theme.menuHover : "transparent"
                        Rectangle {
                            visible: row.modelData.kind === "pstn"
                            x: 12; y: 9; width: 32; height: 32; radius: 16
                            color: theme.pick("#48D1CC", "#48D1CC", "#000000")
                            border.color: theme.highContrast ? "#FFFFFF" : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "person-20"; size: 20; color: "#FFFFFF" }
                        }
                        Avatar { visible: row.modelData.kind !== "pstn"; x: 12; y: 9; size: 32; name: row.modelData.name || "?"; photoId: row.modelData.oid || "" }
                        Text {
                            id: rowName
                            x: 60; y: row.modelData.sub ? 6.5 : 11.5
                            width: row.modelData.kind === "pstn" ? implicitWidth : row.width - 68; elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: row.modelData.kind === "pstn" ? row.modelData.name : root.marked(row.modelData.name)
                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                            color: theme.onFill(row, theme.pick("#424242", "#D6D6D6", "#FFFFFF"))
                        }
                        // Teams' External badge on a phone number.
                        Rectangle {
                            visible: row.modelData.kind === "pstn"
                            x: rowName.x + rowName.width + 4; y: 9.5
                            width: extRow.width + 8; height: 24; radius: 4
                            color: theme.pick("#616161", "#ADADAD", "#FFFFFF")
                            Row {
                                id: extRow
                                x: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-error-16-filled"; size: 16; color: theme.pick("#FFFFFF", "#000000", "#000000") }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "External"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#FFFFFF", "#000000", "#000000") }
                            }
                        }
                        Text {
                            visible: !!row.modelData.sub
                            x: 60; y: 27.5; width: row.width - 68; elide: Text.ElideRight
                            text: row.modelData.sub || ""
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                            color: theme.onFill(row, theme.textSecondary)
                        }
                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.current = row.index }
                        TapHandler { onTapped: root.choose(row.modelData) }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: row.modelData.name + (row.modelData.kind === "pstn" ? ", External" : "")
                    }
                }
            }
        }
    }

    // ---- A target ----
    Rectangle {
        id: chosen
        visible: !!root.targetMri
        anchors.fill: parent; radius: 4
        color: theme.pick("#F0F0F0", "#0A0A0A", "#000000")
        border.color: theme.highContrast ? "#FFFFFF" : "transparent"; border.width: 0.67
        Rectangle {
            visible: root.targetMri.startsWith("4:")
            x: 12; y: 8; width: 32; height: 32; radius: 16
            color: theme.pick("#48D1CC", "#48D1CC", "#000000")
            FluentIcon { anchors.centerIn: parent; name: "person-20"; size: 20; color: "#FFFFFF" }
        }
        Avatar {
            visible: !root.targetMri.startsWith("4:")
            x: 12; y: 8; size: 32
            name: root.targetName || "?"; photoId: root.targetMri.replace(/^8:orgid:/, "")
            presence: root.targetPresence
        }
        Text {
            x: 52; anchors.verticalCenter: parent.verticalCenter; width: 255 - 52 - 8; elide: Text.ElideRight
            text: root.targetName || (root.targetMri.startsWith("4:") ? root.targetMri.slice(2) : "")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
        }
        Rectangle {
            id: del
            x: 255; y: 8.33; width: 32; height: 31.33; radius: 4
            color: delHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "delete-20"; size: 20; color: theme.onFill(del, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
            HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.removed() }
            ToolTip {
                visible: delHover.hovered; delay: 500
                y: -height - 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: "Delete"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Delete"
        }
    }
}
