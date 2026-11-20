pragma Singleton
import QtQuick
import Quickshell

// One-line status toasts ("Bluetooth enabled", ...). Delivered through the
// notification daemon (SwayNC owns org.freedesktop.Notifications), so the shell
// needs no OSD surface of its own. Requires `notify-send` (libnotify).
Singleton {
    function status(message) {
        if (!message) return;
        Quickshell.execDetached(["notify-send", "--app-name=Quickshell", "--expire-time=2000", message]);
    }
}
