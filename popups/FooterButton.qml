import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 28
    radius: 4
    color: mouse.containsMouse ? Theme.surface_variant : "transparent"
    border.color: Theme.outline_variant
    border.width: 1

    Row {
        anchors.centerIn: parent
        spacing: 6

        Text {
            visible: root.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.primary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            color: Theme.foreground
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
