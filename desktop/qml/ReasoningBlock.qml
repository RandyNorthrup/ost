import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes

// An agent's "reasoning" ODSL statement (Teams 26304, 541316
// ReasoningCommandRenderer `Ru` / `Eu` / `xu`; a Channel Agent's answer
// measured on winpc 2026-11-22 in "OST TEST 206 agent I"), under the
// message's actions, 8 below them:
// - a header (a transparent Fluent button, padding 5 12 5 0): "Reasoned
//   for …" (the service's own REASONING_HEADER, else Teams' "Reasoned for
//   {n} seconds"; "Reasoning" while it is still going, for up to
//   projectAgentReasoningTimeoutMinutes after the message; "Reasoning
//   Results" with no duration), 14/20 #707070, wrapping, its 16 px chevron
//   6 after the text;
// - opened, 1 under it, a card (#FAFAFA, a #E0E0E0 hairline, radius 12,
//   padding 16) whose list scrolls within 208 (2 in), scrolled to its end:
//   each step 8 apart, a 20 px check (a spinner while it runs) and its
//   title 12 after it (14/20 #424242, wrapping; rows at least 28 tall),
//   with a 14 px chevron 4 from the end when it has substeps; a step opens
//   to its substeps (14/20 #616161, 44 in and 12 from the end, 8 apart),
//   a workflow's trigger step with "View workflow setup message".
// With enableChainOfThoughtNaturalLanguage off, Teams titles each step
// "Step N (Xs):" (bold) with its intents instead.
Column {
    id: root
    /// The statement as parsed (api::messages::reasoning_view).
    property var reasoning: ({})
    /// The message's time (ISO), for the "still reasoning" timeout.
    property string arrival: ""
    property bool open: false
    // Opened, the list shows its end (Teams scrolls to the newest step).
    onOpenChanged: if (open) Qt.callLater(() => list.contentY = Math.max(0, list.contentHeight - list.height))
    Component.onCompleted: if (open) Qt.callLater(() => list.contentY = Math.max(0, list.contentHeight - list.height))
    property var openSteps: ({})
    readonly property bool natural: backend.ecsSetting("extensibility", "enableChainOfThoughtNaturalLanguage") === "true"
    readonly property real timeoutMs: (Number(backend.ecsSetting("messaging", "projectAgentReasoningTimeoutMinutes")) || 10) * 60000
    readonly property bool timedOut: { const t = Date.parse(arrival); return !isNaN(t) && Date.now() > t + timeoutMs }
    readonly property bool active: !!reasoning.active && !timedOut
    function text(key, fallback, params) {
        let t = (reasoning.strings || {})[key.toUpperCase()] || fallback
        for (const k in (params || {})) t = t.split("{{" + k + "}}").join(params[k]).split("{" + k + "}").join(params[k])
        return t
    }
    readonly property bool hasDuration: reasoning.duration !== null && reasoning.duration !== undefined
    readonly property string header: active ? text("reasoning_active_state", qsTr("Reasoning", "messaging:k356onxo3"))
        : hasDuration ? text("reasoning_header", qsTr("Reasoned for {{duration}} seconds", "messaging:kbsi59914"), { duration: String(Math.floor(reasoning.duration / 1000)) })
        : text("reasoning_header_no_duration", qsTr("Reasoning Results", "messaging:kch0t590v"))
    readonly property var steps: natural
        ? (reasoning.steps || [])
        : (reasoning.iterations || []).map(i => ({ title: "<b>" + text("reasoning_iteration_title", qsTr("Step {{iterationString}}:", "messaging:k77q4cs63"), { iterationString: (i.number + 1) + " (" + i.seconds + "s)" }) + "</b>&nbsp;" + i.intents, active: i.active, substeps: [], rich: true }))
    /// The step being worked on (Teams shows it under the header while
    /// reasoning).
    readonly property string currentStep: { const a = (reasoning.steps || []).filter(s => s.active); return a.length ? a[a.length - 1].title : "" }
    spacing: 1
    /// The width the header wants (the bubble grows to it).
    readonly property real wanted: headText.implicitWidth + 0.67 + 12 + 6 + 19 + 0.67

    // Header.
    Item {
        id: head
        width: root.width
        height: headText.height + 10 + 1.33
        Text {
            id: headText
            x: 0.67; y: 5.67
            width: Math.min(implicitWidth, root.width - 0.67 - 12 - 6 - 19 - 0.67)
            text: root.header
            wrapMode: Text.Wrap
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 14
            color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
        }
        FluentIcon {
            x: headText.x + headText.width + 6 + 1.5; anchors.verticalCenter: headText.verticalCenter
            size: 16; name: root.open ? "chevron-up-16" : "chevron-down-16"
            color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.open = !root.open }
        Accessible.role: Accessible.Button
        Accessible.name: root.header
        Accessible.onPressAction: root.open = !root.open
    }
    // While reasoning: the current step under the header (measured on
    // winpc 2026-11-22: a 14 px orb, the step's title 8 after it, 14/20
    // #707070 on one line, right under the header).
    Row {
        visible: root.active && !root.open && root.currentStep !== ""
        width: root.width
        height: visible ? 20 : 0
        spacing: 8
        CotOrb { anchors.verticalCenter: parent.verticalCenter }
        Text {
            width: parent.width - 22
            text: root.currentStep
            elide: Text.ElideRight
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 14
            color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
        }
    }
    // The steps.
    Rectangle {
        visible: root.open
        width: root.width
        height: visible ? Math.min(208, stepCol.height + 4) + 32 + 1.33 : 0
        radius: 12
        color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
        border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
        Flickable {
            id: list
            x: 16.67; y: 16.67
            width: parent.width - 33.33; height: Math.min(208, stepCol.height + 4)
            contentHeight: stepCol.height + 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            Column {
                id: stepCol
                x: 2; y: 2
                width: list.width - 4
                spacing: 8
                Repeater {
                    model: root.steps
                    Column {
                        id: step
                        required property var modelData
                        required property int index
                        readonly property bool hasSubs: (modelData.substeps || []).length > 0
                        readonly property bool stepOpen: root.openSteps[index] === true
                        width: stepCol.width
                        spacing: 0
                        Item {
                            width: parent.width
                            height: Math.max(28, stepText.height)
                            Item {
                                width: 20; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                FluentIcon { visible: !step.modelData.active || !root.active; size: 20; name: "checkmark-circle-20"; color: theme.text }
                                Spinner20 { visible: !!step.modelData.active && root.active; anchors.centerIn: parent; size: 16 }
                            }
                            Text {
                                id: stepText
                                x: 32
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, parent.width - 32 - (step.hasSubs ? 18 : 0))
                                text: step.modelData.title
                                textFormat: step.modelData.rich ? Text.StyledText : Text.PlainText
                                wrapMode: Text.Wrap
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                                font.family: theme.font; font.pixelSize: 14
                                color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                            }
                            FluentIcon {
                                visible: step.hasSubs
                                x: parent.width - 14; anchors.verticalCenter: parent.verticalCenter
                                size: 14; name: step.stepOpen ? "chevron-down-16" : "chevron-right-16"
                                color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
                            }
                            HoverHandler { enabled: step.hasSubs; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                enabled: step.hasSubs
                                onTapped: { const o = Object.assign({}, root.openSteps); o[step.index] = !step.stepOpen; root.openSteps = o }
                            }
                            Accessible.role: step.hasSubs ? Accessible.Button : Accessible.StaticText
                            Accessible.name: stepText.text
                        }
                        Column {
                            visible: step.stepOpen
                            x: 44; width: parent.width - 44 - 12
                            spacing: 8
                            Repeater {
                                model: step.stepOpen ? step.modelData.substeps : []
                                Column {
                                    required property var modelData
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        width: parent.width
                                        text: modelData.title
                                        wrapMode: Text.Wrap
                                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                                        font.family: theme.font; font.pixelSize: 14
                                        color: theme.textSecondary
                                    }
                                    // A workflow's trigger step: its setup message.
                                    Rectangle {
                                        visible: !!modelData.link
                                        width: Math.min(parent.width, setupRow.implicitWidth + 24); height: 32
                                        radius: 4
                                        color: setupHover.hovered ? theme.rowHover : theme.surface
                                        border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                                        Row {
                                            id: setupRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root.text("reasoning_message_link", qsTr("View workflow setup message", "messaging:k4jkg2njx"))
                                                elide: Text.ElideRight
                                                font.family: theme.font; font.pixelSize: 14
                                                color: theme.text
                                            }
                                        }
                                        HoverHandler { id: setupHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: backend.openExternal(String(modelData.link)) }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: root.text("reasoning_message_link", qsTr("View workflow setup message", "messaging:k4jkg2njx"))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Fluent's small spinner.
    component Spinner20: Item {
        property real size: 16
        width: size; height: size
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: 2; strokeColor: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF"); fillColor: "transparent"
                PathAngleArc { centerX: size / 2; centerY: size / 2; radiusX: size / 2 - 1; radiusY: size / 2 - 1; startAngle: 0; sweepAngle: 360 } }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: 2; strokeColor: theme.brand; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: size / 2; centerY: size / 2; radiusX: size / 2 - 1; radiusY: size / 2 - 1; startAngle: -90; sweepAngle: 100 } }
            RotationAnimator on rotation { from: 0; to: 360; duration: 1500; loops: Animation.Infinite; running: parent.visible }
        }
    }

    // Fluent AI's chain-of-thought latency animation (fai-CoTLatencyAnimation,
    // Teams 26304 758615 and its griffel keyframes f6ywpep / f8shvhy /
    // f9fqfen): three 14 px circles with horizontal gradients (#d161aa to
    // #e96d80, #42a3a6 to #73af69, #65a5dd to #8173ee) that take turns
    // growing in from the left and shrinking out to the right, 3.6 s a
    // cycle, each step eased cubic-bezier(0.8, 0, 0.2, 1).
    component CotOrb: Item {
        id: orb
        width: 14; height: 14
        property real t: 0
        NumberAnimation on t { from: 0; to: 1; duration: 3600; loops: Animation.Infinite; running: orb.visible }
        // cubic-bezier(0.8, 0, 0.2, 1) at x in [0, 1].
        function ease(x) {
            let lo = 0, hi = 1, u = x
            for (let i = 0; i < 24; i++) {
                u = (lo + hi) / 2
                const bx = 3 * (1 - u) * (1 - u) * u * 0.8 + 3 * (1 - u) * u * u * 0.2 + u * u * u
                if (bx < x) lo = u; else hi = u
            }
            return 3 * (1 - u) * u * u + u * u * u
        }
        // Keyframes [[offset, opacity, translateX %, scale]] at t.
        function at(frames, t) {
            for (let i = 0; i < frames.length - 1; i++) {
                const a = frames[i], b = frames[i + 1]
                if (t >= a[0] && t <= b[0]) {
                    const k = b[0] > a[0] ? ease((t - a[0]) / (b[0] - a[0])) : 0
                    return [a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k]
                }
            }
            const l = frames[frames.length - 1]
            return [l[1], l[2], l[3]]
        }
        readonly property var dots: [
            { c1: "#d161aa", c2: "#e96d80", f: [[0, 1, 0, 1], [0.1667, 0, 50, 0], [0.5, 0, -50, 0], [0.6667, 0, -50, 0], [0.8333, 1, 0, 1], [1, 1, 0, 1]] },
            { c1: "#42a3a6", c2: "#73af69", f: [[0, 1, -50, 0], [0.1667, 1, 0, 1], [0.3333, 1, 0, 1], [0.5, 0, 50, 0], [0.6667, 0, -50, 0], [1, 1, -50, 0]] },
            { c1: "#65a5dd", c2: "#8173ee", f: [[0, 0, -50, 0], [0.1667, 0, -50, 0], [0.3333, 1, -50, 0], [0.5, 1, 0, 1], [0.6667, 1, 0, 1], [0.8333, 0, 50, 0], [1, 0, 0, 0]] }
        ]
        Repeater {
            model: orb.dots
            Rectangle {
                id: dot
                required property var modelData
                readonly property var v: orb.at(modelData.f, orb.t)
                width: 14; height: 14; radius: 7
                opacity: v[0]
                transform: [Scale { origin.x: 7; origin.y: 7; xScale: dot.v[2]; yScale: dot.v[2] }, Translate { x: 14 * dot.v[1] / 100 }]
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: dot.modelData.c1 }
                    GradientStop { position: 1; color: dot.modelData.c2 }
                }
            }
        }
        Accessible.role: Accessible.ProgressBar
    }
}
