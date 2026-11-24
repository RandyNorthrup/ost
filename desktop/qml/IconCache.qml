pragma Singleton
import QtQuick

// SVG source text by URL, so each icon file is read once.
QtObject {
    property var entries: ({})
    function get(url) { return entries[url] }
    function put(url, text) { entries[url] = text }
}
