import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import "."

// Unified Quickshell Control Center
// Toggle via IPC: quickshell ipc call settings toggle <system|devices|network|bluetooth|theme|notifications|privacy|launcher|power|about>
PanelWindow {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string stateDir: homeDir + "/.local/state/quickshell-launcher"

    // Grouped like a desktop settings application; IDs remain usable through IPC.
    readonly property var tabs: [
        { id: "system",       label: "Sound & Display", glyph: "󰒓", group: "HARDWARE" },
        { id: "devices",      label: "Devices",         glyph: "󰍹", group: "HARDWARE" },
        { id: "typography",   label: "Typography",      glyph: "󰛖", group: "PERSONALIZATION" },
        { id: "bar",          label: "Bar modules",     glyph: "󰕰", group: "PERSONALIZATION" },
        { id: "sharing",      label: "Display Sharing", glyph: "󰍹", group: "HARDWARE" },
        { id: "system-settings", label: "System",       glyph: "󰒓", group: "SYSTEM" },
        { id: "network",      label: "Network",         glyph: "󰖩", group: "CONNECTIVITY" },
        { id: "bluetooth",    label: "Bluetooth",       glyph: "󰂯", group: "CONNECTIVITY" },
        { id: "theme",        label: "Appearance",      glyph: "󰏘", group: "PERSONALIZATION" },
        { id: "notifications",label: "Notifications",   glyph: "󰂚", group: "PERSONALIZATION" },
        { id: "privacy",      label: "Privacy",         glyph: "󰒃", group: "PRIVACY" },
        { id: "launcher",     label: "Launcher & Apps", glyph: "󰍉", group: "APPLICATIONS" },
        { id: "power",        label: "Power",           glyph: "󰐥", group: "SYSTEM" },
        { id: "about",        label: "About",           glyph: "󰋼", group: "SYSTEM" }
    ]
    // Compute the filtered navigation model once. Delegates use this same
    // array for group separators, avoiding invalid source-index lookups.
    readonly property var visibleTabs: {
        const term = settingsSearch.trim().toLowerCase();
        return term.length === 0 ? tabs : tabs.filter(t =>
            ((t.label || "") + " " + (t.group || "")).toLowerCase().indexOf(term) >= 0);
    }

    // ------------------------------------------------------------------ state
    property string portalStatus: "Not checked"
    property bool open: false
    property string activeTab: "system"
    property string settingsSearch: ""
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    // System telemetry
    property int volPercent: 50
    property bool volMuted: false
    property int micPercent: 50
    property bool micMuted: false
    property int brightPercent: 70
    property bool caffeineOn: false

    // Network state
    property bool wifiEnabled: true
    property string activeSsid: ""
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string passwordSsid: ""

    // Shared state and telemetry for the additional settings pages.
    property var hiddenApps: []
    property var monitors: []
    property var inputDevices: []
    property bool notificationsAvailable: false
    property bool doNotDisturb: false
    property string distroName: "Loading…"
    property string kernelVersion: ""
    property string hostName: ""
    property string powerProfile: "balanced"
    property string statusBanner: ""
    property string confirmPowerId: ""

    screen: targetScreen
    visible: open || frame.opacity > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ------------------------------------------------------------------ process helpers
    Component {
        id: capComp
        Process {
            id: cap
            property var cb: null
            stdout: StdioCollector {
                onStreamFinished: {
                    if (cap.cb) cap.cb(text);
                    cap.destroy(400);
                }
            }
            onExited: cap.destroy(2500)
        }
    }

    function runCapture(cmd, cb) {
        return capComp.createObject(root, { command: cmd, cb: cb, running: true });
    }

    function sh(script, args) {
        Quickshell.execDetached(["sh", "-c", script, "_"].concat(args || []));
    }

    // Shown in the banner at the top of this window.
    function notify(msg) {
        statusBanner = msg;
        statusBannerTimer.restart();
    }

    Timer { id: statusBannerTimer; interval: 2500; onTriggered: root.statusBanner = "" }
    Timer { id: powerConfirmTimer; interval: 9000; onTriggered: root.confirmPowerId = "" }

    // ------------------------------------------------------------------ persistence
    function loadSettings() {
        runCapture(["cat", stateDir + "/state.json"], function (t) {
            try {
                const state = JSON.parse(t);
                root.hiddenApps = Array.isArray(state.hidden) ? state.hidden : [];
            } catch (e) { root.hiddenApps = []; }
        });
    }

    function unhideApp(appId) {
        runCapture(["cat", stateDir + "/state.json"], function (t) {
            let s = { apps: ({}), emoji: [], hidden: [] };
            try { s = JSON.parse(t); } catch (e) {}
            s.hidden = (s.hidden || []).filter(x => x !== appId);
            root.hiddenApps = s.hidden;
            root.sh("mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/state.json\"", [root.stateDir, JSON.stringify(s)]);
            root.notify("Unhid " + appId);
        });
    }

    // ------------------------------------------------------------------ hardware polling
    function refreshSystem() {
        // Sink volume
        runCapture(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], function (t) {
            const m = /Volume:\s*([0-9.]+)/.exec(t);
            if (m) root.volPercent = Math.round(parseFloat(m[1]) * 100);
            root.volMuted = t.indexOf("[MUTED]") >= 0;
        });
        // Source (mic) volume
        runCapture(["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"], function (t) {
            const m = /Volume:\s*([0-9.]+)/.exec(t);
            if (m) root.micPercent = Math.round(parseFloat(m[1]) * 100);
            root.micMuted = t.indexOf("[MUTED]") >= 0;
        });
        // Brightness
        runCapture(["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"], function (t) {
            const v = parseInt(t.trim());
            if (!isNaN(v)) root.brightPercent = v;
        });
        // Caffeine status
        runCapture(["sh", "-c", "pgrep -x hypridle >/dev/null && echo off || echo on"], function (t) {
            root.caffeineOn = t.trim() === "on";
        });
    }

    function refreshNetwork(rescan) {
        wifiScanning = true;
        runCapture(["nmcli", "radio", "wifi"], function (t) {
            root.wifiEnabled = t.trim() === "enabled";
        });
        const cmd = rescan
            ? ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
            : ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"];
        runCapture(cmd, function (t) {
            root.wifiScanning = false;
            const lines = t.split("\n").filter(l => l.length > 0);
            const seen = {};
            const out = [];
            root.activeSsid = "";
            for (let i = 0; i < lines.length; i++) {
                // Split unescaped colons
                const parts = lines[i].split(":");
                if (parts.length < 4) continue;
                const inUse = parts[0] === "*";
                const ssid = parts[1];
                if (!ssid || seen[ssid]) continue;
                seen[ssid] = true;
                if (inUse) root.activeSsid = ssid;
                out.push({
                    inUse: inUse,
                    ssid: ssid,
                    signal: parseInt(parts[2]) || 0,
                    security: parts[3] || "Open"
                });
            }
            out.sort((a, b) => (a.inUse === b.inUse) ? (b.signal - a.signal) : (a.inUse ? -1 : 1));
            root.wifiNetworks = out;
        });
    }

    function refreshDevices() {
        runCapture(["hyprctl", "monitors", "-j"], function (raw) {
            try {
                const data = JSON.parse(raw);
                root.monitors = Array.isArray(data) ? data : [];
            } catch (e) { root.monitors = []; }
        });
        runCapture(["hyprctl", "devices", "-j"], function (raw) {
            try {
                const data = JSON.parse(raw);
                const list = [];
                const groups = [
                    { key: "keyboards", type: "Keyboard" },
                    { key: "mice", type: "Mouse" },
                    { key: "tablets", type: "Tablet" },
                    { key: "touch", type: "Touch" }
                ];
                for (let i = 0; i < groups.length; i++) {
                    const entries = data[groups[i].key] || [];
                    for (let j = 0; j < entries.length; j++)
                        list.push({ type: groups[i].type, name: entries[j].name || entries[j].address || "Unknown device" });
                }
                root.inputDevices = list;
            } catch (e) { root.inputDevices = []; }
        });
    }

    // Notifications are owned by SwayNC; `swaync-client -d` toggles DND and prints the new state.
    function toggleDoNotDisturb() {
        runCapture(["swaync-client", "-d", "-sw"], function (raw) {
            const v = raw.trim();
            if (v !== "true" && v !== "false") return;
            root.doNotDisturb = (v === "true");
            root.notify(root.doNotDisturb ? "Do Not Disturb enabled" : "Do Not Disturb disabled");
        });
    }

    function refreshPowerProfile() {
        runCapture(["powerprofilesctl", "get"], function (raw) {
            if (raw.trim()) root.powerProfile = raw.trim();
        });
    }

    function setPowerProfile(profile) {
        Quickshell.execDetached(["powerprofilesctl", "set", profile]);
        powerProfile = profile;
        notify("Power profile: " + profile);
    }

    function refreshAbout() {
        runCapture(["sh", "-c", "grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '\"'"], function (raw) {
            root.distroName = raw.trim() || "Linux";
        });
        runCapture(["uname", "-r"], function (raw) { root.kernelVersion = raw.trim(); });
        runCapture(["hostname"], function (raw) { root.hostName = raw.trim(); });
    }

    function refreshNotificationsNow() {
        runCapture(["swaync-client", "-D", "-sw"], function (raw) {
            const v = raw.trim();
            root.notificationsAvailable = (v === "true" || v === "false");
            root.doNotDisturb = (v === "true");
        });
    }

    function refreshPortalStatus() {
        runCapture(["sh", "-c", 'for unit in xdg-desktop-portal.service xdg-desktop-portal-hyprland.service; do printf "%s: " "$unit"; systemctl --user is-active "$unit" 2>/dev/null || true; done'], function (raw) {
            root.portalStatus = raw.trim() || "Portal service status unavailable";
        });
    }

    function restartPortals() {
        Quickshell.execDetached(["systemctl", "--user", "restart", "xdg-desktop-portal.service", "xdg-desktop-portal-hyprland.service"]);
        root.notify("Restarted desktop portal services");
        portalRefreshTimer.restart();
    }
    Timer { id: portalRefreshTimer; interval: 1200; onTriggered: root.refreshPortalStatus() }

    function runConfirmedPower(id) {
        const commands = {
            logout: ["sh", "-c", 'loginctl terminate-session "$XDG_SESSION_ID"'],
            reboot: ["systemctl", "reboot"],
            off: ["systemctl", "poweroff"]
        };
        const cmd = commands[id];
        root.confirmPowerId = "";
        root.dismiss();
        if (cmd) Quickshell.execDetached(cmd);
    }

    function connectWifi(ssid, password) {
        notify("Connecting to " + ssid + "…");
        const cmd = password && password.length > 0
            ? ["nmcli", "dev", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "dev", "wifi", "connect", ssid];
        runCapture(cmd, function (t) {
            root.passwordSsid = "";
            root.refreshNetwork(false);
            root.notify(t.indexOf("successfully") >= 0 ? ("Connected to " + ssid) : ("Failed to connect to " + ssid));
        });
    }

    // ------------------------------------------------------------------ open / close
    function normalizeTab(tab) {
        if (tab === "apps" || tab === "search") return "launcher";
        if (tab === "appearance") return "theme";
        if (tab === "sound" || tab === "display" || tab === "audio") return "system";
        if (tab === "sharing" || tab === "display-sharing") return "sharing";
        if (tab === "type" || tab === "fonts") return "typography";
        if (tab === "system-settings" || tab === "system-info") return "system-settings";
        if (tab === "battery") return "power";
        return tab;
    }

    function present(tab) {
        tab = normalizeTab(tab);
        const fm = Hyprland.focusedMonitor;
        if (fm) {
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) targetScreen = Quickshell.screens[i];
        }
        if (tab) {
            for (let i = 0; i < tabs.length; i++) if (tabs[i].id === tab) activeTab = tab;
        }
        passwordSsid = "";
        confirmPowerId = "";
        loadSettings();
        refreshSystem();
        refreshNetwork(false);
        refreshDevices();
        refreshNotificationsNow();
        refreshPortalStatus();
        refreshAbout();
        refreshPowerProfile();
        open = true;
        frame.forceActiveFocus();
    }

    function dismiss() {
        open = false;
        passwordSsid = "";
        confirmPowerId = "";
    }

    function toggle(tab) {
        const destination = normalizeTab(tab);
        if (open && (!destination || activeTab === destination)) dismiss();
        else present(destination);
    }

    // ------------------------------------------------------------------ UI
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 130 } }
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Rectangle {
        id: frame
        width: Math.min(940, parent.width - 48)
        height: Math.min(660, parent.height - 48)
        anchors.centerIn: parent
        radius: 0
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline_variant
        clip: true
        focus: true

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.98
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Keys.onPressed: (ev) => {
            if (ev.key === Qt.Key_Escape) {
                if (root.passwordSsid !== "") root.passwordSsid = "";
                else root.dismiss();
                ev.accepted = true;
            } else if (ev.key === Qt.Key_F && (ev.modifiers & Qt.ControlModifier)) {
                settingsSearchInput.forceActiveFocus();
                ev.accepted = true;
            } else if (ev.key === Qt.Key_Tab) {
                let idx = 0;
                for (let i = 0; i < root.tabs.length; i++) if (root.tabs[i].id === root.activeTab) idx = i;
                root.activeTab = root.tabs[(idx + 1) % root.tabs.length].id;
                ev.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---- Left Sidebar Navigation
            Rectangle {
                Layout.preferredWidth: 210
                Layout.fillHeight: true
                color: Theme.background
                border.width: 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        Layout.leftMargin: 6
                        Layout.topMargin: 4
                        Layout.bottomMargin: 10
                        text: "CONTROL CENTER"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1
                        color: Theme.primary
                    }

                    TextInput {
                        id: settingsSearchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        text: root.settingsSearch
                        color: Theme.on_surface
                        selectionColor: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        clip: true
                        onTextChanged: root.settingsSearch = text
                        Rectangle { anchors.fill: parent; z: -1; color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant }
                        Text {
                            visible: settingsSearchInput.text.length === 0
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search settings  [Ctrl+F]"
                            color: Theme.on_surface_variant
                            font: settingsSearchInput.font
                        }
                    }

                    ListView {
                        id: navigationList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.visibleTabs
                        delegate: Column {
                            id: navEntry
                            required property var modelData
                            required property int index
                            width: navigationList.width
                            spacing: firstInGroup ? 2 : 0
                            readonly property bool firstInGroup: index === 0 || !root.visibleTabs[index - 1] || (root.visibleTabs[index - 1].group || "") !== (modelData.group || "")
                            height: (firstInGroup ? 18 : 0) + 34

                            Text {
                                visible: navEntry.firstInGroup
                                width: parent.width
                                height: visible ? 16 : 0
                                x: 7
                                verticalAlignment: Text.AlignVCenter
                                text: navEntry.modelData.group
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: true
                                font.letterSpacing: 0.8
                                color: Theme.on_surface_variant
                            }

                            Rectangle {
                                id: navButton
                                width: parent.width
                                height: 34
                                radius: 0
                                readonly property bool active: root.activeTab === navEntry.modelData.id
                                color: active ? Theme.alpha(Theme.primary, 0.18)
                                              : (navMouse.containsMouse ? Theme.surface_variant : "transparent")
                                border.width: active ? 1 : 0
                                border.color: Theme.alpha(Theme.primary, 0.65)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 7
                                    spacing: 9
                                    Text {
                                        text: navEntry.modelData.glyph
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        color: navButton.active ? Theme.primary : Theme.on_surface_variant
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: navEntry.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: navButton.active
                                        color: navButton.active ? Theme.on_surface : Theme.on_surface_variant
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: navMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeTab = navEntry.modelData.id;
                                        if (root.activeTab === "system") root.refreshSystem();
                                        else if (root.activeTab === "network") root.refreshNetwork(false);
                                        else if (root.activeTab === "devices") root.refreshDevices();
                                        else if (root.activeTab === "notifications") root.refreshNotificationsNow();
                                        else if (root.activeTab === "privacy") root.loadSettings();
                                        else if (root.activeTab === "launcher") root.loadSettings();
                                        else if (root.activeTab === "about") root.refreshAbout();
                                        else if (root.activeTab === "power") root.refreshPowerProfile();
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 0
                        color: closeMouse.containsMouse ? Theme.surface_variant : "transparent"
                        border.width: 1
                        border.color: Theme.outline_variant
                        Text {
                            anchors.centerIn: parent
                            text: "Close  [Esc]"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.on_surface_variant
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.dismiss()
                        }
                    }
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.outline_variant }

            // ---- Right Content Area
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Header bar
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        Text {
                            Layout.fillWidth: true
                            text: {
                                for (let i = 0; i < root.tabs.length; i++)
                                    if (root.tabs[i].id === root.activeTab) return root.tabs[i].label.toUpperCase();
                                return "";
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.8
                            color: Theme.on_surface
                        }
                        Text {
                            visible: root.statusBanner !== ""
                            text: root.statusBanner
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.success
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.outline_variant }

                // ============================================================== TAB 1: SYSTEM
                ColumnLayout {
                    visible: root.activeTab === "system"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    spacing: 16

                    // Output Volume
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: 0
                        color: Theme.surface_variant
                        border.width: 1
                        border.color: Theme.outline_variant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: (root.volMuted ? "󰖁  Output Volume (Muted)" : "󰕾  Output Volume")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.on_surface
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.volPercent + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.primary
                                }
                                Rectangle {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 22
                                    radius: 0
                                    color: root.volMuted ? Theme.alpha(Theme.error, 0.25) : Theme.background
                                    border.width: 1
                                    border.color: root.volMuted ? Theme.error : Theme.outline_variant
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.volMuted ? "Unmute" : "Mute"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.on_surface
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.volMuted = !root.volMuted;
                                            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                        }
                                    }
                                }
                            }
                            // Flat Slider
                            Rectangle {
                                id: volTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 12
                                radius: 0
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.outline_variant
                                Rectangle {
                                    width: Math.max(0, Math.min(parent.width, parent.width * (root.volPercent / 150.0)))
                                    height: parent.height
                                    radius: 0
                                    color: root.volMuted ? Theme.outline : Theme.primary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    function applyVol(mx) {
                                        const pct = Math.max(0, Math.min(150, Math.round((mx / width) * 150)));
                                        root.volPercent = pct;
                                        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (pct / 100.0).toFixed(2)]);
                                    }
                                    onPressed: (m) => applyVol(m.x)
                                    onPositionChanged: (m) => { if (pressed) applyVol(m.x); }
                                }
                            }
                        }
                    }

                    // Screen Brightness
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: 0
                        color: Theme.surface_variant
                        border.width: 1
                        border.color: Theme.outline_variant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "󰃠  Display Brightness"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.on_surface
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.brightPercent + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.primary
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 12
                                radius: 0
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.outline_variant
                                Rectangle {
                                    width: Math.max(0, Math.min(parent.width, parent.width * (root.brightPercent / 100.0)))
                                    height: parent.height
                                    radius: 0
                                    color: Theme.warning
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    function applyBright(mx) {
                                        const pct = Math.max(1, Math.min(100, Math.round((mx / width) * 100)));
                                        root.brightPercent = pct;
                                        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
                                    }
                                    onPressed: (m) => applyBright(m.x)
                                    onPositionChanged: (m) => { if (pressed) applyBright(m.x); }
                                }
                            }
                        }
                    }

                    // Quick Toggles Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 0
                            color: root.caffeineOn ? Theme.alpha(Theme.primary, 0.2) : Theme.surface_variant
                            border.width: 1
                            border.color: root.caffeineOn ? Theme.primary : Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: "󰅶  Caffeine: " + (root.caffeineOn ? "ON" : "OFF")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.caffeineOn = !root.caffeineOn;
                                    Quickshell.execDetached([root.homeDir + "/.config/hypr/scripts/caffeine.sh", "toggle"]);
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: "󰄀  Capture Region"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.dismiss();
                                    Quickshell.execDetached(["omasnap", "--capture-region"]);
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ============================================================== TAB 2: NETWORK
                ColumnLayout {
                    visible: root.activeTab === "network"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 34
                            radius: 0
                            color: root.wifiEnabled ? Theme.alpha(Theme.primary, 0.2) : Theme.surface_variant
                            border.width: 1
                            border.color: root.wifiEnabled ? Theme.primary : Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: root.wifiEnabled ? "󰖩  Wi-Fi: ON" : "󰖪  Wi-Fi: OFF"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    const next = !root.wifiEnabled;
                                    root.wifiEnabled = next;
                                    Quickshell.execDetached(["nmcli", "radio", "wifi", next ? "on" : "off"]);
                                    if (next) root.refreshNetwork(true);
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 34
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: root.wifiScanning ? "Scanning…" : "󰑓  Rescan"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.refreshNetwork(true)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 34
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: "󰆍  Open nmtui"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.dismiss();
                                    Quickshell.execDetached(["ghostty", "-T", "nmtui", "nmtui"]);
                                }
                            }
                        }
                    }

                    // Password box when connecting to secured SSID
                    Rectangle {
                        visible: root.passwordSsid !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 0
                        color: Theme.surface_variant
                        border.width: 1
                        border.color: Theme.primary

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                text: "Password for " + root.passwordSsid + ":"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                            }
                            TextInput {
                                id: wifiPassInput
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Keys.onReturnPressed: root.connectWifi(root.passwordSsid, text)
                            }
                            Rectangle {
                                Layout.preferredWidth: 74
                                Layout.preferredHeight: 26
                                radius: 0
                                color: Theme.primary
                                Text {
                                    anchors.centerIn: parent
                                    text: "Connect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.on_primary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.connectWifi(root.passwordSsid, wifiPassInput.text)
                                }
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.wifiNetworks
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 40
                            radius: 0
                            color: modelData.inUse ? Theme.alpha(Theme.primary, 0.16) : Theme.surface_variant
                            border.width: 1
                            border.color: modelData.inUse ? Theme.primary : Theme.outline_variant

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    text: modelData.inUse ? "󰤨" : "󰤢"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    color: modelData.inUse ? Theme.primary : Theme.on_surface_variant
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.ssid
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.on_surface
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.security + " · " + modelData.signal + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.on_surface_variant
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (modelData.inUse) {
                                        Quickshell.execDetached(["nmcli", "con", "down", modelData.ssid]);
                                        root.notify("Disconnected " + modelData.ssid);
                                    } else if (modelData.security === "" || modelData.security === "--") {
                                        root.connectWifi(modelData.ssid, "");
                                    } else {
                                        // Try saved profile first; prompt password if needed
                                        root.runCapture(["nmcli", "con", "up", modelData.ssid], function (out) {
                                            if (out.indexOf("successfully") >= 0) {
                                                root.refreshNetwork(false);
                                                root.notify("Connected to " + modelData.ssid);
                                            } else {
                                                root.passwordSsid = modelData.ssid;
                                                wifiPassInput.text = "";
                                                wifiPassInput.forceActiveFocus();
                                            }
                                        });
                                    }
                                }
                            }
                        }
                    }
                }

                // ============================================================== TAB 3: BLUETOOTH
                ColumnLayout {
                    visible: root.activeTab === "bluetooth"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    spacing: 12

                    readonly property var ad: Bluetooth.defaultAdapter

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 160
                            Layout.preferredHeight: 34
                            radius: 0
                            color: (parent.parent.ad && parent.parent.ad.enabled) ? Theme.alpha(Theme.primary, 0.2) : Theme.surface_variant
                            border.width: 1
                            border.color: (parent.parent.ad && parent.parent.ad.enabled) ? Theme.primary : Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: (parent.parent.parent.ad && parent.parent.parent.ad.enabled) ? "󰂯  Bluetooth: ON" : "󰂲  Bluetooth: OFF"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    BluetoothPower.toggle();
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 34
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? "Scanning…" : "󰑓  Scan Devices"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    const a = Bluetooth.defaultAdapter;
                                    if (a) a.discovering = !a.discovering;
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values : []
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 42
                            radius: 0
                            color: modelData.connected ? Theme.alpha(Theme.primary, 0.16) : Theme.surface_variant
                            border.width: 1
                            border.color: modelData.connected ? Theme.primary : Theme.outline_variant

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    text: modelData.connected ? "󰂱" : "󰂯"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    color: modelData.connected ? Theme.primary : Theme.on_surface_variant
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.address
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.on_surface
                                }
                                Text {
                                    text: modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Available")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: modelData.connected ? Theme.success : Theme.on_surface_variant
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (modelData.connected) modelData.disconnect();
                                    else modelData.connect();
                                }
                            }
                        }
                    }
                }

                // ============================================================== TAB 4: APPEARANCE
                ColumnLayout {
                    visible: root.activeTab === "theme"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: "󰔎  Toggle Dark / Light Theme"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Quickshell.execDetached(["update_theme", "toggle"]);
                                    root.notify("Toggled theme");
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            Text {
                                anchors.centerIn: parent
                                text: "󰸉  Choose Wallpaper"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: Theme.on_surface
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.dismiss();
                                    Quickshell.execDetached(["wallpicker"]);
                                }
                            }
                        }
                    }

                    Text {
                        text: "ACTIVE WALLUST PALETTE"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.on_surface_variant
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 8
                        columnSpacing: 6
                        rowSpacing: 6
                        Repeater {
                            model: [
                                Theme.color0, Theme.color1, Theme.color2, Theme.color3,
                                Theme.color4, Theme.color5, Theme.color6, Theme.color7,
                                Theme.color8, Theme.color9, Theme.color10, Theme.color11,
                                Theme.color12, Theme.color13, Theme.color14, Theme.color15
                            ]
                            delegate: Rectangle {
                                required property color modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: 0
                                color: modelData
                                border.width: 1
                                border.color: Theme.outline_variant
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 0
                        color: Theme.surface_variant
                        border.width: 1
                        border.color: Theme.outline_variant
                        Text {
                            anchors.centerIn: parent
                            text: "󰑓  Reload Hyprland & Quickshell"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.on_surface
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Quickshell.execDetached(["hyprctl", "reload"]);
                                root.notify("Reloaded Hyprland");
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ============================================================== TAB 5: LAUNCHER & APPS
                ColumnLayout {
                    visible: root.activeTab === "launcher"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    spacing: 14

                    // File Index Cache Management
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: 0
                        color: Theme.surface_variant
                        border.width: 1
                        border.color: Theme.outline_variant
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            Text {
                                Layout.fillWidth: true
                                text: "Scoped File Index (Documents, Downloads, Pictures, Videos, Projects)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.on_surface
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 28
                                radius: 0
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.outline_variant
                                Text {
                                    anchors.centerIn: parent
                                    text: "Rebuild Cache"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        Quickshell.execDetached(["quickshell", "ipc", "call", "launcher", "reindex"]);
                                        root.notify("Rebuilding scoped file index…");
                                    }
                                }
                            }
                        }
                    }

                    // Hidden Apps Manager
                    Text {
                        text: "HIDDEN LAUNCHER APPS (" + root.hiddenApps.length + ")"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.on_surface_variant
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.hiddenApps
                        delegate: Rectangle {
                            required property string modelData
                            width: ListView.view.width
                            height: 36
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.on_surface
                                }
                                Text {
                                    text: "Unhide"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.unhideApp(modelData)
                            }
                        }
                    }
                }

                // ============================================================== DEVICES
                ColumnLayout {
                    visible: root.activeTab === "devices"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 18
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "DISPLAYS"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredWidth: 90; Layout.preferredHeight: 27
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            Text { anchors.centerIn: parent; text: "Refresh"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                            MouseArea { anchors.fill: parent; onClicked: root.refreshDevices() }
                        }
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 176
                        clip: true
                        spacing: 4
                        model: root.monitors
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width; height: 48
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text { text: (modelData.name || "Display") + (modelData.focused ? "  ·  Focused" : ""); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                Text { text: (modelData.width || "?") + " × " + (modelData.height || "?") + "  ·  " + (modelData.refreshRate ? Math.round(modelData.refreshRate) + " Hz" : "") + "  ·  Scale " + (modelData.scale || 1); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 34
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        Text { anchors.centerIn: parent; text: "Open display arrangement tool"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                        MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["wdisplays"]) }
                    }
                    Text { text: "INPUT DEVICES"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 3
                        model: root.inputDevices
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width; height: 31
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                Text { text: modelData.type; Layout.preferredWidth: 70; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                                Text { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface }
                            }
                        }
                    }
                    Text { visible: root.monitors.length === 0 && root.inputDevices.length === 0; text: "No device information available. Check that Hyprland is running."; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                }

                // ============================================================== BAR MODULES
                ColumnLayout {
                    visible: root.activeTab === "bar"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 10
                    Text { text: "PANEL VISIBILITY"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    Text { text: "Choose which modules occupy space in the top bar. Changes are saved automatically."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                    Repeater {
                        model: [
                            { key: "showWorkspaces", title: "Workspaces", detail: "Hyprland workspace indicators" },
                            { key: "showMpris", title: "Media player", detail: "Current track and playback controls" },
                            { key: "showDictation", title: "Dictation", detail: "Dictation status and controls" },
                            { key: "showTray", title: "System tray", detail: "Application tray icons" },
                            { key: "showBluetooth", title: "Bluetooth", detail: "Bluetooth status and device popup" },
                            { key: "showCaffeine", title: "Caffeine", detail: "Idle inhibition indicator" },
                            { key: "showNetwork", title: "Network", detail: "Wi-Fi status and network popup" },
                            { key: "showBattery", title: "Battery", detail: "Battery level and power status" },
                            { key: "showClock", title: "Clock", detail: "Date and time in the centre of the bar" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: modelData.title; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                    Text { text: modelData.detail; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                                }
                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: Config[modelData.key] ? Theme.primary : Theme.outline
                                    Rectangle {
                                        width: 16; height: 16; radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Config[modelData.key] ? parent.width - width - 3 : 3
                                        color: Theme.foreground
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.set(modelData.key, !Config[modelData.key])
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== TYPOGRAPHY
                ColumnLayout {
                    visible: root.activeTab === "typography"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 14
                    Text { text: "TYPE & READABILITY"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 158
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Font family"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                Item { Layout.fillWidth: true }
                                Text { text: Config.fontFamily; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary; elide: Text.ElideRight; Layout.maximumWidth: 210 }
                            }
                            TextInput {
                                id: fontFamilyInput
                                Layout.fillWidth: true; Layout.preferredHeight: 34
                                text: Config.fontFamily
                                color: Theme.on_surface; selectionColor: Theme.primary
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: TextInput.AlignVCenter
                                leftPadding: 10
                                Rectangle { anchors.fill: parent; z: -1; color: Theme.background; border.width: 1; border.color: Theme.outline_variant }
                                onEditingFinished: Config.set("fontFamily", text.trim() || "sans-serif")
                            }
                            Text { text: "Preview: The quick brown fox jumps over 1234567890"; Layout.fillWidth: true; font.family: Config.fontFamily; font.pixelSize: Theme.fontSizeLarge; color: Theme.foreground; elide: Text.ElideRight }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 114
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Interface scale"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                Item { Layout.fillWidth: true }
                                Text { text: Math.round(Config.fontScale * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.primary }
                            }
                            Rectangle {
                                id: fontScaleTrack
                                Layout.fillWidth: true
                                height: 18
                                color: "transparent"
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 5
                                    color: Theme.background
                                    Rectangle { width: parent.width * ((Config.fontScale - 0.8) / 0.6); height: parent.height; color: Theme.primary }
                                }
                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * ((Config.fontScale - 0.8) / 0.6) - width / 2))
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.foreground; border.width: 1; border.color: Theme.outline
                                }
                                MouseArea {
                                    anchors.fill: parent; preventStealing: true; cursorShape: Qt.PointingHandCursor
                                    function updateScale(mx) { Config.set("fontScale", Math.round((0.8 + Math.max(0, Math.min(1, mx / width)) * 0.6) * 20) / 20); }
                                    onPressed: mouse => updateScale(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) updateScale(mouse.x); }
                                }
                            }
                            Text { text: "Changes apply to the bar, popups, launcher and settings. Restart the shell only if a font refuses to refresh."; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== DISPLAY SHARING
                ColumnLayout {
                    visible: root.activeTab === "sharing"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 12
                    Text { text: "SCREEN CAPTURE & PORTALS"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 116
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 6
                            Text { text: "Desktop sharing services"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                            Text { text: root.portalStatus; Layout.fillWidth: true; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary; wrapMode: Text.WordWrap }
                            Text { text: "xdg-desktop-portal-hyprland handles screen capture and window selection. PipeWire carries the video stream to browsers and meeting apps."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 38
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            Text { anchors.centerIn: parent; text: "Refresh status"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface }
                            MouseArea { anchors.fill: parent; onClicked: root.refreshPortalStatus() }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 38
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            Text { anchors.centerIn: parent; text: "Restart portal"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                            MouseArea { anchors.fill: parent; onClicked: root.restartPortals() }
                        }
                    }
                    Text { text: "For screen sharing, make sure xdg-desktop-portal-hyprland and pipewire are installed. Do not run a second portal backend alongside the Hyprland one."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== SYSTEM
                ColumnLayout {
                    visible: root.activeTab === "system-settings"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 12
                    Text { text: "SESSION & SYSTEM CONTROLS"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    Repeater {
                        model: [
                            { title: "Reload Hyprland configuration", detail: "Apply the current compositor configuration", command: ["hyprctl", "reload"] },
                            { title: "Restart desktop portals", detail: "Refresh screen sharing and file picker integration", command: ["systemctl", "--user", "restart", "xdg-desktop-portal.service", "xdg-desktop-portal-hyprland.service"] }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 64
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 10; spacing: 3
                                Text { text: modelData.title; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                Text { text: modelData.detail; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { Quickshell.execDetached(modelData.command); root.notify(modelData.title); } }
                        }
                    }
                    Text { text: "System information is available under About. Network, audio, Bluetooth, power and display controls have their own pages."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== NOTIFICATIONS
                ColumnLayout {
                    visible: root.activeTab === "notifications"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 12
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 100
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 7
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Do Not Disturb"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                Item { Layout.fillWidth: true }
                                Text { text: root.notificationsAvailable ? (root.doNotDisturb ? "Enabled" : "Disabled") : "SwayNC unavailable"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: root.doNotDisturb ? Theme.warning : Theme.on_surface_variant }
                            }
                            Text { text: "SwayNC owns desktop notifications. Do Not Disturb silences notification popups while enabled."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                            Rectangle {
                                Layout.preferredWidth: 190; Layout.preferredHeight: 29
                                color: root.doNotDisturb ? Theme.alpha(Theme.warning, 0.20) : Theme.background
                                border.width: 1; border.color: root.doNotDisturb ? Theme.warning : Theme.outline_variant
                                Text { anchors.centerIn: parent; text: root.doNotDisturb ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface }
                                MouseArea { anchors.fill: parent; onClicked: root.toggleDoNotDisturb() }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 42
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        Text { anchors.centerIn: parent; text: "Dismiss all notifications"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface }
                        MouseArea { anchors.fill: parent; onClicked: { Quickshell.execDetached(["swaync-client", "-C", "-sw"]); root.notify("Dismissed all notifications"); } }
                    }
                    Text { text: "Notification appearance is configured in SwayNC (~/.config/swaync/)."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== PRIVACY
                ColumnLayout {
                    visible: root.activeTab === "privacy"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 12
                    Text { text: "LOCAL DATA & SEARCH"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 112
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 6
                            Text { text: "Launcher file index"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                            Text { text: "The launcher indexes files in Documents, Downloads, Pictures, Videos and Projects. The index is stored locally at ~/.local/state/quickshell-launcher/."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                            Rectangle {
                                Layout.preferredWidth: 160; Layout.preferredHeight: 26
                                color: Theme.background; border.width: 1; border.color: Theme.outline_variant
                                Text { anchors.centerIn: parent; text: "Clear local file index"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                                MouseArea { anchors.fill: parent; onClicked: { Quickshell.execDetached(["quickshell", "ipc", "call", "launcher", "clearCache"]); root.notify("Local file index cleared"); } }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 112
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 6
                            Text { text: "Clipboard history"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                            Text { text: "Clipboard history is accessed only when you open the Clipboard launcher mode. This shell does not upload clipboard contents."; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== ABOUT
                ColumnLayout {
                    visible: root.activeTab === "about"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 10
                    Text { text: "SYSTEM INFORMATION"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; color: Theme.on_surface_variant }
                    Repeater {
                        model: [
                            { label: "Distribution", value: root.distroName },
                            { label: "Hostname", value: root.hostName },
                            { label: "Kernel", value: root.kernelVersion },
                            { label: "Compositor", value: "Hyprland" },
                            { label: "Shell", value: "Quickshell" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 40
                            color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                Text { text: modelData.label; Layout.preferredWidth: 125; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                                Text { text: modelData.value || "—"; Layout.fillWidth: true; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 36
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        Text { anchors.centerIn: parent; text: "Reload Hyprland configuration"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                        MouseArea { anchors.fill: parent; onClicked: { Quickshell.execDetached(["hyprctl", "reload"]); root.notify("Reloaded Hyprland"); } }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ============================================================== TAB 6: POWER
                GridLayout {
                    visible: root.activeTab === "power"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 12

                    Rectangle {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 66
                        color: Theme.surface_variant
                        border.width: 1
                        border.color: Theme.outline_variant
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12
                            Text { text: "󰁹"; font.family: Theme.fontFamily; font.pixelSize: 24; color: Battery.barColor }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: Battery.hasBattery ? Battery.statusText : "Battery information unavailable"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Theme.on_surface }
                                    Item { Layout.fillWidth: true }
                                    Text { text: Battery.hasBattery ? Battery.percentage + "%" : "—"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; color: Battery.barColor }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: 7
                                    color: Theme.background
                                    Rectangle { width: parent.width * (Battery.percent / 100); height: parent.height; color: Battery.barColor }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Power profile"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: ["power-saver", "balanced", "performance"]
                            delegate: Rectangle {
                                required property string modelData
                                Layout.preferredWidth: 104
                                Layout.preferredHeight: 28
                                color: root.powerProfile === modelData ? Theme.alpha(Theme.primary, 0.20) : Theme.surface_variant
                                border.width: 1
                                border.color: root.powerProfile === modelData ? Theme.primary : Theme.outline_variant
                                Text { anchors.centerIn: parent; text: modelData; font.family: Theme.fontFamily; font.pixelSize: 9; color: root.powerProfile === modelData ? Theme.primary : Theme.on_surface }
                                MouseArea { anchors.fill: parent; onClicked: root.setPowerProfile(modelData) }
                            }
                        }
                    }

                    Repeater {
                        model: [
                            { id: "lock",   label: "Lock Screen", glyph: "󰌾", confirm: false, cmd: ["hyprlock"] },
                            { id: "sleep",  label: "Suspend",     glyph: "󰒲", confirm: false, cmd: ["systemctl", "suspend"] },
                            { id: "logout", label: "Log Out",     glyph: "󰍃", confirm: true,  cmd: ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""] },
                            { id: "reboot", label: "Restart",     glyph: "󰜉", confirm: true,  cmd: ["systemctl", "reboot"] },
                            { id: "off",    label: "Shut Down",   glyph: "󰐥", confirm: true,  cmd: ["systemctl", "poweroff"] }
                        ]
                        delegate: Rectangle {
                            id: pCard
                            required property var modelData
                            readonly property bool armed: root.confirmPowerId === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredHeight: 90
                            radius: 0
                            color: armed ? Theme.alpha(Theme.error, 0.22) : Theme.surface_variant
                            border.width: 1
                            border.color: armed ? Theme.error : Theme.outline_variant

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: pCard.modelData.glyph
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 22
                                    color: Theme.primary
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: pCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.on_surface
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (pCard.modelData.confirm) {
                                        root.confirmPowerId = pCard.modelData.id;
                                        powerConfirmTimer.restart();
                                        return;
                                    }
                                    root.dismiss();
                                    Quickshell.execDetached(pCard.modelData.cmd);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A real centered modal, not a status string tucked into the settings page.
    Rectangle {
        id: powerConfirmOverlay
        anchors.fill: parent
        visible: root.open && root.confirmPowerId.length > 0
        z: 1000
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 130 } }
        MouseArea { anchors.fill: parent; onClicked: root.confirmPowerId = "" }

        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: powerConfirmColumn.implicitHeight + 34
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline
            scale: powerConfirmOverlay.visible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: powerConfirmColumn
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.confirmPowerId === "off" ? "󰐥" : (root.confirmPowerId === "reboot" ? "󰜉" : "󰍃")
                    font.family: Theme.fontFamily; font.pixelSize: 28; color: Theme.error
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.confirmPowerId === "off" ? "Shut down this computer?" : (root.confirmPowerId === "reboot" ? "Restart this computer?" : "Log out of this session?")
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; color: Theme.foreground
                }
                Text {
                    Layout.fillWidth: true
                    text: "Your current session will end. Unsaved work may be lost."
                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 100; Layout.preferredHeight: 32
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        Text { anchors.centerIn: parent; text: "Cancel"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.foreground }
                        MouseArea { anchors.fill: parent; onClicked: root.confirmPowerId = "" }
                    }
                    Rectangle {
                        Layout.preferredWidth: 100; Layout.preferredHeight: 32
                        color: Theme.alpha(Theme.error, 0.18); border.width: 1; border.color: Theme.error
                        Text { anchors.centerIn: parent; text: "Confirm"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; color: Theme.error }
                        MouseArea { anchors.fill: parent; onClicked: root.runConfirmedPower(root.confirmPowerId) }
                    }
                }
            }
        }
    }
}