import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root
    property bool barVisible: true
    property string pendingLauncherAction: ""
    property var pendingLauncherArgs: []

    function callLauncher(action, args) {
        pendingLauncherAction = action;
        pendingLauncherArgs = args || [];
        if (launcherLoader.active) dispatchLauncherAction();
        else launcherLoader.activeAsync = true;
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
        if (launcherLoader.active) {
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

    LazyLoader {
        id: launcherLoader
        Launcher {}
        onActiveChanged: {
            if (active) root.dispatchLauncherAction();
        }
    }

    Connections {
        target: launcherLoader.active ? launcherLoader.item : null
        ignoreUnknownSignals: true
        function onOpenChanged() {
            if (!launcherLoader.item) return;
            if (launcherLoader.item.open) launcherUnloadTimer.stop();
            else launcherUnloadTimer.restart();
        }
    }

    IpcHandler {
        target: "bar"
        function toggle() { root.barVisible = !root.barVisible; }
    }

    IpcHandler {
        target: "popup"
        function toggle(name: string): void {
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
            for (let i = 0; i < bars.instances.length; i++) bars.instances[i].activePopup = "";
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(mode: string): void { root.callLauncher("toggle", [mode]); }
        function open(mode: string): void { root.callLauncher("present", [mode]); }
        function close(): void { root.closeLauncher(); }
        function dmenu(prompt: string, inPath: string, outPath: string): void {
            root.callLauncher("dmenu", [prompt, inPath, outPath]);
        }
        function reindex(): void { root.callLauncher("reindex", []); }
        function reloadConfig(): void { root.callLauncher("reloadConfig", []); }
    }

    Variants {
        id: bars
        model: Quickshell.screens
        Bar { visible: root.barVisible }
    }
}
