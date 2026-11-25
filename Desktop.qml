import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "."

PanelWindow {
    id: root

    required property var modelData
    screen: modelData
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property bool menuOpen: false
    property string memoryText: "Reading memory…"
    property string loadText: "Reading system load…"

    function saveWidgetPosition(which, item) {
        if (which === "clock") {
            Config.set("desktopClockX", Math.round(item.x));
            Config.set("desktopClockY", Math.round(item.y));
        } else {
            Config.set("desktopSystemX", Math.round(item.x));
            Config.set("desktopSystemY", Math.round(item.y));
        }
    }

    Process {
        id: statsProc
        command: ["sh", "-c", "free -h | awk '/^Mem:/ {print $3 \" / \" $2}'; printf '\\n'; cut -d' ' -f1-3 /proc/loadavg"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length > 0 && lines[0]) root.memoryText = lines[0].trim();
                if (lines.length > 1 && lines[1]) root.loadText = lines[1].trim();
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: statsProc.running = true
    }

    Component.onCompleted: statsProc.running = true

    // Right-click on the desktop opens the context menu. Only right-clicks are
    // accepted here; ordinary left-clicks continue to the desktop underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        z: 0
        onClicked: (mouse) => {
            const menu = contextMenu;
            menu.x = Math.max(12, Math.min(mouse.x, root.width - menu.width - 12));
            menu.y = Math.max(12, Math.min(mouse.y, root.height - menu.height - 12));
            root.menuOpen = true;
        }
    }

    // When the menu is open, a left-click outside it dismisses the menu.
    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        acceptedButtons: Qt.LeftButton
        z: 5
        onClicked: root.menuOpen = false
    }

    Item {
        id: widgetsLayer
        anchors.fill: parent
        visible: Config.desktopWidgetsEnabled
        z: 1

        Rectangle {
            id: clockWidget
            x: Config.desktopClockX
            y: Config.desktopClockY
            width: 286
            height: 126
            radius: Theme.popupRadius
            color: Theme.alpha(Theme.surface, 0.88)
            border.width: 1
            border.color: Theme.outline_variant

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 5

                Text {
                    text: Qt.formatTime(new Date(), "HH:mm")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 42
                    font.bold: true

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: parent.text = Qt.formatTime(new Date(), "HH:mm")
                    }
                }

                Text {
                    text: Qt.formatDate(new Date(), "dddd, d MMMM yyyy")
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                drag.target: clockWidget
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onReleased: root.saveWidgetPosition("clock", clockWidget)
            }
        }

        Rectangle {
            id: systemWidget
            x: Config.desktopSystemX
            y: Config.desktopSystemY
            width: 286
            height: 116
            radius: Theme.popupRadius
            color: Theme.alpha(Theme.surface, 0.88)
            border.width: 1
            border.color: Theme.outline_variant

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: "SYSTEM"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Row {
                    spacing: 8
                    Text {
                        text: "󰍛"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                    }
                    Text {
                        text: "Memory  " + root.memoryText
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                Row {
                    spacing: 8
                    Text {
                        text: "󰓅"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                    }
                    Text {
                        text: "Load       " + root.loadText
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                drag.target: systemWidget
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onReleased: root.saveWidgetPosition("system", systemWidget)
            }
        }
    }

    Rectangle {
        id: contextMenu
        visible: root.menuOpen
        z: 10
        width: 224
        height: menuColumn.implicitHeight + 18
        radius: Theme.popupRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline_variant

        Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3

            Text {
                text: "DESKTOP"
                leftPadding: 10
                topPadding: 7
                bottomPadding: 7
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 36
                radius: 4
                color: widgetsToggle.containsMouse ? Theme.surface_variant : "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: Config.desktopWidgetsEnabled ? "Hide desktop widgets" : "Show desktop widgets"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    id: widgetsToggle
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Config.set("desktopWidgetsEnabled", !Config.desktopWidgetsEnabled);
                        root.menuOpen = false;
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 36
                radius: 4
                color: wallpaperAction.containsMouse ? Theme.surface_variant : "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Change wallpaper"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    id: wallpaperAction
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Quickshell.execDetached(["waypaper"]);
                        root.menuOpen = false;
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 36
                radius: 4
                color: configAction.containsMouse ? Theme.surface_variant : "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Open Quickshell config"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    id: configAction
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Quickshell.execDetached([Config.terminalCmd, "-e", "nvim", Config.configDir]);
                        root.menuOpen = false;
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 36
                radius: 4
                color: themeAction.containsMouse ? Theme.surface_variant : "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Refresh theme"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    id: themeAction
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Quickshell.execDetached(["quickshell", "ipc", "call", "theme", "reload"]);
                        root.menuOpen = false;
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.menuOpen
        onActivated: root.menuOpen = false
    }
}
