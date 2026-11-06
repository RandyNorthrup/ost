import QtQuick
import QtQuick.Controls.Basic

// The Planner app, laid out as Teams desktop's (measured at 1x): a 289 px
// pane with Planner, Create a plan, My day, My tasks, My plans and
// Pinned; the content has the view's header, Grid / Board, the filters
// (All, Private tasks, Assigned to me), and the tasks grid (Task name,
// Source, Due, Priority) with "Add new task". Board groups the tasks
// into columns (by source in My tasks, by bucket in a plan).
Item {
    id: root
    /// The backend's planner_json, parsed.
    property var plannerData: ({})
    property bool busy: false
    signal load(string view, string planJson)
    signal add(string title, string due)
    signal complete(string taskJson)
    signal createPlan(string groupId, string team, string title)
    signal addToPlan(string planJson, string title)
    signal deletePlan(string planId)
    /// Your teams (plans are created in one): [{id, name}].
    property var teams: []
    signal remove(string taskJson)

    property string view: "mytasks"
    property var plan: null
    property string filter: "assigned"
    property bool board: false
    property string search: ""
    readonly property var tasks: (plannerData.tasks || []).filter(t =>
        (view !== "mytasks" || filter === "all" || (filter === "private" ? t.kind === "todo" : t.kind === "planner"))
        && (!search || t.title.toLowerCase().indexOf(search.toLowerCase()) >= 0))
    readonly property var plans: plannerData.plans || []

    function open(v, p) {
        view = v; plan = p || null
        load(v, p ? JSON.stringify(p) : "")
    }
    Component.onCompleted: open("mytasks")

    function dueText(d) {
        if (!d) return ""
        const day = new Date(d + "T00:00:00"), today = new Date(); today.setHours(0, 0, 0, 0)
        const n = Math.round((day - today) / 86400000)
        if (n === 0) return "Today"
        if (n === 1) return "Tomorrow"
        if (n === -1) return "Yesterday"
        return Qt.formatDate(day, "ddd M/d")
    }
    readonly property var columns: {
        const key = t => view === "plan" ? (t.bucket || "No bucket") : t.source
        const out = []
        for (const t of tasks) {
            let c = out.find(c => c.name === key(t))
            if (!c) { c = { name: key(t), tasks: [] }; out.push(c) }
            c.tasks.push(t)
        }
        return out
    }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // The left pane
    Rectangle {
        id: pane
        width: 289; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Row {
            x: 24; y: 19; spacing: 10
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "clipboard-task-list-ltr-24-filled"; size: 22; color: theme.brand }
            Text { text: "Planner"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        }
        // Create a plan: plans belong to a team; the menu lists yours.
        Rectangle {
            x: 16; y: 77; width: 153; height: 32; radius: theme.radius
            color: cph.hovered ? theme.brandHover : theme.brandFill
            Row {
                anchors.centerIn: parent; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 20; color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Create a plan"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
            }
            HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: planDialog.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Create a plan"
        }
        Column {
            x: 8; y: 133; width: parent.width - 16
            Repeater {
                model: [
                    { key: "myday", label: "My day", icon: "weather-sunny-20" },
                    { key: "mytasks", label: "My tasks", icon: "task-list-ltr-20" },
                    { key: "plans", label: "My plans", icon: "grid-20" }
                ]
                Rectangle {
                    id: nav
                    required property var modelData
                    readonly property bool sel: root.view === modelData.key || (modelData.key === "plans" && root.view === "plan")
                    width: parent.width; height: 46; radius: theme.radius
                    color: sel ? theme.selected : nh.hovered ? theme.rowHover : "transparent"
                    Rectangle { visible: nav.sel; width: 3; height: 20; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: theme.brand }
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: nav.modelData.icon; size: 20; color: nav.sel ? theme.brand : theme.textStrong }
                    Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: nav.modelData.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: nav.sel ? Font.DemiBold : Font.Normal; color: theme.text }
                    HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.open(nav.modelData.key) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
            Item { width: 1; height: 12 }
            Text { x: 8; text: "Pinned"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
            Item { width: 1; height: 12 }
            Text { x: 8; text: "Pinned items will appear here."; font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong }
        }
    }

    // Content
    Item {
        id: content
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        // Header
        Row {
            x: 32; y: 18; spacing: 10
            FluentIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.view === "plan" ? "grid-20" : root.view === "myday" ? "weather-sunny-20" : root.view === "plans" ? "grid-20" : "checkmark-circle-20"
                size: 20; color: theme.textStrong
            }
            Text {
                text: root.view === "plan" && root.plan ? root.plan.title : root.view === "plans" ? "My plans" : root.view === "myday" ? "My day" : "My tasks"
                font.family: theme.font; font.pixelSize: theme.base + 2; font.weight: Font.Bold
                color: theme.text
            }
            Text {
                visible: root.view === "plan" && !!root.plan
                anchors.verticalCenter: parent.verticalCenter
                text: root.plan ? root.plan.team : ""
                font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary
            }
        }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }

        // Toolbar: Grid / Board, filters, search.
        Row {
            visible: root.view === "mytasks" || root.view === "plan" || root.view === "myday"
            x: 18; y: 77; spacing: 8
            Repeater {
                model: [{ key: false, label: "Grid", icon: "grid-20" }, { key: true, label: "Board", icon: "board-20" }]
                Chip {
                    required property var modelData
                    on: root.board === modelData.key; icon: modelData.icon; label: modelData.label
                    onClicked: root.board = modelData.key
                }
            }
            Rectangle { visible: root.view === "mytasks"; width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.divider }
            Repeater {
                model: root.view === "mytasks" ? [{ key: "all", label: "All" }, { key: "private", label: "Private tasks" }, { key: "assigned", label: "Assigned to me" }] : []
                Chip {
                    required property var modelData
                    on: root.filter === modelData.key; label: modelData.label
                    onClicked: root.filter = modelData.key
                }
            }
            Rectangle {
                width: searching.visible ? 200 : 32; height: 32; radius: theme.radius
                color: searching.visible ? theme.input : (sh.hovered ? theme.rowHover : "transparent")
                border.color: searching.visible ? theme.stroke : "transparent"
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 18; color: theme.textStrong }
                TextInput {
                    id: searching
                    visible: root.search.length > 0 || activeFocus
                    x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    onTextChanged: root.search = text
                    Keys.onEscapePressed: { text = ""; focus = false }
                    Accessible.name: "Search tasks"
                }
                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: searching.forceActiveFocus() }
                Accessible.role: Accessible.Button
                Accessible.name: "Search"
            }
        }

        // My plans: a list of the plans of your teams.
        ListView {
            visible: root.view === "plans"
            x: 16; y: 76; width: parent.width - 32; height: parent.height - y
            model: root.plans
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 56; radius: theme.radius
                color: ph.hovered ? theme.rowHover : "transparent"
                Rectangle {
                    x: 12; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: theme.radius
                    color: theme.brandTint
                    FluentIcon { anchors.centerIn: parent; name: "grid-20"; size: 18; color: theme.brand }
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    Text { text: modelData.title; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                    Text { text: modelData.team; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.open("plan", modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: "Plan " + modelData.title
            }
            Text {
                visible: !root.busy && root.plans.length === 0
                y: 16; x: 16
                text: "Your teams don't have any plans yet."
                font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
            }
        }

        // My day: today's tasks (due today).
        // The grid
        Item {
            id: grid
            visible: !root.board && root.view !== "plans"
            x: 0; y: 124; width: parent.width; height: parent.height - y
            readonly property var rows: root.view === "myday"
                ? root.tasks.filter(t => root.dueText(t.due) === "Today") : root.tasks
            Row {
                id: head
                x: 49; height: 46
                HeadCell { label: "Task name"; width: Math.max(260, grid.width * 0.42) }
                HeadCell { label: root.view === "plan" ? "Bucket" : "Source"; width: Math.max(160, grid.width * 0.25) }
                HeadCell { label: "Due"; width: 140 }
                HeadCell { label: "Priority"; width: 110 }
            }
            Rectangle { y: head.height; x: 0; width: parent.width; height: 1; color: theme.dividerSoft }
            // Add new task (private tasks, as in Teams' My tasks).
            Item {
                id: addRow
                visible: root.view !== "plan"
                y: head.height + 1; width: parent.width; height: visible ? 46 : 0
                FluentIcon { x: 21; anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 18; color: theme.brand }
                TextInput {
                    id: newTask
                    x: 49; width: parent.width - 120; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !newTask.text; text: "Add new task"; color: theme.brand; font: newTask.font }
                    Keys.onReturnPressed: {
                        if (!text.trim()) return
                        if (root.view === "plan" && root.plan) root.addToPlan(JSON.stringify(root.plan), text.trim())
                        else root.add(text.trim(), root.view === "myday" ? Qt.formatDate(new Date(), "yyyy-MM-dd") : "")
                        text = ""
                    }
                    Keys.onEscapePressed: { text = ""; focus = false }
                    Accessible.name: "Add new task"
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
            }
            ListView {
                anchors { top: addRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                clip: true
                model: grid.rows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: trow
                    required property var modelData
                    width: ListView.view.width; height: 46
                    color: trh.hovered ? theme.rowHover : "transparent"
                    // Complete: the round check before the name.
                    Rectangle {
                        x: 19; anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: "transparent"
                        FluentIcon { anchors.centerIn: parent; name: ch.hovered ? "checkmark-circle-20" : "circle-20"; size: 20; color: ch.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.complete(JSON.stringify(trow.modelData)) }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Mark " + trow.modelData.title + " complete"
                    }
                    Row {
                        x: 49; height: parent.height
                        Cell { width: Math.max(260, grid.width * 0.42); text: trow.modelData.title; strong: true }
                        Cell { width: Math.max(160, grid.width * 0.25); text: root.view === "plan" ? trow.modelData.bucket : trow.modelData.source }
                        Cell {
                            width: 140; text: root.dueText(trow.modelData.due)
                            danger: !!trow.modelData.due && new Date(trow.modelData.due + "T23:59:59") < new Date()
                        }
                        Cell { width: 110; text: trow.modelData.priority === "Medium" ? "" : trow.modelData.priority }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
                    HoverHandler { id: trh }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.title + (modelData.due ? ", due " + root.dueText(modelData.due) : "")
                }
            }
        }

        // Board: a column per source or bucket.
        Flickable {
            visible: root.board && root.view !== "plans"
            x: 18; y: 124; width: parent.width - 18; height: parent.height - y
            contentWidth: boardRow.width; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: boardRow
                spacing: 12
                Repeater {
                    model: root.columns
                    Rectangle {
                        required property var modelData
                        width: 280; height: Math.min(boardCol.height + 52, 600); radius: 8
                        color: theme.pane
                        Text { x: 12; y: 12; text: modelData.name + "  " + modelData.tasks.length; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                        Column {
                            id: boardCol
                            x: 8; y: 40; width: parent.width - 16; spacing: 8
                            Repeater {
                                model: parent.parent.modelData.tasks
                                Rectangle {
                                    required property var modelData
                                    width: boardCol.width; height: cardCol.height + 20; radius: 6
                                    color: theme.surface; border.color: theme.dividerSoft
                                    Column {
                                        id: cardCol
                                        x: 12; y: 10; width: parent.width - 24; spacing: 4
                                        Text { width: parent.width; wrapMode: Text.Wrap; text: modelData.title; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                                        Text { visible: !!modelData.due; text: root.dueText(modelData.due); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                    }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: modelData.title
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            visible: !root.busy && !root.plannerData.error && root.view !== "plans" && grid.rows.length === 0 && !root.board
            anchors.horizontalCenter: parent.horizontalCenter; y: 300
            text: root.view === "myday" ? "Nothing is due today." : "You have no tasks here."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
        }
        Text {
            visible: !!root.plannerData.error
            anchors.centerIn: parent
            text: root.plannerData.error || ""
            font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
        }
        BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: root.busy }
    }

    // Create a plan: a name and the team it belongs to.
    Popup {
        id: planDialog
        anchors.centerIn: parent
        width: 400; padding: 20; modal: true
        property int team: 0
        onOpened: { planName.text = ""; team = 0; planName.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 14
            Text { text: "Create a plan"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Rectangle {
                width: 360; height: 32; radius: theme.radius
                color: theme.input; border.color: planName.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: planName
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !planName.text; text: "Plan name"; color: theme.textTertiary; font: planName.font }
                    Keys.onReturnPressed: planDialog.create()
                    Accessible.name: "Plan name"
                }
            }
            Text { text: "Team"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
            ComboBox {
                id: teamBox
                width: 360
                model: root.teams.map(t => t.name)
                currentIndex: planDialog.team
                onActivated: i => planDialog.team = i
                Accessible.name: "Team"
            }
            Row {
                spacing: 8
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.brandFill
                    Text { anchors.centerIn: parent; text: "Create"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: planDialog.create() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Create"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: planDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
        function create() {
            const t = root.teams[team]
            if (!planName.text.trim() || !t) return
            root.createPlan(t.id, t.name, planName.text.trim())
            close()
            root.open("plans")
        }
    }

    component Chip: Rectangle {
        id: chip
        property bool on
        property string label
        property string icon
        signal clicked()
        height: 32; radius: 16
        width: chipRow.implicitWidth + 24
        color: on ? theme.brandTint : (chh.hovered ? theme.rowHover : theme.surface)
        border.color: on ? theme.brand : theme.stroke
        border.width: on ? 2 : 1
        Row {
            id: chipRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!chip.icon; anchors.verticalCenter: parent.verticalCenter; name: chip.icon || "add-20"; size: 16; color: chip.on ? theme.brand : theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        }
        HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.checked: on
    }
    component HeadCell: Item {
        property string label
        height: 46
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
    }
    component Cell: Item {
        property alias text: t.text
        property bool strong: false
        property bool danger: false
        height: 46
        Text {
            id: t
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 12; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            color: parent.danger ? theme.danger : parent.strong ? theme.text : theme.textStrong
        }
    }

    // Test harness hooks
    function addForTest(title) { root.add(title, "") }
    function createPlanForTest(name) { const t = root.teams.find(t => t.name === "OST Test Team"); if (t) root.createPlan(t.id, t.name, name); return !!t }
    function completeForTest(title) {
        const t = (plannerData.tasks || []).find(t => t.title === title)
        if (t) root.complete(JSON.stringify(t))
        return !!t
    }
}
