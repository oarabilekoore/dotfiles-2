import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "popups"

// Desktop notification daemon (org.freedesktop.Notifications), replacing SwayNC.
//
// - Cards appear bottom-centre and look like the old SwayNC popups (see popups/NotificationCard.qml).
// - Timeouts follow the SwayNC config: normal 5s, low 3s, critical stays until dismissed,
//   and an app-supplied timeout (notify-send -t) always wins.
// - A notification carrying a synchronous hint (x-canonical-private-synchronous, as sent by
//   prgnotifier and sysnotifier) replaces the card that has the same key in place.
// - The `value` hint (0-100) draws the OSD progress bar used by volume / brightness / mic.
// - The popup window only exists while at least one card is showing, so an idle daemon
//   costs almost nothing.
//
// Control from the shell:
//   qs ipc call notifications toggleDnd | setDnd true|false | isDnd | clear
Scope {
    id: root

    // Behaviour (mirrors ~/.config/swaync/config.json).
    readonly property int timeoutNormal: 5000
    readonly property int timeoutLow: 3000
    readonly property int maxVisible: 5
    readonly property int bottomMargin: 15
    readonly property int cardSpacing: 8

    // Do Not Disturb hides ordinary notifications. OSD cards (volume etc.) and
    // critical notifications still show.
    property bool dnd: false

    // Live Notification objects by entry id. Kept out of the ListModel on purpose: the model
    // holds plain copies for rendering, this map is only used to act on the real objects.
    property var live: ({})
    property int nextEid: 1

    ListModel { id: entries }

    // ---------------------------------------------------------------- helpers

    function indexOfEid(eid) {
        for (let i = 0; i < entries.count; i++)
            if (entries.get(i).eid === eid) return i;
        return -1;
    }

    function indexOfKey(key) {
        if (!key) return -1;
        for (let i = 0; i < entries.count; i++)
            if (entries.get(i).key === key) return i;
        return -1;
    }

    // Icon string for the card: embedded image, absolute path, or themed icon name.
    // Status notifications often come from small shell scripts without an app icon,
    // so infer a useful symbolic icon from their title/body as a fallback.
    function statusGlyph(n) {
        if (n.image) return "";
        const text = ((n.summary || "") + " " + (n.body || "")).toLowerCase();
        if (text.includes("airplane") || text.includes("flight mode")) return "󰀝";
        if (text.includes("caffeine") || text.includes("keep awake")) return "󰅶";
        if (text.includes("mute") || text.includes("volume")) return "";
        if (text.includes("caps lock") || text.includes("capslock")) return "󰪛";
        if (text.includes("mouse") || text.includes("touchpad") || text.includes("pointer")) return "󰍽";
        return "";
    }

    function iconSource(n) {
        if (n.image && n.image.length > 0) return n.image;
        // Recognised shell status notifications use the Nerd Font glyph below;
        // do not try loading their appIcon as a missing theme icon.
        if (root.statusGlyph(n).length > 0) return "";
        const ic = n.appIcon || "";
        if (ic.length === 0) {
            return "";
        }
        if (ic.startsWith("/")) return "file://" + ic;
        if (ic.startsWith("file:") || ic.startsWith("image:")) return ic;
        return Quickshell.iconPath(ic, true);
    }

    // Milliseconds; 0 = never expires. Explicit app timeouts win.
    function timeoutFor(n, urgency) {
        const t = Number(n.expireTimeout);
        if (t === 0) return 0;
        if (t > 0) return t >= 100 ? Math.round(t) : Math.round(t * 1000);   // ms (or seconds, defensively)
        if (urgency === NotificationUrgency.Critical) return 0;
        return urgency === NotificationUrgency.Low ? root.timeoutLow : root.timeoutNormal;
    }

    function wire(n, eid) {
        // Fires when the client retracts the notification (CloseNotification) or we close it.
        // Ignore it if this object no longer owns the entry (replaced by a newer one).
        n.closed.connect(function () {
            if (root.live[eid] !== n) return;
            delete root.live[eid];
            root.removeEid(eid);
        });
    }

    function removeEid(eid) {
        const i = root.indexOfEid(eid);
        if (i >= 0) entries.remove(i);
    }

    function dismissEid(eid) {
        const n = root.live[eid];
        delete root.live[eid];
        root.removeEid(eid);
        if (n) n.dismiss();
    }

    function expireEid(eid) {
        const n = root.live[eid];
        delete root.live[eid];
        root.removeEid(eid);
        if (n) n.expire();
    }

    // Invoke an action by identifier, then close the card. "default" is the click action.
    function invoke(eid, identifier) {
        const n = root.live[eid];
        if (n) {
            for (let i = 0; i < n.actions.length; i++) {
                if (n.actions[i].identifier === identifier) {
                    n.actions[i].invoke();
                    break;
                }
            }
        }
        root.dismissEid(eid);
    }

    function clearAll() {
        while (entries.count > 0) root.dismissEid(entries.get(0).eid);
    }

    function announce(title, message) {
        Quickshell.execDetached([
            "notify-send", "--app-name=Quickshell", "--expire-time=1500",
            "-h", "string:x-canonical-private-synchronous:dnd", title, message
        ]);
    }

    function add(n) {
        const h = n.hints || ({});
        const key = String(h["x-canonical-private-synchronous"] || h["synchronous"] || h["x-dunst-stack-tag"] || "");
        const rawValue = h["value"];
        const value = (rawValue === undefined || rawValue === null || rawValue === "")
                      ? -1 : Math.round(Math.max(0, Math.min(100, Number(rawValue))));
        const urgency = Math.round(Number(n.urgency));
        const isOsd = value >= 0 || key.length > 0;

        // Not tracking a notification makes Quickshell drop it, so DND needs nothing more.
        if (root.dnd && !isOsd && urgency !== NotificationUrgency.Critical) return;

        n.tracked = true;

        const acts = [];
        for (let i = 0; i < n.actions.length; i++) {
            const a = n.actions[i];
            if (a.identifier !== "default") acts.push({ id: a.identifier, text: a.text });
        }

        const data = {
            key: key,
            appName: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            icon: root.iconSource(n),
            glyph: root.statusGlyph(n),
            urgency: urgency,
            value: value,
            timeout: root.timeoutFor(n, urgency),
            actions: JSON.stringify(acts)
        };

        // Same sync key as a card already on screen: update it in place, no flicker.
        const idx = root.indexOfKey(key);
        if (idx >= 0) {
            const eid = entries.get(idx).eid;
            const rev = entries.get(idx).rev + 1;
            const old = root.live[eid];
            root.live[eid] = n;                       // old object's closed handler now ignores itself
            if (old && old !== n) old.dismiss();
            root.wire(n, eid);
            entries.set(idx, Object.assign({}, data, { rev: rev }));
            return;
        }

        const eid = root.nextEid++;
        root.live[eid] = n;
        root.wire(n, eid);
        entries.append(Object.assign({ eid: eid, rev: 0 }, data));

        while (entries.count > root.maxVisible) root.dismissEid(entries.get(0).eid);
    }

    // ---------------------------------------------------------------- server

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: false
        onNotification: (n) => root.add(n)
    }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void {
            root.dnd = !root.dnd;
            root.announce("Do Not Disturb", root.dnd ? "On" : "Off");
        }
        function setDnd(enabled: bool): void {
            root.dnd = enabled;
            root.announce("Do Not Disturb", root.dnd ? "On" : "Off");
        }
        function isDnd(): bool { return root.dnd; }
        function clear(): void { root.clearAll(); }
    }

    // ---------------------------------------------------------------- window

    readonly property var targetScreen: {
        const fm = Hyprland.focusedMonitor;
        if (fm) {
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) return Quickshell.screens[i];
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    LazyLoader {
        active: entries.count > 0

        PanelWindow {
            screen: root.targetScreen
            anchors.bottom: true
            margins.bottom: root.bottomMargin
            implicitWidth: 260
            implicitHeight: stack.implicitHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Column {
                id: stack
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.cardSpacing

                Repeater {
                    model: entries
                    delegate: NotificationCard {
                        onExpired: root.expireEid(eid)
                        onDismissed: root.dismissEid(eid)
                        onActivated: root.invoke(eid, "default")
                        onActionInvoked: (identifier) => root.invoke(eid, identifier)
                    }
                }
            }
        }
    }
}
