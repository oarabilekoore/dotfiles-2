pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Backlight control shared by the OSD and the settings popup (via brightnessctl).
Singleton {
    id: root

    property int percent: 0
    property bool available: false
    property int pending: -1          // newest value requested while a set is still running

    function refresh() {
        if (!readProc.running) readProc.running = true;
    }

    function run(v) {
        setProc.command = ["brightnessctl", "-c", "backlight", "-q", "set", v + "%"];
        setProc.running = true;
    }

    function set(p) {
        const v = Math.max(1, Math.min(100, Math.round(p)));   // never 0%: black screen
        root.percent = v;                                       // optimistic, re-read afterwards
        if (setProc.running) { root.pending = v; return; }
        run(v);
    }

    function step(delta) { set(root.percent + delta); }

    function parse(t) {
        // brightnessctl -m: device,class,current,percent%,max
        const f = t.trim().split("\n")[0].split(",");
        if (f.length >= 5) {
            const p = parseInt(f[3]);
            if (!isNaN(p)) { root.percent = p; root.available = true; }
        }
    }

    Process {
        id: setProc
        onExited: {
            if (root.pending >= 0) {
                const v = root.pending;
                root.pending = -1;
                root.run(v);
            } else {
                root.refresh();
            }
        }
    }

    Process {
        id: readProc
        command: ["brightnessctl", "-c", "backlight", "-m", "info"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Component.onCompleted: refresh()
}
