import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes

// An agent's ODSL commands that Teams draws in the message body, after the
// text (inside its "see more" cut), as 541316's renderers do (measured on
// winpc 2026-11-22 from a Channel Agent in "OST TEST 246 agent", in the
// thread pane; the statements from Teams' augloop resolver `rt`):
// - plan (PlanCommand `kc`): a card, white, radius 8, a 0.67 #BDBDBD
//   dashed edge while it is a draft (solid #E0E0E0 once saved); the plan's
//   title (14/20 semibold #616161, padding 8 16, 40 tall); its tasks in a
//   tree scrolled within 275 (padding 0 16): a summary task with a 12 px
//   chevron in a 16 x 20 box (padding 4 0) and its title semibold, the
//   others 48 in, each 8 padded with its title (14/20 #242424) and the due
//   date (a calendar glyph #BDBDBD in 24 x 20, then M/d 12/20 medium) 4
//   under it and a 0.67 #E0E0E0 line under the row; then, 16 under the
//   card, Save to Planner (primary), Ask for changes and a ··· menu
//   (Discard), small buttons 24 tall, 8 apart (a saved plan: View in
//   Planner);
// - tasks (TasksCommand `qm` / `Qo`): a card per task, white, a 0.67
//   #E0E0E0 edge, radius 8, padding 8 12, 4 apart: the status tag
//   (#F5F5F5, radius 4, 19.3 tall, a 12 px status glyph and 10/14 text
//   #424242), the title as a link (12/16 #242424), then the assignees'
//   20 px pictures and the due date (12/16 medium) 12 apart;
// - questionsList (QuestionsListCommand `td` / `Xc`, from Teams' code: the
//   Facilitator's, not seen live): the questions grouped by topic, each
//   group's title semibold, then the questions in order with who asked.
// The dates are the due date's local day, as Teams' new Date(due) gives.
Column {
    id: root
    property var message: ({})
    property var host: null
    spacing: 8
    readonly property var cards: {
        const out = []
        ;(message.suggested || []).forEach((a, ai) => {
            if (a.kind !== "odsl") return
            ;(a.statements || []).forEach((st, si) => {
                const c = st.command
                if (c && ["plan", "tasks", "questionsList"].indexOf(c.kind) >= 0 && (c.kind !== "plan" || (c.tasks || []).length) && (c.kind !== "tasks" || (c.tasks || []).length))
                    out.push({ c: c, st: st, si: si, ai: ai })
            })
        })
        return out
    }
    readonly property bool shown: cards.length > 0
    readonly property var peopleNames: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    function nameOf(mri) { return mri === backend.userMri ? backend.userName : (root.peopleNames[mri] || "") }
    function str(c, key, dflt) { return (c && c.strings && c.strings[key]) || dflt }
    function day(due) { if (!due) return ""; const d = new Date(due); return isNaN(d) ? "" : (d.getMonth() + 1) + "/" + d.getDate() }
    function invoke(e, result) {
        if (root.host) root.host.suggestedAction(root.message, { kind: "odsl", statement: e.st.raw, statementIndex: e.si, suggestedActionIndex: e.ai, result: result })
    }

    Repeater {
        model: root.cards
        Loader {
            required property var modelData
            width: root.width
            sourceComponent: modelData.c.kind === "plan" ? planComp : modelData.c.kind === "tasks" ? tasksComp : questionsComp
            property var entry: modelData
        }
    }

    // A due date: the calendar glyph and M/d.
    component DueDate: Row {
        property string due
        spacing: 4
        height: 20
        Item {
            width: 24; height: 20
            FluentIcon { anchors.centerIn: parent; size: 14; name: "calendar-ltr-16"; color: theme.pick("#BDBDBD", "#5C5C5C", "#FFFFFF") }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.day(parent.due)
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.Medium
            color: theme.text
        }
        Accessible.role: Accessible.StaticText
        Accessible.name: qsTr("Due on %1", "messaging:kzaxss4q").replace("{{date}}", root.day(due))
    }
    // A small Fluent button (24 tall, padding 0 8, 12 px).
    component SmallButton: Rectangle {
        id: btn
        property string label
        property string glyph
        property bool primary: false
        property bool enabled_: true
        signal clicked()
        width: Math.max(glyph && !label ? 37.3 : 64, btnRow.implicitWidth + 17.3)
        height: 24; radius: 4
        color: !enabled_ ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : btnHover.hovered ? theme.rowHover : theme.surface
        border.width: 0.67
        border.color: primary || !enabled_ ? "transparent" : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Row {
            id: btnRow
            anchors.centerIn: parent; spacing: 4
            FluentIcon { visible: btn.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; size: 20; name: btn.glyph; color: btn.enabled_ ? theme.onFill(btn, btn.primary ? "white" : theme.text) : theme.disabled }
            Text {
                visible: btn.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                font.family: theme.font; font.pixelSize: 12
                color: btn.enabled_ ? theme.onFill(btn, btn.primary ? "white" : theme.text) : theme.disabled
            }
        }
        HoverHandler { id: btnHover; enabled: btn.enabled_; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled_; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: btn.label || qsTr("More options")
    }

    Component {
        id: planComp
        Column {
            id: plan
            readonly property var e: parent ? parent.entry : null
            readonly property var c: e ? e.c : ({})
            readonly property bool saved: c.state === "SAVED"
            readonly property bool busy: c.action_status === "SAVING" || c.action_status === "DISCARDING"
            /// Collapsed summary tasks (by task id).
            property var collapsed: ({})
            readonly property var rows: {
                const tasks = c.tasks || []
                if (!c.hierarchical) return tasks.map(t => ({ t: t, level: 0, parent: false }))
                const out = []
                const kids = id => tasks.filter(t => t.parent === id)
                for (const t of tasks.filter(t => !t.parent)) {
                    const k = kids(t.task_id)
                    out.push({ t: t, level: 0, parent: t.summary || k.length > 0 })
                    if (!plan.collapsed[t.task_id]) for (const x of k) out.push({ t: x, level: 1, parent: false })
                }
                return out
            }
            width: parent ? parent.width : 0
            spacing: 16
            Item {
                id: planCard
                width: parent.width
                height: 40 + Math.min(275, tree.contentHeight) + 8
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: theme.surface
                    border.width: plan.saved ? 0.67 : 0
                    border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                }
                // The draft's dashed edge.
                Shape {
                    visible: !plan.saved
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 0.67
                        strokeColor: theme.pick("#BDBDBD", "#5C5C5C", "#FFFFFF")
                        fillColor: "transparent"
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [4, 3]
                        PathRectangle { x: 0.33; y: 0.33; width: planCard.width - 0.67; height: planCard.height - 0.67; radius: 8 }
                    }
                }
                Text {
                    x: 16; y: 10; width: parent.width - 32; height: 20
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: plan.c.title || ""
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.textSecondary
                    Accessible.role: Accessible.Heading
                }
                Flickable {
                    id: tree
                    x: 16; y: 40
                    width: parent.width - 32; height: Math.min(275, contentHeight)
                    contentHeight: treeCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: tree.contentHeight > tree.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    Column {
                        id: treeCol
                        width: tree.width - 8
                        spacing: 2
                        Repeater {
                            model: plan.rows
                            Item {
                                id: taskRow
                                required property var modelData
                                readonly property real indent: modelData.level > 0 ? 48 : (plan.c.hierarchical ? 16 : 0)
                                width: treeCol.width
                                height: 8 + taskTitle.height + 4 + 20 + 8 + 0.67
                                Item {
                                    visible: taskRow.modelData.parent
                                    y: 4; width: 16; height: 20
                                    FluentIcon { anchors.centerIn: parent; size: 12; name: plan.collapsed[taskRow.modelData.t.task_id] ? "chevron-right-12" : "chevron-down-12"; color: theme.text }
                                    TapHandler {
                                        onTapped: { const o = Object.assign({}, plan.collapsed); o[taskRow.modelData.t.task_id] = !o[taskRow.modelData.t.task_id]; plan.collapsed = o }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                                Text {
                                    id: taskTitle
                                    x: taskRow.indent + 2 + 8; y: 8
                                    width: parent.width - x - 10
                                    wrapMode: Text.Wrap
                                    text: taskRow.modelData.t.title
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    font.family: theme.font; font.pixelSize: 14
                                    font.weight: taskRow.modelData.parent ? Font.DemiBold : Font.Normal
                                    color: theme.text
                                }
                                DueDate {
                                    visible: !!taskRow.modelData.t.due
                                    x: taskTitle.x; y: taskTitle.y + taskTitle.height + 4
                                    due: taskRow.modelData.t.due
                                }
                                Rectangle { y: parent.height - 0.67; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
                            }
                        }
                    }
                }
            }
            Flow {
                width: parent.width
                spacing: 8
                SmallButton {
                    visible: !plan.saved
                    primary: true
                    enabled_: !plan.busy
                    label: root.str(plan.c, "ODSL_DRAFTWORKBACKPLAN_CREATE_LABEL", qsTr("Save to Planner", "messaging:kamke6z31"))
                    onClicked: root.invoke(plan.e, { actionName: "SavePlan" })
                }
                SmallButton {
                    visible: !plan.saved
                    enabled_: !plan.busy
                    label: root.str(plan.c, "ODSL_ASK_FOR_CHANGES_LABEL", qsTr("Ask for changes", "messaging:ka50nowgh"))
                    onClicked: if (root.host) root.host.suggestedAction(root.message, { kind: "botMention", text: root.str(plan.c, "ODSL_MAKES_THESE_CHANGES_LABEL", qsTr("make these changes: ", "messaging:k7wpsucc3")) })
                }
                SmallButton {
                    id: planMore
                    visible: !plan.saved
                    enabled_: !plan.busy
                    glyph: "more-horizontal-20"
                    onClicked: { planMenu.parent = planMore; planMenu.x = 0; planMenu.y = planMore.height + 4; planMenu.open() }
                    MenuPopup {
                        id: planMenu
                        items: [{ label: root.str(plan.c, "ODSL_DRAFTWORKBACKPLAN_DISCARD_LABEL", qsTr("Discard", "messaging:k9qi4h5w7")), icon: "delete-20" }]
                        onPicked: i => root.invoke(plan.e, { actionName: "DiscardPlan" })
                    }
                }
                SmallButton {
                    visible: plan.saved
                    glyph: "open-20"
                    label: root.str(plan.c, "ODSL_VIEW_IN_PLANNER_LABEL", qsTr("View in Planner", "messaging:kd5n2nr8"))
                    onClicked: if (plan.c.plan_link) Qt.openUrlExternally(plan.c.plan_link)
                }
            }
        }
    }

    Component {
        id: tasksComp
        Column {
            id: tasks
            readonly property var e: parent ? parent.entry : null
            readonly property var c: e ? e.c : ({})
            width: parent ? parent.width : 0
            spacing: 8
            Repeater {
                model: tasks.c.tasks || []
                Rectangle {
                    id: taskCard
                    required property var modelData
                    readonly property string status: modelData.percent >= 100 ? "done" : modelData.percent > 0 ? "progress" : "new"
                    width: tasks.width
                    height: 8 + 19.3 + 4 + taskLink.height + 4 + 22.5 + 8 + 1.34
                    radius: 8
                    color: theme.surface
                    border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                    // The status tag.
                    Rectangle {
                        id: tag
                        x: 12.67; y: 8.67
                        width: tagRow.implicitWidth + 14 + 1.34; height: 19.3; radius: 4
                        color: theme.pick("#F5F5F5", "#333333", "#000000")
                        Row {
                            id: tagRow
                            anchors.centerIn: parent; spacing: 4
                            FluentIcon {
                                anchors.verticalCenter: parent.verticalCenter; size: 12
                                name: taskCard.status === "done" ? "checkmark-circle-16-filled" : taskCard.status === "progress" ? "circle-12" : "clock-12"
                                color: taskCard.status === "done" ? theme.pick("#107C10", "#54B054", "#3FF23F") : theme.text
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: taskCard.status === "done" ? qsTr("Completed", "messaging:k98ed46r9") : taskCard.status === "progress" ? qsTr("In progress", "messaging:k2bo8zkqt") : qsTr("Not started", "messaging:k1a0xblcv")
                                font.family: theme.font; font.pixelSize: 10
                                color: theme.textStrong
                            }
                        }
                        Accessible.role: Accessible.StaticText
                        Accessible.name: qsTr("Task status {{status}}", "messaging:k1as6clxi").replace("{{status}}", tagRow.children[1].text)
                    }
                    Text {
                        id: taskLink
                        x: 12.67; y: tag.y + tag.height + 4
                        width: parent.width - 25.34
                        wrapMode: Text.Wrap
                        maximumLineCount: 2; elide: Text.ElideRight
                        text: taskCard.modelData.title
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 12
                        font.underline: linkHover.hovered
                        color: theme.text
                        HoverHandler { id: linkHover; enabled: !!taskCard.modelData.link; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !!taskCard.modelData.link; onTapped: Qt.openUrlExternally(taskCard.modelData.link) }
                        Accessible.role: Accessible.Link; Accessible.name: text
                    }
                    Row {
                        x: 12.67; y: taskLink.y + taskLink.height + 4
                        spacing: 12
                        Row {
                            visible: (taskCard.modelData.assignments || []).length > 0
                            spacing: -4
                            Repeater {
                                model: (taskCard.modelData.assignments || []).slice(0, 3)
                                Avatar { required property var modelData; y: 2.5; size: 20; photoId: "8:orgid:" + modelData; name: root.nameOf("8:orgid:" + modelData) || "?" }
                            }
                        }
                        DueDate { visible: !!taskCard.modelData.due; due: taskCard.modelData.due; y: 1.25 }
                    }
                }
            }
        }
    }

    Component {
        id: questionsComp
        Column {
            id: ql
            readonly property var e: parent ? parent.entry : null
            readonly property var c: e ? e.c : ({})
            // Grouped by topic, in first-seen order.
            readonly property var groups: {
                const out = []
                for (const q of (c.questions || [])) {
                    let g = out.find(x => x.topic === q.topic)
                    if (!g) { g = { topic: q.topic, questions: [] }; out.push(g) }
                    g.questions.push(q)
                }
                return out
            }
            width: parent ? parent.width : 0
            spacing: 12
            Repeater {
                model: ql.groups
                Column {
                    id: group
                    required property var modelData
                    width: ql.width
                    spacing: 4
                    Text {
                        visible: !!group.modelData.topic
                        width: parent.width; wrapMode: Text.Wrap
                        text: group.modelData.topic
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    Repeater {
                        model: group.modelData.questions
                        Text {
                            required property var modelData
                            required property int index
                            width: group.width; wrapMode: Text.Wrap
                            textFormat: Text.StyledText
                            readonly property string who: (modelData.from || []).map(f => root.nameOf(f) || qsTr("Unknown user", "messaging:k5wwwkm51")).join(", ")
                            text: (index + 1) + ". " + String(modelData.question).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                + (who ? " <font color=\"" + theme.textSecondary + "\">- " + who.replace(/</g, "&lt;") + "</font>" : "")
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.text
                        }
                    }
                }
            }
        }
    }
}
