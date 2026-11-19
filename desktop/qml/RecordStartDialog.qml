import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Teams' start dialogs for Record and transcribe (spoken-language-
// selection-dialog, measured on winpc, 2026-11-09), a Fluent dialog with
// 24.67 padding:
// - "transcription": "What language is everyone speaking?" (480 wide):
//   the text at 64.67, "Spoken language" (12/20 #616161) at 107, the
//   language dropdown (30 tall) at 132.67, Cancel / Confirm at 177.33.
// - "recordingAndTranscription": "Start recording and transcription"
//   (522 wide): the same, then a divider (10 above it), "More options"
//   (44 tall, chevron) opening "Choose what to record" with "Video and
//   audio" / "Audio only" in a 51.33 tall rounded box; buttons below.
// - "recording" (the transcript already runs): "Start recording" (522
//   wide), only the "Choose what to record" box at 63.33.
// The language list is Teams': the current choice first, then all 57.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// "transcription", "recordingAndTranscription" or "recording";
    /// "copilot" (Turn on Copilot for everyone: the same spoken-language
    /// question, Teams' MeetingCollabUFDCopilotOnlyMode entry point).
    property string mode: "transcription"
    readonly property bool languageOnly: mode === "transcription" || mode === "copilot"
    property string language: "en-us"
    property bool audioOnly: false
    property bool moreOptions: true
    signal confirmed(string language, bool audioOnly)

    readonly property var languages: [
        ["sq-al", qsTr("Albanian (Albania)")], ["ar-sa", qsTr("Arabic (Saudi Arabia)")], ["ar-ae", qsTr("Arabic (United Arab Emirates)")],
        ["bg-bg", qsTr("Bulgarian (Bulgaria)")], ["ca-es", qsTr("Catalan (Catalan)")], ["zh-cn", qsTr("Chinese (Simplified, China)")],
        ["zh-hk", qsTr("Chinese (Traditional, Hong Kong SAR)")], ["zh-tw", qsTr("Chinese (Traditional, Taiwan)")], ["hr-hr", qsTr("Croatian (Croatia)")],
        ["cs-cz", qsTr("Czech (Czechia)")], ["da-dk", qsTr("Danish (Denmark)")], ["nl-be", qsTr("Dutch (Belgium)")], ["nl-nl", qsTr("Dutch (Netherlands)")],
        ["en-au", qsTr("English (Australia)")], ["en-ca", qsTr("English (Canada)")], ["en-in", qsTr("English (India)")], ["en-nz", qsTr("English (New Zealand)")],
        ["en-gb", qsTr("English (UK)")], ["en-us", qsTr("English (US)")], ["et-ee", qsTr("Estonian (Estonia)")], ["fil-ph", qsTr("Filipino (Philippines)")],
        ["fi-fi", qsTr("Finnish (Finland)")], ["fr-ca", qsTr("French (Canada)")], ["fr-fr", qsTr("French (France)")], ["de-de", qsTr("German (Germany)")],
        ["de-ch", qsTr("German (Switzerland)")], ["el-gr", qsTr("Greek (Greece)")], ["he-il", qsTr("Hebrew (Israel)")], ["hi-in", qsTr("Hindi (India)")],
        ["hu-hu", qsTr("Hungarian (Hungary)")], ["is-is", qsTr("Icelandic (Iceland)")], ["id-id", qsTr("Indonesian (Indonesia)")], ["it-it", qsTr("Italian (Italy)")],
        ["ja-jp", qsTr("Japanese (Japan)")], ["kk-kz", qsTr("Kazakh (Kazakhstan)")], ["ko-kr", qsTr("Korean (Korea)")], ["lv-lv", qsTr("Latvian (Latvia)")],
        ["lt-lt", qsTr("Lithuanian (Lithuania)")], ["ms-my", qsTr("Malay (Malaysia)")], ["mt-mt", qsTr("Maltese (Malta)")], ["nb-no", qsTr("Norwegian (Norway)")],
        ["pl-pl", qsTr("Polish (Poland)")], ["pt-br", qsTr("Portuguese (Brazil)")], ["pt-pt", qsTr("Portuguese (Portugal)")], ["ro-ro", qsTr("Romanian (Romania)")],
        ["ru-ru", qsTr("Russian (Russia)")], ["sr-rs", qsTr("Serbian (Cyrillic, Serbia)")], ["sk-sk", qsTr("Slovak (Slovakia)")], ["sl-si", qsTr("Slovenian (Slovenia)")],
        ["es-mx", qsTr("Spanish (Mexico)")], ["es-es", qsTr("Spanish (Spain)")], ["sv-se", qsTr("Swedish (Sweden)")], ["th-th", qsTr("Thai (Thailand)")],
        ["tr-tr", qsTr("Turkish (Turkey)")], ["uk-ua", qsTr("Ukrainian (Ukraine)")], ["vi-vn", qsTr("Vietnamese (Vietnam)")], ["cy-gb", qsTr("Welsh (United Kingdom)")]]
    function languageName(code) { const l = languages.find(x => x[0] === code); return l ? l[1] : code }

    function ask(m) {
        mode = m
        language = backend.setting("spokenLanguage") || "en-us"
        audioOnly = false
        moreOptions = true
        open()
    }

    readonly property bool withLanguage: mode !== "recording"
    readonly property bool withRecordMode: !languageOnly
    width: languageOnly ? 480 : 522
    height: buttons.y + 31.33 + 24.67

    Text {
        x: 24.67; y: 24.67; height: 31.33
        width: root.width - 24.67 - 74.67
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.languageOnly ? qsTr("What language is everyone speaking?")
            : root.mode === "recording" ? qsTr("Start recording") : qsTr("Start recording and transcription")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    // Close (32 x 31.33 at the title's end).
    Rectangle {
        id: hcFill1
        x: root.width - 24.67 - 32; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close")
    }
    Column {
        id: content
        x: 24.67; y: root.withLanguage ? 64.67 : 63.33
        width: root.width - 49.33
        Text {
            visible: root.withLanguage
            width: parent.width
            wrapMode: Text.Wrap
            text: qsTr("Select the correct language to ensure the accuracy of features that process audio.")
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 19.33; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item { visible: root.withLanguage; width: 1; height: 107 - 64.67 - 38.67 }
        Text {
            visible: root.withLanguage
            height: 20; verticalAlignment: Text.AlignVCenter
            text: qsTr("Spoken language")
            font.family: theme.font; font.pixelSize: 12
            color: theme.textSecondary
        }
        Item { visible: root.withLanguage; width: 1; height: 5.67 }
        Dropdown {
            id: langDrop
            visible: root.withLanguage
            x: 0.67; width: parent.width - 1.33
            label: root.languageName(root.language)
            // Teams: the current choice first, then every language.
            options: [[root.language, root.languageName(root.language)]].concat(root.languages)
            onPicked: code => root.language = code
            accessibleName: qsTr("Spoken language")
        }
        // "More options" with "Choose what to record".
        Item { visible: root.withLanguage && root.withRecordMode; width: 1; height: 16.67 }
        Rectangle { visible: root.withLanguage && root.withRecordMode; width: parent.width; height: 0.67; color: theme.divider }
        Item {
            visible: root.withLanguage && root.withRecordMode
            width: parent.width; height: 44
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.text; rotation: root.moreOptions ? 0 : -90 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("More options"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.moreOptions = !root.moreOptions }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More options")
        }
        Rectangle {
            visible: root.withRecordMode && (root.moreOptions || !root.withLanguage)
            x: 2; width: parent.width - 4; height: 51.33; radius: 6
            color: theme.surface
            border.color: theme.dividerSoft; border.width: 0.67
            Text {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Choose what to record")
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            Dropdown {
                x: parent.width - 10 - 248.67; anchors.verticalCenter: parent.verticalCenter
                width: 248.67
                label: root.audioOnly ? qsTr("Audio only") : qsTr("Video and audio")
                options: [["video", qsTr("Video and audio")], ["audio", qsTr("Audio only")]]
                onPicked: code => root.audioOnly = code === "audio"
                accessibleName: qsTr("Choose what to record")
            }
        }
    }
    Row {
        id: buttons
        x: root.width - 24.67 - width
        // Measured: 14.67 under the language dropdown, 18 under the
        // record box (18.67 in "Start recording").
        y: content.y + content.height + (root.languageOnly ? 14.67 : root.mode === "recording" ? 18.67 : 18)
        spacing: 8
        component DialogButton: Rectangle {
            id: db
            property string label
            property bool primary: false
            signal clicked()
            width: 96; height: 31.33; radius: 4
            color: primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill)
                           : (dbHover.hovered ? theme.menuHover : theme.surface)
            border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
            Text {
                anchors.centerIn: parent
                text: db.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.onFill(db, db.primary ? theme.textOnBrand : theme.text)
            }
            HoverHandler { id: dbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: db.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: db.label
        }
        DialogButton { label: qsTr("Cancel"); onClicked: root.close() }
        DialogButton {
            label: qsTr("Confirm"); primary: true
            onClicked: {
                if (root.withLanguage) backend.setSetting("spokenLanguage", root.language)
                root.close()
                root.confirmed(root.language, root.audioOnly)
            }
        }
    }

    // Fluent's Dropdown: 30 tall, a hairline border with a darker bottom
    // edge, text 12 in, the chevron at the end; its list (padding 4, rows
    // 32, max 300) opens below, or above when there's no room.
}
