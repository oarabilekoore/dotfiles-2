import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool isEnabled: adapter && adapter.enabled

    readonly property bool hasConnectedDevice: {
        if (!adapter || !adapter.devices || !adapter.devices.values) return false;
        for (let i = 0; i < adapter.devices.values.length; i++) {
            let d = adapter.devices.values[i];
            if (d && d.connected) return true;
        }
        return false;
    }

    readonly property string btIcon: {
        if (!isEnabled) return "󰂲";
        if (hasConnectedDevice) return "󰂱";
        return "";
    }

    Process {
        id: bluetuiProc
        command: ["ghostty", "--class", "floating", "-e", "bluetui"]
    }

    height: Theme.barHeight
    width: Theme.moduleWidth
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName)) ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Text {
        id: btText
        anchors.centerIn: parent
        text: root.btIcon
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: root.isEnabled ? Theme.foreground : Theme.color7
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                bluetuiProc.running = true;
            } else {
                if (parentBar) {
                    parentBar.activePopup = (parentBar.activePopup === root.popupName ? "" : root.popupName);
                }
            }
        }
    }
}
