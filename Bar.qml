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

    // The reference uses broad, shallow backplates separated by clear gaps.
    // Keep the three zones stretched across the bar instead of wrapping each
    // zone tightly around its contents.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: barWindow.activePopup = ""
    }

    RowLayout {
        id: barSegments
        anchors.fill: parent
        spacing: 12

        // Left segment: workspace, tray and media modules.
        Rectangle {
            id: leftSegment
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
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

        // Centre segment: clock stays centred in its own wide section.
        Rectangle {
            id: clockSegment
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            radius: height / 2
            color: Theme.background
            border.width: 1
            border.color: Theme.outline_variant
            visible: Config.showClock

            ClockModule {
                id: clockMod
                anchors.centerIn: parent
                parentBar: barWindow
                visible: Config.showClock
            }
        }

        // Right segment: status modules retain their original order and actions.
        Rectangle {
            id: rightSegment
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            radius: height / 2
            color: Theme.background
            border.width: 1
            border.color: Theme.outline_variant

            Row {
                id: rightModules
                anchors.right: parent.right
                anchors.rightMargin: 8
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

                // Separate connectivity, audio and power into quiet groups.
                Item {
                    width: Config.showNetwork ? 10 : 0
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
