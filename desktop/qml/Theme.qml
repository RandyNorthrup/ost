import QtQuick

// Design tokens, read from the Teams desktop client (its Fluent CSS
// variables and computed colours, light and dark, at 1x).
QtObject {
    /// Dark theme on: chosen in Settings > Appearance, or the system's.
    property bool dark: false
    function pick(light, darkValue) { return dark ? darkValue : light }
    // Message HTML as shown: a shared contact's card icon in brand colour.
    // Headings as paragraphs of class h1-h3: Qt adds its own heading size on
    // top of a stylesheet's, so only Teams' measured sizes apply this way.
    function messageHtml(h) {
        return String(h || "").replace(/src="ost-contact-card"/g, 'style="vertical-align: middle" src="' + Qt.resolvedUrl("../assets/icons/contact-card-inline-" + (dark ? "dark" : "light") + ".svg") + '"')
            .replace(/<h([123])>/g, '<p class="h$1">').replace(/<\/h[123]>/g, "</p>")
    }

    // Find in chat's highlight (Teams' mark: #F9E2AE behind #242424, light
    // and dark alike).
    readonly property color findMark: "#F9E2AE"
    // Words starting with one of the terms (Teams marks "OST" in "OST's",
    // not in "post"): group 1 is what comes before, group 2 the term.
    function termPattern(terms) {
        const t = (terms || []).filter(x => !!x).map(x => String(x).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
        return t.length ? new RegExp("(^|[^A-Za-z0-9_])(" + t.join("|") + ")", "gi") : null
    }
    // HTML with the search terms marked in its text (not inside tags).
    function markTerms(h, terms) {
        const re = termPattern(terms)
        if (!re) return h
        return String(h || "").replace(/(<[^>]*>)|([^<]+)/g, (m, tag, text) => tag ? tag
            : text.replace(re, '$1<span style="background-color:' + findMark + '; color:#242424">$2</span>'))
    }

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
    // Teams' announcement colour schemes "0".."11" (443282 module 8196):
    // the palette's Background2 / Foreground2 (light: tint, shade; dark the
    // other way round), the first six light on dark text, the rest dark.
    readonly property var bannerPalette: [["#A9D3F2", "#004377"], ["#D2CCF8", "#3F3682"], ["#F7C0E3", "#80215D"],
                                          ["#F4BFAB", "#7A2101"], ["#ECDFA5", "#6C5700"], ["#BDD99B", "#294903"]]
    readonly property var bannerNames: dark
        ? ["Aegean blue", "Midnight purple", "Sangria", "Espresso", "Gothic gold", "Space green", "Cornflower blue", "Thistle purple", "Pink", "Coral", "Mellow yellow", "Jade"]
        : ["Periwinkle Blue", "Lavender", "Rose", "Orange sherbet", "Flax yellow", "Teal", "Navy blue", "Indigo", "Mulberry red", "Fire orange", "Raw umber", "Ocean green"]
    // [background, text] of scheme `t`.
    function banner(t) {
        let i = parseInt(t, 10); if (isNaN(i) || i < 0 || i > 11) i = 0
        const pair = bannerPalette[i % 6]
        const bg2 = dark ? pair[1] : pair[0], fg2 = dark ? pair[0] : pair[1]
        return i < 6 ? [bg2, fg2] : [fg2, bg2]
    }
    readonly property color bubble: pick("#F5F5F5", "#292929")         // others' bubbles
    readonly property color input: pick("#FFFFFF", "#292929")          // compose box
    readonly property color selected: pick("#FFFFFF", "#242424")       // the open row in a pane
    readonly property color rowHover: pick("#EBEBEB", "#2E2E2E")
    readonly property color searchFill: pick("#FAFAFA", "#242424")
    readonly property color menu: pick("#FFFFFF", "#292929")           // flyouts, tooltips
    readonly property color menuHover: pick("#F5F5F5", "#3D3D3D")      // NeutralBackground1Hover (menu items)
    readonly property color inputFilled: pick("#F5F5F5", "#141414")    // filled-darker inputs (dialogs)
    readonly property color pressed: pick("#E0E0E0", "#1F1F1F")        // NeutralBackground1Pressed
    readonly property color quoteFill: pick("#FAFAFA", "#1F1F1F")      // NeutralBackground2 (quote cards)
    readonly property color selectionFill: pick("#B4D5FE", "#264F78")  // selected text
    readonly property color quoteBorder: pick("#F0F0F0", "#3D3D3D")    // NeutralStroke3
    readonly property color quoteBar: pick("#C7C7C7", "#757575")       // NeutralStroke1Hover
    readonly property color brandLink: pick("#4F52B2", "#9EA2FF")      // transparent brand buttons ("About")
    // Fluent shadows: two layers each (ambient, key), as the client's CSS.
    readonly property color shadowAmbient: pick(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(0, 0, 0, 0.24))
    readonly property color shadowKey: pick(Qt.rgba(0, 0, 0, 0.14), Qt.rgba(0, 0, 0, 0.28))

    // Lines
    readonly property color divider: pick("#E0E0E0", "#525252")        // NeutralStroke2
    readonly property color dividerSoft: pick("#EBEBEB", "#3D3D3D")    // NeutralStroke3
    readonly property color stroke: pick("#D1D1D1", "#666666")         // NeutralStroke1 (chips)
    readonly property color strokeHover: pick("#C7C7C7", "#757575")
    readonly property color strokePressed: pick("#B3B3B3", "#6B6B6B")       // NeutralStroke1Pressed
    readonly property color strokeAccessibleHover: pick("#575757", "#BDBDBD")   // NeutralStrokeAccessibleHover
    readonly property color strokeAccessiblePressed: pick("#4D4D4D", "#B3B3B3") // NeutralStrokeAccessiblePressed
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
    readonly property color bgDisabled: pick("#F0F0F0", "#141414")     // NeutralBackgroundDisabled
    readonly property color editorFilled: pick("#EBEBEB", "#1F1F1F")   // Teams' status-note editor (CKEditor)
    readonly property color icon: pick("#424242", "#D6D6D6")
    readonly property color badge: "#C4314B"
    readonly property color danger: pick("#C4314B", "#E37D80")
    readonly property color redForeground1: pick("#BC2F32", "#E37D80")  // colorPaletteRedForeground1 (failed sends)
    readonly property color redForeground3: pick("#D13438", "#E37D80")  // colorPaletteRedForeground3 (required marks)
    readonly property color brandForeground2: pick("#444791", "#9299F7")  // colorBrandForeground2 (forward card's time link)
    readonly property color brandForeground1: pick("#4F52B2", "#7F85F5")  // colorBrandForeground1 (links, e.g. the compose hint)
    readonly property color successFg: pick("#0E700E", "#54B054")       // colorStatusSuccessForeground1 (toast)
    readonly property color greenForeground2: pick("#0B5A08", "#9FD89F") // colorPaletteGreenForeground2 (an open breakout room)
    readonly property color cardStroke: pick("#E6E6E6", "#3D3D3D")      // the breakout rooms pane's assignment card
    readonly property color peerNoteFill: pick("#E6E6E6", "#333333")    // the status bar over a 1:1's compose box
    readonly property color savedFg: pick("#C239B3", "#D24ED0")         // colorPaletteBerryForeground1 (saved bookmark)
    readonly property color inputFilledDark: pick("#F0F0F0", "#141414") // the forward dialog's picker
    readonly property color disabledStrong: pick("#C7C7C7", "#5C5C5C")  // a disabled primary button's text
    readonly property color redBackground1: pick("#FDF6F6", "#3F1011")  // colorPaletteRedBackground1 (failed bubble)
    readonly property color redBorder1: pick("#F1BBBC", "#D13438")      // colorPaletteRedBorder1
    // Teams' raised-hand outline.
    readonly property color handRaised: "#EAA300"
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
    // Teams' code font (code blocks, inline code).
    readonly property string mono: "Cascadia Mono"
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
