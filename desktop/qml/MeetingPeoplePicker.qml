import QtQuick
import QtQuick.Controls

// Teams' people picker in Meeting options (co-organizers, specific
// presenters and producers: a Fluent TagPicker), measured on winpc
// 2026-11-11 (CSS px):
// - the box 498.7 wide, 33.3 tall with one row, white, radius 4, a 0.67
//   NeutralStroke1 border with the accessible stroke at the bottom (hover
//   and focus darken it; focused, a 2 px brand line under it), 12 in;
// - picked people as tags: 20 tall, radius 12, #F5F5F5, a 16 px Fluent
//   colourful avatar (one initial) 1 in, the name 14/20 #424242 6 after it,
//   then the dismiss (12) 2 after the name and 5 from the end; tags 4
//   apart, 6.7 from the box's top; then the search field;
// - "Search for participants" (#707070) only while nobody is picked;
// - the matches drop 2.2 under the box: white, radius 4, 4 + 2 in, the
//   menu shadow; rows 44 tall (6 8 padding, radius 4) with a 32 px avatar
//   and the name 14 #242424 4 after it; hover #F5F5F5; at most 15.5rem
//   (248) tall, then it scrolls.
// Teams offers the meeting's invitees (its picker without people search,
// as in a meeting), minus anyone already picked in the same section; the
// caller passes them in `candidates`. Clicking a tag, or Backspace in an
// empty field, removes the person.
Item {
    id: root
    width: 498.7
    height: box.height
    property string placeholder: "Search for participants"
    /// Who's picked: [{mri, upn, objectId, tenantId}].
    property var picked: []
    /// Whom the picker offers (same shape).
    property var candidates: []
    /// {mri: display name}.
    property var names: ({})
    /// Teams' maxPeopleSelectionAllowed (0: no limit).
    property int max: 0
    property bool hasError: false
    property bool disabled: false
    signal changed(var people)

    function nameOf(p) { return names[p.mri] || p.displayName || p.upn || "" }
    readonly property string query: field.text.trim()
    readonly property bool full: max > 0 && picked.length >= max
    readonly property var matches: full ? [] : candidates.filter(p => picked.every(x => x.mri !== p.mri)
        && nameOf(p).toLowerCase().indexOf(query.toLowerCase()) >= 0)
    property bool open: false
    property int current: -1
    onQueryChanged: { current = -1; if (field.activeFocus) open = true }

    function pick(p) {
        if (!p) return
        changed(picked.concat([p]))
        field.text = ""
        field.forceActiveFocus()
    }
    function unpick(i) { changed(picked.filter((_, j) => j !== i)) }

    Rectangle {
        id: box
        width: parent.width
        height: Math.max(33.3, tags.height + 13.3)
        radius: 4
        color: root.disabled ? "transparent" : theme.surface
        border.width: 0.67
        border.color: root.disabled ? theme.divider : root.hasError ? theme.redForeground3
            : field.activeFocus ? theme.strokePressed : boxH.hovered ? theme.strokeHover : theme.stroke
        clip: true
        // The accessible stroke along the bottom, and the brand line while
        // focused.
        Rectangle {
            visible: !root.disabled && !root.hasError
            anchors.bottom: parent.bottom; x: 0.67; width: parent.width - 1.33
            height: field.activeFocus ? 2 : 0.67
            color: field.activeFocus ? theme.brand
                : boxH.hovered ? theme.strokeAccessibleHover : theme.textSecondary
        }
        HoverHandler { id: boxH; enabled: !root.disabled; cursorShape: Qt.IBeamCursor }
        TapHandler { enabled: !root.disabled; onTapped: { field.forceActiveFocus(); root.open = true } }
        Flow {
            id: tags
            x: 12.67; y: 6.7
            width: parent.width - 12.67 - 20
            spacing: 4
            Repeater {
                model: root.picked
                Rectangle {
                    id: tag
                    required property var modelData
                    required property int index
                    width: 23.7 + tagName.implicitWidth + 4 + 19.7
                    height: 20; radius: 12
                    color: tagH.hovered && !root.disabled ? theme.pick("#E0E0E0", "#3D3D3D") : theme.pick("#F5F5F5", "#2E2E2E")
                    Avatar {
                        x: 1.7; anchors.verticalCenter: parent.verticalCenter
                        size: 16; colorful: true; name: root.nameOf(tag.modelData)
                    }
                    Text {
                        id: tagName
                        x: 25.7; y: -1
                        height: 20; verticalAlignment: Text.AlignVCenter
                        text: root.nameOf(tag.modelData)
                        font.family: theme.font; font.pixelSize: 14
                        color: root.disabled ? theme.disabled : theme.textStrong
                    }
                    FluentIcon {
                        x: tagName.x + tagName.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter
                        name: "dismiss-12"; size: 12
                        color: root.disabled ? theme.disabled : theme.textStrong
                    }
                    HoverHandler { id: tagH; enabled: !root.disabled; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: !root.disabled; onTapped: root.unpick(tag.index) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove " + root.nameOf(modelData)
                }
            }
            TextInput {
                id: field
                width: Math.max(60, tags.width - (root.picked.length ? 150 : 0))
                height: 20
                enabled: !root.disabled
                verticalAlignment: TextInput.AlignVCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                selectByMouse: true
                Text {
                    visible: !field.text && root.picked.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.placeholder
                    font: field.font
                    color: root.disabled ? theme.disabled : theme.pick("#707070", "#ADADAD")
                }
                onActiveFocusChanged: if (!activeFocus) root.open = false
                // The dialog's Escape: close the list first.
                function closeDropForEscape() { if (!root.open) return false; root.open = false; return true }
                Keys.onDownPressed: { root.open = true; if (root.matches.length) root.current = (root.current + 1) % root.matches.length }
                Keys.onUpPressed: if (root.matches.length) root.current = (root.current - 1 + root.matches.length) % root.matches.length
                Keys.onReturnPressed: if (root.current >= 0 && root.current < root.matches.length) root.pick(root.matches[root.current])
                Keys.onEnterPressed: if (root.current >= 0 && root.current < root.matches.length) root.pick(root.matches[root.current])
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && !field.text && root.picked.length) { root.unpick(root.picked.length - 1); event.accepted = true }
                }
                Accessible.role: Accessible.ComboBox
                Accessible.name: root.placeholder
            }
        }
    }

    // The matches, over the dialog (not clipped by its scrolling list).
    Popup {
        id: drop
        parent: box
        visible: root.open && !root.disabled
        y: box.height + 2.2
        width: root.width
        height: Math.min(248, 12 + list.contentHeight)
        padding: 0
        focus: false
        closePolicy: Popup.NoAutoClose
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        ListView {
            id: list
            x: 6; y: 6; width: parent.width - 12; height: parent.height - 12
            clip: true
            interactive: contentHeight > height
            model: root.matches
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width; height: 44; radius: 4
                color: index === root.current || rowH.hovered ? theme.menuHover : "transparent"
                Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 32; colorful: true; name: root.nameOf(row.modelData) }
                Text {
                    x: 44; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 52; elide: Text.ElideRight
                    text: root.nameOf(row.modelData)
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                HoverHandler { id: rowH; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.pick(row.modelData) }
                Accessible.role: Accessible.ListItem
                Accessible.name: root.nameOf(modelData)
            }
        }
    }
    function openForTest() { field.forceActiveFocus(); open = true }
    function typeForTest(t) { field.forceActiveFocus(); field.text = t; open = true }
}
