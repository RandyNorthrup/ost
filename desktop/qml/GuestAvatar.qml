import QtQuick

// The avatar Teams gives a guest its join shield flagged: one of eight
// rounded-square app glyphs, picked by hashing the participant id the way
// Teams does (sum of char codes × position, modulo 8).
Image {
    property string personId: ""
    property int size: 32
    width: size; height: size
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
    source: "../assets/lobby/guest-" + pick(personId) + ".svg"

    function pick(id) {
        let g = 0
        for (let i = 0; i < id.length; i++) g += id.charCodeAt(i) * (i + 1)
        return Math.abs(g) % 8
    }
}
