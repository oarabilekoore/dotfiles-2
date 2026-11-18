import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool isCaffeineOn: false

    Process {
        id: checkProc
        command: ["bash", "-c", "if [ -f /tmp/caffeine_on ]; then echo 'on'; else echo 'off'; fi"]
        stdout: StdioCollector {
            onTextChanged: {
                root.isCaffeineOn = (text.trim() === "on");
            }
        }
    }

    Process {
        id: toggleProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/caffeine.sh", "toggle"]
        onExited: checkProc.running = true
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: checkProc.running = true
    }

    Component.onCompleted: checkProc.running = true

    height: Theme.barHeight
    width: Theme.moduleWidth
    color: mouseArea.containsMouse ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Text {
        id: cafIcon
        anchors.centerIn: parent
        text: root.isCaffeineOn ? "󰅶" : "󰛊"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: root.isCaffeineOn ? Theme.foreground : Theme.color7
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: toggleProc.running = true
    }
}
