import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    property bool barVisible: true

    // Keep heavyweight windows out of the idle object tree. They are created on
    // first use and destroyed shortly after being closed.
    property string pendingSettingsTab: ""
    property string pendingLauncherAction: ""
    property var pendingLauncherArgs: []

    function toggleSettings(tab) {
        if (!settingsLoader.active) {
            pendingSettingsTab = tab;
            settingsLoader.activeAsync = true;
        } else if (settingsLoader.item) {
            settingsLoader.item.toggle(tab);
        } else {
            pendingSettingsTab = tab;
        }
    }

    function closeSettings() {
        pendingSettingsTab = "";
        if (settingsLoader.item) {
            settingsLoader.item.dismiss();
            settingsUnloadTimer.restart();
        } else {
            settingsLoader.active = false;
        }
    }

    function callLauncher(action, args) {
        pendingLauncherAction = action;
        pendingLauncherArgs = args || [];
        if (!launcherLoader.active) launcherLoader.activeAsync = true;
        if (launcherLoader.item) dispatchLauncherAction();
    }

    function dispatchLauncherAction() {
        const target = launcherLoader.item;
        const action = pendingLauncherAction;
        const args = pendingLauncherArgs;
        if (!target || action.length === 0) return;

        pendingLauncherAction = "";
        pendingLauncherArgs = [];

        if (action === "toggle") target.toggle(args[0]);
        else if (action === "present") target.present(args[0]);
        else if (action === "dmenu") target.presentDmenu(args[0], args[1], args[2]);
        else if (action === "reindex") target.rebuildFileCache(true);
        else if (action === "reloadConfig") {
            target.loadBangConfig();
            target.loadSnippets();
        }
    }

    function closeLauncher() {
        pendingLauncherAction = "";
        pendingLauncherArgs = [];
        if (launcherLoader.item) {
            launcherLoader.item.dismiss();
            launcherUnloadTimer.restart();
        } else {
            launcherLoader.active = false;
        }
    }

    Timer {
        id: launcherUnloadTimer
        interval: 2200
        repeat: false
        onTriggered: {
            if (launcherLoader.item && !launcherLoader.item.open)
                launcherLoader.active = false;
        }
    }

    Timer {
        id: settingsUnloadTimer
        interval: 1400
        repeat: false
        onTriggered: {
            if (settingsLoader.item && !settingsLoader.item.open)
                settingsLoader.active = false;
        }
    }

    LazyLoader {
        id: settingsLoader
        active: false

        Settings {
            osd: null
            notificationCenter: null
        }

        onActiveChanged: {
            if (active && root.pendingSettingsTab.length > 0) {
                const tab = root.pendingSettingsTab;
                root.pendingSettingsTab = "";
                item.toggle(tab);
            }
        }
    }

    LazyLoader {
        id: launcherLoader
        active: false

        Launcher {}

        onActiveChanged: {
            if (active) root.dispatchLauncherAction();
        }
    }

    Connections {
        target: launcherLoader.item
        ignoreUnknownSignals: true

        function onOpenChanged() {
            if (!launcherLoader.item) return;
            if (launcherLoader.item.open) launcherUnloadTimer.stop();
            else launcherUnloadTimer.restart();
        }
    }

    Connections {
        target: settingsLoader.item
        ignoreUnknownSignals: true

        function onOpenChanged() {
            if (!settingsLoader.item) return;
            if (settingsLoader.item.open) settingsUnloadTimer.stop();
            else settingsUnloadTimer.restart();
        }
    }

    IpcHandler {
        target: "bar"
        function toggle() {
            root.barVisible = !root.barVisible;
        }
    }

    // Open/close any popup from a keybind, on the focused monitor:
    //   quickshell ipc call popup toggle settings
    // names: settings, wifi, bluetooth, volume, battery, calendar, mpris, traymenu
    IpcHandler {
        target: "popup"
        function toggle(name: string): void {
            if (name === "settings") {
                root.toggleSettings("system");
                return;
            }
            const fm = Hyprland.focusedMonitor;
            const focused = fm ? fm.name : "";
            let target = null;
            for (let i = 0; i < bars.instances.length; i++) {
                const b = bars.instances[i];
                if (b.screen && b.screen.name === focused) target = b;
            }
            if (!target && bars.instances.length > 0) target = bars.instances[0];
            for (let i = 0; i < bars.instances.length; i++) {
                const b = bars.instances[i];
                if (b === target) b.activePopup = (b.activePopup === name ? "" : name);
                else b.activePopup = "";
            }
        }
        function close(): void {
            root.closeSettings();
            for (let i = 0; i < bars.instances.length; i++) bars.instances[i].activePopup = "";
        }
    }

    // SwayNC owns org.freedesktop.Notifications; no duplicate notification server.

    IpcHandler {
        target: "settings"
        function toggle(tab: string): void {
            root.toggleSettings(tab);
        }
        function close(): void {
            root.closeSettings();
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(mode: string): void {
            root.callLauncher("toggle", [mode]);
        }
        function open(mode: string): void {
            root.callLauncher("present", [mode]);
        }
        function close(): void {
            root.closeLauncher();
        }
        function dmenu(prompt: string, inPath: string, outPath: string): void {
            root.callLauncher("dmenu", [prompt, inPath, outPath]);
        }
        function reindex(): void {
            root.callLauncher("reindex", []);
        }
        function reloadConfig(): void {
            root.callLauncher("reloadConfig", []);
        }
    }

    // The bar is the bootstrap window. Heavy launcher/settings windows are lazy.
    Variants {
        id: bars
        model: Quickshell.screens
        Bar {
            visible: root.barVisible
            osd: null
            notificationCenter: null
        }
    }
}
