import QtQuick

// A message's text, as the chat draws it (the engine's safe HTML).
Text {
    property var message
    /// Right to left, a message keeps its own direction (Teams' dir="auto").
    readonly property bool ostAutoDirection: true
    /// Find's terms to mark in it.
    property var mark: []
    lineHeight: 20; lineHeightMode: Text.FixedHeight
    text: !message ? "" : message.deleted ? qsTr("This message has been deleted.")
        : "<style>a { color: " + theme.link + "; text-decoration: none; } .mention { color: " + theme.brandForeground1
          + "; } .mention-me { color: " + theme.mentionMe + "; font-weight: 700; }"
          // Paragraphs with no space between them, as in the chat (a Channel
          // Agent's welcome in a posts channel, measured 2026-11-22: <p>s 20
          // apart).
          + " p { margin-top: 0px; margin-bottom: 0px; }</style>" + (mark && mark.length ? theme.markTerms(message.html ? theme.messageHtml(message.html) : message.text, mark) : message.html ? theme.messageHtml(message.html) : message.text)
    textFormat: message && message.deleted ? Text.PlainText : Text.RichText
    wrapMode: Text.Wrap
    font.family: theme.font; font.pixelSize: theme.base
    font.italic: !!message && message.deleted === true
    color: message && message.deleted ? theme.textSecondary : theme.text
    linkColor: theme.link
    onLinkActivated: link => Qt.openUrlExternally(link)
    HoverHandler { cursorShape: parent && parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
    Accessible.name: message ? message.text : ""
}
