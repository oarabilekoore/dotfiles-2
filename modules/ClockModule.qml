import QtQuick
import QtQuick.Controls
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
        command: [Config.terminalCmd, "-e", "tzselect"]
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    function ordinal(day) {
        const mod100 = day % 100;
        if (mod100 >= 11 && mod100 <= 13) return day + "th";
        switch (day % 10) {
        case 1: return day + "st";
        case 2: return day + "nd";
        case 3: return day + "rd";
        default: return day + "th";
        }
    }

    readonly property string timeText: {
        const now = sysClock.date;
        const h = String(now.getHours()).padStart(2, "0");
        const m = String(now.getMinutes()).padStart(2, "0");
        const time = h + ":" + m;
        const weekday = root.dayNames[now.getDay()];

        if (Config.clockFormat === "long")
            return weekday + ", " + root.ordinal(now.getDate()) + " " + root.monthNames[now.getMonth()] + ", " + time;
        if (Config.clockFormat === "time")
            return time;
        return weekday + " " + time;
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

    Menu {
        id: formatMenu
        title: "Date and time format"

        MenuItem {
            text: "Current  ·  Sunday 00:31"
            checkable: true
            checked: Config.clockFormat === "weekday"
            onTriggered: Config.set("clockFormat", "weekday")
        }
        MenuItem {
            text: "Long  ·  Sunday, 12th November, 00:31"
            checkable: true
            checked: Config.clockFormat === "long"
            onTriggered: Config.set("clockFormat", "long")
        }
        MenuItem {
            text: "Time only  ·  00:31"
            checkable: true
            checked: Config.clockFormat === "time"
            onTriggered: Config.set("clockFormat", "time")
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                formatMenu.popup();
            } else if (parentBar) {
                parentBar.activePopup = (parentBar.activePopup === root.popupName ? "" : root.popupName);
            }
        }
    }
}
