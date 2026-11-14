import QtQuick

// Your video effects as every view shows them (Camera ▾, the pre-join
// picker, the Video effects and settings pane): the background, the blur
// kind, Adjust brightness, Soft focus and Mirror my video. They are
// settings, so they persist; backend applies them to the camera as they
// change (src/video_effects.rs). Teams' catalog is loaded on first use.
QtObject {
    id: fx
    /// "none", "blur" or a catalog id.
    property string background: backend.setting("videoBackground") || "none"
    property string blurKind: backend.setting("videoBlur") === "portrait" ? "portrait" : "standard"
    property bool brightness: backend.setting("adjustBrightness") === "true"
    property bool softFocus: backend.setting("softFocus") === "true"
    /// Teams mirrors your own preview unless you turn it off.
    property bool mirror: backend.setting("mirrorMyVideo") !== "false"
    property var catalog: []

    function load() {
        if (catalog.length === 0) catalog = JSON.parse(backend.videoBackgrounds())
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
    readonly property string blurLabel: blurKind === "portrait" ? "Portrait blur" : "Standard blur"
}
