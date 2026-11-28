import QtQuick

// Design tokens, read from the Teams desktop client (its Fluent CSS
// variables and computed colours, light and dark, at 1x).
QtObject {
    /// Dark theme on: chosen in Settings > Appearance, or the system's.
    property bool dark: false
    /// Teams' Classic theme: Light with its purple title bar (measured).
    property bool classic: false
    /// Teams' High contrast theme (Fluent's Teams high-contrast tokens,
    /// docs/spec/teams-tokens-high-contrast.json; `dark` is on with it):
    /// black surfaces, white text and strokes, #1AEBFF for hover, selection
    /// and indicators with black on it, #FFFF00 links, #3FF23F disabled.
    property bool highContrast: false
    /// High contrast's colours.
    readonly property color hcHighlight: "#1AEBFF"
    readonly property color hcLink: "#FFFF00"
    readonly property color hcDisabled: "#3FF23F"
    /// Fluent's TransparentStroke: none, but white in High contrast (the
    /// outline its bubbles, cards, menus and inputs get there).
    readonly property color transparentStroke: highContrast ? "#FFFFFF" : "transparent"
    /// Text or an icon on a hovered, pressed or selected fill: black on
    /// High contrast's #1AEBFF (Fluent's Foreground*Hover/Selected), else
    /// its usual colour.
    function ink(onHighlight, normal) { return highContrast && onHighlight ? "#000000" : normal }
    /// Text or an icon drawn on a fill: black on a light fill in High
    /// contrast (the #1AEBFF hover and selection, a white primary button),
    /// else its usual colour.
    /// `fills` is the Rectangle (or a list of them) that may be under it;
    /// a hidden one doesn't count.
    function onFill(fills, normal) {
        if (!highContrast) return normal
        const list = Array.isArray(fills) ? fills : [fills]
        for (let i = 0; i < list.length; i++) {
            const f = list[i]
            if (!f || !f.visible) continue
            const c = Qt.color(f.color)
            if (c.a > 0.5 && (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.5) return "#000000"
        }
        return normal
    }
    /// A colour that is fixed outside High contrast (`normal`) and `hc` in it.
    // OneDrive's sixteen folder colours, in the picker's order, with their
    // codes and the shades its folder drawing uses (main, background,
    // accent, gradient start, gradient stop, count).
    readonly property var folderColors: [
        { code: "0", name: qsTr("Yellow"), hex: "#FFCE3C", shades: ["#FFCE3C", "#F5B800", "#B64D07", "#FFE561", "#FFB515", "#8F3900"] },
        { code: "8", name: qsTr("Grey"), hex: "#B0B7BA", shades: ["#B0B7BA", "#96A3A7", "#575757", "#BDBFBF", "#A0ADB2", "#361500"] },
        { code: "1", name: qsTr("Dark red"), hex: "#E73E29", shades: ["#E73E29", "#D62E1F", "#590700", "#FF5028", "#C92828", "#000000"] },
        { code: "9", name: qsTr("Light red"), hex: "#FFBCB2", shades: ["#FFBCB2", "#F58076", "#BD2113", "#FFC7BA", "#FF9191", "#910C00"] },
        { code: "2", name: qsTr("Dark orange"), hex: "#EE7110", shades: ["#EE7110", "#E56000", "#6B2500", "#FF8E1D", "#DB5101", "#361500"] },
        { code: "10", name: qsTr("Light orange"), hex: "#FFBF84", shades: ["#FFBF84", "#FF8E3D", "#A14200", "#FFC48A", "#FF8C4A", "#782E00"] },
        { code: "3", name: qsTr("Dark green"), hex: "#3F9F4A", shades: ["#3F9F4A", "#33852C", "#053B00", "#5EB75A", "#1D8539", "#001404"] },
        { code: "11", name: qsTr("Light green"), hex: "#8ED290", shades: ["#8ED290", "#5BC26B", "#0B6E1A", "#B6E6AC", "#62BD71", "#00520A"] },
        { code: "4", name: qsTr("Dark teal"), hex: "#27938E", shades: ["#27938E", "#037D81", "#003133", "#3DB7AB", "#106E70", "#000000"] },
        { code: "12", name: qsTr("Light teal"), hex: "#7AD1CD", shades: ["#7AD1CD", "#5DC6C9", "#07676B", "#94EBE2", "#5DB4B6", "#0E4E4E"] },
        { code: "5", name: qsTr("Dark blue"), hex: "#1E84D0", shades: ["#1E84D0", "#036DC9", "#032F54", "#2F9ADE", "#0E6EC2", "#000000"] },
        { code: "13", name: qsTr("Light blue"), hex: "#86C8F7", shades: ["#86C8F7", "#73B3EB", "#1F64A1", "#9FDAFF", "#6EB6F0", "#004881"] },
        { code: "6", name: qsTr("Dark purple"), hex: "#9A61C7", shades: ["#9A61C7", "#7E54B8", "#370086", "#BC7ADD", "#7342AD", "#000000"] },
        { code: "14", name: qsTr("Light purple"), hex: "#D4AFF6", shades: ["#D4AFF6", "#BA90F5", "#7A2AD2", "#E2BFFA", "#BD94EF", "#5915A1"] },
        { code: "7", name: qsTr("Dark pink"), hex: "#CC53B4", shades: ["#CC53B4", "#BC4293", "#5C003D", "#E36DE3", "#BA3E91", "#000000"] },
        { code: "15", name: qsTr("Light pink"), hex: "#F7AAE7", shades: ["#F7AAE7", "#ED87CB", "#B8148C", "#FFBEFF", "#F097D2", "#8F0069"] }
    ]
    /// A coloured folder: OneDrive's shades in place of the yellow folder
    /// drawing's (front gradient, back, its dark stop), for FluentIcon swaps.
    function folderSwaps(code) {
        if (!code || String(code) === "0") return ({})
        const f = folderColors.find(c => c.code === String(code))
        if (!f) return ({})
        const c = f.shades
        return { "#FFDD57": c[3], "#F7AB40": c[4], "#D48300": c[1], "#C77B00": c[1], "#BA7300": c[2] }
    }
    function hc(normal, hcValue) { return highContrast ? hcValue : normal }
    readonly property color titleBar: classic ? "#444791" : chrome
    readonly property color titleIcon: classic ? "#FFFFFF" : icon
    readonly property color titleIconDisabled: classic ? "#BDBDBD" : disabled
    readonly property color titleHover: classic ? Qt.rgba(1, 1, 1, 0.1) : hover
    readonly property color titleSearchFill: classic ? "#E8EBFA" : searchFill
    readonly property color titleSearchIcon: classic ? "#4F52B2" : icon
    /// The compact profile card hovering a picture or name opens (Main
    /// sets it).
    property var hoverCard: null
    /// Light, dark and High contrast values. Without a High contrast value,
    /// a light background (#E0E0E0 and lighter) becomes black and anything
    /// else (text, icons, strokes) white.
    function pick(light, darkValue, hcValue) {
        // Not a colour (an asset variant, a flag): the dark one.
        if (highContrast) return hcValue !== undefined ? hcValue : typeof light === "string" && light[0] === "#" ? hcFor(light) : darkValue
        return dark ? darkValue : light
    }
    function hcFor(light) {
        const c = Qt.color(light)
        if (c.a === 0) return light
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) >= 0.74 ? "#000000" : "#FFFFFF"
    }
    /// Teams' regional formats (Settings ▸ General ▸ Language and regional
    /// formats; read once, as a change applies after a restart). Every
    /// date and time OST shows goes through these.
    readonly property var regional: JSON.parse(backend.regionalFormatsJson())
    /// Teams' App language reads right to left (Arabic, Hebrew, Persian):
    /// it then mirrors its whole layout (dir="rtl"); src/i18n.cpp mirrors
    /// OST's windows the same way.
    readonly property bool rtl: Qt.application.layoutDirection === Qt.RightToLeft
    /// The icons Teams mirrors then (its Fluent icons' flipInRtl), by stem.
    readonly property var rtlFlips: {
        const m = ({})
        if (rtl) JSON.parse(backend.rtlFlipIconsJson()).forEach(n => m[n] = true)
        return m
    }
    /// Whether a Fluent icon ("arrow-reply-20-filled") is drawn mirrored.
    function iconFlips(name) { return rtl && rtlFlips[String(name).replace(/(-\d+)?(-filled)?$/, "")] === true }
    /// A date or time in a Qt pattern, in the app language's culture (its
    /// month and day names, AM/PM and digits: Arabic-Indic in ar-SA, as
    /// Teams' Intl formatting shows them).
    function fmtTime(d, f) { return new Date(d).toLocaleTimeString(Qt.locale(), f) }
    /// Teams' end slot (the contextual panes on the right, such as View
    /// meetings): its width for the window's (--slot-width per breakpoint,
    /// measured in Teams on the web 2026-11-27: 1280 → 360, 1600 → 420,
    /// 1700 → 480, 1920 → 600), narrowed so the main area keeps its 320
    /// (--main-slot-min-width) beside what is left of it.
    function endSlotWidth(windowWidth, leftWidth) {
        const w = windowWidth
        const slot = w >= 2560 ? 720 : w >= 1920 ? 600 : w >= 1680 ? 480 : w >= 1440 ? 420 : w >= 947 ? 360 : 320
        return Math.max(0, Math.min(slot, w - leftWidth - 320))
    }
    function fmtDate(d, f) { return new Date(d).toLocaleDateString(Qt.locale(), f) }
    function fmtDateTime(d, f) { return new Date(d).toLocaleString(Qt.locale(), f) }
    function time(d) { return fmtTime(d, regional.shortTime) }
    function longTime(d) { return fmtTime(d, regional.longTime) }
    function date(d) { return fmtDate(d, regional.shortDate) }
    /// This year's dates leave the year out, as Teams.
    function dateNoYear(d) { return fmtDate(d, regional.shortDateNoYear) }
    function dateMaybeYear(d) { const x = new Date(d); return x.getFullYear() === new Date().getFullYear() ? dateNoYear(x) : date(x) }
    function longDate(d) { return fmtDate(d, regional.longDate) }
    function longDateNoYear(d) { return fmtDate(d, regional.longDateNoYear) }
    function dateTime(d) { return date(d) + " " + time(d) }
    /// An activity's place with Teams' date markup in it (an app's custom
    /// location, Teams' activity renderer 542284): <DateTimeRange> as
    /// "Nov 20, 8:23 PM - 9:02 PM" (the end's date left out on the same
    /// day), <DateRange>, <DateTime>, <Date>; the year only when not this
    /// year's.
    function activityPlace(s) {
        s = String(s || "")
        if (!/<Dat(.+?)>(.+?)<[/]Dat\1>/.test(s)) return s
        const now = new Date()
        const fmt = (d, withTime, thisYear) => isNaN(d.getTime()) ? ""
            : fmtDate(d, thisYear ? "MMM d" : "MMM d, yyyy") + (withTime ? ", " + time(d) : "")
        const ranges = [{ re: /<DateTimeRange><StartDateTime>(.+?)<[/]StartDateTime><EndDateTime>(.+?)<[/]EndDateTime><[/]DateTimeRange>/, withTime: true },
                        { re: /<DateRange><StartDate>(.+?)<[/]StartDate><EndDate>(.+?)<[/]EndDate><[/]DateRange>/, withTime: false }]
        for (const r of ranges) {
            const m = s.match(r.re)
            if (m) {
                const a = new Date(m[1]), b = new Date(m[2])
                const sameDay = a.toDateString() === b.toDateString()
                const thisYear = a.getFullYear() === now.getFullYear() && b.getFullYear() === now.getFullYear()
                if (sameDay && !r.withTime) return s.replace(r.re, fmt(a, false, thisYear))
                const x = fmt(a, r.withTime, thisYear)
                const y = sameDay ? (isNaN(b.getTime()) ? "" : time(b)) : fmt(b, r.withTime, thisYear)
                const both = y ? x + " - " + y : x
                return both ? s.replace(r.re, both) : s
            }
        }
        for (const r of [{ re: /<DateTime>(.+?)<[/]DateTime>/, withTime: true }, { re: /<Date>(.+?)<[/]Date>/, withTime: false }]) {
            const m = s.match(r.re)
            if (m) {
                const d = new Date(m[1])
                const v = fmt(d, r.withTime, d.getFullYear() === now.getFullYear())
                return v ? s.replace(r.re, v) : s
            }
        }
        return s
    }
    /// The short date with a two-digit year (the chat list's older dates,
    /// date fields).
    readonly property string shortYearPattern: regional.shortDate.replace("yyyy", "yy")
    function dateShortYear(d) { return fmtDate(d, shortYearPattern) }
    /// A style sheet giving rich text's links `c`: Text's linkColor works
    /// for StyledText only, and Qt's rich text otherwise draws links
    /// #0000FF. Put it ahead of the HTML (and keep fragment markers out:
    /// Qt then imports only what lies between them).
    function linkCss(c, plain) { return "<style>a { color: " + c + (plain ? "; text-decoration: none" : "") + "; }</style>" }
    // Message HTML as shown: a shared contact's card icon in brand colour.
    // Headings as paragraphs of class h1-h3: Qt adds its own heading size on
    // top of a stylesheet's, so only Teams' measured sizes apply this way.
    function messageHtml(h) {
        return String(h || "").replace(/src="ost-contact-card"/g, 'style="vertical-align: middle" src="' + Qt.resolvedUrl("../assets/icons/contact-card-inline-" + (dark ? "dark" : "light") + ".svg") + '"')
            .replace(/<h([123])>/g, '<p class="h$1">').replace(/<\/h[123]>/g, "</p>")
            // Table borders: 0.67 px, but at least one device pixel (a
            // thinner line falls between pixel rows and vanishes).
            .replace(/<table border="0\.67"/g, '<table border="' + tableBorder + '"')
    }
    readonly property real tableBorder: Math.max(0.67, 1 / ((Qt.application.screens[0] || { devicePixelRatio: 1 }).devicePixelRatio || 1))

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
    readonly property color brand: pick("#5B5FC7", "#7F85F5", "#1AEBFF")          // BrandForeground1 / indicators
    readonly property color brandFill: pick("#5B5FC7", "#4F52B2", "#FFFFFF")      // BrandBackground (buttons)
    readonly property color brandHover: pick("#4F52B2", "#5B5FC7", "#1AEBFF")
    readonly property color brandTint: pick("#E8EBFA", "#2B2B40", "#000000")      // your bubbles
    /// A checked switch, checkbox or radio (brand; High contrast's #1AEBFF).
    readonly property color checkedFill: highContrast ? hcHighlight : brandFill
    /// Links in messages and text (brand; High contrast's yellow).
    readonly property color link: highContrast ? hcLink : brand
    readonly property color textOnBrand: highContrast ? "#000000" : "#FFFFFF"   // NeutralForegroundOnBrand

    // Surfaces
    readonly property color chrome: pick("#EBEBEB", "#0A0A0A", "#000000")         // title bar, app rail
    readonly property color pane: pick("#F5F5F5", "#1A1A1A", "#000000")           // list panes
    readonly property color surface: pick("#FFFFFF", "#1F1F1F", "#000000")        // conversation, cards
    readonly property color mentionMe: pick("#DA3B01", "#F48E64", "#FFFF00")      // your name where you're @mentioned
    readonly property color channelPage: pick("#FAFAFA", "#141414", "#000000")    // behind channel post cards
    readonly property color cardEdge: pick("#E3E3E3", "#383838", "#FFFFFF")       // channel post card outline
    // Received inline code's box (Teams' NeutralBackground1 / NeutralStroke1).
    readonly property color inlineCodeFill: pick("#FFFFFF", "#292929", "#000000")
    readonly property color inlineCodeStroke: pick("#D1D1D1", "#666666", "#FFFFFF")
    // Teams' announcement colour schemes "0".."11" (443282 module 8196):
    // the palette's Background2 / Foreground2 (light: tint, shade; dark the
    // other way round), the first six light on dark text, the rest dark.
    readonly property var bannerPalette: [["#A9D3F2", "#004377"], ["#D2CCF8", "#3F3682"], ["#F7C0E3", "#80215D"],
                                          ["#F4BFAB", "#7A2101"], ["#ECDFA5", "#6C5700"], ["#BDD99B", "#294903"]]
    readonly property var bannerNames: dark
        ? [qsTr("Aegean blue"), qsTr("Midnight purple"), qsTr("Sangria"), qsTr("Espresso"), qsTr("Gothic gold"), qsTr("Space green"), qsTr("Cornflower blue"), qsTr("Thistle purple"), qsTr("Pink"), qsTr("Coral"), qsTr("Mellow yellow"), qsTr("Jade")]
        : [qsTr("Periwinkle Blue"), qsTr("Lavender"), qsTr("Rose"), qsTr("Orange sherbet"), qsTr("Flax yellow"), qsTr("Teal"), qsTr("Navy blue"), qsTr("Indigo"), qsTr("Mulberry red"), qsTr("Fire orange"), qsTr("Raw umber"), qsTr("Ocean green")]
    // [background, text] of scheme `t`.
    function banner(t) {
        let i = parseInt(t, 10); if (isNaN(i) || i < 0 || i > 11) i = 0
        const pair = bannerPalette[i % 6]
        const bg2 = dark ? pair[1] : pair[0], fg2 = dark ? pair[0] : pair[1]
        return i < 6 ? [bg2, fg2] : [fg2, bg2]
    }
    readonly property color bubble: pick("#F5F5F5", "#292929", "#000000")         // others' bubbles
    readonly property color input: pick("#FFFFFF", "#292929", "#000000")          // compose box
    readonly property color selected: pick("#FFFFFF", "#242424", "#1AEBFF")       // the open row in a pane
    readonly property color rowHover: pick("#EBEBEB", "#2E2E2E", "#1AEBFF")
    // Teams' New meeting controls (measured on winpc in light, dark and
    // High contrast, 2026-11-16): a hovered bar button or More grid item,
    // the other half of a hovered split button, and Leave's two halves.
    readonly property color nmcHover: pick("#EBEBEB", "#333333", "#1AEBFF")
    readonly property color nmcHoverOther: pick("#F5F5F5", "#3D3D3D", "#1AEBFF")
    readonly property color nmcLeaveHover: pick("#FDF3F4", "#3B0509", "#1AEBFF")
    readonly property color nmcLeaveHoverOther: pick("#FDF6F3", "#411200", "#1AEBFF")
    /// Leave's glyph (CallEnd, colorPaletteRedForeground1-like).
    readonly property color nmcLeave: pick("#B10E1C", "#DC626D", "#FFFFFF")
    /// More while a dragged control is over it (unpin), its glyph brand.
    readonly property color nmcDropTarget: pick("#D6D6D6", "#141414", "#1AEBFF")
    /// A checked bar button's glyph and underline (People with its pane open).
    readonly property color nmcChecked: pick("#5B5FC7", "#7F85F5", "#FFFFFF")
    readonly property color searchFill: pick("#FAFAFA", "#242424", "#000000")
    readonly property color menu: pick("#FFFFFF", "#292929", "#000000")           // flyouts, tooltips
    readonly property color menuHover: pick("#F5F5F5", "#3D3D3D", "#1AEBFF")      // NeutralBackground1Hover (menu items)
    readonly property color inputFilled: pick("#F5F5F5", "#141414", "#000000")    // filled-darker inputs (dialogs)
    readonly property color pressed: pick("#E0E0E0", "#1F1F1F", "#1AEBFF")        // NeutralBackground1Pressed
    readonly property color quoteFill: pick("#FAFAFA", "#1F1F1F", "#000000")      // NeutralBackground2 (quote cards)
    readonly property color selectionFill: pick("#B4D5FE", "#264F78", "#1AEBFF")  // selected text
    readonly property color quoteBorder: pick("#F0F0F0", "#3D3D3D", "#FFFFFF")    // NeutralStroke3
    readonly property color quoteBar: pick("#C7C7C7", "#757575", "#FFFFFF")       // NeutralStroke1Hover
    readonly property color brandLink: pick("#4F52B2", "#9EA2FF", "#FFFF00")      // transparent brand buttons ("About")
    // Fluent shadows: two layers each (ambient, key), as the client's CSS.
    readonly property color shadowAmbient: pick(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(0, 0, 0, 0.24))
    readonly property color shadowKey: pick(Qt.rgba(0, 0, 0, 0.14), Qt.rgba(0, 0, 0, 0.28))

    // Lines
    readonly property color divider: pick("#E0E0E0", "#525252", "#FFFFFF")        // NeutralStroke2
    readonly property color dividerSoft: pick("#EBEBEB", "#3D3D3D", "#FFFFFF")    // NeutralStroke3
    readonly property color stroke: pick("#D1D1D1", "#666666", "#FFFFFF")         // NeutralStroke1 (chips)
    readonly property color strokeHover: pick("#C7C7C7", "#757575", "#1AEBFF")
    readonly property color strokePressed: pick("#B3B3B3", "#6B6B6B", "#1AEBFF")       // NeutralStroke1Pressed
    readonly property color strokeAccessibleHover: pick("#575757", "#BDBDBD", "#1AEBFF")   // NeutralStrokeAccessibleHover
    readonly property color strokeAccessiblePressed: pick("#4D4D4D", "#B3B3B3", "#1AEBFF") // NeutralStrokeAccessiblePressed
    readonly property color edge: pick("#EFEFEF", "#232323", "#FFFFFF")           // between panes
    readonly property color titleHairline: pick("#DDDDDD", "#1F1F1F", "#FFFFFF")

    // Hover on chrome
    readonly property color hover: pick("#E0E0E0", "#2E2E2E", "#1AEBFF")

    // Text and icons
    readonly property color text: pick("#242424", "#FFFFFF", "#FFFFFF")           // NeutralForeground1
    readonly property color textStrong: pick("#424242", "#D6D6D6", "#FFFFFF")     // NeutralForeground2
    readonly property color textSecondary: pick("#616161", "#ADADAD", "#FFFFFF")  // NeutralForeground3
    readonly property color textTertiary: pick("#707070", "#999999", "#FFFFFF")   // NeutralForeground4
    readonly property color disabled: pick("#BDBDBD", "#5C5C5C", "#3FF23F")
    readonly property color bgDisabled: pick("#F0F0F0", "#141414", "#000000")     // NeutralBackgroundDisabled
    readonly property color editorFilled: pick("#EBEBEB", "#1F1F1F", "#000000")   // Teams' status-note editor (CKEditor)
    readonly property color icon: pick("#424242", "#D6D6D6", "#FFFFFF")
    // High contrast: a white badge with black text (Teams, measured).
    readonly property color badge: highContrast ? "#FFFFFF" : "#C4314B"
    readonly property color danger: pick("#C4314B", "#E37D80", "#FFFFFF")
    readonly property color redForeground1: pick("#BC2F32", "#E37D80", "#FFFFFF")  // colorPaletteRedForeground1 (failed sends)
    readonly property color redForeground3: pick("#D13438", "#E37D80", "#FFFFFF")  // colorPaletteRedForeground3 (required marks)
    readonly property color brandForeground2: pick("#444791", "#9299F7", "#FFFF00")  // colorBrandForeground2 (forward card's time link)
    readonly property color brandForeground1: pick("#4F52B2", "#7F85F5", "#FFFF00")  // colorBrandForeground1 (links, e.g. the compose hint)
    readonly property color successFg: pick("#0E700E", "#54B054", "#FFFFFF")       // colorStatusSuccessForeground1 (toast)
    readonly property color greenForeground2: pick("#0B5A08", "#9FD89F", "#FFFFFF") // colorPaletteGreenForeground2 (an open breakout room)
    readonly property color greenForeground1: pick("#0E700E", "#54B054", "#FFFFFF") // colorPaletteGreenForeground1 (a free room's "Available")
    readonly property color cardStroke: pick("#E6E6E6", "#3D3D3D", "#FFFFFF")      // the breakout rooms pane's assignment card
    readonly property color peerNoteFill: pick("#E6E6E6", "#333333", "#000000")    // the status bar over a 1:1's compose box
    readonly property color effectTile: pick("#E6E6E6", "#333333", "#000000")      // a video effect tile (NeutralBackground5)
    readonly property color savedFg: pick("#C239B3", "#D24ED0", "#FFFFFF")         // colorPaletteBerryForeground1 (saved bookmark)
    readonly property color inputFilledDark: pick("#F0F0F0", "#141414", "#000000") // the forward dialog's picker
    readonly property color disabledStrong: pick("#C7C7C7", "#5C5C5C", "#3FF23F")  // a disabled primary button's text
    readonly property color redBackground1: pick("#FDF6F6", "#3F1011", "#000000")  // colorPaletteRedBackground1 (failed bubble)
    readonly property color redBorder1: pick("#F1BBBC", "#D13438", "#FFFFFF")      // colorPaletteRedBorder1
    // Teams' raised-hand outline.
    readonly property color handRaised: "#EAA300"
    readonly property color unreadTint: pick("#FDF3F4", "#3E1F25", "#000000")

    // Calls use the dark stage in every theme, as in Teams.
    // High contrast (Teams' meeting window, measured on winpc 2026-11-15):
    // black throughout, the toolbar's 0.67 px white underline, white icons
    // and labels, and Leave without its red (white on black, #1AEBFF hover).
    readonly property color stage: highContrast ? "#000000" : "#1F1F1F"
    readonly property color stageBar: highContrast ? "#000000" : "#292929"
    readonly property color stageTile: highContrast ? "#000000" : "#2E2E2E"
    readonly property color stageText: "#FFFFFF"
    readonly property color stageTextSecondary: highContrast ? "#FFFFFF" : "#ADADAD"
    readonly property color stageControlHover: highContrast ? hcHighlight : "#3D3D3D"
    readonly property color stageEdge: highContrast ? "#FFFFFF" : "transparent"
    readonly property color accept: highContrast ? "#FFFFFF" : "#107C10"
    readonly property color acceptHover: highContrast ? hcHighlight : "#0E700E"
    readonly property color leave: highContrast ? "#000000" : "#C4314B"
    readonly property color leaveHover: highContrast ? hcHighlight : "#B12C44"

    // Teams' font is Segoe UI. OST can't ship it (it comes with Windows), so
    // it ships Microsoft's open Selawik, made to match it, and uses Segoe UI
    // itself when the machine has it installed.
    readonly property string font: Qt.fontFamilies().indexOf("Segoe UI") >= 0 ? "Segoe UI" : "Selawik"
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
