import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import ".."

PopupBase {
    id: root

    popupName: "bluetooth"
    implicitWidth: 340
    implicitHeight: Math.min(520, btLayout.implicitHeight + 28)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!adapter && adapter.enabled

    // Connected devices first, then alphabetical
    readonly property var devices: {
        const src = (adapter && adapter.devices) ? adapter.devices.values : null;
        if (!src) return [];
        const out = [];
        for (let i = 0; i < src.length; i++) {
            if (src[i]) out.push(src[i]);
        }
        out.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            return String(a.name || a.address).localeCompare(String(b.name || b.address));
        });
        return out;
    }

    onVisibleChanged: {
        // Don't leave radio discovery running in the background
        if (!visible && root.adapter && root.adapter.discovering) root.adapter.discovering = false;
    }

    Process {
        id: bluetuiProc
        command: ["ghostty", "--class", "floating", "-e", "bluetui"]
    }


    ScriptModel {
        id: devModel
        values: root.devices
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        ColumnLayout {
            id: btLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.primary
                }

                Text {
                    text: "Bluetooth"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.foreground
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    visible: root.btOn
                    glyph: "󰑐"
                    active: !!root.adapter && root.adapter.discovering
                    onClicked: if (root.adapter) root.adapter.discovering = !root.adapter.discovering
                }

                ToggleSwitch {
                    checked: root.btOn
                    interactive: !!root.adapter
                    onToggled: {
                        BluetoothPower.toggle();
                    }
                }
            }

            Divider {}

            // ---- Bluetooth off: centred notice ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                visible: !root.btOn

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰂲"
                        font.family: Theme.fontFamily
                        font.pixelSize: 32
                        color: Theme.color7
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.adapter ? "Bluetooth is off" : "No Bluetooth adapter found"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.color7
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !!root.adapter
                        text: "Turn it on to see your devices"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.outline
                    }
                }
            }

            // ---- Bluetooth on ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.btOn
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "DEVICES"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.on_surface_variant
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (root.adapter && root.adapter.discovering) ? "Scanning..." : root.devices.length + " known"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: (root.adapter && root.adapter.discovering) ? Theme.primary : Theme.outline
                    }
                }

                ListView {
                    id: devList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(48, Math.min(240, contentHeight))
                    clip: true
                    spacing: 4
                    model: devModel
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    delegate: Rectangle {
                        id: devRow
                        required property var modelData
                        readonly property var dev: modelData

                        width: ListView.view.width - (devList.interactive ? 8 : 0)
                        height: 46
                        radius: 6
                        color: devMouse.containsMouse ? Theme.surface_variant : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                Layout.preferredWidth: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: (devRow.dev && devRow.dev.connected) ? "󰂱" : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                color: (devRow.dev && devRow.dev.connected) ? Theme.primary : Theme.color7
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: devRow.dev ? (devRow.dev.name || devRow.dev.address) : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall + 1
                                    font.bold: !!devRow.dev && devRow.dev.connected
                                    color: Theme.foreground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: devRow.dev ? devRow.dev.address : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: Theme.outline
                                }
                            }

                            Rectangle {
                                implicitWidth: 78
                                implicitHeight: 24
                                radius: 4
                                color: btnMouse.containsMouse ? Theme.surface : "transparent"
                                border.color: Theme.outline_variant
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: (devRow.dev && devRow.dev.connected) ? "Disconnect" : "Connect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: (devRow.dev && devRow.dev.connected) ? Theme.error : Theme.foreground
                                }

                                MouseArea {
                                    id: btnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!devRow.dev) return;
                                        if (devRow.dev.connected) devRow.dev.disconnect();
                                        else devRow.dev.connect();
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: devMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.devices.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: "No devices yet. Press scan to look for nearby ones."
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.on_surface_variant
                }
            }

            Divider {}

            FooterButton {
                glyph: ""
                label: "Open Bluetooth Manager (bluetui)"
                onClicked: {
                    bluetuiProc.running = false;
                    bluetuiProc.running = true;
                    root.dismiss();
                }
            }
        }
    }
}
