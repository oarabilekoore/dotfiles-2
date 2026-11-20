import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import ".."

Row {
    id: root

    property var parentBar: null
    property bool expanded: false

    readonly property int iconSize: 16
    readonly property int expanderWidth: 24

    spacing: 0
    visible: trayRepeater.count > 0

    // Match Omarchy: keep a small chevron visible and reveal the tray on hover.
    // The expanded state follows the pointer across the chevron and tray icons.
    HoverHandler {
        onHoveredChanged: root.expanded = hovered
    }

    Item {
        width: root.expanderWidth
        height: Theme.barHeight

        Text {
            anchors.centerIn: parent
            text: ">"
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.bold: true
            color: Theme.foreground
            rotation: root.expanded ? 90 : 0

            Behavior on rotation {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    Repeater {
        id: trayRepeater
        model: SystemTray.items

        delegate: Rectangle {
            id: box
            required property var modelData
            readonly property var item: modelData

            width: root.expanded ? Theme.moduleWidth : 0
            height: Theme.barHeight
            clip: true
            color: trayMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
            radius: Theme.moduleRadius

            Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            function openMenu() {
                const bar = root.parentBar;
                if (!bar || !box.item || !box.item.hasMenu) return;
                const same = bar.activePopup === "traymenu" && bar.trayItem === box.item;
                bar.trayItem = box.item;
                bar.trayAnchor = box;
                bar.activePopup = same ? "" : "traymenu";
            }

            Text {
                anchors.centerIn: parent
                visible: trayIcon.status !== Image.Ready
                text: box.item && box.item.title ? box.item.title.charAt(0).toUpperCase() : "?"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.foreground
            }

            // Keep the application's supplied icon untouched, including its colours.
            IconImage {
                id: trayIcon
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                implicitSize: root.iconSize
                mipmap: true
                source: box.item ? box.item.icon : ""
            }

            MouseArea {
                id: trayMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor

                onClicked: (mouse) => {
                    if (!box.item) return;
                    if (mouse.button === Qt.RightButton) {
                        box.openMenu();
                    } else if (mouse.button === Qt.MiddleButton) {
                        box.item.secondaryActivate();
                    } else if (box.item.onlyMenu) {
                        box.openMenu();
                    } else {
                        box.item.activate();
                    }
                }
            }
        }
    }
}
