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
    /// The chosen filter (Teams' Custom Filters app), "" for none.
    property string filter: backend.setting("videoFilter") || ""
    /// The app's page and filters: {url, filters: [{id, name, category,
    /// thumb}]}.
    property var filters: ({})
    /// Teams' quick-picker filters (videoEffectsQuickPickerFilters, the
    /// Custom Filters ones: Sweet, Animated purple gradient, Blue waves).
    readonly property var quickFilterIds: ["a0d54440-381e-4328-baf9-bf0323b4b39c", "8e94f1b1-4eca-49a2-96ba-80485b8d17e9", "b46b3bf9-f679-4547-9787-e5731deb6fc5"]
    readonly property var quickFilters: (filters.filters || []).filter(f => quickFilterIds.indexOf(f.id) >= 0)
        .sort((a, b) => quickFilterIds.indexOf(a.id) - quickFilterIds.indexOf(b.id))

    function load() {
        if (catalog.length === 0) catalog = JSON.parse(backend.videoBackgrounds())
        uploads = JSON.parse(backend.videoUploads())
        if (!filters.url) filters = JSON.parse(backend.videoFilters())
    }
    property Connections watch: Connections {
        target: backend
        function onVideoBackgroundsReady() { fx.catalog = JSON.parse(backend.videoBackgrounds()) }
        function onVideoFiltersReady() { fx.filters = JSON.parse(backend.videoFilters()) }
    }
    // A filter chosen in an earlier run needs the app's page.
    Component.onCompleted: if (filter.length > 0) filters = JSON.parse(backend.videoFilters())
    function setFilter(id) {
        filter = id
        backend.setSetting("videoFilter", id)
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
    /// Teams' Green Screen (Settings ▸ Devices) and your backdrop colour
    /// ("#RRGGBB", "" until you pick one: then the detected one is used).
    property bool greenScreen: backend.setting("greenScreen") === "true"
    property string greenScreenColor: backend.setting("greenScreenColor") || ""
    property string detectedColor: ""
    function setGreenScreen(on) { greenScreen = on; backend.setSetting("greenScreen", on ? "true" : "false") }
    function setGreenScreenColor(c) { greenScreenColor = c; backend.setSetting("greenScreenColor", c) }
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
