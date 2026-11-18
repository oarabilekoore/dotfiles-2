import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    property bool barVisible: true

    IpcHandler {
        target: "bar"
        function toggle() {
            root.barVisible = !root.barVisible;
        }
    }

    // Open/close any popup from a keybind, on the focused monitor:
    //   quickshell ipc call popup toggle settings
    // names: settings, wifi, bluetooth, volume, battery, calendar, mpris
    IpcHandler {
        target: "popup"
        function toggle(name: string): void {
            if (name === "settings") {
                settings.toggle("system");
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
            settings.dismiss();
            for (let i = 0; i < bars.instances.length; i++) bars.instances[i].activePopup = "";
        }
    }

    // OSD is intentionally disabled. Use SwayNC for desktop notifications.
    // No Quickshell NotificationServer is instantiated, so SwayNC can own
    // org.freedesktop.Notifications without competing with this shell.

    Settings {
        id: settings
        osd: null
        notificationCenter: null
    }

    // Open/close the unified control center:
    //   quickshell ipc call settings toggle <system|network|bluetooth|theme|launcher|power>
    IpcHandler {
        target: "settings"
        function toggle(tab: string): void {
            settings.toggle(tab);
        }
        function close(): void {
            settings.dismiss();
        }
    }

    Launcher {
        id: launcher
    }

    // Open/close the launcher from a keybind:
    //   quickshell ipc call launcher toggle all
    // modes: all, files, clipboard, emoji, hidden
    IpcHandler {
        target: "launcher"
        function toggle(mode: string): void {
            launcher.toggle(mode);
        }
        function close(): void {
            launcher.dismiss();
        }
    }

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