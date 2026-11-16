import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// Teams Premium's dialog (Settings and more ▸ Unlock Teams Premium / Teams
// Premium benefits / Get Teams Premium; every page measured on winpc
// 2026-11-15 while a trial was started and cancelled on ost-test1). All are
// 600 wide and centred, with Close (32 x 31.33) 24 in from the top right.
// - "offer": Teams' header picture (600 x 128), the diamond (68) in a 108
//   px badge (white to #C6B1DE, 136°) at 74; "Start your free Teams Premium
//   trial" (24/32 bold) at 197; three features (52 px pictures at 110, text
//   at 177) at 244, 311, 378; the free-trial line and Terms link at 460 and
//   480; View all benefits and Start trial at 544.67.
// - "pending" (Start trial, until the trial is active): Teams' 192 px logo
//   at 204, 128; "Getting your trial ready..." (20/28 semibold) at 353;
//   "This might take a minute." (14/20) at 399; a 32 px spinner at 441.3.
// - "active": "Your Teams Premium trial is now active!" at 197, "Here's how
//   to make the most of it:" at 244, three tips (60 and 48 px pictures at
//   120), the 24-hour note at 495 and Got it at 550 (605.33 tall).
// - "home" (in the trial): "You've got 60 days left to enjoy your free
//   trial of Teams Premium" (24/32 bold, two lines, the days in Teams' blue
//   to purple) at 197; "How's your trial going?…" at 269.67; three cards
//   (radius 6, the depth-4 shadow, 176 tall) at 312; Cancel trial (12),
//   Buy now and Request a license at 544.67.
// - "licensed" (Premium, after Cancel trial until it ends): Teams' wider
//   header (600 x 240), the diamond at 206, "You've got Teams Premium!" at
//   309, its line at 349.67, the same cards at 404 (580 tall).
// - "benefits": Back and "Your benefits with Premium" (20/28) at 24; the
//   three benefit sections (240 x 192 pictures, bullet lists, Learn more),
//   the middle one on #FAFAFA, in a scrolling area from 63.33; the trial's
//   footer under it.
// - "cancel": Back (32, 32), Teams' warning picture (600 x 200 at 90), "Are
//   you sure you want to cancel your trial?" (20/28 semibold) at 322, the
//   two lines at 363 and 438; Never mind and Cancel trial at 546.7.
// Start trial: the auth service's lfts/TeamsPremium acquire, then the
// trial until it is active; Cancel trial: …/cancel (api::premium).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600
    height: page === "active" ? 605.33 : page === "licensed" ? 580 : 600
    anchors.centerIn: Overlay.overlay
    closePolicy: root.page === "pending" ? Popup.NoAutoClose : Popup.CloseOnEscape
    readonly property var st: backend.premiumJson ? JSON.parse(backend.premiumJson) : ({})
    property string page: "offer"
    property string backTo: "home"
    signal feedbackRequested()
    signal helpRequested()
    /// Open the page for Settings and more's item: the offer, or (in or
    /// after a trial) Teams Premium's home.
    function openFor(kind) {
        page = kind === "offer" ? "offer" : (st.mode === "trial" ? "home" : "licensed")
        open()
    }
    // Start trial's wait and outcome.
    Connections {
        target: backend
        function onPremiumJsonChanged() {
            if (!root.opened) return
            if (root.st.starting) root.page = "pending"
            else if (root.page === "pending") root.page = root.st.started ? "active" : "offer"
            else if (root.page === "cancel" && root.st.canceled) root.page = "licensed"
        }
    }
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    component CloseButton: Rectangle {
        id: cb
        property bool onPicture: false
        property bool usable: true
        x: 544; y: 24; width: 32; height: 31.33; radius: 4
        color: onPicture ? (cbh.hovered ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.5)) : (cbh.hovered ? theme.menuHover : "transparent")
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(cb, cb.usable ? theme.hc("#424242", "#FFFFFF") : theme.hc("#BDBDBD", "#3FF23F")) }
        HoverHandler { id: cbh; enabled: cb.usable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: cb.usable; onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
        Accessible.onPressAction: if (cb.usable) root.close()
    }
    component DialogButton: Rectangle {
        id: db
        property string label
        property string kind: "secondary"   // "primary", "secondary", "subtle", "link"
        property string icon: ""
        property real size: 14
        signal clicked()
        height: kind === "link" ? 20 : 31.33; radius: 4
        width: kind === "link" ? dbRow.implicitWidth : Math.max(kind === "subtle" ? 0 : 96, dbRow.implicitWidth + 24)
        color: kind === "primary" ? (dbh.hovered ? theme.brandHover : theme.brandFill)
             : kind === "secondary" ? (dbh.hovered ? theme.menuHover : theme.surface)
             : (dbh.hovered && kind === "subtle" ? theme.menuHover : "transparent")
        border.color: theme.stroke; border.width: kind === "secondary" ? 0.67 : 0
        Row {
            id: dbRow
            anchors.centerIn: parent; spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: db.label; font.family: theme.font; font.pixelSize: db.size; font.weight: db.size < 14 ? Font.Normal : Font.DemiBold; font.underline: db.kind === "link" && dbh.hovered; color: theme.onFill(db, db.kind === "primary" ? theme.textOnBrand : db.kind === "link" ? theme.brandFill : db.kind === "subtle" ? theme.textStrong : theme.text) }
            FluentIcon { visible: !!db.icon; anchors.verticalCenter: parent.verticalCenter; name: db.icon; size: 20; color: theme.onFill(db, theme.text) }
        }
        HoverHandler { id: dbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: db.clicked() }
        Accessible.role: db.kind === "link" ? Accessible.Link : Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: db.clicked()
    }
    // The header picture, the badge and the diamond (offer, active, home,
    // licensed).
    component Hero: Item {
        id: hero
        property bool wide: false
        width: 600; height: wide ? 274 : 182
        Item {
            width: 600; height: hero.wide ? 240 : 128
            clip: true
            Rectangle {
                width: 600; height: parent.height + 8; radius: 8; color: "transparent"; clip: true
                Image { width: 600; height: hero.wide ? 240 : 128; source: hero.wide ? "../assets/dialogs/premium-licensed-header.jpg" : "../assets/dialogs/premium-header.png"; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true }
            }
        }
        Shape {
            x: 246; y: hero.wide ? 186 : 74; width: 108; height: 108
            visible: !hero.wide
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0; strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 54 - 54 * Math.sin(136 * Math.PI / 180); y1: 54 + 54 * Math.cos(136 * Math.PI / 180)
                    x2: 54 + 54 * Math.sin(136 * Math.PI / 180); y2: 54 - 54 * Math.cos(136 * Math.PI / 180)
                    GradientStop { position: 0.1669; color: theme.hc("#FFFFFF", "#000000") }
                    GradientStop { position: 1.2623; color: theme.hc("#C6B1DE", "#FFFFFF") }
                }
                PathAngleArc { centerX: 54; centerY: 54; radiusX: 54; radiusY: 54; startAngle: 0; sweepAngle: 360 }
            }
        }
        Rectangle { visible: hero.wide; x: 246; y: 186; width: 108; height: 108; radius: 54; color: theme.hc("#FFFFFF", "#000000") }
        Image { x: 266; y: hero.wide ? 206 : 94; width: 68; height: 68; source: "../assets/dialogs/premium-diamond.svg"; sourceSize: Qt.size(136, 136); smooth: true }
    }
    component Title: Text {
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    component Line: Text {
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.textStrong
    }
    // The three cards of the trial's and Premium's home.
    component Cards: Item {
        width: 600; height: 176
        Repeater {
            model: [
                { x: 24, w: 167.57, icon: "premium-card-benefits.svg", title: "Explore your benefits", text: "See what’s included in Teams Premium.", link: "View benefits", act: "benefits" },
                { x: 206.57, w: 181.11, icon: "premium-card-feedback.svg", title: "Share feedback", text: "Help us improve your Premium experience.", link: "Share feedback", act: "feedback" },
                { x: 402.69, w: 173.31, icon: "premium-card-help.svg", title: "Get help", text: "Browse our Teams Premium help articles.", link: "Get help", act: "help" }
            ]
            FluentSurface {
                required property var modelData
                x: modelData.x; width: modelData.w; height: 176
                depth: 4; radius: 6; color: theme.surface
                Image { x: 16; y: 16; width: 32; height: 32; source: "../assets/dialogs/" + parent.modelData.icon; sourceSize: Qt.size(64, 64); smooth: true }
                Text { x: 16; y: 63; width: parent.width - 32; text: parent.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { x: 16; y: 93; width: parent.width - 32; text: parent.modelData.text; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                DialogButton {
                    x: 16; y: 140; kind: "link"; label: parent.modelData.link
                    onClicked: {
                        if (parent.modelData.act === "benefits") { root.backTo = root.page; root.page = "benefits" }
                        else if (parent.modelData.act === "feedback") { root.close(); root.feedbackRequested() }
                        else { root.close(); root.helpRequested() }
                    }
                }
            }
        }
    }
    // The trial's footer (home and benefits): Cancel trial, Buy now and
    // Request a license (Teams embeds Microsoft 365's licence request app;
    // OST opens it in the browser).
    component TrialFooter: Item {
        width: 600; height: 31.33
        DialogButton { x: 24; kind: "subtle"; size: 12; label: "Cancel trial"; onClicked: { root.backTo = root.page; root.page = "cancel" } }
        Row {
            x: 576 - width; spacing: 10
            DialogButton { label: "Buy now"; icon: "open-20"; onClicked: Qt.openUrlExternally("https://signup.microsoft.com/get-started/signup?products=CFQ7TTC0RM8K%3a0007&fOfferId=a8a931ff-8672-48ce-b5db-8d70f738012c") }
            DialogButton { kind: "primary"; label: "Request a license"; onClicked: Qt.openUrlExternally("https://admin.microsoft.com/centrohost?appname=LicenseRequest&feature=host-license-request-app") }
        }
    }

    // ---- offer ----
    Item {
        visible: root.page === "offer"
        anchors.fill: parent
        Hero {}
        CloseButton { onPicture: true }
        Title { y: 197; text: "Start your free Teams Premium trial" }
        Repeater {
            model: [
                { y: 244, image: "premium-protected.svg", title: "More protected", text: "Expand security in meetings & calls with added controls and features." },
                { y: 311, image: "premium-engaging.svg", title: "More engaging", text: "Build stronger connections with branded experiences in meetings and collaborative call handling in Queues app." },
                { y: 378, image: "premium-intelligent.svg", title: "More intelligent", text: "Use AI to focus on what matters most in every meeting or call." }
            ]
            Item {
                required property var modelData
                y: modelData.y; width: root.width; height: 52
                Image { x: 110; width: 52; height: 52; source: "../assets/dialogs/" + parent.modelData.image; sourceSize: Qt.size(104, 104); smooth: true }
                Text { x: 177; width: 313; text: parent.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { x: 177; y: 20; width: 313; text: parent.modelData.text; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 460
            // Teams' string when Start trial fails (premium-benefits).
            text: root.st.error ? "We ran into a problem setting up your trial. Let's try again." : "Free 60-day trial, no card required."
            font.family: theme.font; font.pixelSize: 12; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.st.error ? theme.danger : theme.textSecondary
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 480
            text: "Microsoft Teams Trial Terms & Conditions."
            font.family: theme.font; font.pixelSize: 12; lineHeight: 14; lineHeightMode: Text.FixedHeight
            color: theme.brandLink
            font.underline: termsHover.hovered
            HoverHandler { id: termsHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2194722") }
            Accessible.role: Accessible.Link
            Accessible.name: text
        }
        DialogButton { x: 24; y: 544.67; kind: "subtle"; label: "View all benefits"; onClicked: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2227979") }
        DialogButton { x: 480; y: 544.67; kind: "primary"; label: root.st.error ? "Try again" : "Start trial"; onClicked: backend.startPremiumTrial() }
    }

    // ---- pending ----
    Item {
        visible: root.page === "pending"
        anchors.fill: parent
        CloseButton { usable: false }
        Image { x: 204; y: 128; width: 192; height: 192; source: "../assets/dialogs/premium-loading.svg"; sourceSize: Qt.size(384, 384); smooth: true }
        Text {
            width: root.width; y: 353; horizontalAlignment: Text.AlignHCenter
            text: "Getting your trial ready..."
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Line { y: 399; text: "This might take a minute."; color: theme.text }
        // Fluent's spinner (32): a brand arc turning on a light track.
        Item {
            x: 284; y: 441.3; width: 32; height: 32
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath { strokeWidth: 3; strokeColor: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF"); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 16; centerY: 16; radiusX: 14.5; radiusY: 14.5; startAngle: 0; sweepAngle: 360 } }
            }
            Shape {
                id: spinArc
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath { strokeWidth: 3; strokeColor: theme.brand; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 16; centerY: 16; radiusX: 14.5; radiusY: 14.5; startAngle: -90; sweepAngle: 100 } }
                RotationAnimator on rotation { from: 0; to: 360; duration: 1500; loops: Animation.Infinite; running: root.page === "pending" && root.opened }
            }
            Accessible.role: Accessible.ProgressBar
            Accessible.name: "Getting your trial ready"
        }
    }

    // ---- active ----
    Item {
        visible: root.page === "active"
        anchors.fill: parent
        Hero {}
        CloseButton { onPicture: true }
        Title { y: 197; text: "Your Teams Premium trial is now active!" }
        Line { y: 244; text: "Here's how to make the most of it:"; color: theme.text }
        Repeater {
            model: [
                { y: 279, ty: 279, size: 60, tx: 195, image: "premium-active-translate.svg", text: "Talk to people globally with live-translated captions and record meetings to generate AI notes in recap." },
                { y: 354, ty: 358, size: 48, tx: 183, image: "premium-active-watermark.svg", text: "Turn on watermarking for your next confidential meeting" },
                { y: 417, ty: 421, size: 48, tx: 183, image: "premium-active-queues.svg", text: "View rich call history and analytics for call queues in Queues app" }
            ]
            Item {
                required property var modelData
                width: root.width
                Image { x: 120; y: parent.modelData.y; width: parent.modelData.size; height: parent.modelData.size; source: "../assets/dialogs/" + parent.modelData.image; sourceSize: Qt.size(120, 120); smooth: true }
                Text { x: parent.modelData.tx; y: parent.modelData.ty; width: 480 - parent.modelData.tx; text: parent.modelData.text; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 495
            text: "Premium features may take up to 24 hours to become available."
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        DialogButton { x: 480; y: 550; kind: "primary"; label: "Got it"; onClicked: root.close() }
    }

    // ---- home (in the trial) ----
    Item {
        visible: root.page === "home"
        anchors.fill: parent
        Hero {}
        CloseButton { onPicture: true }
        // The title: Teams draws the days in its title gradient (#0071CB
        // to #5B4BB9 at 100.84° across the 548-wide heading; the days fall
        // at its blue end).
        Text {
            x: 26; y: 197; width: 548
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            readonly property int days: root.st.daysLeft || 0
            text: "You’ve got <span style=\"color:#2A5FC6\">" + days + (days === 1 ? " day" : " days") + "</span> left to enjoy your free trial of Teams Premium"
            font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: "You’ve got " + days + " days left to enjoy your free trial of Teams Premium"
        }
        Line { x: 20; y: 269.67; width: 560; text: "How's your trial going? Request a license anytime to keep using premium features."; lineHeight: 18.67 }
        Cards { y: 312 }
        TrialFooter { y: 544.67 }
    }

    // ---- licensed (after Cancel trial, while Premium lasts) ----
    Item {
        visible: root.page === "licensed"
        anchors.fill: parent
        Hero { wide: true }
        CloseButton { onPicture: true }
        Title { y: 309; text: "You’ve got Teams Premium!" }
        Line { x: 37.38; y: 349.67; width: 525.24; text: "Explore Premium features, tips, and resources that make every meeting and call more protected, engaging, and intelligent."; lineHeight: 19.33 }
        Cards { y: 404 }
    }

    // ---- benefits ----
    Item {
        visible: root.page === "benefits"
        anchors.fill: parent
        DialogButton { x: 24; y: 24; width: 32; kind: "subtle"; icon: "arrow-left-20"; label: ""; onClicked: root.page = root.backTo; Accessible.name: "Back to Premium home" }
        Text {
            x: 66; y: 24; height: 31.33; verticalAlignment: Text.AlignVCenter
            text: "Your benefits with Premium"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        CloseButton {}
        Flickable {
            id: benefitsScroll
            x: 0; y: 63.33; width: 600; height: 457
            clip: true
            contentHeight: 1007.3 - 63.33
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            component Section: Item {
                id: sec
                property real sectionTop
                property bool pictureLeft: true
                property string picture
                property string title
                property string text
                property var points: []
                property string url
                property bool shaded: false
                /// The picture's offset from the title (measured per section).
                property real pictureDy: 18.7
                y: sectionTop - 63.33; width: 586
                height: col.y + col.height
                Rectangle { visible: sec.shaded; y: -16; width: 586; height: sec.height + 32; color: theme.pick("#FAFAFA", "#1F1F1F", "#000000") }
                Image { x: sec.pictureLeft ? 0 : 346; y: col.y + sec.pictureDy; width: 240; height: 192; source: "../assets/dialogs/" + sec.picture; sourceSize: Qt.size(480, 384); fillMode: Image.PreserveAspectFit; smooth: true }
                Column {
                    id: col
                    x: sec.pictureLeft ? 264 : 24; width: 298
                    spacing: 0
                    Text { text: sec.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Item { width: 1; height: 10 }
                    Text { width: 298; text: sec.text; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                    Item { width: 1; height: 16 }
                    Repeater {
                        model: sec.points
                        Item {
                            required property string modelData
                            width: 298; height: pt.height
                            Text { x: 10; text: "•"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                            Text { id: pt; x: 22; width: 276; text: parent.modelData; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                        }
                    }
                    Item { width: 1; height: 24 }
                    DialogButton { label: "Learn more"; icon: "open-20"; width: 123.4; onClicked: Qt.openUrlExternally(sec.url) }
                }
            }
            Section {
                sectionTop: 79.3; picture: "premium-benefits-protected.svg"; title: "More protected"
                text: "Expand security in meetings & calls with added controls and features"
                points: ["End-to-end encryption for up to 200 participants", "Watermarks for video, audio, and shared content", "Designate who can record in meetings", "Real-time sensitive content detection", "Meeting sensitivity labels*", "Turn off copy and paste of meeting chat*"]
                url: "https://support.microsoft.com/en-us/office/advanced-meeting-protection-in-microsoft-teams-premium-46e39bcb-40e0-4617-84be-14be9dd99780"
            }
            Section {
                sectionTop: 340.7; pictureLeft: false; shaded: true; pictureDy: 58.6; picture: "premium-benefits-engaging.svg"; title: "More engaging"
                text: "Create rich, personalized experiences for stronger connections with colleagues and customers"
                points: ["Queues app with shared call history across the queue, silent coaching features, and rich analytics in Teams Phone", "Manage customer appointments end-to-end, from scheduling to follow-up with Advanced Bookings", "Bring your brand into every meeting with your organization’s logo, colors, branded reactions, and custom backgrounds", "Turn every interview, QBR, and exec review into a consistent experience with admin-approved templates*"]
                url: "https://support.microsoft.com/en-us/office/engaging-meeting-experiences-in-microsoft-teams-premium-b48c2174-0faa-4cf9-800b-75e030c115e3"
            }
            Section {
                sectionTop: 682; pictureDy: 34.7; picture: "premium-benefits-intelligent.svg"; title: "More intelligent"
                text: "Use AI to focus on what matters most in every meeting or call."
                points: ["AI generated summaries, action items, and personalized highlights", "AI-generated chapters in meeting recordings", "Live translation for captions and transcripts in 40 languages", "Personalized timeline markers in meeting recordings", "AI-powered speaker recognition in transcript"]
                url: "https://support.microsoft.com/en-us/office/intelligent-productivity-with-microsoft-teams-premium-d5b02821-b9b1-4687-8c77-2f903ea68ad2"
            }
            Text {
                y: 959.3 - 63.33; width: 586; height: 48
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: "*Must be turned on by your admin."
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.textSecondary
            }
        }
        TrialFooter { y: 544.67; visible: root.st.mode === "trial" }
    }

    // ---- cancel ----
    Item {
        visible: root.page === "cancel"
        anchors.fill: parent
        DialogButton { x: 32; y: 32; width: 32; height: 21.33; kind: "subtle"; icon: "arrow-left-20"; label: ""; onClicked: root.page = root.backTo; Accessible.name: "Back to Premium home" }
        CloseButton {}
        Image { x: 200; y: 90; width: 200; height: 200; source: "../assets/dialogs/premium-cancel.svg"; sourceSize: Qt.size(400, 400); smooth: true }
        Text {
            x: 22; y: 322; width: 556; horizontalAlignment: Text.AlignHCenter
            text: "Are you sure you want to cancel your trial?"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Line { x: 20; y: 363; width: 560; color: theme.text; text: root.st.cancelError ? "We ran into a problem canceling your trial. Let's try again." : "Canceling your trial means losing access to AI-powered meeting recaps, advanced meeting protection, and more. To request access to Teams Premium again, you’ll need to contact your admin." }
        Line { x: 20; y: 438; width: 560; color: theme.text; text: "Note: Your trial will cancel within 24 hours." }
        DialogButton { x: 367.4; y: 546.7; label: "Never mind"; width: 99.6; onClicked: root.page = root.backTo }
        DialogButton {
            x: 482; y: 546.7; kind: "primary"; label: root.st.cancelError ? "Try again" : "Cancel trial"
            opacity: root.st.canceling ? 0.6 : 1
            onClicked: if (!root.st.canceling) backend.cancelPremiumTrial()
        }
    }
}
