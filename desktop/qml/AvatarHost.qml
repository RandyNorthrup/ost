import QtQuick

// Teams' avatars renderer: Microsoft's Avatars video app (Teams' ECS
// avatarAppId), hosted as Teams desktop hosts it, out of sight, on OST's
// TeamsJS host (WebApp's teamsHost, frameContext sidePanel): it signs in
// by nested app auth, keeps your avatars with Mesh, lists them to the
// host (video.personalizedEffectsChanged) and draws the chosen one into
// the camera-less frames OST gives it on WebView2's texture-stream path,
// each with its viseme model's newest result from your microphone
// (src/avatars.rs, vfx/src/avatar.rs). Choosing an avatar and background
// is Teams' video.effectParameterChange [avatarId, backgroundId].
Item {
    id: host
    /// {appId, url, studio, name} from the app's definition.
    property var app: ({})
    /// Run the app (Teams loads it while avatars can be shown: avatar
    /// mode, the Avatars tabs).
    property bool wanted: false
    readonly property bool running: wanted && !!app.url && backend.signedIn
    /// The chosen avatar and its background ("" for none).
    property string avatarId: ""
    property string backgroundId: ""
    /// Your avatars and their backgrounds as the app lists them (Teams'
    /// avatarInfo.avatarItems): [{id, type ("avatar"/"background"),
    /// name, thumbnail}].
    property var items: []
    readonly property var avatars: items.filter(i => i.type === "avatar")
    readonly property var backgrounds: items.filter(i => i.type === "background")
    /// The app has asked for frames.
    property bool registered: false
    /// The app takes effect choices (video.registerForVideoEffect): Teams
    /// then sends the chosen avatar; the app builds it and asks for frames.
    property bool effectRegistered: false
    /// The app has applied the chosen avatar (its first frame with it).
    property bool applied: false
    property bool listed: false
    /// The meeting chat of the call, for the app's context.
    property string thread: ""
    signal hostEvent(string name, string json)
    width: 16; height: 16
    opacity: 0.01

    function select(avatar, background) {
        avatarId = avatar || ""
        backgroundId = background || ""
        applied = false
        if (effectRegistered) apply()
    }
    /// Teams' video.effectParameterChange: the avatar and its background,
    /// "microsoft_none" for none (what Teams' renderer receives).
    function apply() {
        send("video.effectParameterChange", [avatarId, backgroundId || "microsoft_none"])
    }
    /// Muted: Teams tells the app to drop the audio inference result
    /// (video.mediaStream.audioInferenceDiscardStatusChange), and OST's
    /// lip sync rests.
    property bool muted: false
    onMutedChanged: { backend.setAvatarMuted(muted); send("video.mediaStream.audioInferenceDiscardStatusChange", [{ discardAudioInferenceResult: muted }]) }
    /// Your own meeting reaction (like, heart, laugh, surprised,
    /// applause): the app plays it as an emote.
    function reaction(type) { send("meeting.meetingReactionReceived", [{ meetingReactionType: type }]) }
    /// Teams' events to video apps (video.inPreview, video.videoOn,
    /// video.isMuted, video.teamsCallId, meeting reactions…).
    function send(func, args) { if (loader.item) loader.item.sendFrameMessage(func, args) }

    Loader {
        id: loader
        anchors.fill: parent
        active: host.running
        onActiveChanged: if (!active) { host.registered = false; host.effectRegistered = false; host.applied = false }
        sourceComponent: WebApp {
            appName: host.app.name || "Avatars"
            appId: host.app.appId || ""
            teamsHost: true
            showHeader: false
            frameContext: "sidePanel"
            hostThread: host.thread
            homeTemplate: host.app.url || ""
            // Teams desktop's video extensibility: WebView2's texture
            // streams; meetings for the reactions the app plays as emotes.
            runtimeSupports: ({ video: { mediaStream: {}, sharedFrame: {} }, meeting: {} })
            videoApp: ({ socket: backend.avatarSocket(), appOrigin: "https://mesh.public.onecdn.static.microsoft" })
            frameScript: (Qt.application.arguments.indexOf("--avatar-test") >= 0 ? "window.__ostDebug = 1;\n" : "") + backend.videoAppFrameScript()
            onHostEvent: (name, json) => {
                let a = null
                try { a = JSON.parse(json) } catch (e) {}
                if (name === "personalizedEffects") {
                    host.items = (a || []).map(e => ({ id: String(e.id || ""), type: String(e.type || ""), name: String(e.name || ""), thumbnail: String(e.thumbnail || "") }))
                    host.listed = true
                    console.info("AVATARS listed " + host.avatars.length + " avatars, " + host.backgrounds.length + " backgrounds")
                } else if (name === "videoRegistered") {
                    host.registered = true
                    console.info("AVATARS registered for frames " + json)
                } else if (name === "videoEffectRegistered") {
                    host.effectRegistered = true
                    if (host.avatarId) host.apply()
                } else if (name === "videoEffectReadiness") {
                    host.applied = !!(a && a[0])
                    console.info("AVATARS readiness " + json)
                } else console.info("AVATARS " + name)
                host.hostEvent(name, json)
            }
        }
    }
}
