pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User preferences persisted to ~/.config/quickshell/settings.json.
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string configPath: configDir + "/settings.json"
    property bool isLoaded: false

    // Appearance
    property string fontFamily: "JetBrainsMono Nerd Font Propo"
    property real fontScale: 1.0
    property int cornerRadius: 0

    // Bar
    property int barHeight: 22
    property int barMargin: 0
    property bool showWorkspaces: true
    property bool showMpris: true
    property bool showDictation: true
    property bool showCaffeine: true
    property bool showTray: true
    property bool showNetwork: true
    property bool showBluetooth: true
    property bool showBattery: true
    property bool showClock: true
    property string clockFormat: "weekday"

    // Desktop widgets
    property bool desktopWidgetsEnabled: true
    property int desktopClockX: 36
    property int desktopClockY: 84
    property int desktopSystemX: 36
    property int desktopSystemY: 232

    // Apps
    property string terminalCmd: "ghostty"

    readonly property var persistedKeys: [
        "fontFamily", "fontScale", "cornerRadius",
        "barHeight", "barMargin",
        "showWorkspaces", "showMpris", "showDictation", "showCaffeine", "showTray",
        "showNetwork", "showBluetooth", "showBattery", "showClock", "clockFormat",
        "desktopWidgetsEnabled", "desktopClockX", "desktopClockY", "desktopSystemX", "desktopSystemY",
        "terminalCmd"
    ]

    function save() {
        if (isLoaded) saveTimer.restart();
    }

    function set(key, value) {
        if (root[key] === value) return;
        root[key] = value;
        save();
    }

    function loadFromJson(raw) {
        try {
            if (raw && raw.trim().length > 0) {
                const parsed = JSON.parse(raw);
                for (let i = 0; i < persistedKeys.length; i++) {
                    const k = persistedKeys[i];
                    if (parsed.hasOwnProperty(k)) root[k] = parsed[k];
                }
            }
        } catch (e) {
            console.warn("Config: failed to parse settings.json:", e);
        }
        isLoaded = true;
    }

    Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", root.configDir]);
            const out = {};
            for (let i = 0; i < root.persistedKeys.length; i++) {
                const k = root.persistedKeys[i];
                out[k] = root[k];
            }
            configFile.setText(JSON.stringify(out, null, 2));
        }
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadFromJson(text())
        onLoadFailed: root.isLoaded = true
    }
}
