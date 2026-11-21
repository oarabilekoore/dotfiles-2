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

    // Clicking the transparent space between the three capsules closes popups.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: barWindow.activePopup = ""
    }

    // Left capsule: workspaces, tray and media controls stay together.
    Rectangle {
        id: leftCapsule
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: leftModules.implicitWidth + 16
        height: Theme.barHeight
        radius: height / 2
        color: Theme.background
        border.width: 1
        border.color: Theme.outline_variant

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
    }

    // The clock is its own capsule, visually detached from both sides.
    Rectangle {
        id: clockCapsule
        anchors.centerIn: parent
        width: Config.showClock ? clockMod.width + 16 : 0
        height: Theme.barHeight
        radius: height / 2
        color: Config.showClock ? Theme.background : "transparent"
        border.width: Config.showClock ? 1 : 0
        border.color: Theme.outline_variant
        visible: Config.showClock

        ClockModule {
            id: clockMod
            anchors.centerIn: parent
            parentBar: barWindow
            visible: Config.showClock
        }
    }

    // Right capsule: keep every existing status module, with quiet separators
    // to create the grouped rhythm shown in the reference.
    Rectangle {
        id: rightCapsule
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: rightModules.implicitWidth + 12
        height: Theme.barHeight
        radius: height / 2
        color: Theme.background
        border.width: 1
        border.color: Theme.outline_variant

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

            // Network, audio and power are visually separated without
            // changing their order, visibility or interaction behaviour.
            Item {
                width: Config.showNetwork ? 8 : 0
                height: Theme.barHeight
                visible: Config.showNetwork
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 14
                    radius: 1
                    color: Theme.outline
                }
            }

            NetworkModule {
                id: netMod
                parentBar: barWindow
                visible: Config.showNetwork
            }

            Item {
                width: Config.showNetwork ? 8 : 0
                height: Theme.barHeight
                visible: Config.showNetwork
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 14
                    radius: 1
                    color: Theme.outline
                }
            }

            VolumeModule { id: volMod; parentBar: barWindow }

            Item {
                width: Config.showBattery ? 8 : 0
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
