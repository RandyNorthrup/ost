import QtQuick
import QtQuick.Window

// One of Teams' emoticon images (personal expressions) for a reaction or
// emoji key, at a Teams named size ("medium" for the hover bar's
// reactions); drawn at `size` px.
Image {
    id: root
    property string key
    property string named: "medium"
    property int size: 20
    width: size; height: size
    sourceSize: Qt.size(size * 3, size * 3)
    fillMode: Image.PreserveAspectFit
    smooth: true; mipmap: true
    source: {
        backend.emoticonsVersion
        if (!key) return ""
        return backend.emoticonUrl(key, backend.emoticonSize(named, Screen.devicePixelRatio > 1))
    }
}
