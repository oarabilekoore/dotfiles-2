import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import ".."

PopupBase {
    id: root

    popupName: "wifi"
    implicitWidth: 360
    implicitHeight: Math.min(600, mainCol.implicitHeight + 28)

    // ---- devices & networks -------------------------------------------------
    readonly property var wifiDev: {
        const list = Networking.devices ? Networking.devices.values : null;
        if (!list) return null;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (d && d.scannerEnabled !== undefined) return d;   // only WifiDevice has a scanner
        }
        return null;
    }

    // Connected first, then saved, then strongest signal. Hidden (nameless) networks are skipped.
    readonly property var networks: {
        const src = (wifiDev && wifiDev.networks) ? wifiDev.networks.values : null;
        if (!src) return [];
        const out = [];
        for (let i = 0; i < src.length; i++) {
            if (src[i] && src[i].name) out.push(src[i]);
        }
        out.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known) return a.known ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
        return out;
    }

    readonly property var connectedNetwork: (networks.length > 0 && networks[0].connected) ? networks[0] : null
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool hwBlocked: Networking.wifiHardwareEnabled === false

    // ---- connect / login state ---------------------------------------------
    property var promptNet: null        // network waiting for a password
    escapeCloses: promptNet === null    // while prompting, Escape only cancels the prompt
    property var pendingNet: null       // network we asked NetworkManager to join
    property bool pendingHadPsk: false
    property string statusText: ""
    property bool statusIsError: false

    function setStatus(msg, isError) {
        root.statusText = msg;
        root.statusIsError = isError;
    }

    function isOpen(net) {
        return net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe;
    }

    function isPsk(net) {
        return net.security === WifiSecurityType.WpaPsk
            || net.security === WifiSecurityType.Wpa2Psk
            || net.security === WifiSecurityType.Sae;
    }

    function securityLabel(net) {
        if (isOpen(net)) return "Open";
        if (isPsk(net)) return "Secured";
        return "Enterprise / other";
    }

    function connectTo(net) {
        if (!net || net.connected) return;
        root.setStatus("", false);
        root.pendingNet = net;
        root.pendingHadPsk = false;
        if (isOpen(net) || net.known) {
            root.promptNet = null;
            net.connect();
        } else if (isPsk(net)) {
            root.promptNet = net;
            pwField.text = "";
            Qt.callLater(() => pwField.forceActiveFocus());
        } else {
            root.pendingNet = null;
            root.setStatus("This network type needs nmtui (Advanced settings below)", true);
        }
    }

    function submitPassword() {
        if (!root.promptNet || pwField.text.length === 0) return;
        root.pendingNet = root.promptNet;
        root.pendingHadPsk = true;
        root.setStatus("", false);
        root.promptNet.connectWithPsk(pwField.text);
        root.promptNet = null;
        pwField.text = "";
    }

    Connections {
        target: root.pendingNet
        ignoreUnknownSignals: true

        function onConnectionFailed(reason) {
            const net = root.pendingNet;
            if (!net) return;
            if (reason === ConnectionFailReason.NoSecrets) {
                // Saved profile lost its secret, or the PSK we just sent was rejected
                root.promptNet = net;
                root.setStatus(root.pendingHadPsk ? "Wrong password, try again" : "Password required", true);
                pwField.text = "";
                Qt.callLater(() => pwField.forceActiveFocus());
            } else {
                root.setStatus("Could not connect to " + net.name, true);
            }
            root.pendingNet = null;
        }

        function onConnectedChanged() {
            if (root.pendingNet && root.pendingNet.connected) {
                const name = root.pendingNet.name;
                root.pendingNet = null;
                root.setStatus("Connected to " + name, false);
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            root.promptNet = null;
            root.pendingNet = null;
            root.setStatus("", false);
            if (root.wifiDev) root.wifiDev.scannerEnabled = true;
        } else if (root.wifiDev) {
            root.wifiDev.scannerEnabled = false;
        }
    }

    Process {
        id: rescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
    }

    Process {
        id: nmtuiProc
        command: ["ghostty", "--class", "floating", "-e", "nmtui"]
    }

    ScriptModel {
        id: netModel
        values: root.networks
    }

    // ---- UI -----------------------------------------------------------------
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

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰤨"
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.primary
                }

                Text {
                    text: "Wi-Fi"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.foreground
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    visible: root.wifiOn
                    glyph: "󰑐"
                    active: rescanProc.running
                    onClicked: {
                        root.setStatus("Scanning for networks...", false);
                        if (root.wifiDev) root.wifiDev.scannerEnabled = true;
                        rescanProc.running = false;
                        rescanProc.running = true;
                    }
                }

                ToggleSwitch {
                    checked: root.wifiOn
                    interactive: !root.hwBlocked
                    onToggled: {
                        Networking.wifiEnabled = !Networking.wifiEnabled;
                    }
                }
            }

            Divider {}

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.hwBlocked ? "Wi-Fi is blocked by a hardware switch" : root.statusText
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: (root.hwBlocked || root.statusIsError) ? Theme.error : Theme.on_surface_variant
            }

            // ---- Wi-Fi off ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                visible: !root.wifiOn

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰖪"
                        font.family: Theme.fontFamily
                        font.pixelSize: 32
                        color: Theme.color7
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Wi-Fi is turned off"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.color7
                    }
                }
            }

            // ---- Wi-Fi on ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.wifiOn
                spacing: 10

                // Connected card
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.connectedNetwork !== null
                    implicitHeight: connCol.implicitHeight + 20
                    radius: 6
                    color: Theme.surface_variant
                    border.color: Theme.alpha(Theme.primary, 0.4)
                    border.width: 1

                    ColumnLayout {
                        id: connCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: Theme.primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.connectedNetwork ? root.connectedNetwork.name : ""
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                                color: Theme.foreground
                            }

                            Rectangle {
                                implicitWidth: 78
                                implicitHeight: 24
                                radius: 4
                                color: disMouse.containsMouse ? Theme.error : Theme.surface
                                border.color: Theme.outline_variant
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "Disconnect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.foreground
                                }

                                MouseArea {
                                    id: disMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.connectedNetwork) {
                                            const name = root.connectedNetwork.name;
                                            root.connectedNetwork.disconnect();
                                            root.setStatus("Disconnected from " + name, false);
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Signal " + (root.connectedNetwork ? Math.round(root.connectedNetwork.signalStrength * 100) : 0)
                                  + "%   ·   " + (root.wifiDev ? root.wifiDev.name : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.on_surface_variant
                        }
                    }
                }

                // Inline password prompt
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.promptNet !== null
                    implicitHeight: pwdCol.implicitHeight + 20
                    radius: 6
                    color: Theme.surface_variant
                    border.color: Theme.primary
                    border.width: 1

                    ColumnLayout {
                        id: pwdCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Password for " + (root.promptNet ? root.promptNet.name : "")
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            color: Theme.foreground
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 4
                                color: Theme.surface
                                border.color: pwField.activeFocus ? Theme.primary : Theme.outline_variant
                                border.width: 1

                                TextInput {
                                    id: pwField
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.foreground
                                    selectionColor: Theme.primary
                                    selectedTextColor: Theme.on_primary
                                    echoMode: eyeBtn.active ? TextInput.Normal : TextInput.Password
                                    onAccepted: root.submitPassword()
                                    Keys.onEscapePressed: root.promptNet = null
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    visible: pwField.text.length === 0
                                    text: "Enter password"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.outline
                                }
                            }

                            IconButton {
                                id: eyeBtn
                                implicitWidth: 30
                                implicitHeight: 30
                                glyph: active ? "󰈈" : "󰈉"
                                onClicked: active = !active
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                implicitWidth: 64
                                implicitHeight: 26
                                radius: 4
                                color: cancelMouse.containsMouse ? Theme.surface : "transparent"
                                border.color: Theme.outline_variant
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.foreground
                                }

                                MouseArea {
                                    id: cancelMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.promptNet = null;
                                        pwField.text = "";
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 78
                                implicitHeight: 26
                                radius: 4
                                opacity: pwField.text.length > 0 ? 1.0 : 0.5
                                color: Theme.primary

                                Text {
                                    anchors.centerIn: parent
                                    text: "Connect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Theme.on_primary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.submitPassword()
                                }
                            }
                        }
                    }
                }

                // Section header
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "AVAILABLE NETWORKS"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.on_surface_variant
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.networks.length + " found"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.outline
                    }
                }

                // Network list (show 3 visible, rest scroll)
                ListView {
                    id: netList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(164, Math.max(52, contentHeight))
                    clip: true
                    spacing: 4
                    model: netModel
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property var net: modelData
                        readonly property bool isPrompt: root.promptNet === net

                        width: ListView.view.width - (netList.interactive ? 8 : 0)
                        height: 52
                        radius: 6
                        color: rowMouse.containsMouse ? Theme.surface_variant
                             : (isPrompt ? Theme.alpha(Theme.primary, 0.12)
                             : (net && net.connected ? Theme.alpha(Theme.primary, 0.08) : "transparent"))
                        border.color: isPrompt ? Theme.primary : "transparent"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    const s = row.net ? row.net.signalStrength : 0;
                                    if (s >= 0.75) return "󰤨";
                                    if (s >= 0.50) return "󰤥";
                                    if (s >= 0.25) return "󰤢";
                                    return "󰤟";
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                color: (row.net && row.net.connected) ? Theme.primary : Theme.foreground
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: row.net ? row.net.name : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall + 1
                                    font.bold: !!row.net && row.net.connected
                                    color: (row.net && row.net.connected) ? Theme.primary : Theme.foreground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (!row.net) return "";
                                        if (row.net.stateChanging) return "Connecting...";
                                        if (row.net.connected) return "Connected";
                                        if (row.net.known) return "Saved";
                                        return root.securityLabel(row.net);
                                    }
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.on_surface_variant
                                }
                            }

                            Text {
                                visible: !!row.net && !root.isOpen(row.net)
                                text: "󰌾"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.outline
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.connectTo(row.net)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.networks.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: "No networks found. Try the rescan button."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.on_surface_variant
                }
            }

            Divider {}

            FooterButton {
                glyph: "󰀂"
                label: "Advanced Network Settings (nmtui)"
                onClicked: {
                    nmtuiProc.running = false;
                    nmtuiProc.running = true;
                    root.dismiss();
                }
            }
        }
    }
}
