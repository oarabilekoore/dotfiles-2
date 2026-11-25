import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Io
import ".."

PopupBase {
    id: root

    popupName: "battery"
    implicitWidth: 300
    implicitHeight: mainCol.implicitHeight + 28

    // All battery maths lives in Battery.qml (shared with the bar module)
    readonly property var dev: Battery.dev
    readonly property int percentage: Battery.percentage
    readonly property bool isCharging: Battery.charging
    readonly property bool isPendingCharge: Battery.plugged && !Battery.charging
    readonly property real changeRateWatts: dev ? Math.abs(dev.changeRate) : 0.0

    property string currentProfile: ""
    property bool profileLoaded: false

    Process {
        id: getProfileProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onTextChanged: {
                let p = text.trim();
                if (p.length > 0) {
                    root.currentProfile = p;
                    root.profileLoaded = true;
                }
            }
        }
    }

    Component.onCompleted: getProfileProc.running = true

    Process {
        id: setProfileProc
        onExited: {
            getProfileProc.running = true;
            Notify.status("Power profile updated");
        }
    }

    onVisibleChanged: {
        if (visible) getProfileProc.running = true;
    }

    function formatTime(seconds) {
        if (!seconds || seconds <= 0) return "";
        let hrs = Math.floor(seconds / 3600);
        let mins = Math.floor((seconds % 3600) / 60);
        if (hrs > 0) return hrs + "h " + mins + "m";
        return mins + "m";
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        ColumnLayout {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            // Header Row: Title & Battery icon
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: Battery.icon
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Battery.color
                }

                Text {
                    text: "Battery & Power"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.foreground
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.percentage + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    color: Battery.color
                }
            }

            // Status bar indicator
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Theme.surface_variant

                Rectangle {
                    width: Math.max(0, Math.min(parent.width, parent.width * (Battery.percent / 100.0)))
                    height: parent.height
                    radius: 3
                    color: Battery.barColor
                }
            }

            // Power Stats Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statsCol.implicitHeight + 16
                radius: 6
                color: Theme.surface_variant
                border.color: Theme.outline_variant
                border.width: 1

                ColumnLayout {
                    id: statsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Status:"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.on_surface_variant
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Battery.statusText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            color: Battery.plugged ? Theme.success : Theme.foreground
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.dev && ((root.isCharging && root.dev.timeToFull > 0) || (!Battery.plugged && root.dev.timeToEmpty > 0))
                        Text {
                            text: root.isCharging ? "Time to Full:" : "Time Remaining:"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.on_surface_variant
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.isCharging ? root.formatTime(root.dev ? root.dev.timeToFull : 0) : root.formatTime(root.dev ? root.dev.timeToEmpty : 0)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            color: Theme.foreground
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.changeRateWatts > 0.05
                        Text {
                            text: "Power Rate:"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.on_surface_variant
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.changeRateWatts.toFixed(1) + " W"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            color: Theme.foreground
                        }
                    }
                }
            }

            // Power Profiles Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "POWER PROFILE"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    color: Theme.on_surface_variant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Performance
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 4
                        color: root.profileLoaded && root.currentProfile === "performance" ? Theme.primary : (perfMouse.containsMouse ? Theme.surface_variant : "transparent")
                        border.color: root.profileLoaded && root.currentProfile === "performance" ? Theme.primary : Theme.outline_variant
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "󰓅"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: root.profileLoaded && root.currentProfile === "performance" ? Theme.on_primary : Theme.foreground
                            }
                            Text {
                                text: "Perf"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: root.profileLoaded && root.currentProfile === "performance" ? Theme.on_primary : Theme.foreground
                            }
                        }

                        MouseArea {
                            id: perfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentProfile = "performance";
                                setProfileProc.command = ["powerprofilesctl", "set", "performance"];
                                setProfileProc.running = true;
                            }
                        }
                    }

                    // Balanced
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 4
                        color: root.profileLoaded && root.currentProfile === "balanced" ? Theme.primary : (balMouse.containsMouse ? Theme.surface_variant : "transparent")
                        border.color: root.profileLoaded && root.currentProfile === "balanced" ? Theme.primary : Theme.outline_variant
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "󰾅"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: root.profileLoaded && root.currentProfile === "balanced" ? Theme.on_primary : Theme.foreground
                            }
                            Text {
                                text: "Bal"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: root.profileLoaded && root.currentProfile === "balanced" ? Theme.on_primary : Theme.foreground
                            }
                        }

                        MouseArea {
                            id: balMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentProfile = "balanced";
                                setProfileProc.command = ["powerprofilesctl", "set", "balanced"];
                                setProfileProc.running = true;
                            }
                        }
                    }

                    // Power Saver
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 4
                        color: root.profileLoaded && root.currentProfile === "power-saver" ? Theme.primary : (saverMouse.containsMouse ? Theme.surface_variant : "transparent")
                        border.color: root.profileLoaded && root.currentProfile === "power-saver" ? Theme.primary : Theme.outline_variant
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "󰾆"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: root.profileLoaded && root.currentProfile === "power-saver" ? Theme.on_primary : Theme.foreground
                            }
                            Text {
                                text: "Saver"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: root.profileLoaded && root.currentProfile === "power-saver" ? Theme.on_primary : Theme.foreground
                            }
                        }

                        MouseArea {
                            id: saverMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentProfile = "power-saver";
                                setProfileProc.command = ["powerprofilesctl", "set", "power-saver"];
                                setProfileProc.running = true;
                            }
                        }
                    }
                }
            }

            // Bottom spacing
            Item { Layout.preferredHeight: 2 }
        }
    }
}
