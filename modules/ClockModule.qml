import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "calendar"
    property var osd: null

    readonly property bool showingOsd: Config.osdOnClock && osd && osd.shown
    height: Theme.barHeight
    width: Math.max(clockText.implicitWidth, osdText.implicitWidth) + 22
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName)) ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Process {
        id: tzProc
        command: ["ghostty", "--class", "floating", "-e", "tzselect"]
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    function formatTime() {
        let now = new Date();
        let day = root.dayNames[now.getDay()];
        let h = String(now.getHours()).padStart(2, '0');
        let m = String(now.getMinutes()).padStart(2, '0');
        return day + " " + h + ":" + m;
    }

    Text {
        id: clockText
        anchors.centerIn: parent
        text: root.formatTime()
        visible: !root.showingOsd
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.foreground
    }

    Row {
        id: osdText
        anchors.centerIn: parent
        visible: root.showingOsd
        spacing: 7
        opacity: root.showingOsd ? 1 : 0
        scale: root.showingOsd ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Text {
            text: root.osd ? root.osd.glyph : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.primary
        }
        Text {
            text: root.osd ? root.osd.label : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            color: Theme.foreground
        }
    }

    // Refresh every minute
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: clockText.text = root.formatTime()
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
