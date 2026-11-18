import QtQuick
import ".."

Rectangle {
    id: root

    property bool checked: false
    property bool interactive: true
    signal toggled()

    implicitWidth: 44
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.primary : Theme.outline_variant
    border.color: checked ? Theme.primary : Theme.outline
    border.width: 1
    opacity: interactive ? 1.0 : 0.45

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 3 : 3
        color: root.checked ? Theme.on_primary : Theme.on_surface_variant

        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
