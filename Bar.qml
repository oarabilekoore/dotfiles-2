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

    property string activePopup: ""
    property var trayItem: null
    property var trayAnchor: null

    // Auto-hide keeps a tiny hover target at the top edge so the bar can
    // always be revealed without reserving the full bar height.
    property bool barShown: true
    readonly property int revealHeight: 3

    Timer {
        id: hideTimer
        interval: 550
        repeat: false
        onTriggered: {
            if (Config.autoHideBar
                    && !hoverSensor.containsMouse
                    && barWindow.activePopup === "") {
                barWindow.barShown = false;
            }
        }
    }

    Component.onCompleted: {
        if (Config.autoHideBar)
            hideTimer.start();
    }

    Connections {
        target: Config

        function onAutoHideBarChanged() {
            if (!Config.autoHideBar) {
                hideTimer.stop();
                barWindow.barShown = true;
            } else if (!hoverSensor.containsMouse && barWindow.activePopup === "") {
                hideTimer.restart();
            }
        }
    }

    onActivePopupChanged: {
        if (activePopup === "" && Config.autoHideBar && !hoverSensor.containsMouse)
            hideTimer.restart();
        else
            hideTimer.stop();
    }

    // Clicks pass through the transparent bar area except where modules
    // provide their own controls. This area only handles empty-space clicks.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: barWindow.activePopup = ""
    }

    // Hover-only sensor. No mouse buttons are accepted, so module clicks
    // continue to reach their own controls.
    MouseArea {
        id: hoverSensor
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: barWindow.barShown ? parent.height : barWindow.revealHeight
        z: 10
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onEntered: {
            hideTimer.stop();
            barWindow.barShown = true;
        }

        onExited: {
            if (Config.autoHideBar && barWindow.activePopup === "")
                hideTimer.restart();
        }
    }

    Item {
        id: barContent
        anchors.fill: parent
        y: barWindow.barShown ? 0 : -Theme.barHeight + barWindow.revealHeight

        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
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
            visible: Config.showClock
        }

        Row {
            id: rightModules
            anchors.right: parent.right
            anchors.rightMargin: 2
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

            // Keep the subtle separators between the right-side status groups.
            Item {
                width: 10
                height: Theme.barHeight
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 14
                    radius: 1
                    color: Theme.outline
                }
            }

            VolumeModule {
                id: volMod
                parentBar: barWindow
            }

            Item {
                width: Config.showBattery ? 10 : 0
                height: Theme.barHeight
                visible: Config.showBattery
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 14
                    radius: 1
                    color: Theme.outline
                }
            }

            BatteryModule {
                id: batMod
                parentBar: barWindow
                visible: Config.showBattery
            }
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

    // Keep the power popup pre-rendered so its controls and profile state are
    // ready before it is shown. Only the layer surface visibility changes.
    BatteryPopup {
        visible: barWindow.activePopup === "battery"
        parentBar: barWindow
        anchorItem: batMod
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
