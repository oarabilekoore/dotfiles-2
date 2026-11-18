import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import ".."

Row {
    id: root

    property var parentBar: null

    // Every icon is forced to this size and drawn monochrome in the theme's foreground
    // colour, so mixed app icons (coloured, tiny, huge, symbolic) all look the same.
    readonly property int iconSize: 16
    // false: greyscale keeping the icon's shading, tinted with Theme.foreground
    // true:  flat silhouette in Theme.foreground
    readonly property bool silhouette: false

    spacing: 0
    visible: trayRepeater.count > 0

    Repeater {
        id: trayRepeater
        model: SystemTray.items

        delegate: Rectangle {
            id: box
            required property var modelData
            readonly property var item: modelData

            width: Theme.moduleWidth
            height: Theme.barHeight
            color: trayMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
            radius: Theme.moduleRadius

            function openMenu() {
                const bar = root.parentBar;
                if (!bar || !box.item || !box.item.hasMenu) return;
                const same = bar.activePopup === "traymenu" && bar.trayItem === box.item;
                bar.trayItem = box.item;
                bar.trayAnchor = box;
                bar.activePopup = same ? "" : "traymenu";
            }

            // Shown when an app gives us no usable icon
            Text {
                anchors.centerIn: parent
                visible: trayIcon.status !== Image.Ready
                text: box.item && box.item.title ? box.item.title.charAt(0).toUpperCase() : "?"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.foreground
            }

            IconImage {
                id: trayIcon
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                implicitSize: root.iconSize
                mipmap: true
                source: box.item ? box.item.icon : ""

                layer.enabled: true
                layer.effect: MultiEffect {
                    saturation: -1.0
                    brightness: root.silhouette ? 1.0 : 0.35
                    contrast: root.silhouette ? 0.0 : 0.15
                    colorization: 1.0
                    colorizationColor: Theme.foreground
                }
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
