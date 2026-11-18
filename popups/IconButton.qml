import QtQuick
import ".."

Rectangle {
    id: root

    property string glyph: ""
    property bool active: false
    signal clicked()

    implicitWidth: 26
    implicitHeight: 26
    radius: 4
    color: mouse.containsMouse ? Theme.surface_variant : "transparent"
    border.color: Theme.outline_variant
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Theme.fontFamily
        font.pixelSize: 14
        color: root.active ? Theme.primary : Theme.foreground
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
