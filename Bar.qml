import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "modules"
import "popups"

PanelWindow {
    id: barWindow

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        left: Theme.barMargin
        right: Theme.barMargin
        top: Theme.barMargin
    }

    implicitHeight: Theme.barHeight
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell"

    property var osd: null
    property var notificationCenter: null
    property string activePopup: ""
    property var trayItem: null
    property var trayAnchor: null

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: barWindow.activePopup = ""
    }

    Rectangle {
        anchors.fill: parent
        z: -2
        radius: Theme.barRadius
        color: Theme.background
        border.width: 1
        border.color: Theme.outline_variant
    }

    Row {
        id: leftModules
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Workspaces { visible: Config.showWorkspaces }
SystemTrayModule {
            id: trayMod
            parentBar: barWindow
            visible: Config.showTray
        }

        MprisModule {
            id: mprisMod
            parentBar: barWindow
            visible: Config.showMpris
        }

    }

    ClockModule {
        id: clockMod
        anchors.centerIn: parent
        parentBar: barWindow
        osd: barWindow.osd
        visible: Config.showClock
    }

    Row {
        id: rightModules
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        
        BluetoothModule {
            id: btMod
            parentBar: barWindow
            visible: Config.showBluetooth
        }

        CaffeineModule { visible: Config.showCaffeine }

        NetworkModule {
            id: netMod
            parentBar: barWindow
            visible: Config.showNetwork
        }

        VolumeModule { id: volMod; parentBar: barWindow }

        BatteryModule {
            id: batMod
            parentBar: barWindow
            visible: Config.showBattery
        }

    }

    // Popup windows are expensive layer surfaces with their own object trees.
    // Only the selected popup exists; closing it destroys its object tree.
    LazyLoader {
        activeAsync: barWindow.activePopup === "wifi"
        WifiPopup {
            parentBar: barWindow
            anchorItem: netMod
        }
    }

    LazyLoader {
        activeAsync: barWindow.activePopup === "volume"
        VolumePopup {
            parentBar: barWindow
            anchorItem: volMod
        }
    }

    LazyLoader {
        activeAsync: barWindow.activePopup === "bluetooth"
        BluetoothPopup {
            parentBar: barWindow
            anchorItem: btMod
        }
    }

    LazyLoader {
        activeAsync: barWindow.activePopup === "battery"
        BatteryPopup {
            parentBar: barWindow
            anchorItem: batMod
        }
    }

    LazyLoader {
        activeAsync: barWindow.activePopup === "traymenu"
        TrayMenuPopup {
            parentBar: barWindow
            anchorItem: barWindow.trayAnchor
        }
    }

    LazyLoader {
        activeAsync: barWindow.activePopup === "calendar"
        CalendarPopup {
            parentBar: barWindow
            anchorItem: clockMod
        }
    }

    LazyLoader {
        activeAsync: barWindow.activePopup === "mpris"
        MprisPopup {
            parentBar: barWindow
            anchorItem: mprisMod
            player: mprisMod.activePlayer
        }
    }
}
