import QtQuick

// Design tokens measured from the Teams desktop/web client (1280x800, 1x).
QtObject {
    readonly property color brand: "#5B5FC7"
    readonly property color brandHover: "#4F52B2"
    readonly property color brandTint: "#E8EBFA"
    readonly property color chrome: "#EBEBEB"        // title bar, app rail
    readonly property color pane: "#F5F5F5"          // list pane, other bubbles
    readonly property color surface: "#FFFFFF"
    readonly property color searchFill: "#FAFAFA"
    readonly property color divider: "#E0E0E0"
    readonly property color dividerSoft: "#EBEBEB"
    readonly property color stroke: "#D1D1D1"
    readonly property color hover: "#E0E0E0"
    readonly property color text: "#242424"
    readonly property color textSecondary: "#616161"
    readonly property color textTertiary: "#707070"
    readonly property color icon: "#424242"
    readonly property color badge: "#C4314B"
    readonly property color danger: "#C4314B"

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
