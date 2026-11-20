pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User settings persisted to ~/.config/quickshell/settings.json.
//
// Every key below is read somewhere in the shell. Unknown keys in an old
// settings.json are ignored and dropped on the next save, so settings that no
// longer do anything can't linger. Add a key here only together with the code
// that consumes it.
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string configPath: configDir + "/settings.json"
    property bool isLoaded: false

    // Appearance (Theme.qml)
    property string fontFamily: "JetBrainsMono Nerd Font Propo"
    property real fontScale: 1.0
    property int cornerRadius: 0

    // Bar (Bar.qml / Theme.qml)
    property int barHeight: 32
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

    // Apps
    property string terminalCmd: "ghostty"

    readonly property var persistedKeys: [
        "fontFamily", "fontScale", "cornerRadius",
        "barHeight", "barMargin",
        "showWorkspaces", "showMpris", "showDictation", "showCaffeine", "showTray",
        "showNetwork", "showBluetooth", "showBattery", "showClock",
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
