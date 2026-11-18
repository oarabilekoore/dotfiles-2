import QtQuick
import Quickshell
import Quickshell.Networking
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "wifi"

    readonly property var wifiDev: {
        if (!Networking.devices || !Networking.devices.values) return null;
        for (let i = 0; i < Networking.devices.values.length; i++) {
            let d = Networking.devices.values[i];
            if (d && d.scannerEnabled !== undefined) return d;
        }
        return null;
    }

    readonly property var connectedNetwork: {
        if (!wifiDev || !wifiDev.networks || !wifiDev.networks.values) return null;
        for (let i = 0; i < wifiDev.networks.values.length; i++) {
            let n = wifiDev.networks.values[i];
            if (n && n.connected) return n;
        }
        return null;
    }

    readonly property bool isConnected: connectedNetwork !== null
    readonly property real signalStrength: connectedNetwork ? connectedNetwork.signalStrength : 0.0

    readonly property string networkIcon: {
        if (!Networking.wifiEnabled) return "󰖪";
        if (!isConnected) return "󰤯";
        if (signalStrength >= 0.8) return "󰤨";
        if (signalStrength >= 0.6) return "󰤥";
        if (signalStrength >= 0.4) return "󰤢";
        if (signalStrength >= 0.2) return "󰤟";
        return "󰤯";
    }

    height: Theme.barHeight
    width: Theme.moduleWidth
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName)) ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Text {
        id: netIcon
        anchors.centerIn: parent
        text: root.networkIcon
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: root.isConnected ? Theme.foreground : Theme.color7
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (parentBar) {
                parentBar.activePopup = (parentBar.activePopup === root.popupName ? "" : root.popupName);
            }
        }
    }
}
