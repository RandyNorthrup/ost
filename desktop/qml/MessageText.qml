import QtQuick

// A message's text, as the chat draws it (the engine's safe HTML).
Text {
    property var message
    /// Find's terms to mark in it.
    property var mark: []
    lineHeight: 20; lineHeightMode: Text.FixedHeight
    text: !message ? "" : message.deleted ? "This message has been deleted."
        : "<style>a { color: " + theme.brand + "; text-decoration: none; } .mention { color: " + theme.brandForeground1
          + "; } .mention-me { color: " + theme.mentionMe + "; font-weight: 700; }</style>" + (mark && mark.length ? theme.markTerms(message.html ? theme.messageHtml(message.html) : message.text, mark) : message.html ? theme.messageHtml(message.html) : message.text)
    textFormat: message && message.deleted ? Text.PlainText : Text.RichText
    wrapMode: Text.Wrap
    font.family: theme.font; font.pixelSize: theme.base
    font.italic: !!message && message.deleted === true
    color: message && message.deleted ? theme.textSecondary : theme.text
    linkColor: theme.brand
    onLinkActivated: link => Qt.openUrlExternally(link)
    HoverHandler { cursorShape: parent && parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
    Accessible.name: message ? message.text : ""
}
