import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "modules"
import "popups"

PanelWindow {
    id: barWindow

    // Required for multi-monitor Variants
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

    // Active popup: "wifi", "volume", "bluetooth", "battery", "calendar", "mpris", "settings", "traymenu" or "".
    // Popups dismiss themselves (focus loss) by clearing this.
    property string activePopup: ""

    // Tray item whose menu the "traymenu" popup shows, and the icon it hangs under
    property var trayItem: null
    property var trayAnchor: null

    // Click on empty bar space closes any popup
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: barWindow.activePopup = ""
    }

    // Rounded bar body with a subtle Geist-style border
    Rectangle {
        id: barBg
        anchors.fill: parent
        z: -2
        radius: Theme.barRadius
        color: Theme.background
        border.width: 1
        border.color: Theme.outline_variant
    }

    // --- LEFT MODULES ---
    Row {
        id: leftModules
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Workspaces { visible: Config.showWorkspaces }

        MprisModule {
            id: mprisMod
            parentBar: barWindow
            visible: Config.showMpris
        }

        DictationModule { visible: Config.showDictation }
    }

    // --- CENTER MODULE (CLOCK) ---
    ClockModule {
        id: clockMod
        anchors.centerIn: parent
        parentBar: barWindow
        osd: barWindow.osd
        visible: Config.showClock
    }

    // --- RIGHT MODULES ---
    Row {
        id: rightModules
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        SystemTrayModule {
            id: trayMod
            parentBar: barWindow
            visible: Config.showTray
        }

        BluetoothModule {
            id: btMod
            parentBar: barWindow
            visible: Config.showBluetooth
        }

        CaffeineModule {
            id: cafMod
            visible: Config.showCaffeine
        }

        NetworkModule {
            id: netMod
            parentBar: barWindow
            visible: Config.showNetwork
        }

        VolumeModule {
            id: volMod
            parentBar: barWindow
        }

        BatteryModule {
            id: batMod
            parentBar: barWindow
            visible: Config.showBattery
        }

        SettingsModule {
            id: setMod
            parentBar: barWindow
        }
    }

    // --- POPUPS ---
    WifiPopup {
        parentBar: barWindow
        anchorItem: netMod
        visible: barWindow.activePopup === "wifi"
    }

    VolumePopup {
        parentBar: barWindow
        anchorItem: volMod
        visible: barWindow.activePopup === "volume"
    }

    BluetoothPopup {
        parentBar: barWindow
        anchorItem: btMod
        visible: barWindow.activePopup === "bluetooth"
    }

    BatteryPopup {
        parentBar: barWindow
        anchorItem: batMod
        visible: barWindow.activePopup === "battery"
    }

    TrayMenuPopup {
        parentBar: barWindow
        anchorItem: barWindow.trayAnchor
        visible: barWindow.activePopup === "traymenu"
    }

    SettingsPopup {
        parentBar: barWindow
        anchorItem: setMod
        visible: barWindow.activePopup === "settings"
    }

    CalendarPopup {
        parentBar: barWindow
        anchorItem: clockMod
        visible: barWindow.activePopup === "calendar"
    }

    MprisPopup {
        parentBar: barWindow
        anchorItem: mprisMod
        player: mprisMod.activePlayer
        visible: barWindow.activePopup === "mpris"
    }
}
