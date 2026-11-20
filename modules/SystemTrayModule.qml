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
    visible: activeRepeater.count > 0

    // Shared tray entry used by both status groups. Passive entries are placed
    // after active and attention-seeking entries, regardless of registration order.
    component TrayEntry: Rectangle {
        id: entry

        required property var modelData
        property var trayRoot: null
        property bool passiveGroup: false
        readonly property var item: modelData
        readonly property bool belongsHere: (item.status === Status.Passive) === passiveGroup

        width: trayRoot && trayRoot.expanded && belongsHere ? Theme.moduleWidth : 0
        height: Theme.barHeight
        clip: true
        color: trayMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
        radius: Theme.moduleRadius

        Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        function openMenu() {
            const bar = entry.trayRoot ? entry.trayRoot.parentBar : null;
            if (!bar || !entry.item || !entry.item.hasMenu) return;
            const same = bar.activePopup === "traymenu" && bar.trayItem === entry.item;
            bar.trayItem = entry.item;
            bar.trayAnchor = entry;
            bar.activePopup = same ? "" : "traymenu";
        }

        Text {
            anchors.centerIn: parent
            visible: trayIcon.status !== Image.Ready
            text: entry.item && entry.item.title ? entry.item.title.charAt(0).toUpperCase() : "?"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            color: Theme.foreground
        }

        // Preserve the original icon supplied by each application.
        IconImage {
            id: trayIcon
            anchors.centerIn: parent
            width: trayRoot ? trayRoot.iconSize : 16
            height: trayRoot ? trayRoot.iconSize : 16
            implicitSize: trayRoot ? trayRoot.iconSize : 16
            mipmap: true
            source: entry.item ? entry.item.icon : ""
        }

        MouseArea {
            id: trayMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor

            onClicked: (mouse) => {
                if (!entry.item) return;
                if (mouse.button === Qt.RightButton) {
                    entry.openMenu();
                } else if (mouse.button === Qt.MiddleButton) {
                    entry.item.secondaryActivate();
                } else if (entry.item.onlyMenu) {
                    entry.openMenu();
                } else {
                    entry.item.activate();
                }
            }
        }
    }

    Item {
        width: root.expanderWidth
        height: Theme.barHeight

        Text {
            anchors.centerIn: parent
            text: "⌄"
            font.family: Theme.fontFamily
            font.pixelSize: 19
            font.bold: true
            color: Theme.foreground
            rotation: root.expanded ? 180 : 0

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

    // Active and NeedsAttention icons stay at the front.
    Repeater {
        id: activeRepeater
        model: SystemTray.items
        delegate: TrayEntry {
            trayRoot: root
            passiveGroup: false
        }
    }

    // Passive (idle/deactivated) icons are always grouped at the end.
    Repeater {
        model: SystemTray.items
        delegate: TrayEntry {
            passiveGroup: true
        }
    }
}
