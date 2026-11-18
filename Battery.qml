pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "."

// Single source of truth for the battery module and the battery popup.
Singleton {
    id: root

    // First real battery (UPowerDeviceType 2 = Battery); fall back to the composite display device.
    readonly property var dev: {
        const list = UPower.devices ? UPower.devices.values : null;
        if (list) {
            for (let i = 0; i < list.length; i++) {
                const b = list[i];
                if (b && b.type === 2 && b.isPresent) return b;
            }
        }
        const dd = UPower.displayDevice;
        return (dd && dd.isPresent) ? dd : null;
    }

    readonly property bool hasBattery: dev !== null

    // UPowerDevice.percentage is documented as energy / energyCapacity, i.e. a 0..1 ratio,
    // while the old code treated it as 0..100 (so 80% rounded to "1%" and showed the empty icon).
    // Derive the percentage from energy/capacity and only fall back to the raw value, normalised.
    readonly property real percent: {
        if (!dev) return 0;
        let p;
        if (dev.energyCapacity > 0 && dev.energy > 0) {
            p = dev.energy / dev.energyCapacity * 100;
        } else {
            p = dev.percentage;
            if (p <= 1.0) p = p * 100;
        }
        return Math.max(0, Math.min(100, p));
    }
    readonly property int percentage: Math.round(percent)

    // UPowerDeviceState: 1 charging, 2 discharging, 3 empty, 4 fully charged, 5 pending charge, 6 pending discharge
    readonly property int state: dev ? dev.state : 0
    readonly property bool charging: state === 1
    readonly property bool full: state === 4
    readonly property bool plugged: hasBattery && (state === 1 || state === 4 || state === 5 || !UPower.onBattery)

    readonly property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    readonly property var dischargingIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

    // Same plug glyph as the Waybar battery module when on AC
    readonly property string plugIcon: ""

    readonly property string icon: {
        if (!hasBattery) return "󰚥";
        const idx = Math.max(0, Math.min(9, Math.round(percent / 10) - 1));
        if (plugged) return plugIcon;
        return dischargingIcons[idx];
    }

    readonly property color color: {
        if (!hasBattery || plugged) return Theme.foreground;
        if (percent <= 20) return Theme.error;
        if (percent <= 40) return Theme.warning;
        return Theme.foreground;
    }

    readonly property color barColor: {
        if (plugged) return Theme.success;
        if (percent <= 20) return Theme.error;
        if (percent <= 40) return Theme.warning;
        return Theme.primary;
    }

    readonly property string statusText: {
        if (!hasBattery) return "No battery";
        if (charging) return "Charging";
        if (full) return "Fully charged";
        if (plugged) return "Plugged in";
        return "On battery";
    }
}
