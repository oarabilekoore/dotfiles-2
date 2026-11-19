pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string fontFamily: Config.fontFamily
    readonly property int fontSize: Math.max(10, Math.round(13 * Config.fontScale))
    readonly property int fontSizeSmall: Math.max(9, Math.round(11 * Config.fontScale))
    readonly property int fontSizeLarge: Math.max(12, Math.round(15 * Config.fontScale))
    readonly property int barHeight: Config.barHeight
    // Bar and popup geometry is driven by the user's persisted settings.
    readonly property int barRadius: Config.cornerRadius
    readonly property int barMargin: Config.barMargin
    // Fixed width of every icon module on the right (like Waybar)
    readonly property int moduleWidth: 31
    readonly property int moduleRadius: 0
    readonly property int popupRadius: Config.cornerRadius

    // Defaults mirror palette.json so there is no flash of another theme at startup.
    property color background: "#050505"
    property color foreground: "#ededed"
    property color cursor: "#4688df"
    property color surface: "#0a0a0a"
    property color on_surface: "#fafafa"
    property color surface_variant: "#141414"
    property color on_surface_variant: "#a1a1aa"
    property color primary: "#4688df"
    property color on_primary: "#fafafa"
    property color secondary: "#df8957"
    property color outline: "#52525b"
    property color outline_variant: "#262626"
    property color error: "#c91c51"
    property color warning: "#f09434"
    property color success: "#15c988"
    property color color0: "#0a0a0a"
    property color color1: "#c91c51"
    property color color2: "#15c988"
    property color color3: "#f09434"
    property color color4: "#4688df"
    property color color5: "#df8957"
    property color color6: "#52bad1"
    property color color7: "#a1a1aa"
    property color color8: "#52525b"
    property color color9: "#bf2443"
    property color color10: "#15c988"
    property color color11: "#f09434"
    property color color12: "#4688df"
    property color color13: "#df8957"
    property color color14: "#52bad1"
    property color color15: "#fafafa"

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property var paletteKeys: [
        "background", "foreground", "cursor", "surface", "on_surface",
        "surface_variant", "on_surface_variant", "primary", "on_primary",
        "secondary", "outline", "outline_variant", "error", "warning", "success",
        "color0", "color1", "color2", "color3", "color4", "color5", "color6", "color7",
        "color8", "color9", "color10", "color11", "color12", "color13", "color14", "color15"
    ]

    property string lastText: ""

    function loadPalette(txt) {
        if (!txt || txt === root.lastText) return;
        try {
            const p = JSON.parse(txt);
            for (const k of root.paletteKeys) {
                if (typeof p[k] === "string" && p[k].length > 0) root[k] = p[k];
            }
            root.lastText = txt;
        } catch (e) {
            console.warn("Theme: could not parse palette.json:", e);
        }
    }

    FileView {
        id: paletteFile
        path: Quickshell.shellPath("palette.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadPalette(text())
    }

    // update_theme can request an immediate refresh after it atomically writes
    // the wallpaper-derived palette. File watching remains the normal path.
    IpcHandler {
        target: "theme"
        function reload(): void { paletteFile.reload(); }
    }

}