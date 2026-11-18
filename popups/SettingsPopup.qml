import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import ".."

// Quick settings: power actions, toggle tiles, output volume and brightness.
PopupBase {
    id: root

    popupName: "settings"
    implicitWidth: 340
    implicitHeight: col.implicitHeight + 28

    // ---- audio ----
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }
    readonly property var sinkAudio: sink ? sink.audio : null

    readonly property string volGlyph: {
        if (!sinkAudio || sinkAudio.muted) return "󰝟";
        const p = Math.round(sinkAudio.volume * 100);
        return p <= 30 ? "󰕿" : (p <= 70 ? "󰖀" : "󰕾");
    }

    // ---- wifi / bluetooth ----
    readonly property var wifiDev: {
        if (!Networking.devices || !Networking.devices.values) return null;
        for (let i = 0; i < Networking.devices.values.length; i++) {
            const d = Networking.devices.values[i];
            if (d && d.scannerEnabled !== undefined) return d;
        }
        return null;
    }
    readonly property var connectedNetwork: {
        if (!wifiDev || !wifiDev.networks || !wifiDev.networks.values) return null;
        for (let i = 0; i < wifiDev.networks.values.length; i++) {
            const n = wifiDev.networks.values[i];
            if (n && n.connected) return n;
        }
        return null;
    }
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!btAdapter && btAdapter.enabled
    readonly property string btDevice: {
        if (!btAdapter || !btAdapter.devices || !btAdapter.devices.values) return "";
        for (let i = 0; i < btAdapter.devices.values.length; i++) {
            const d = btAdapter.devices.values[i];
            if (d && d.connected) return d.name;
        }
        return "";
    }

    // ---- processes / state ----
    property bool airplane: false
    property bool caffeine: false
    property bool nightLight: false
    property string profile: "balanced"

    // centered confirmation dialog for logout / reboot / shutdown
    property string armed: ""
    Timer { id: armTimer; interval: 5000; onTriggered: root.armed = "" }

    function refreshAll() {
        airplaneProc.running = true;
        caffeineProc.running = true;
        nightProc.running = true;
        profileProc.running = true;
        Brightness.refresh();
    }
    onVisibleChanged: {
        if (visible) refreshAll();
        else root.armed = "";
    }

    Process {
        id: airplaneProc
        command: ["sh", "-c", "if rfkill list 2>/dev/null | grep -q 'Soft blocked: no'; then echo off; else echo on; fi"]
        stdout: StdioCollector { onStreamFinished: root.airplane = (text.trim() === "on") }
    }
    Process {
        id: airplaneSet
        onExited: airplaneProc.running = true
    }
    Process {
        id: caffeineProc
        command: ["sh", "-c", "[ -f /tmp/caffeine_on ] && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.caffeine = (text.trim() === "on") }
    }
    Process {
        id: caffeineSet
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/caffeine.sh", "toggle"]
        onExited: caffeineProc.running = true
    }
    // Night light needs `hyprsunset` (pacman -S hyprsunset)
    Process {
        id: nightProc
        command: ["sh", "-c", "pgrep -x hyprsunset >/dev/null && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.nightLight = (text.trim() === "on") }
    }
    Process {
        id: nightSet
        command: ["sh", "-c", "if pgrep -x hyprsunset >/dev/null; then pkill -x hyprsunset; else setsid hyprsunset -t 4000 >/dev/null 2>&1 & fi"]
        onExited: nightDelay.restart()
    }
    Timer { id: nightDelay; interval: 400; onTriggered: nightProc.running = true }
    Process {
        id: profileProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p.length > 0) root.profile = p; }
        }
    }
    Process {
        id: profileSet
        onExited: profileProc.running = true
    }
    Process { id: powerProc }

    function cycleProfile() {
        const order = ["power-saver", "balanced", "performance"];
        const next = order[(order.indexOf(root.profile) + 1) % order.length];
        root.profile = next;
        profileSet.command = ["powerprofilesctl", "set", next];
        profileSet.running = true;
        if (root.parentBar && root.parentBar.osd) root.parentBar.osd.showStatus("Power profile: " + next);
    }

    function toggleAirplane() {
        const next = !root.airplane;
        root.airplane = next;
        airplaneSet.command = ["rfkill", next ? "block" : "unblock", "all"];
        airplaneSet.running = true;
        if (root.parentBar && root.parentBar.osd) root.parentBar.osd.showStatus(next ? "Airplane mode enabled" : "Airplane mode disabled");
    }

    // Each entry: what to run once confirmed (lock and sleep need no confirmation)
    function powerAction(name) {
        const needsConfirm = (name === "log out" || name === "restart" || name === "shut down");
        if (needsConfirm) {
            root.armed = name;
            armTimer.restart();
            return;
        }
        root.armed = "";
        const cmds = {
            "lock": ["loginctl", "lock-session"],
            "sleep": ["systemctl", "suspend"]
        };
        powerProc.command = cmds[name];
        powerProc.running = true;
        root.dismiss();
    }

    function openDetail(name) {
        if (root.parentBar) root.parentBar.activePopup = name;
    }

    // ---- UI ----
    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            // Header: battery + power actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    visible: Battery.hasBattery
                    text: Battery.icon
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Battery.color
                }
                Text {
                    visible: Battery.hasBattery
                    text: Battery.percentage + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.foreground
                }

                Item { Layout.fillWidth: true }

                // Improved power action icons
                IconButton { glyph: "󰌾"; implicitWidth: 28; implicitHeight: 28; onClicked: root.powerAction("lock") }         // lock
                IconButton { glyph: "󰒲"; implicitWidth: 28; implicitHeight: 28; onClicked: root.powerAction("sleep") }        // suspend
                IconButton { glyph: "󰍃"; implicitWidth: 28; implicitHeight: 28; active: root.armed === "log out"; onClicked: root.powerAction("log out") }
                IconButton { glyph: "󰜉"; implicitWidth: 28; implicitHeight: 28; active: root.armed === "restart"; onClicked: root.powerAction("restart") }    // restart
                IconButton { glyph: "󰐥"; implicitWidth: 28; implicitHeight: 28; active: root.armed === "shut down"; onClicked: root.powerAction("shut down") } // power off
            }

            Divider {}

            // Toggle tiles
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                QuickTile {
                    glyph: Networking.wifiEnabled ? "󰖩" : "󰖪"
                    title: "Wi-Fi"
                    subtitle: !Networking.wifiEnabled ? "Off"
                              : (root.connectedNetwork ? root.connectedNetwork.name : "Not connected")
                    active: Networking.wifiEnabled
                    hasDetail: true
                    onClicked: { Networking.wifiEnabled = !Networking.wifiEnabled; if (root.parentBar && root.parentBar.osd) root.parentBar.osd.showStatus(Networking.wifiEnabled ? "Wi-Fi enabled" : "Wi-Fi disabled"); }
                    onDetailClicked: root.openDetail("wifi")
                }
                QuickTile {
                    glyph: root.btOn ? "󰂯" : "󰂲"
                    title: "Bluetooth"
                    subtitle: !root.btOn ? "Off" : (root.btDevice.length > 0 ? root.btDevice : "On")
                    active: root.btOn
                    hasDetail: true
                    onClicked: BluetoothPower.toggle()
                    onDetailClicked: root.openDetail("bluetooth")
                }
                QuickTile {
                    glyph: "󰀝"
                    title: "Airplane mode"
                    subtitle: root.airplane ? "On" : "Off"
                    active: root.airplane
                    onClicked: root.toggleAirplane()
                }
                QuickTile {
                    glyph: "󰖔"
                    title: "Night light"
                    subtitle: root.nightLight ? "On" : "Off"
                    active: root.nightLight
                    onClicked: { const next = !root.nightLight; nightSet.running = true; if (root.parentBar && root.parentBar.osd) root.parentBar.osd.showStatus(next ? "Night light enabled" : "Night light disabled"); }
                }
                QuickTile {
                    glyph: "󰅶"
                    title: "Caffeine"
                    subtitle: root.caffeine ? "Staying awake" : "Off"
                    active: root.caffeine
                    onClicked: { const next = !root.caffeine; caffeineSet.running = true; if (root.parentBar && root.parentBar.osd) root.parentBar.osd.showStatus(next ? "Caffeine enabled" : "Caffeine disabled"); }
                }
                QuickTile {
                    glyph: root.profile === "power-saver" ? "󰌪"
                           : (root.profile === "performance" ? "󱐋" : "󰓅")
                    title: "Power mode"
                    subtitle: root.profile === "power-saver" ? "Power saver"
                              : (root.profile === "performance" ? "Performance" : "Balanced")
                    active: root.profile !== "balanced"
                    onClicked: root.cycleProfile()
                }
            }

            Divider {}

            // Sliders (volume + brightness only, no microphone)
            QsSlider {
                glyph: root.volGlyph
                value: root.sinkAudio ? root.sinkAudio.volume : 0
                muted: root.sinkAudio ? root.sinkAudio.muted : false
                onMoved: (v) => {
                    if (!root.sinkAudio) return;
                    if (v > 0) root.sinkAudio.muted = false;
                    root.sinkAudio.volume = v;
                }
                onGlyphClicked: if (root.sinkAudio) root.sinkAudio.muted = !root.sinkAudio.muted
            }
            QsSlider {
                visible: Brightness.available
                glyph: "󰃠"
                value: Brightness.percent / 100
                onMoved: (v) => Brightness.set(Math.round(v * 100))
                onGlyphClicked: Brightness.set(100)
            }
        }

        // Centered confirmation popup overlay
        Rectangle {
            id: confirmOverlay
            anchors.fill: parent
            visible: root.armed.length > 0
            color: Qt.rgba(0, 0, 0, 0.5)
            radius: Theme.popupRadius
            z: 100

            opacity: root.armed.length > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            MouseArea {
                anchors.fill: parent
                onClicked: root.armed = ""
            }

            Rectangle {
                anchors.centerIn: parent
                width: 240
                height: confirmCol.implicitHeight + 32
                radius: 8
                color: Theme.surface
                border.color: Theme.outline_variant
                border.width: 1

                scale: root.armed.length > 0 ? 1 : 0.9
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: confirmCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.armed === "shut down" ? "󰐦" : (root.armed === "restart" ? "󰑙" : "󰍃")
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        color: Theme.warning
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.armed.charAt(0).toUpperCase() + root.armed.slice(1) + "?"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.foreground
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Are you sure you want to " + root.armed + "?"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.on_surface_variant
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10

                        Rectangle {
                            implicitWidth: 80
                            implicitHeight: 30
                            radius: 4
                            color: cancelConfirmMouse.containsMouse ? Theme.surface_variant : "transparent"
                            border.color: Theme.outline_variant
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.foreground
                            }

                            MouseArea {
                                id: cancelConfirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.armed = ""
                            }
                        }

                        Rectangle {
                            implicitWidth: 80
                            implicitHeight: 30
                            radius: 4
                            color: confirmMouse.containsMouse ? Theme.alpha(Theme.error, 0.3) : Theme.alpha(Theme.error, 0.2)
                            border.color: Theme.error
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Confirm"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: Theme.error
                            }

                            MouseArea {
                                id: confirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const name = root.armed;
                                    root.armed = "";
                                    const cmds = {
                                        "log out": ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""],
                                        "restart": ["systemctl", "reboot"],
                                        "shut down": ["systemctl", "poweroff"]
                                    };
                                    powerProc.command = cmds[name];
                                    powerProc.running = true;
                                    root.dismiss();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
