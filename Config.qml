pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string configPath: configDir + "/settings.json"
    property bool isLoaded: false
    property bool isSaving: false

    // 1. Appearance & Bar
    property string colorScheme: "wallust"          // "wallust" | "dark" | "light"
    property bool wallustAutoReload: true
    property string accentColor: "#7aa2f7"
    property string fontFamily: "JetBrainsMono Nerd Font Propo"
    property real fontScale: 1.0
    property int cornerRadius: 0
    property int borderWidth: 1
    property string barPosition: "top"
    property int barHeight: 32
    property bool barFloating: false
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

    // 2. Hyprland & Input
    property int gapsIn: 4
    property int gapsOut: 8
    property int hyprBorderSize: 1
    property int hyprRounding: 0
    property string hyprLayout: "dwindle"
    property bool hyprBlur: false
    property int hyprBlurPasses: 2
    property bool hyprShadows: false
    property bool hyprAnimations: true
    property bool focusFollowsMouse: true
    property real mouseSensitivity: 0.0
    property bool naturalScroll: false

    // 3. Display, Sound, Network & Power
    property int brightnessStep: 5
    property bool nightLightEnabled: false
    property int nightLightTemp: 4200
    property int idleDimSeconds: 180
    property int idleLockSeconds: 300
    property int idleDpmsSeconds: 600

    property int volumeStep: 5
    property bool allowOverAmplification: false
    property bool muteMicOnStartup: false
    property int osdTimeoutMs: 1800
    property bool osdOnClock: true
    property bool notificationsEnabled: true
    property bool notificationsDoNotDisturb: false
    property string preferredPlayer: "ncspot"

    property int wifiScanIntervalSec: 15
    property bool btAutoPower: true
    property bool btShowBattery: true

    property string powerProfile: "balanced"
    property int batteryWarnPercent: 20
    property int batteryCritPercent: 10
    property bool caffeineOnFullscreen: true
    property bool caffeineOnAc: false

    // 4. Launcher & Hister Search
    property int launcherWidth: 680
    property int launcherMaxResults: 9
    property bool histerEnabled: true
    property string histerCommand: "hister" // retained for older settings.json files
    property string histerServerUrl: "http://127.0.0.1:4433"
    property bool launcherShowRecent: true
    property string terminalCmd: "ghostty"
    property string fileManagerCmd: "yazi"
    property string shellPrefix: ">"
    property string calcPrefix: "="
    property string emojiPrefix: ":"

    readonly property var persistedKeys: [
        "colorScheme", "wallustAutoReload", "accentColor", "fontFamily", "fontScale",
        "cornerRadius", "borderWidth", "barPosition", "barHeight", "barFloating", "barMargin",
        "showWorkspaces", "showMpris", "showDictation", "showCaffeine", "showTray",
        "showNetwork", "showBluetooth", "showBattery", "showClock",
        "gapsIn", "gapsOut", "hyprBorderSize", "hyprRounding", "hyprLayout",
        "hyprBlur", "hyprBlurPasses", "hyprShadows", "hyprAnimations",
        "focusFollowsMouse", "mouseSensitivity", "naturalScroll",
        "brightnessStep", "nightLightEnabled", "nightLightTemp",
        "idleDimSeconds", "idleLockSeconds", "idleDpmsSeconds",
        "volumeStep", "allowOverAmplification", "muteMicOnStartup", "osdTimeoutMs", "osdOnClock", "notificationsEnabled", "notificationsDoNotDisturb", "preferredPlayer",
        "wifiScanIntervalSec", "btAutoPower", "btShowBattery",
        "powerProfile", "batteryWarnPercent", "batteryCritPercent", "caffeineOnFullscreen", "caffeineOnAc",
        "launcherWidth", "launcherMaxResults", "launcherShowRecent", "histerEnabled", "histerCommand", "histerServerUrl", "terminalCmd", "fileManagerCmd",
        "shellPrefix", "calcPrefix", "emojiPrefix"
    ]

    function save() {
        if (!isLoaded) return;
        isSaving = true;
        saveTimer.restart();
    }

    function set(key, value) {
        if (root[key] === value) return;
        root[key] = value;
        save();
    }

    function resetSection(keys) {
        const defaults = {
            colorScheme: "wallust", wallustAutoReload: true, accentColor: "#7aa2f7",
            fontFamily: "JetBrainsMono Nerd Font Propo", fontScale: 1.0, cornerRadius: 0,
            borderWidth: 1, barPosition: "top", barHeight: 32, barFloating: false, barMargin: 0,
            gapsIn: 4, gapsOut: 8, hyprBorderSize: 1, hyprRounding: 0, hyprLayout: "dwindle",
            hyprBlur: false, hyprBlurPasses: 2, hyprShadows: false, hyprAnimations: true,
            focusFollowsMouse: true, mouseSensitivity: 0.0, naturalScroll: false,
            brightnessStep: 5, nightLightEnabled: false, nightLightTemp: 4200,
            idleDimSeconds: 180, idleLockSeconds: 300, idleDpmsSeconds: 600,
            volumeStep: 5, allowOverAmplification: false, muteMicOnStartup: false,
            osdTimeoutMs: 1800, osdOnClock: true, notificationsEnabled: true, notificationsDoNotDisturb: false, preferredPlayer: "ncspot",
            wifiScanIntervalSec: 15, btAutoPower: true, btShowBattery: true,
            powerProfile: "balanced", batteryWarnPercent: 20, batteryCritPercent: 10,
            caffeineOnFullscreen: true, caffeineOnAc: false,
            launcherWidth: 680, launcherMaxResults: 9, launcherShowRecent: true,
            histerEnabled: true, histerCommand: "hister", histerServerUrl: "http://127.0.0.1:4433",
            terminalCmd: "ghostty", fileManagerCmd: "yazi",
            shellPrefix: ">", calcPrefix: "=", emojiPrefix: ":"
        };
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i];
            if (defaults.hasOwnProperty(k)) root[k] = defaults[k];
        }
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
            root.isSaving = false;
        }
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadFromJson(text())
        onLoadFailed: {
            root.isLoaded = true;
        }
    }

    function applyHyprland() {
        const batch = [
            `keyword general:gaps_in ${gapsIn}`,
            `keyword general:gaps_out ${gapsOut}`,
            `keyword general:border_size ${hyprBorderSize}`,
            `keyword general:layout ${hyprLayout}`,
            `keyword decoration:rounding ${hyprRounding}`,
            `keyword decoration:blur:enabled ${hyprBlur ? "true" : "false"}`,
            `keyword decoration:blur:passes ${hyprBlurPasses}`,
            `keyword decoration:shadow:enabled ${hyprShadows ? "true" : "false"}`,
            `keyword animations:enabled ${hyprAnimations ? "true" : "false"}`,
            `keyword input:follow_mouse ${focusFollowsMouse ? 1 : 0}`,
            `keyword input:sensitivity ${mouseSensitivity}`,
            `keyword input:touchpad:natural_scroll ${naturalScroll ? "true" : "false"}`
        ].join(" ; ");
        Quickshell.execDetached(["hyprctl", "--batch", batch]);
    }

    function applyNightLight() {
        if (nightLightEnabled) {
            Quickshell.execDetached(["sh", "-c", `pkill -x hyprsunset; hyprsunset -t ${nightLightTemp} &`]);
        } else {
            Quickshell.execDetached(["pkill", "-x", "hyprsunset"]);
        }
    }

    function applyPowerProfile(profile) {
        set("powerProfile", profile);
        Quickshell.execDetached(["powerprofilesctl", "set", profile]);
    }
}