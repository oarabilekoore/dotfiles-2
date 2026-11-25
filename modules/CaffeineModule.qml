import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    // caffeine.sh creates / removes this flag file; we just watch it.
    readonly property string flagPath: "/tmp/caffeine_on"
    property bool isCaffeineOn: false

    // Event-driven: no polling process. loadFailed == flag file absent == off.
    FileView {
        id: flag
        path: root.flagPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.isCaffeineOn = true
        onLoadFailed: root.isCaffeineOn = false
    }

    Process {
        id: toggleProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/caffeine.sh", "toggle"]
        onExited: flag.reload()
    }

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
        // Cheap resync in case the flag was toggled externally (keybind) before the watch caught it.
        onContainsMouseChanged: if (containsMouse) flag.reload()
        onClicked: toggleProc.running = true
    }
}
