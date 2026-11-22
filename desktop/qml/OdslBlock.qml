import QtQuick

// An agent's Action.ODSL suggested actions as Teams' suggested-action-odsl
// chunk draws them (Teams 26304, 50945 `Q` / `j`):
// - only for agents Teams knows (Copilot apps such as the Facilitator, a
//   Channel Agent, chat agents, agentic users), with ODSL processing on
//   (extensibility enableSuggestedActionODSLProcessing) and its command
//   list set (enableSuggestedActionODSLCommandNames, plus the commands
//   other flags add); otherwise Teams' note that some interactions aren't
//   available (the Facilitator's own note for the Facilitator; on the
//   first action only);
// - each statement whose command is enabled is drawn by its renderer: a
//   "reasoning" one as ReasoningBlock; one that isn't enabled gets the
//   same note;
// - an action with no statements (a Channel Agent's "paMetrics") draws
//   nothing.
// Teams draws the reasoning in its own slot under the actions; the notes
// sit with the actions.
Column {
    id: root
    property var message: ({})
    /// SeeMoreRules (the agent lists).
    property var rules: null
    /// Show the reasoning opened (the harness).
    property bool openReasoning: false
    spacing: 8
    function setting(ns, key, dflt) {
        const v = backend.ecsSetting(ns, key)
        if (v === "") return dflt
        try { return JSON.parse(v) } catch (e) { return dflt }
    }
    readonly property bool processing: setting("extensibility", "enableSuggestedActionODSLProcessing", true) === true
    readonly property var commandNames: setting("extensibility", "enableSuggestedActionODSLCommandNames",
        ["tasks", "meetingDocument", "taskExecutionProgress", "openNotes", "createMeeting", "createOvertimeMeeting", "agendaTimer", "questionsList", "proactiveDocGenOffer"])
    readonly property var enabledNames: {
        const n = Array.isArray(commandNames) ? commandNames.slice() : []
        if (setting("extensibility", "enableAvTechSupportBrbMessage", false) === true) n.push("avTechSupport")
        if (setting("messaging", "enableChatAgentPreviewMessage", false) === true) n.push("teamsChatAgentPreview")
        if (setting("messaging", "enableChannelAgentTabUI", false) === true) n.push("channelAgentPreferencesAndSkills")
        if (setting("messaging", "enableStopPowerAutomateFlow", true) === true) n.push("stopPowerAutomateFlow")
        if (setting("virtualEvents", "enableTownhallModeratorHub", false) === true) n.push("openModeratorHub")
        return n
    }
    readonly property string bot: String(message.sender_mri || "").indexOf("28:") === 0 ? String(message.sender_mri).slice(3).toLowerCase() : ""
    readonly property bool facilitator: !!rules && bot !== "" && rules.copilotApps.indexOf(bot) >= 0
    readonly property var chatAgentBots: { const l = setting("messaging", "chatAgentBotIds", ["a812e88f-ee42-44ce-945c-56a54119eb28", "1f596be5-e7dc-4c5c-886f-655908ec77b1"]); return Array.isArray(l) ? l.map(x => String(x).toLowerCase()) : [] }
    readonly property bool agent: !!rules && bot !== "" && (facilitator || rules.projectAgentBots.indexOf(bot) >= 0 || chatAgentBots.indexOf(bot) >= 0)
    /// What to draw, in order: {kind: "note", text} or {kind: "reasoning", reasoning}.
    readonly property var parts: {
        const out = []
        const all = message.suggested || []
        all.forEach((a, i) => {
            if (a.kind !== "odsl") return
            const note = facilitator ? qsTr("Some content isn't showing because your Teams setup doesn't support it. If you reply to this message, Facilitator won't be able take any action.", "messaging:k49yd8toa")
                : i === 0 ? qsTr("Some interactions may not be available because of your Teams setup.", "messaging:kc7lkaja3") : ""
            if (!processing || !Array.isArray(commandNames) || !agent) { if (note) out.push({ kind: "note", text: note }); return }
            for (const st of (a.statements || [])) {
                if (enabledNames.indexOf(st.name) < 0) { if (note) out.push({ kind: "note", text: note }); continue }
                if (st.name === "reasoning" && st.reasoning) out.push({ kind: "reasoning", reasoning: st.reasoning })
            }
        })
        // Teams draws the reasoning after the rest.
        return out.filter(p => p.kind !== "reasoning").concat(out.filter(p => p.kind === "reasoning"))
    }
    readonly property bool shown: parts.length > 0
    /// The width it wants (the bubble grows to it).
    readonly property real wanted: { let w = 0; for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it) w = Math.max(w, it.wanted || 0) } return w }

    Repeater {
        id: rep
        model: root.parts
        Loader {
            id: part
            required property var modelData
            readonly property real wanted: item ? item.wanted : 0
            width: root.width
            sourceComponent: modelData.kind === "note" ? noteComp : reasoningComp
            Component {
                id: noteComp
                Text {
                    readonly property real wanted: implicitWidth
                    width: part.width
                    text: part.modelData.text
                    wrapMode: Text.Wrap
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
            }
            Component {
                id: reasoningComp
                ReasoningBlock {
                    width: part.width
                    reasoning: part.modelData.reasoning
                    arrival: root.message.time || ""
                    open: root.openReasoning
                }
            }
        }
    }
}
