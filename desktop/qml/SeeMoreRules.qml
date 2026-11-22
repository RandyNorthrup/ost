import QtQuick

// Which messages Teams cuts with "see more", and where (Teams 26304; ECS
// settings over Teams' own defaults, config-prod):
// - Posts channels, the posts list (395276 `nn` / `fn`): a post's text is
//   cut at 200 px (seeMoreThresholdValueForPost, unless
//   enableDefaultExpandedPostMessage), a reply's at 80
//   (channelPaneSeeMoreTruncationThreshold), a Channel Agent's reply at 140
//   (projectAgentReplyTruncationThreshold). A message with cards keeps its
//   text whole (enableSeeMoreExperienceForCardsInChannels: its cards are
//   cut instead). Opening a post (its reply chain) shows everything.
// - Chats and threads channels (349533 `_shouldMessageBeCompacted`, `cs`):
//   only an agent's messages, cut at 220 (chatPaneSeeMoreTruncationThreshold)
//   with a fade and "See more": a Channel Agent's (projectAgentBotIds,
//   teamAgentGlobalAppId; enableSeeMoreForChannelAgentMessages), a Copilot
//   app's in a channel (copilotAppsIds), a chat agent's
//   (chatAgentCopilotBotIds; enableSeeMoreForChatAgentMessages), the
//   Facilitator's answers in a meeting chat
//   (enableSeeMoreForFacilitatorMessages: QuestionsSummarization,
//   MeetingsQnA, ChatQnA, WebSearch, ProactiveQnA; all of its messages with
//   enableSeeMoreForAllFacilitatorMessages), any bot's with
//   enableSeeMoreForBotMessages, and every top-level message of a threads
//   channel with enableSeeMoreButtonThreadedChannels.
QtObject {
    id: rules
    function setting(ns, key, dflt) {
        const v = backend.ecsSetting(ns, key)
        if (v === "") return dflt
        try { return JSON.parse(v) } catch (e) { return dflt }
    }
    function on(ns, key, dflt) { return setting(ns, key, dflt) === true }
    function num(ns, key) { const v = setting(ns, key, null); return typeof v === "number" && v > 0 ? v : 0 }
    function list(ns, key, dflt) { const v = setting(ns, key, dflt); return Array.isArray(v) ? v.map(x => String(x).toLowerCase()) : [] }
    function botId(m) { return String(m && m.sender_mri || "").indexOf("28:") === 0 ? String(m.sender_mri).slice(3).toLowerCase() : "" }

    readonly property var projectAgentBots: list("messaging", "projectAgentBotIds", ["3cf96df7-3ecf-460a-a065-d1ca251969e4", "3914e2ec-62b6-4dec-96c1-5710a9c532ef"])
    readonly property string teamAgentApp: String(setting("messaging", "teamAgentGlobalAppId", "910a971c-0c2a-4a1a-a400-87f760622aee")).toLowerCase()
    readonly property var copilotApps: list("messaging", "copilotAppsIds", ["8e55a7b1-6766-4f0a-8610-ecacfe3d569a"])
    readonly property var chatAgentBots: list("messaging", "chatAgentCopilotBotIds", ["4046041d-19bb-4afe-a8d6-f464d894f139", "1f596be5-e7dc-4c5c-886f-655908ec77b1"])

    /// A Channel Agent's message (Teams' isProjectAgent: its bot, or the
    /// team agent's app).
    function projectAgent(m) {
        const b = botId(m)
        return (b !== "" && projectAgentBots.indexOf(b) >= 0) || (!!m && String(m.sender_app || "").toLowerCase() === teamAgentApp && teamAgentApp !== "")
    }

    /// Posts list: the height a post (or reply) is cut at; 0 when it isn't.
    function postLimit(m, isReply) {
        if (!m || m.deleted || (m.cards || []).length > 0 && on("extensibility", "enableSeeMoreExperienceForCardsInChannels", true)) return 0
        if (isReply) {
            if (projectAgent(m)) return num("messaging", "projectAgentReplyTruncationThreshold") || 140
            return num("channels", "channelPaneSeeMoreTruncationThreshold") || 80
        }
        if (on("channels", "enableDefaultExpandedPostMessage", false)) return 0
        return num("channels", "seeMoreThresholdValueForPost") || 200
    }

    /// Chats and threads: the height an agent's message is cut at (0: not).
    /// `kind`: "chat", "meeting" or "channel"; `topLevel`: not a reply in a
    /// thread.
    function chatLimit(m, kind, topLevel) {
        if (!m || m.deleted || m.mine) return 0
        const b = botId(m)
        const cut = num("messaging", "chatPaneSeeMoreTruncationThreshold") || 220
        if (kind === "channel" && topLevel && on("channels", "enableSeeMoreButtonThreadedChannels", false)) return cut
        if (kind === "meeting" && (m.bot_kind || "") !== "") {
            if (on("meetingConversation", "enableSeeMoreForAllFacilitatorMessages", false)) return cut
            if (on("meetingConversation", "enableSeeMoreForFacilitatorMessages", false)
                && ["QuestionsSummarization", "MeetingsQnA", "ChatQnA", "WebSearch", "ProactiveQnA"].indexOf(m.bot_kind) >= 0) return cut
        }
        if (b !== "" && on("messaging", "enableSeeMoreForChatAgentMessages", false) && chatAgentBots.indexOf(b) >= 0) return cut
        if (on("messaging", "enableSeeMoreForChannelAgentMessages", false)
            && (projectAgent(m) || (kind === "channel" && b !== "" && copilotApps.indexOf(b) >= 0))) return cut
        if (b !== "" && on("messaging", "enableSeeMoreForBotMessages", false)) return cut
        return 0
    }
}
