import QtQuick
import Quickshell
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "settings"

    height: Theme.barHeight
    width: Theme.moduleWidth
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName))
           ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Text {
        anchors.centerIn: parent
        text: "󰒓"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.foreground
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.parentBar)
                root.parentBar.activePopup = (root.parentBar.activePopup === root.popupName ? "" : root.popupName);
        }
    }
}
