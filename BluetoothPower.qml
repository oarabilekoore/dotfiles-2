pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Bluetooth may be software- or hard-blocked by rfkill.  When enabling it,
// run the privileged unblock in a terminal so sudo can prompt interactively.
Singleton {
    id: root

    property bool enabling: false

    Process {
        id: unblockProc
        command: [Config.terminalCmd || "ghostty", "--class", "floating", "-e", "sh", "-lc",
                  "sudo rfkill unblock all && bluetoothctl power on"]
        onStarted: root.enabling = true
        onExited: {
            root.enabling = false;
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 650
        repeat: false
        onTriggered: {
            const adapter = Bluetooth.defaultAdapter;
            if (adapter && !adapter.enabled) {
                console.warn("BluetoothPower: adapter is still off; check sudo/rfkill and bluetooth.service.");
                root.showStatus("Bluetooth could not be enabled");
            } else if (adapter && adapter.enabled) {
                root.showStatus("Bluetooth enabled");
            }
        }
    }

    function showStatus(message) {
        Notify.status(message);
    }

    function enable() {
        if (root.enabling || unblockProc.running) return;
        root.showStatus("Authorizing Bluetooth…");
        unblockProc.running = true;
    }

    function disable() {
        const adapter = Bluetooth.defaultAdapter;
        if (adapter && adapter.enabled) adapter.enabled = false;
        root.showStatus("Bluetooth disabled");
    }

    function toggle() {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter) return;
        if (adapter.enabled) root.disable();
        else root.enable();
    }
}
