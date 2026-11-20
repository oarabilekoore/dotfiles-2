import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "calendar"

    height: Theme.barHeight
    width: clockText.implicitWidth + 22
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName)) ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Process {
        id: tzProc
        command: [Config.terminalCmd, "--class", "floating", "-e", "tzselect"]
    }

    // Ticks once a minute; the label below is bound to it, so no extra timer is needed.
    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    readonly property string timeText: {
        const now = sysClock.date;
        const h = String(now.getHours()).padStart(2, "0");
        const m = String(now.getMinutes()).padStart(2, "0");
        return root.dayNames[now.getDay()] + " " + h + ":" + m;
    }

    Text {
        id: clockText
        anchors.centerIn: parent
        text: root.timeText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.foreground
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                tzProc.running = true;
            } else {
                if (parentBar) {
                    parentBar.activePopup = (parentBar.activePopup === root.popupName ? "" : root.popupName);
                }
            }
        }
    }
}
