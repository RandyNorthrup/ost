import QtQuick

// Your video effects as every view shows them (Camera ▾, the pre-join
// picker, the Video effects and settings pane): the background, the blur
// kind, Adjust brightness, Soft focus and Mirror my video. They are
// settings, so they persist; backend applies them to the camera as they
// change (src/video_effects.rs). Teams' catalog is loaded on first use.
QtObject {
    id: fx
    /// "none", "blur", a catalog id or one of your uploads' uuid.
    property string background: backend.setting("videoBackground") || "none"
    property string blurKind: backend.setting("videoBlur") === "portrait" ? "portrait" : "standard"
    property bool brightness: backend.setting("adjustBrightness") === "true"
    property bool softFocus: backend.setting("softFocus") === "true"
    /// Teams mirrors your own preview unless you turn it off.
    property bool mirror: backend.setting("mirrorMyVideo") !== "false"
    property var catalog: []
    /// Your own backgrounds (Add new), oldest first: [{id, thumb}].
    property var uploads: []

    function load() {
        if (catalog.length === 0) catalog = JSON.parse(backend.videoBackgrounds())
        uploads = JSON.parse(backend.videoUploads())
    }
    property Connections watch: Connections {
        target: backend
        function onVideoBackgroundsReady() { fx.catalog = JSON.parse(backend.videoBackgrounds()) }
    }

    function setBackground(id) {
        background = id
        backend.setSetting("videoBackground", id)
    }
    function setBlur(kind) {
        blurKind = kind
        backend.setSetting("videoBlur", kind)
        setBackground("blur")
    }
    function setBrightness(on) { brightness = on; backend.setSetting("adjustBrightness", on ? "true" : "false") }
    function setSoftFocus(on) { softFocus = on; backend.setSetting("softFocus", on ? "true" : "false") }
    function setMirror(on) { mirror = on; backend.setSetting("mirrorMyVideo", on ? "true" : "false") }
    /// Teams' Add new with the chosen file's URL: the picture becomes one
    /// of your backgrounds and is applied. Teams' message for the banner.
    function addUpload(url) {
        const path = decodeURIComponent(String(url).replace(/^file:\/\//, ""))
        const r = JSON.parse(backend.addVideoBackground(path))
        if (r.error) return r.error
        uploads = JSON.parse(backend.videoUploads())
        setBackground(r.id)
        return "Background added."
    }
    function removeUpload(id) {
        if (!backend.removeVideoBackground(id)) return "Couldn't remove background."
        uploads = JSON.parse(backend.videoUploads())
        if (background === id) setBackground("none")
        return "Background removed."
    }
    readonly property string blurLabel: blurKind === "portrait" ? "Portrait blur" : "Standard blur"
}
