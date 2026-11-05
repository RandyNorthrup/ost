import QtQuick

// Design tokens, read from the Teams desktop client (its Fluent CSS
// variables and computed colours, light and dark, at 1x).
QtObject {
    /// Dark theme on: chosen in Settings > Appearance, or the system's.
    property bool dark: false
    function pick(light, darkValue) { return dark ? darkValue : light }

    // Brand
    readonly property color brand: pick("#5B5FC7", "#7F85F5")          // BrandForeground1 / indicators
    readonly property color brandFill: pick("#5B5FC7", "#4F52B2")      // BrandBackground (buttons)
    readonly property color brandHover: pick("#4F52B2", "#5B5FC7")
    readonly property color brandTint: pick("#E8EBFA", "#2B2B40")      // your bubbles
    readonly property color textOnBrand: "#FFFFFF"

    // Surfaces
    readonly property color chrome: pick("#EBEBEB", "#0A0A0A")         // title bar, app rail
    readonly property color pane: pick("#F5F5F5", "#1A1A1A")           // list panes
    readonly property color surface: pick("#FFFFFF", "#1F1F1F")        // conversation, cards
    readonly property color mentionMe: pick("#DA3B01", "#F48E64")      // your name where you're @mentioned
    readonly property color channelPage: pick("#FAFAFA", "#141414")    // behind channel post cards
    readonly property color cardEdge: pick("#E3E3E3", "#383838")       // channel post card outline
    readonly property color bubble: pick("#F5F5F5", "#292929")         // others' bubbles
    readonly property color input: pick("#FFFFFF", "#292929")          // compose box
    readonly property color selected: pick("#FFFFFF", "#242424")       // the open row in a pane
    readonly property color rowHover: pick("#EBEBEB", "#2E2E2E")
    readonly property color searchFill: pick("#FAFAFA", "#242424")
    readonly property color menu: pick("#FFFFFF", "#292929")           // flyouts, tooltips

    // Lines
    readonly property color divider: pick("#E0E0E0", "#525252")        // NeutralStroke2
    readonly property color dividerSoft: pick("#EBEBEB", "#3D3D3D")    // NeutralStroke3
    readonly property color stroke: pick("#D1D1D1", "#666666")         // NeutralStroke1 (chips)
    readonly property color strokeHover: pick("#C7C7C7", "#757575")
    readonly property color edge: pick("#EFEFEF", "#232323")           // between panes
    readonly property color titleHairline: pick("#DDDDDD", "#1F1F1F")

    // Hover on chrome
    readonly property color hover: pick("#E0E0E0", "#2E2E2E")

    // Text and icons
    readonly property color text: pick("#242424", "#FFFFFF")           // NeutralForeground1
    readonly property color textStrong: pick("#424242", "#D6D6D6")     // NeutralForeground2
    readonly property color textSecondary: pick("#616161", "#ADADAD")  // NeutralForeground3
    readonly property color textTertiary: pick("#707070", "#999999")   // NeutralForeground4
    readonly property color disabled: pick("#BDBDBD", "#5C5C5C")
    readonly property color icon: pick("#424242", "#D6D6D6")
    readonly property color badge: "#C4314B"
    readonly property color danger: pick("#C4314B", "#E37D80")
    readonly property color unreadTint: pick("#FDF3F4", "#3E1F25")

    // Calls use the dark stage in every theme, as in Teams.
    readonly property color stage: "#1F1F1F"
    readonly property color stageBar: "#292929"
    readonly property color stageTile: "#2E2E2E"
    readonly property color stageText: "#FFFFFF"
    readonly property color stageTextSecondary: "#ADADAD"
    readonly property color stageControlHover: "#3D3D3D"
    readonly property color accept: "#107C10"
    readonly property color acceptHover: "#0E700E"
    readonly property color leave: "#C4314B"
    readonly property color leaveHover: "#B12C44"

    readonly property string font: "Selawik"
    readonly property int base: 14
    readonly property int small: 12
    readonly property int caption: 10
    readonly property int title: 18

    readonly property int titleBarHeight: 48
    readonly property int railWidth: 68
    readonly property int listWidth: 320
    readonly property int headerHeight: 61
    readonly property int radius: 4
}
