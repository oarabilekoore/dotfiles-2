import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "."

// Launcher: apps, hybrid sparse-vector+FTS5 file & image search, rich previews, clipboard + OCR,
// emoji, snippets, calculator, unit conversion, configurable !bangs, and dmenu IPC.
//
//   quickshell ipc call launcher toggle <all|files|clipboard|emoji|snippets|hidden>
//   quickshell ipc call launcher dmenu "" "" ""
//
// Sigils in All mode:
//   "/" files   ";" clipboard   "'" emoji   "," snippets   ">" shell   "=" calc   "!" bangs
PanelWindow {
    id: root

    // ------------------------------------------------------------------ config
    property string searchUrl: "https://duckduckgo.com/?q="
    property string terminal: "ghostty"

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string stateDir: homeDir + "/.local/state/quickshell-launcher"
    readonly property string fileCachePath: stateDir + "/file-index.txt"
    readonly property string bangConfigPath: homeDir + "/.config/quickshell/bangs.json"
    readonly property string snippetConfigPath: homeDir + "/.config/quickshell/snippets.json"
    readonly property string hydrogenBin: "hydrogen"

    readonly property var searchDirs: [
        homeDir + "/Documents",
        homeDir + "/Downloads",
        homeDir + "/Pictures",
        homeDir + "/Videos",
        homeDir + "/Projects"
    ]

    readonly property var modeOrder: ["all", "files", "clipboard", "emoji", "snippets"]
    readonly property var modeMeta: ({
        all:       { label: "All",       glyph: "󰍉", hint: "Search apps, file contents, snippets (,hdr), or !sl / !sh / !yt / !hister…" },
        files:     { label: "Files",     glyph: "󰈔", hint: "Search filenames, document contents & image OCR/captions…" },
        clipboard: { label: "Clipboard", glyph: "󰅌", hint: "Search clipboard history (Del delete, Ctrl+D clear, Ctrl+O OCR)…" },
        emoji:     { label: "Emoji",     glyph: "󰞅", hint: "Search emoji…" },
        snippets:  { label: "Snippets",  glyph: "󰩫", hint: "Search snippets & dynamic templates ({date}, {clipboard}, {uuid})…" },
        hidden:    { label: "Hidden",    glyph: "󰈉", hint: "Hidden applications (Ctrl+B to unhide)…" },
        dmenu:     { label: "Select",    glyph: "󰘳", hint: "Filter options…" }
    })
    // typed as the very first character in "All" mode to jump to a mode
    readonly property var sigils: ({ "/": "files", ";": "clipboard", "'": "emoji", ",": "snippets" })
    property var bangConfig: []
    property var snippetConfig: []
    property string clipboardSnapshot: ""

    readonly property var sysCommands: [
        { id: "lock",      title: "Lock Screen",                       kw: "lock hyprlock screen",                        glyph: "󰌾", cmd: ["hyprlock"] },
        { id: "sleep",     title: "Sleep",                             kw: "suspend sleep",                               glyph: "󰒲", cmd: ["systemctl", "suspend"] },
        { id: "logout",    title: "Log Out",                           kw: "logout sign out exit",                        glyph: "󰍃", confirm: true, cmd: ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""] },
        { id: "reboot",    title: "Restart",                           kw: "reboot restart",                              glyph: "󰜉", confirm: true, cmd: ["systemctl", "reboot"] },
        { id: "poweroff",  title: "Shut Down",                         kw: "poweroff shutdown power off",                 glyph: "󰐥", confirm: true, cmd: ["systemctl", "poweroff"] },
        { id: "theme",     title: "Toggle Theme",                      kw: "theme dark light mode",                       glyph: "󰏘", cmd: ["update_theme", "toggle"] },
        { id: "wall",      title: "Choose Wallpaper",                  kw: "wallpaper background picker",                 glyph: "󰸉", cmd: ["wallpicker"] },
        { id: "caf",       title: "Toggle Caffeine",                   kw: "caffeine awake idle inhibit",                 glyph: "󰅶", cmd: [root.homeDir + "/.config/hypr/scripts/caffeine.sh", "toggle"] },
        { id: "shot",      title: "Capture Region",                    kw: "screenshot snip capture",                     glyph: "󰄀", cmd: ["omasnap", "--capture-region"] },
        { id: "qs",        title: "Quick Settings",                    kw: "settings quick panel",                        glyph: "󰒓", cmd: ["quickshell", "ipc", "call", "popup", "toggle", "settings"] },
        { id: "wifi",      title: "Network Manager",                   kw: "wifi wi-fi network nmtui",                    glyph: "󰖩", cmd: ["ghostty", "-o", "shell_integration=no-title", "-T", "nmtui", "nmtui"] },
        { id: "reidx",     title: "Refresh File & Vector Index",       kw: "reindex refresh files vector fts5 cache",       glyph: "󰑓", keepOpen: true, fn: () => root.rebuildFileCache(true) },
        { id: "reidx-img", title: "Index Images (OCR + Vision Captions)", kw: "reindex images ocr vision captions photos",   glyph: "󰋩", keepOpen: true, fn: () => root.rebuildImageIndex() },
        { id: "m-hidden",  title: "Show Hidden Apps",                  kw: "hidden unhide apps invisible",                glyph: "󰈉", mode: "hidden" },
        { id: "m-files",   title: "Search Files",                      kw: "files find search vector content",            glyph: "󰈔", mode: "files" },
        { id: "m-clip",    title: "Clipboard History",                 kw: "clipboard history paste copy",             glyph: "󰅌", mode: "clipboard" },
        { id: "m-snip",    title: "Text Snippets",                     kw: "snippets templates expand paste",             glyph: "󰩫", mode: "snippets" },
        { id: "m-emoji",   title: "Emoji Picker",                      kw: "emoji emoticon smiley",                       glyph: "󰞅", mode: "emoji" }
    ]

    readonly property var unitTable: ({
        length: { m: 1, meter: 1, meters: 1, km: 1000, cm: 0.01, mm: 0.001, mi: 1609.344, mile: 1609.344, miles: 1609.344,
                  ft: 0.3048, foot: 0.3048, feet: 0.3048, "in": 0.0254, inch: 0.0254, inches: 0.0254, yd: 0.9144 },
        mass:   { kg: 1, g: 0.001, mg: 0.000001, lb: 0.45359237, lbs: 0.45359237, oz: 0.028349523125, t: 1000 },
        volume: { l: 1, ml: 0.001, gal: 3.785411784, qt: 0.946352946, pt: 0.473176473, cup: 0.2365882365, floz: 0.0295735295625 },
        data:   { b: 1, kb: 1000, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 },
        time:   { s: 1, sec: 1, min: 60, h: 3600, hr: 3600, d: 86400, day: 86400, days: 86400, wk: 604800, week: 604800 },
        speed:  { "m/s": 1, "km/h": 0.2777777778, kph: 0.2777777778, mph: 0.44704, kn: 0.5144444444 }
    })

    // ------------------------------------------------------------------ state
    property bool open: false
    property string mode: "all"
    property string query: ""
    property int selected: 0
    property string previousWindowAddress: ""
    property string pendingPasteText: ""
    property int presentGeneration: 0
    property bool actionsOpen: false
    property int actionIndex: 0
    property string confirmKey: ""
    property int gridCols: 12

    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    property var store: ({ apps: ({}), emoji: [], hidden: [] })
    property var emojiData: []
    property var clipLines: []

    // Cached file index + Hybrid Vector/FTS5 content search state
    property var cachedFiles: []
    property double fileCacheTime: 0
    property bool fileIndexing: false
    property bool imageIndexing: false
    property var contentResults: []
    property string contentQuery: ""
    property int contentSearchSeq: 0

    // Universal dmenu state
    property var dmenuLines: []
    property string dmenuPrompt: "Select…"
    property string dmenuOutPath: ""

    property var previewData: ({ kind: "none", key: "" })
    property int previewSeq: 0

    screen: targetScreen
    visible: open || card.opacity > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ------------------------------------------------------------------ process helper
    Component {
        id: capComp
        Process {
            id: cap
            property var cb: null
            stdout: StdioCollector {
                onStreamFinished: {
                    if (cap.cb) cap.cb(text);
                    cap.destroy(500);
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    if (text && text.trim().length > 0) {
                        console.warn("launcher process stderr:", text.trim());
                    }
                }
            }
            onExited: cap.destroy(3000)
        }
    }

    function runCapture(cmd, cb) {
        return capComp.createObject(root, { command: cmd, cb: cb, running: true });
    }

    function sh(script, args) {
        Quickshell.execDetached(["sh", "-c", script, "_"].concat(args || []));
    }

    // ------------------------------------------------------------------ persistence & file cache
    function loadStore() {
        runCapture(["cat", stateDir + "/state.json"], function (t) {
            try {
                const s = JSON.parse(t);
                root.store = {
                    apps: s.apps || ({}),
                    emoji: s.emoji || [],
                    hidden: Array.isArray(s.hidden) ? s.hidden : []
                };
            } catch (e) { /* first run */ }
        });
    }

    function saveStore() {
        sh("mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/state.json\"", [stateDir, JSON.stringify(store)]);
    }

    function bumpApp(id) {
        const apps = Object.assign({}, store.apps);
        const r = apps[id] || { n: 0, t: 0 };
        apps[id] = { n: r.n + 1, t: Date.now() };
        store = { apps: apps, emoji: store.emoji, hidden: store.hidden };
        saveStore();
    }

    function bumpEmoji(g) {
        const list = [g].concat(store.emoji.filter(x => x !== g)).slice(0, 32);
        store = { apps: store.apps, emoji: list, hidden: store.hidden };
        saveStore();
    }

    function isAppHidden(id) {
        return store.hidden.indexOf(id) >= 0;
    }

    function setAppHidden(id, hide) {
        let list = store.hidden.filter(x => x !== id);
        if (hide) list.push(id);
        store = { apps: store.apps, emoji: store.emoji, hidden: list };
        saveStore();
    }

    function copyDesktopPath(id) {
        const file = id.endsWith(".desktop") ? id : (id + ".desktop");
        const script =
            "for d in \"$HOME/.local/share/applications\" " +
            "\"$HOME/.local/share/flatpak/exports/share/applications\" " +
            "\"/var/lib/flatpak/exports/share/applications\" " +
            "\"/usr/local/share/applications\" " +
            "\"/usr/share/applications\"; do " +
            "  if [ -f \"$d/$1\" ]; then printf '%s' \"$d/$1\" | wl-copy; exit 0; fi; " +
            "done; " +
            "found=$(find /usr/share/applications \"$HOME/.local/share/applications\" -name \"$1\" 2>/dev/null | head -n1); " +
            "[ -n \"$found\" ] && printf '%s' \"$found\" | wl-copy || printf '%s' \"$1\" | wl-copy";
        sh(script, [file]);
    }

    // Loads from disk cache first; refreshes Vector + FTS5 + filename cache asynchronously
    function ensureFileCache() {
        const now = Date.now();
        if (cachedFiles.length > 0 && (now - fileCacheTime) < 600000) return;

        if (cachedFiles.length === 0) {
            runCapture(["cat", fileCachePath], function (t) {
                if (t && t.length > 0 && root.cachedFiles.length === 0) {
                    root.cachedFiles = t.split("\n").filter(l => l.length > 0);
                }
            });
        }
        rebuildFileCache(false);
    }

    function clearFileCache() {
        cachedFiles = [];
        fileCacheTime = 0;
        contentResults = [];
        sh("rm -f \"$1\"", [fileCachePath]);
    }

    function rebuildFileCache(force) {
        if (fileIndexing) return;
        const now = Date.now();
        if (!force && cachedFiles.length > 0 && (now - fileCacheTime) < 600000) return;

        fileIndexing = true;
        runCapture([hydrogenBin, "index", "sync"], function (syncOut) {
            try {
                const info = JSON.parse(syncOut);
                if (info && info.image_worker_started) root.imageIndexing = true;
            } catch (e) {}
            runCapture(["cat", fileCachePath], function (t) {
                root.fileIndexing = false;
                root.fileCacheTime = Date.now();
                if (t && t.length > 0) {
                    root.cachedFiles = t.split("\n").filter(l => l.length > 0);
                }
                if ((root.mode === "files" || root.mode === "all") && root.query.trim().length >= 2) {
                    root.requestContentSearch();
                }
            });
        });
    }

    function rebuildImageIndex() {
        if (imageIndexing) return;
        imageIndexing = true;
        runCapture([hydrogenBin, "index", "sync-images"], function (_out) {
            root.imageIndexing = false;
            if ((root.mode === "files" || root.mode === "all") && root.query.trim().length >= 2) {
                root.requestContentSearch();
            }
        });
    }

    function requestContentSearch() {
        const q = query.trim();
        if ((mode !== "files" && mode !== "all") || q.length < 2 || q.charAt(0) === "!" || q.charAt(0) === ">" || q.charAt(0) === "=") {
            contentResults = [];
            contentQuery = q;
            return;
        }
        const seq = ++contentSearchSeq;
        runCapture([hydrogenBin, "query", q, "--limit", "25"], function (raw) {
            if (seq !== root.contentSearchSeq) return;
            root.contentQuery = q;
            try {
                const parsed = JSON.parse(raw);
                root.contentResults = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                root.contentResults = [];
            }
        });
    }

    Timer { id: contentSearchTimer; interval: 100; repeat: false; onTriggered: root.requestContentSearch() }

    function installDefaultBangs() {
        runCapture(["cat", Quickshell.shellPath("data/bangs.json")], function (raw) {
            try {
                const parsed = JSON.parse(raw);
                root.bangConfig = Array.isArray(parsed) ? parsed : [];
                root.sh('mkdir -p "$HOME/.config/quickshell"; [ -e "$1" ] || cp "$2" "$1"', [root.bangConfigPath, Quickshell.shellPath("data/bangs.json")]);
            } catch (e) {
                console.warn("launcher: bundled bangs.json could not be loaded:", e);
                root.bangConfig = [];
            }
        });
    }

    function loadBangConfig() {
        runCapture(["cat", bangConfigPath], function (raw) {
            if (raw && raw.trim().length > 0) {
                try {
                    const parsed = JSON.parse(raw);
                    root.bangConfig = Array.isArray(parsed) ? parsed.filter(b => b && /^[a-z0-9_-]+$/i.test(String(b.bang || "")) && ["cmd", "command", "sh", "shell", "url"].indexOf(b.type) >= 0) : [];
                    if (root.bangConfig.length === 0) root.installDefaultBangs();
                } catch (e) {
                    console.warn("launcher: invalid bangs.json; using bundled defaults:", e);
                    root.installDefaultBangs();
                }
            } else root.installDefaultBangs();
        });
    }

    function loadSnippets() {
        runCapture(["cat", snippetConfigPath], function (raw) {
            if (!raw || !raw.trim().length) return;
            try {
                const parsed = JSON.parse(raw);
                if (Array.isArray(parsed)) {
                    root.snippetConfig = parsed.filter(s => s && (s.trigger || s.title) && typeof s.body === "string");
                }
            } catch (e) {
                console.warn("launcher: invalid snippets.json:", e);
            }
        });
        runCapture(["wl-paste", "-n"], function (clip) {
            root.clipboardSnapshot = String(clip || "");
        });
    }

    function findBang(name) {
        const key = String(name || "").toLowerCase();
        for (let i = 0; i < bangConfig.length; i++) {
            const b = bangConfig[i];
            if (String(b.bang || "").toLowerCase() === key) return b;
            const aliases = Array.isArray(b.aliases) ? b.aliases : [];
            if (aliases.some(alias => String(alias).toLowerCase() === key)) return b;
        }
        return null;
    }

    function currentBangType() {
        const match = /^!([a-z0-9_-]+)/i.exec(query.trim());
        const entry = match ? findBang(match[1]) : null;
        return entry ? entry.type : "";
    }

    Component.onCompleted: {
        loadStore();
        ensureFileCache();
        loadBangConfig();
        loadSnippets();
    }

    // ------------------------------------------------------------------ open / close
    function normalizeMode(m) {
        if (m === "hidden" || m === "dmenu") return m;
        return (m && modeOrder.indexOf(m) >= 0) ? m : "all";
    }

    function enterMode(m) {
        if (m === "clipboard") loadClipboard();
        else if (m === "files" || m === "all") ensureFileCache();
        else if (m === "emoji") loadEmoji();
        else if (m === "snippets") loadSnippets();
    }

    function setMode(m) {
        const nextMode = normalizeMode(m);
        if (mode === "dmenu" && nextMode !== "dmenu" && dmenuOutPath) finishDmenu("");
        const changed = nextMode !== mode;
        mode = nextMode;
        if (changed) {
            query = "";
            if (searchInput.text.length > 0) searchInput.text = "";
            previewData = ({ kind: "none", key: "" });
        }
        selected = 0;
        actionsOpen = false;
        confirmKey = "";
        enterMode(mode);
        if (mode === "clipboard") clipboardRefreshTimer.restart();
        focusTimer.restart();
    }

    function cycleMode(dir) {
        if (mode === "dmenu") return;
        const idx = modeOrder.indexOf(mode);
        if (idx < 0) {
            setMode("all");
            return;
        }
        setMode(modeOrder[(idx + dir + modeOrder.length) % modeOrder.length]);
    }

    function present(m) {
        if (mode === "dmenu" && dmenuOutPath) finishDmenu("");
        const wasOpen = open;
        const fm = Hyprland.focusedMonitor;
        if (fm) {
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) targetScreen = Quickshell.screens[i];
        }
        searchInput.text = "";
        query = "";
        mode = normalizeMode(m);
        selected = 0;
        actionsOpen = false;
        confirmKey = "";
        enterMode(mode);
        if (mode !== "snippets") loadSnippets();

        if (wasOpen) {
            open = true;
            focusTimer.restart();
            return;
        }

        const request = ++presentGeneration;
        runCapture(["hyprctl", "-j", "activewindow"], function (raw) {
            if (request !== root.presentGeneration) return;
            try {
                const active = JSON.parse(raw);
                root.previousWindowAddress = active && active.address ? String(active.address) : "";
            } catch (e) {
                root.previousWindowAddress = "";
            }
            root.open = true;
            focusTimer.restart();
        });
    }

    function presentDmenu(prompt, inPath, outPath) {
        if (dmenuOutPath) finishDmenu("");
        const fm = Hyprland.focusedMonitor;
        if (fm) {
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) targetScreen = Quickshell.screens[i];
        }
        dmenuPrompt = (prompt && prompt.trim().length > 0) ? prompt.trim() : "Select…";
        dmenuOutPath = String(outPath || "");
        dmenuLines = [];
        searchInput.text = "";
        query = "";
        mode = "dmenu";
        selected = 0;
        actionsOpen = false;
        confirmKey = "";

        runCapture(["cat", String(inPath || "")], function (raw) {
            root.dmenuLines = String(raw || "").split("\n").filter(l => l.length > 0);
            root.open = true;
            focusTimer.restart();
        });
    }

    function finishDmenu(value) {
        const out = dmenuOutPath;
        dmenuOutPath = "";
        dmenuLines = [];
        if (out) {
            sh("mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", [out, String(value || "")]);
        }
        open = false;
        actionsOpen = false;
        confirmKey = "";
        mode = "all";
    }

    function pasteIntoPreviousApp(text) {
        const content = String(text || "");
        if (!content.length) return;
        pendingPasteText = content;
        dismiss();
        pasteTimer.restart();
    }

    function dismiss() {
        if (mode === "dmenu" && dmenuOutPath) {
            finishDmenu("");
            return;
        }
        open = false;
        actionsOpen = false;
        confirmKey = "";
    }

    function toggle(m) {
        const nm = normalizeMode(m);
        if (open && mode === nm) dismiss();
        else present(nm);
    }

    Timer { id: focusTimer; interval: 30; onTriggered: searchInput.forceActiveFocus() }
    Timer {
        id: pasteTimer
        interval: 220
        repeat: false
        onTriggered: {
            const text = root.pendingPasteText;
            const address = root.previousWindowAddress;
            root.pendingPasteText = "";
            if (!text.length) return;
            root.sh(
                "printf '%s' \"$2\" | wl-copy --type text/plain;charset=utf-8; " +
                "if [ -n \"$1\" ]; then hyprctl dispatch focuswindow \"address:$1\" >/dev/null 2>&1 || true; fi; " +
                "sleep 0.18; wtype -M ctrl v -m ctrl",
                [address, text]
            );
        }
    }
    Timer { id: confirmTimer; interval: 12000; onTriggered: root.confirmKey = "" }
    Timer { id: previewDebounce; interval: 90; onTriggered: root.loadPreview() }
    Timer {
        id: clipboardRefreshTimer
        interval: 180
        repeat: false
        onTriggered: if (root.open && root.mode === "clipboard") root.loadClipboard()
    }

    // ------------------------------------------------------------------ text scoring / highlight
    function scoreText(text, terms, fuzzy) {
        const lower = String(text).toLowerCase();
        let total = 0;
        const hits = [];
        for (let t = 0; t < terms.length; t++) {
            const q = terms[t];
            const i = lower.indexOf(q);
            if (i >= 0) {
                let s = 300 - Math.min(i, 60);
                if (lower === q) s = 1000;
                else if (i === 0) s = 700;
                else {
                    const c = lower.charAt(i - 1);
                    if (c === " " || c === "-" || c === "_" || c === "." || c === "/" || c === "(") s = 500;
                }
                total += s;
                for (let k = 0; k < q.length; k++) hits.push(i + k);
            } else if (fuzzy && q.length >= 2) {
                let pos = -1, gaps = 0, last = -2;
                const idx = [];
                for (let k = 0; k < q.length; k++) {
                    const j = lower.indexOf(q.charAt(k), pos + 1);
                    if (j < 0) return null;
                    if (j !== last + 1) gaps++;
                    idx.push(j);
                    last = j;
                    pos = j;
                }
                total += Math.max(20, 160 - gaps * 20);
                for (let k = 0; k < idx.length; k++) hits.push(idx[k]);
            } else {
                return null;
            }
        }
        return { s: terms.length > 0 ? total / terms.length : 0, hits: hits };
    }

    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlight(text, hits, color) {
        const str = String(text);
        if (!hits || hits.length === 0) return esc(str);
        const set = {};
        for (let i = 0; i < hits.length; i++) set[hits[i]] = true;
        let out = "";
        let on = false;
        for (let i = 0; i < str.length; i++) {
            const h = set[i] === true;
            if (h && !on) { out += "<font color=\"" + color + "\"><b>"; on = true; }
            if (!h && on) { out += "</b></font>"; on = false; }
            out += esc(str.charAt(i));
        }
        if (on) out += "</b></font>";
        return out;
    }

    function iconSrc(name, fallback) {
        if (name && name.charAt(0) === "/") return "file://" + name;
        if (name) {
            const p = Quickshell.iconPath(name, true);
            if (p !== "") return p;
        }
        if (fallback) {
            if (fallback.charAt(0) === "/") return "file://" + fallback;
            const fp = Quickshell.iconPath(fallback, true);
            if (fp !== "") return fp;
        }
        return "";
    }

    function fmtNum(v) {
        if (!isFinite(v)) return "∞";
        if (Math.abs(v) < 1e15 && Math.round(v) === v) return String(v);
        return String(parseFloat(v.toPrecision(12)));
    }

    function humanSize(b) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        let v = b;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (i === 0 ? String(v) : v.toFixed(1)) + " " + u[i];
    }

    function tilde(p) {
        return p.indexOf(homeDir) === 0 ? "~" + p.slice(homeDir.length) : p;
    }

    function generateUuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
            const r = Math.random() * 16 | 0;
            const v = c === "x" ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    function expandSnippet(rawBody) {
        const d = new Date();
        const pad = (n) => (n < 10 ? "0" : "") + n;
        const dateStr = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
        const timeStr = pad(d.getHours()) + ":" + pad(d.getMinutes());
        return String(rawBody || "")
            .replace(/\{date\}/g, dateStr)
            .replace(/\{time\}/g, timeStr)
            .replace(/\{datetime\}/g, dateStr + " " + timeStr)
            .replace(/\{uuid\}/g, generateUuid())
            .replace(/\{clipboard\}/g, clipboardSnapshot);
    }

    // ------------------------------------------------------------------ calculator
    function calcEval(src) {
        const s = src.toLowerCase().replace(/×/g, "*").replace(/÷/g, "/").replace(/\*\*/g, "^");
        const toks = [];
        let i = 0;
        const isDigit = (c) => c >= "0" && c <= "9";
        const isAlpha = (c) => c >= "a" && c <= "z";
        while (i < s.length) {
            const c = s.charAt(i);
            if (c === " ") { i++; continue; }
            if (isDigit(c) || c === ".") {
                let j = i;
                while (j < s.length && (isDigit(s.charAt(j)) || s.charAt(j) === ".")) j++;
                if (s.charAt(j) === "e") {
                    let k = j + 1;
                    if (s.charAt(k) === "+" || s.charAt(k) === "-") k++;
                    if (isDigit(s.charAt(k))) {
                        while (k < s.length && isDigit(s.charAt(k))) k++;
                        j = k;
                    }
                }
                const v = parseFloat(s.slice(i, j));
                if (isNaN(v)) return NaN;
                toks.push({ t: "n", v: v });
                i = j;
                continue;
            }
            if (isAlpha(c)) {
                let j = i;
                while (j < s.length && (isAlpha(s.charAt(j)) || isDigit(s.charAt(j)) || s.charAt(j) === "_")) j++;
                toks.push({ t: "id", v: s.slice(i, j) });
                i = j;
                continue;
            }
            if ("+-*/^%(),".indexOf(c) >= 0) { toks.push({ t: "o", v: c }); i++; continue; }
            return NaN;
        }

        let p = 0;
        const isOp = (v) => p < toks.length && toks[p].t === "o" && toks[p].v === v;
        const startsOperand = (k) => {
            const t = toks[k];
            return !!t && (t.t === "n" || t.t === "id" || (t.t === "o" && (t.v === "(" || t.v === "-")));
        };
        function callFn(name, a) {
            const x = a[0];
            switch (name) {
            case "sqrt": return Math.sqrt(x);
            case "cbrt": return Math.cbrt(x);
            case "sin": return Math.sin(x);
            case "cos": return Math.cos(x);
            case "tan": return Math.tan(x);
            case "asin": return Math.asin(x);
            case "acos": return Math.acos(x);
            case "atan": return Math.atan(x);
            case "ln": return Math.log(x);
            case "log": return Math.log10(x);
            case "log2": return Math.log2(x);
            case "exp": return Math.exp(x);
            case "abs": return Math.abs(x);
            case "round": return Math.round(x);
            case "floor": return Math.floor(x);
            case "ceil": return Math.ceil(x);
            case "min": return Math.min.apply(null, a);
            case "max": return Math.max.apply(null, a);
            }
            throw new Error("fn");
        }
        function primary() {
            const t = toks[p++];
            if (!t) throw new Error("eof");
            if (t.t === "n") return t.v;
            if (t.t === "o" && t.v === "(") {
                const v = expr();
                if (!isOp(")")) throw new Error(")");
                p++;
                return v;
            }
            if (t.t === "id") {
                if (isOp("(")) {
                    p++;
                    const args = [];
                    if (!isOp(")")) {
                        args.push(expr());
                        while (isOp(",")) { p++; args.push(expr()); }
                    }
                    if (!isOp(")")) throw new Error(")");
                    p++;
                    return callFn(t.v, args);
                }
                if (t.v === "pi") return Math.PI;
                if (t.v === "e") return Math.E;
                if (t.v === "tau") return Math.PI * 2;
            }
            throw new Error("tok");
        }
        function postfix() {
            let v = primary();
            while (isOp("%") && !startsOperand(p + 1)) { p++; v = v / 100; }
            return v;
        }
        function power() {
            const b = postfix();
            if (isOp("^")) { p++; return Math.pow(b, unary()); }
            return b;
        }
        function unary() {
            if (isOp("-")) { p++; return -unary(); }
            if (isOp("+")) { p++; return unary(); }
            return power();
        }
        function term() {
            let v = unary();
            for (;;) {
                if (isOp("*") || isOp("/")) {
                    const o = toks[p++].v;
                    const r = unary();
                    v = o === "*" ? v * r : v / r;
                } else if (isOp("%") && startsOperand(p + 1)) {
                    p++;
                    v = v % unary();
                } else break;
            }
            return v;
        }
        function expr() {
            let v = term();
            while (isOp("+") || isOp("-")) {
                const o = toks[p++].v;
                const r = term();
                v = o === "+" ? v + r : v - r;
            }
            return v;
        }
        try {
            const v = expr();
            return p === toks.length ? v : NaN;
        } catch (e) {
            return NaN;
        }
    }

    function calcItem(q) {
        const body = q.charAt(0) === "=" ? q.slice(1).trim() : q;
        if (body.length === 0) return null;
        const forced = q.charAt(0) === "=";
        if (!forced && !/[-+*\/^%()×÷]/.test(body.replace(/^[-+]/, "")) ) return null;
        if (!forced && /^[a-z ]+$/i.test(body)) return null;
        const v = calcEval(body);
        if (isNaN(v)) return null;
        const txt = fmtNum(v);
        return {
            key: "calc", section: "Calculator", title: txt, subtitle: body + " =", glyph: "󰃬", badge: "Result", hits: [],
            actions: [{ label: "Copy Result", run: () => Quickshell.execDetached(["wl-copy", txt]) }]
        };
    }

    function unitItem(q) {
        const m = /^(-?\d+(?:\.\d+)?)\s*([a-z°\/]+)\s+(?:to|in|as|->)\s+([a-z°\/]+)$/i.exec(q.trim());
        if (!m) return null;
        const val = parseFloat(m[1]);
        const a = m[2].toLowerCase().replace("°", "");
        const b = m[3].toLowerCase().replace("°", "");
        let out = null;
        const temps = { c: 1, f: 1, k: 1 };
        if (temps[a] && temps[b]) {
            let c = a === "c" ? val : (a === "f" ? (val - 32) * 5 / 9 : val - 273.15);
            out = b === "c" ? c : (b === "f" ? c * 9 / 5 + 32 : c + 273.15);
        } else {
            for (const cat in unitTable) {
                const t = unitTable[cat];
                if (t[a] !== undefined && t[b] !== undefined) { out = val * t[a] / t[b]; break; }
            }
        }
        if (out === null) return null;
        const txt = fmtNum(parseFloat(out.toPrecision(10)));
        return {
            key: "unit", section: "Conversion", title: fmtNum(val) + " " + m[2] + " = " + txt + " " + m[3], subtitle: "Unit conversion",
            glyph: "󰓡", badge: "Result", hits: [],
            actions: [{ label: "Copy Result", run: () => Quickshell.execDetached(["wl-copy", txt]) }]
        };
    }

    // ------------------------------------------------------------------ item builders
    function openUrl(u) { Quickshell.execDetached(["xdg-open", u]); }

    function urlItem(q) {
        const t = q.trim();
        if (/\s/.test(t)) return null;
        if (!/^(https?:\/\/\S+|www\.\S+|[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|dev|app|co|ai|me|edu|gov|xyz|tv|sh|bw|za|uk|de|fr|info|wiki|gg|ly|to)(\/\S*)?)$/i.test(t)) return null;
        const url = /^https?:\/\//i.test(t) ? t : "https://" + t;
        return {
            key: "url", section: "Web", title: "Open " + t, subtitle: url, glyph: "󰌷", badge: "URL", hits: [],
            actions: [{ label: "Open in Browser", run: () => root.openUrl(url) },
                      { label: "Copy URL", run: () => Quickshell.execDetached(["wl-copy", url]) }]
        };
    }

    function webItems(q) {
        const url = searchUrl + encodeURIComponent(q.trim());
        return [{ key: "web", section: "Web", title: "Search the web for “" + q.trim() + "”", subtitle: "", glyph: "󰖟",
                  badge: "Web", hits: [], actions: [{ label: "Search", run: () => root.openUrl(url) }] }];
    }

    function bangItems(q) {
        const trimmed = q.trim();
        const match = /^!([a-z0-9_-]*)(?:\s+(.*))?$/i.exec(trimmed);
        if (!match) return [];
        const name = match[1].toLowerCase();
        const body = String(match[2] || "").trim();
        if (!name) {
            return bangConfig.map(b => {
                const isCmd = b.type === "cmd" || b.type === "command";
                const isSh = b.type === "sh" || b.type === "shell";
                const sub = isCmd ? (b.description || ("Run: " + (b.cmd || "")))
                          : (isSh ? (b.description || "Run a shell command")
                          : ("Search " + (b.label || b.bang)));
                return {
                    key: "bang-hint:" + b.bang,
                    section: "Available !bangs",
                    title: "!" + b.bang + (b.label ? " · " + b.label : ""),
                    subtitle: sub,
                    glyph: (isCmd || isSh) ? "󰆍" : "󰖟",
                    badge: (isCmd || isSh) ? "Command" : "Bang",
                    hits: [],
                    actions: [{ label: "Use !" + b.bang, keepOpen: true, run: () => { searchInput.text = "!" + b.bang + " "; searchInput.cursorPosition = searchInput.text.length; searchInput.forceActiveFocus(); } }]
                };
            });
        }
        const bang = findBang(name);
        if (!bang) {
            return [{ key: "bang-unknown:" + name, section: "Bangs", title: "Unknown bang: !" + name,
                      subtitle: "Edit ~/.config/quickshell/bangs.json to add it. Try !sl, !sh, !yt or !hister.", glyph: "󰋔", badge: "Help", hits: [],
                      actions: [{ label: "Open launcher documentation", run: () => root.openUrl("file://" + Quickshell.shellPath("docs/LAUNCHER.md")) }] }];
        }
        if (bang.type === "cmd" || bang.type === "command") {
            const rawCmd = String(bang.cmd || "").trim();
            if (!rawCmd) return [];
            const hasPlaceholder = rawCmd.indexOf("{query}") >= 0;
            if (hasPlaceholder && !body) {
                return [{
                    key: "bang-cmd-hint:" + name,
                    section: bang.label || name,
                    title: "!" + name + " <args>",
                    subtitle: bang.description || ("Runs: " + rawCmd),
                    glyph: "󰆍", badge: "Command", hits: [],
                    actions: [{ label: "Type arguments", keepOpen: true, run: () => {} }]
                }];
            }
            const resolvedCmd = hasPlaceholder ? rawCmd.replace(/\{query\}/g, body) : (body ? rawCmd + " " + body : rawCmd);
            const label = bang.label || name;
            return [{
                key: "bang-cmd:" + name + ":" + resolvedCmd,
                section: label,
                title: label + (body && !hasPlaceholder ? " (" + body + ")" : ""),
                subtitle: "$ " + resolvedCmd,
                glyph: "󰆍", badge: "Command", hits: [],
                actions: [
                    { label: "Run " + label, confirm: !!bang.confirm, run: () => Quickshell.execDetached(["sh", "-c", resolvedCmd]) },
                    { label: "Run in Terminal", confirm: !!bang.confirm, run: () => Quickshell.execDetached([root.terminal, "-e", "sh", "-c", resolvedCmd + "; echo; printf 'Press Enter to close…'; read _"]) },
                    { label: "Copy Command", run: () => Quickshell.execDetached(["wl-copy", resolvedCmd]) }
                ]
            }];
        }
        if (bang.type === "sh" || bang.type === "shell") {
            if (!body) {
                return [{
                    key: "bang-sh-hint:" + name,
                    section: bang.label || "Shell Command",
                    title: "!" + name + " <command>",
                    subtitle: "Type a shell command to execute",
                    glyph: "󰆍", badge: "Command", hits: [],
                    actions: [{ label: "Type a command", keepOpen: true, run: () => {} }]
                }];
            }
            return [{
                key: "bang-sh:" + body,
                section: bang.label || "Shell Command",
                title: body,
                subtitle: "Run shell command",
                glyph: "󰆍", badge: "Command", hits: [],
                actions: [
                    { label: "Run", run: () => Quickshell.execDetached(["sh", "-c", body]) },
                    { label: "Run in Terminal", run: () => Quickshell.execDetached([root.terminal, "-e", "sh", "-c", body + "; echo; printf 'Press Enter to close…'; read _"]) },
                    { label: "Copy Command", run: () => Quickshell.execDetached(["wl-copy", body]) }
                ]
            }];
        }
        if (bang.type === "url") {
            const emptyUrl = String(bang.emptyUrl || "").trim();
            if (!body) {
                return [{
                    key: "bang-url-hint:" + name,
                    section: bang.label || name,
                    title: emptyUrl ? ("Open " + (bang.label || name)) : ("!" + name + " <query>"),
                    subtitle: emptyUrl ? emptyUrl : "Type a search term after the bang",
                    glyph: "󰖟", badge: bang.label || name, hits: [],
                    actions: [emptyUrl ? { label: "Open " + (bang.label || name), run: () => root.openUrl(emptyUrl) } : { label: "Type a query", keepOpen: true, run: () => {} }]
                }];
            }
            const template = String(bang.template || "");
            const url = template.replace(/\{query\}/g, encodeURIComponent(body));
            return [{ key: "bang-url:" + name + ":" + body, section: bang.label || name, title: "Search " + (bang.label || name) + " for “" + body + "”", subtitle: url, glyph: "󰖟", badge: bang.label || name, hits: [], actions: [{ label: "Search " + (bang.label || name), run: () => root.openUrl(url) }] }];
        }
        return [];
    }

    function runItem(q) {
        const cmd = q.slice(1).trim();
        if (cmd.length === 0) return [];
        return [{
            key: "run", section: "Run", title: cmd, subtitle: "Run shell command", glyph: "󰆍", badge: "Command", hits: [],
            actions: [
                { label: "Run", run: () => Quickshell.execDetached(["sh", "-c", cmd]) },
                { label: "Run in Terminal", run: () => Quickshell.execDetached([root.terminal, "-e", "sh", "-c", cmd + "; echo; printf 'Press Enter to close…'; read _"]) }
            ]
        }];
    }

    function launchApp(e) {
        bumpApp(e.id);
        e.execute();
    }

    function buildAppActions(e, hiddenState) {
        const acts = [{ label: "Open", run: () => root.launchApp(e) }];
        const da = e.actions || [];
        for (let k = 0; k < da.length; k++) {
            const a = da[k];
            acts.push({ label: a.name, run: () => { root.bumpApp(e.id); a.execute(); } });
        }
        acts.push({
            label: "Copy .desktop Path",
            run: () => root.copyDesktopPath(e.id)
        });
        acts.push({
            label: "Copy Desktop ID",
            run: () => Quickshell.execDetached(["wl-copy", e.id])
        });
        if (e.execString) {
            acts.push({
                label: "Copy Exec Command",
                run: () => Quickshell.execDetached(["wl-copy", e.execString])
            });
        }
        acts.push({
            label: hiddenState ? "Unhide from Launcher" : "Hide from Launcher",
            keepOpen: true,
            run: () => root.setAppHidden(e.id, !hiddenState)
        });
        return acts;
    }

    function appItems(terms, onlyHidden) {
        const entries = DesktopEntries.applications.values;
        const out = [];
        const now = Date.now();
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (e.noDisplay) continue;
            const hidden = isAppHidden(e.id);
            if (onlyHidden ? !hidden : hidden) continue;

            const rec = store.apps[e.id];
            let boost = 0;
            if (rec) {
                boost = Math.min(rec.n, 30) * 12;
                const days = (now - rec.t) / 86400000;
                if (days < 7) boost += Math.round((7 - days) * 8);
            }
            let s = 0;
            let hits = [];
            if (terms.length > 0) {
                const m = scoreText(e.name, terms, true);
                if (m) { s = m.s; hits = m.hits; }
                else {
                    const extra = ((e.genericName || "") + " " + (e.keywords ? e.keywords.join(" ") : "") + " " + (e.comment || "") + " " + e.id).toLowerCase();
                    let ok = true;
                    for (let t = 0; t < terms.length; t++) if (extra.indexOf(terms[t]) < 0) { ok = false; break; }
                    if (!ok) continue;
                    s = 60;
                }
            }
            out.push({
                key: "app:" + e.id,
                section: onlyHidden ? "Hidden Applications" : "Applications",
                title: e.name,
                subtitle: e.genericName || e.comment || e.id,
                icon: e.icon,
                iconFb: "application-x-executable",
                glyph: "󰣆",
                badge: onlyHidden ? "Hidden" : "Application",
                hits: hits,
                score: s + boost,
                boost: boost,
                actions: buildAppActions(e, hidden)
            });
        }
        out.sort((a, b) => (b.score - a.score) || a.title.localeCompare(b.title));
        return out;
    }

    function commandItems(terms, limit) {
        const out = [];
        for (let i = 0; i < sysCommands.length; i++) {
            const c = sysCommands[i];
            const m = scoreText(c.title, terms, true);
            let s;
            let hits = [];
            if (m) { s = m.s; hits = m.hits; }
            else {
                let ok = true;
                for (let t = 0; t < terms.length; t++) if (c.kw.indexOf(terms[t]) < 0) { ok = false; break; }
                if (!ok) continue;
                s = 80;
            }
            const act = c.fn
                ? { label: c.title, keepOpen: !!c.keepOpen, run: c.fn }
                : (c.mode
                    ? { label: "Open", keepOpen: true, run: () => root.setMode(c.mode) }
                    : { label: c.title, confirm: !!c.confirm, run: () => Quickshell.execDetached(c.cmd) });
            out.push({ key: "cmd:" + c.id, section: "Commands", title: c.title, subtitle: c.confirm ? "Asks for confirmation" : "", glyph: c.glyph,
                       badge: "Command", hits: hits, score: s, actions: [act] });
        }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, limit);
    }

    // ---- file format visuals (live image thumbnails + XDG icon lookup + Nerd Font format glyphs)
    function isImageName(name) {
        return /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i.test(name);
    }

    function fileFormatInfo(name, isDir, fullPath) {
        if (isDir) {
            return { icon: "folder", iconFb: "inode-directory", glyph: "󰉋", fmtBadge: "Folder" };
        }
        const dot = name.lastIndexOf(".");
        const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";

        if (isImageName(name)) {
            return { icon: fullPath, iconFb: "image-x-generic", glyph: "󰋩", fmtBadge: ext.toUpperCase() };
        }

        const table = {
            pdf:      { icon: "application-pdf",        fb: "x-office-document",     glyph: "󰈦" },
            md:       { icon: "text-x-markdown",        fb: "text-x-generic",        glyph: "󰍔" },
            markdown: { icon: "text-x-markdown",        fb: "text-x-generic",        glyph: "󰍔" },
            rst:      { icon: "text-x-generic",         fb: "",                      glyph: "󰍔" },
            org:      { icon: "text-x-generic",         fb: "",                      glyph: "󰍔" },
            tex:      { icon: "text-x-tex",             fb: "text-x-generic",        glyph: "󰙩" },
            typ:      { icon: "text-x-generic",         fb: "",                      glyph: "󰙩" },
            txt:      { icon: "text-x-generic",         fb: "",                      glyph: "󰈙" },
            log:      { icon: "text-x-log",             fb: "text-x-generic",        glyph: "󰈙" },
            doc:      { icon: "x-office-document",      fb: "",                      glyph: "󰈬" },
            docx:     { icon: "x-office-document",      fb: "",                      glyph: "󰈬" },
            odt:      { icon: "x-office-document",      fb: "",                      glyph: "󰈬" },
            rtf:      { icon: "x-office-document",      fb: "",                      glyph: "󰈬" },
            epub:     { icon: "application-epub+zip",   fb: "x-office-document",     glyph: "󰂺" },
            xls:      { icon: "x-office-spreadsheet",   fb: "",                      glyph: "󰈛" },
            xlsx:     { icon: "x-office-spreadsheet",   fb: "",                      glyph: "󰈛" },
            ods:      { icon: "x-office-spreadsheet",   fb: "",                      glyph: "󰈛" },
            csv:      { icon: "text-csv",               fb: "x-office-spreadsheet",  glyph: "󰈛" },
            tsv:      { icon: "text-csv",               fb: "x-office-spreadsheet",  glyph: "󰈛" },
            ppt:      { icon: "x-office-presentation",  fb: "",                      glyph: "󰈧" },
            pptx:     { icon: "x-office-presentation",  fb: "",                      glyph: "󰈧" },
            odp:      { icon: "x-office-presentation",  fb: "",                      glyph: "󰈧" },
            mp4:      { icon: "video-x-generic",        fb: "",                      glyph: "󰕧" },
            mkv:      { icon: "video-x-generic",        fb: "",                      glyph: "󰕧" },
            webm:     { icon: "video-x-generic",        fb: "",                      glyph: "󰕧" },
            mov:      { icon: "video-x-generic",        fb: "",                      glyph: "󰕧" },
            avi:      { icon: "video-x-generic",        fb: "",                      glyph: "󰕧" },
            mp3:      { icon: "audio-x-generic",        fb: "",                      glyph: "󰎆" },
            flac:     { icon: "audio-x-generic",        fb: "",                      glyph: "󰎆" },
            wav:      { icon: "audio-x-generic",        fb: "",                      glyph: "󰎆" },
            ogg:      { icon: "audio-x-generic",        fb: "",                      glyph: "󰎆" },
            m4a:      { icon: "audio-x-generic",        fb: "",                      glyph: "󰎆" },
            opus:     { icon: "audio-x-generic",        fb: "",                      glyph: "󰎆" },
            zip:      { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            tar:      { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            gz:       { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            xz:       { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            zst:      { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            tgz:      { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            bz2:      { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            "7z":     { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            rar:      { icon: "package-x-generic",      fb: "",                      glyph: "󰗀" },
            iso:      { icon: "application-x-cd-image", fb: "package-x-generic",     glyph: "󰗮" },
            py:       { icon: "text-x-python",          fb: "text-x-script",         glyph: "󰌠" },
            ipynb:    { icon: "text-x-python",          fb: "text-x-script",         glyph: "󰌠" },
            rs:       { icon: "text-x-rust",            fb: "text-x-source",         glyph: "󱘗" },
            c:        { icon: "text-x-csrc",            fb: "",                      glyph: "󰙱" },
            h:        { icon: "text-x-chdr",            fb: "",                      glyph: "󰙱" },
            cpp:      { icon: "text-x-c++src",          fb: "",                      glyph: "󰙲" },
            hpp:      { icon: "text-x-c++hdr",          fb: "",                      glyph: "󰙲" },
            js:       { icon: "text-x-javascript",      fb: "text-x-script",         glyph: "󰌞" },
            jsx:      { icon: "text-x-javascript",      fb: "text-x-script",         glyph: "󰌞" },
            ts:       { icon: "text-x-typescript",      fb: "text-x-script",         glyph: "󰛦" },
            tsx:      { icon: "text-x-typescript",      fb: "text-x-script",         glyph: "󰛦" },
            qml:      { icon: "text-x-qml",             fb: "text-x-script",         glyph: "󰘳" },
            sh:       { icon: "text-x-script",          fb: "",                      glyph: "󰆍" },
            fish:     { icon: "text-x-script",          fb: "",                      glyph: "󰆍" },
            zsh:      { icon: "text-x-script",          fb: "",                      glyph: "󰆍" },
            bash:     { icon: "text-x-script",          fb: "",                      glyph: "󰆍" },
            html:     { icon: "text-html",              fb: "",                      glyph: "󰖟" },
            htm:      { icon: "text-html",              fb: "",                      glyph: "󰖟" },
            css:      { icon: "text-css",               fb: "",                      glyph: "󰌜" },
            scss:     { icon: "text-css",               fb: "",                      glyph: "󰌜" },
            json:     { icon: "application-json",       fb: "text-x-generic",        glyph: "󰘦" },
            toml:     { icon: "text-x-generic",         fb: "",                      glyph: "󰘦" },
            yaml:     { icon: "application-x-yaml",     fb: "text-x-generic",        glyph: "󰘦" },
            yml:      { icon: "application-x-yaml",     fb: "text-x-generic",        glyph: "󰘦" },
            xml:      { icon: "application-xml",        fb: "text-x-generic",        glyph: "󰗀" },
            cur:      { icon: "application-x-theme",    fb: "",                      glyph: "󰇀" },
            ani:      { icon: "application-x-theme",    fb: "",                      glyph: "󰇀" }
        };

        const entry = table[ext];
        if (entry) {
            return {
                icon: entry.icon,
                iconFb: entry.fb,
                glyph: entry.glyph,
                fmtBadge: ext ? ext.toUpperCase() : ""
            };
        }
        return {
            icon: "text-x-generic",
            iconFb: "",
            glyph: "󰈔",
            fmtBadge: ext ? ext.toUpperCase() : ""
        };
    }

    function ocrImageFile(filePath) {
        if (!filePath) return;
        const args = [hydrogenBin, "ocr", "file", String(filePath)];
        if (root.previousWindowAddress) args.push("--window", root.previousWindowAddress);
        Quickshell.execDetached(args);
    }

    function buildFileActions(p, dir, isDir, name) {
        const acts = [
            { label: "Open", run: () => Quickshell.execDetached(["xdg-open", p]) },
            { label: "Show in Folder", run: () => root.sh("gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 --method org.freedesktop.FileManager1.ShowItems \"['file://$1']\" '' >/dev/null 2>&1 || xdg-open \"$(dirname \"$1\")\"", [p]) }
        ];
        if (!isDir && isImageName(name)) {
            acts.push({ label: "OCR to Markdown (Ctrl+O)", run: () => root.ocrImageFile(p) });
        }
        acts.push(
            { label: "Copy Path", run: () => Quickshell.execDetached(["wl-copy", p]) },
            { label: "Open Terminal Here", run: () => Quickshell.execDetached([root.terminal, "--working-directory=" + (isDir ? p : dir)]) }
        );
        return acts;
    }

    // ---- hybrid file & image search (Sparse TF-IDF Vector + FTS5/BM25 + Filename Cache)
    function fileItemsFromCache(terms, limit) {
        const out = [];
        const seen = {};
        const qTrim = query.trim();

        // 1. Sparse Vector + FTS5/BM25 content & image OCR/caption matches ranked higher
        if (terms.length > 0 && contentQuery === qTrim && contentResults.length > 0) {
            for (let i = 0; i < contentResults.length; i++) {
                const cr = contentResults[i];
                const p = String(cr.path || "");
                if (!p || seen[p]) continue;
                seen[p] = true;
                const slash = p.lastIndexOf("/");
                const name = p.slice(slash + 1) || p;
                const dir = slash > 0 ? p.slice(0, slash) : "/";
                const m = scoreText(name, terms, false);
                const hh = m ? m.hits : [];
                const snip = String(cr.snippet || "").trim();
                const sub = snip ? (snip + " · " + tilde(dir)) : tilde(dir);
                const vecPct = Math.round((Number(cr.vec) || 0) * 100);
                const fmt = fileFormatInfo(name, false, p);
                const isImgHit = cr.source === "image";
                const badgeText = cr.phrase ? "Phrase"
                                : (vecPct >= 14 ? ((isImgHit ? "Vision " : "Match ") + vecPct + "%")
                                : (fmt.fmtBadge || "Content"));
                out.push({
                    key: "file:" + p,
                    section: "Files · Content & Vision Match",
                    title: name,
                    subtitle: sub,
                    icon: fmt.icon,
                    iconFb: fmt.iconFb,
                    glyph: fmt.glyph,
                    badge: badgeText,
                    hits: hh,
                    score: 2500 + (Number(cr.score) || 0),
                    preview: { type: "file", path: p, isDir: false },
                    actions: buildFileActions(p, dir, false, name)
                });
            }
        }

        // 2. Filename / path cache (deduplicated against content hits)
        const src = cachedFiles;
        for (let i = 0; i < src.length; i++) {
            let p = src[i];
            const isDir = p.length > 1 && p.charAt(p.length - 1) === "/";
            if (isDir) p = p.slice(0, -1);
            if (seen[p]) continue;

            const slash = p.lastIndexOf("/");
            const name = p.slice(slash + 1) || p;
            const dir = slash > 0 ? p.slice(0, slash) : "/";

            let s = 1000 - i;
            let hh = [];
            if (terms.length > 0) {
                const m = scoreText(name, terms, false);
                if (m) {
                    s = m.s * 1.5;
                    hh = m.hits;
                } else {
                    const lp = p.toLowerCase();
                    let ok = true;
                    for (let t = 0; t < terms.length; t++) if (lp.indexOf(terms[t]) < 0) { ok = false; break; }
                    if (!ok) continue;
                    s = 40;
                }
                if (isDir) s += 10;
            }
            seen[p] = true;
            const fmt = fileFormatInfo(name, isDir, p);
            out.push({
                key: "file:" + p,
                section: "Files",
                title: name,
                subtitle: tilde(dir),
                icon: fmt.icon,
                iconFb: fmt.iconFb,
                glyph: fmt.glyph,
                badge: fmt.fmtBadge,
                hits: hh,
                score: s,
                preview: { type: "file", path: p, isDir: isDir },
                actions: buildFileActions(p, dir, isDir, name)
            });
            if (terms.length === 0 && out.length >= limit) break;
        }
        if (terms.length > 0) out.sort((a, b) => b.score - a.score);
        return out.slice(0, limit);
    }

    // ---- snippets & dynamic templates
    function snippetItems(terms) {
        const out = [];
        for (let i = 0; i < snippetConfig.length; i++) {
            const sn = snippetConfig[i];
            const trig = String(sn.trigger || "").trim();
            const title = String(sn.title || trig);
            const rawBody = String(sn.body || "");
            const expanded = expandSnippet(rawBody);
            const singleLine = expanded.replace(/\s+/g, " ").trim();

            let s = 100 - i;
            let hits = [];
            if (terms.length > 0) {
                const mTitle = scoreText(title, terms, true);
                const mTrig = trig ? scoreText(trig, terms, false) : null;
                if (mTrig) {
                    s = mTrig.s + 250;
                } else if (mTitle) {
                    s = mTitle.s;
                    hits = mTitle.hits;
                } else {
                    const hay = (trig + " " + title + " " + rawBody).toLowerCase();
                    let ok = true;
                    for (let t = 0; t < terms.length; t++) if (hay.indexOf(terms[t]) < 0) { ok = false; break; }
                    if (!ok) continue;
                    s = 50;
                }
            }

            out.push({
                key: "snip:" + (trig || i),
                section: "Snippets",
                title: title,
                subtitle: (trig ? ("," + trig + " · ") : "") + singleLine,
                glyph: "󰩫",
                badge: trig ? ("," + trig) : "Snippet",
                hits: hits,
                score: s,
                preview: { type: "snippet", trigger: trig, raw: rawBody, expanded: expanded },
                actions: [
                    { label: "Paste into Previous App", run: () => root.pasteIntoPreviousApp(root.expandSnippet(rawBody)) },
                    { label: "Copy Expanded Text", run: () => Quickshell.execDetached(["wl-copy", root.expandSnippet(rawBody)]) },
                    { label: "Edit snippets.json", run: () => root.openUrl("file://" + root.snippetConfigPath) }
                ]
            });
        }
        if (terms.length > 0) out.sort((a, b) => b.score - a.score);
        return out;
    }

    // ---- universal dmenu
    function dmenuItems(terms) {
        const out = [];
        for (let i = 0; i < dmenuLines.length; i++) {
            const line = dmenuLines[i];
            let s = 10000 - i;
            let hits = [];
            if (terms.length > 0) {
                const m = scoreText(line, terms, true);
                if (!m) continue;
                s = m.s;
                hits = m.hits;
            }
            out.push({
                key: "dmenu:" + i + ":" + line,
                section: dmenuPrompt,
                title: line,
                subtitle: "",
                glyph: "󰘳",
                badge: "",
                hits: hits,
                score: s,
                actions: [
                    { label: "Select", run: () => root.finishDmenu(line) },
                    { label: "Copy & Select", run: () => { Quickshell.execDetached(["wl-copy", line]); root.finishDmenu(line); } }
                ]
            });
        }
        if (terms.length > 0) out.sort((a, b) => b.score - a.score);
        return out.slice(0, 250);
    }

    // ---- clipboard
    function loadClipboard() {
        runCapture(["cliphist", "list"], function (t) {
            root.clipLines = t.split("\n").filter(l => l.length > 0).slice(0, 600);
        });
    }

    function ocrClipboardImage(id) {
        if (!id) return;
        const args = [hydrogenBin, "ocr", "clip", String(id)];
        if (root.previousWindowAddress) args.push("--window", root.previousWindowAddress);
        Quickshell.execDetached(args);
    }

    function deleteClipboardEntry(rawLine) {
        if (!rawLine) return;
        root.clipLines = root.clipLines.filter(l => l !== rawLine);
        root.previewData = ({ kind: "none", key: "" });
        root.runCapture(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "_", rawLine], function () {
            root.loadClipboard();
        });
    }

    function clearClipboardHistory() {
        root.clipLines = [];
        root.previewData = ({ kind: "none", key: "" });
        root.selected = 0;
        root.runCapture(["sh", "-c", "cliphist wipe; wl-copy --clear; rm -rf \"$XDG_RUNTIME_DIR/qs-launcher\""], function () {
            root.clipLines = [];
            root.loadClipboard();
        });
    }

    function clipboardItems(terms) {
        const out = [];
        for (let i = 0; i < clipLines.length && out.length < 150; i++) {
            const line = clipLines[i];
            const tab = line.indexOf("\t");
            const id = tab > 0 ? line.slice(0, tab) : "";
            const text = tab > 0 ? line.slice(tab + 1) : line;
            const img = /^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp|tiff?) (\d+x\d+) \]\]$/i.exec(text);
            const title = img ? "Image · " + img[2].toUpperCase() + " " + img[3] + " · " + img[1] : text;
            let hits = [];
            if (terms.length > 0) {
                const m = scoreText(title, terms, false);
                if (!m) continue;
                hits = m.hits;
            }
            const decode = "cliphist decode \"$1\" | wl-copy";
            const actions = [
                { label: "Paste into Previous Window", run: () => root.sh(decode + "; sleep 0.30; wtype -M ctrl v -m ctrl", [id]) },
                { label: "Copy to Clipboard", run: () => root.sh(decode, [id]) }
            ];
            if (img) {
                actions.push({
                    label: "OCR to Markdown (Ctrl+O)",
                    run: () => root.ocrClipboardImage(id)
                });
            }
            actions.push(
                { label: "Delete Entry (Del)", keepOpen: true, run: () => root.deleteClipboardEntry(line) },
                {
                    label: "Clear All History (Ctrl+D)",
                    confirm: true,
                    keepOpen: true,
                    run: () => root.clearClipboardHistory()
                }
            );
            out.push({
                key: "clip:" + id + ":" + i, rawLine: line, section: "Clipboard History", title: title, subtitle: "", glyph: img ? "󰋩" : "󰅌",
                badge: img ? "Image" : "", hits: hits,
                preview: { type: "clip", id: id, image: !!img, meta: img ? img : null, len: text.length },
                actions: actions
            });
        }
        return out;
    }

    // ---- emoji
    function loadEmoji() {
        if (emojiData.length > 0) return;
        runCapture(["cat", Quickshell.shellPath("data/emoji.json")], function (t) {
            try { root.emojiData = JSON.parse(t); } catch (e) { console.warn("launcher: emoji.json:", e); }
        });
    }

    function emojiItems(terms) {
        const out = [];
        const mk = (e, s) => ({
            key: "emoji:" + e[0], section: e[3], title: e[1], subtitle: e[3], glyph: e[0], isEmoji: true, badge: "", hits: [], score: s,
            actions: [{ label: "Insert into Previous App", run: () => { root.bumpEmoji(e[0]); root.pasteIntoPreviousApp(e[0]); } },
                      { label: "Copy Emoji Only", run: () => { root.bumpEmoji(e[0]); Quickshell.execDetached(["wl-copy", e[0]]); } }]
        });
        if (terms.length === 0) {
            const byGlyph = {};
            for (let i = 0; i < emojiData.length; i++) byGlyph[emojiData[i][0]] = emojiData[i];
            for (let i = 0; i < store.emoji.length; i++) {
                const e = byGlyph[store.emoji[i]];
                if (e) out.push(mk(e, 0));
            }
            for (let i = 0; i < emojiData.length; i++) out.push(mk(emojiData[i], 0));
            return out;
        }
        for (let i = 0; i < emojiData.length; i++) {
            const e = emojiData[i];
            const m = scoreText(e[1], terms, false);
            let s;
            if (m) s = m.s;
            else {
                const hay = (e[2] + " " + e[3]).toLowerCase();
                let ok = true;
                for (let t = 0; t < terms.length; t++) if (hay.indexOf(terms[t]) < 0) { ok = false; break; }
                if (!ok) continue;
                s = 120;
            }
            const rec = store.emoji.indexOf(e[0]);
            if (rec >= 0) s += 60 - rec;
            out.push(mk(e, s));
        }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, 300);
    }

    // ------------------------------------------------------------------ root search
    function rootItems(q, terms) {
        if (q.charAt(0) === "!") return bangItems(q);
        if (q.charAt(0) === ">") return runItem(q);
        if (q.charAt(0) === "=") { const c = calcItem(q); return c ? [c] : []; }

        const pinned = [];
        const calc = calcItem(q); if (calc) pinned.push(calc);
        const unit = unitItem(q); if (unit) pinned.push(unit);
        const url = urlItem(q); if (url) pinned.push(url);

        const apps = appItems(terms, false);
        if (terms.length === 0) {
            const out = pinned.slice();
            let fr = 0;
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i];
                if (a.boost > 0 && fr < 6) { a.section = "Frequently Used"; fr++; }
                out.push(a);
            }
            return out;
        }

        const topApps = apps.slice(0, 6);
        const cmds = commandItems(terms, 4);
        const files = q.length >= 2 ? fileItemsFromCache(terms, 6) : [];
        const snips = q.length >= 2 ? snippetItems(terms).slice(0, 2) : [];

        // If hybrid vector+FTS5 returned strong content hits, promote files near the top
        const hasVectorHit = files.length > 0 && files[0].score >= 2500;
        const primaryGroups = [];
        if (topApps.length > 0) primaryGroups.push({ items: topApps, best: topApps[0].score + 200 });
        if (cmds.length > 0) primaryGroups.push({ items: cmds, best: cmds[0].score + 180 });
        if (hasVectorHit) primaryGroups.push({ items: files, best: 1400 });
        primaryGroups.sort((a, b) => b.best - a.best);

        let out = pinned.slice();
        for (let i = 0; i < primaryGroups.length; i++) out = out.concat(primaryGroups[i].items);
        if (!hasVectorHit && files.length > 0) out = out.concat(files);
        if (snips.length > 0) out = out.concat(snips);
        if (!url) out = out.concat(webItems(q));
        return out;
    }

    function computeResults() {
        if (!root.visible) return [];
        const q = query.trim();
        const terms = q.toLowerCase().split(/\s+/).filter(t => t.length > 0);
        if (mode === "dmenu") return dmenuItems(terms);
        if (mode === "hidden") return appItems(terms, true);
        if (mode === "clipboard") return clipboardItems(terms);
        if (mode === "files") return fileItemsFromCache(terms, 80);
        if (mode === "emoji") return emojiItems(terms);
        if (mode === "snippets") return snippetItems(terms);
        return rootItems(q, terms);
    }

    readonly property var results: computeResults()
    readonly property var current: results.length > 0 ? results[Math.max(0, Math.min(selected, results.length - 1))] : null
    readonly property bool grid: mode === "emoji"
    readonly property bool showPreview: ((mode === "clipboard" || mode === "files" || mode === "snippets") || (mode === "all" && current !== null && current.preview !== undefined)) && results.length > 0

    onResultsChanged: {
        if (selected >= results.length) selected = Math.max(0, results.length - 1);
        Qt.callLater(ensureVisible);
    }
    onCurrentChanged: previewDebounce.restart()

    function ensureVisible() {
        if (grid) gridView.positionViewAtIndex(selected, GridView.Contain);
        else if (selected === 0) listView.positionViewAtBeginning();
        else listView.positionViewAtIndex(selected, ListView.Contain);
    }

    onSelectedChanged: ensureVisible()

    function emptyText() {
        if (mode === "dmenu") return "No matching options";
        if (mode === "hidden") return "No hidden apps";
        if (mode === "clipboard") return "No clipboard history yet.\nEnable the cliphist watcher: wl-paste --type text --watch cliphist store";
        if (mode === "files") return fileIndexing ? "Indexing files, vectors & FTS5…" : "No matching files, images, or contents";
        if (mode === "snippets") return "No snippets found.\nEdit ~/.config/quickshell/snippets.json to add templates.";
        if (mode === "emoji") return emojiData.length === 0 ? "Loading emoji…" : "No emoji found";
        return "No results";
    }

    // ------------------------------------------------------------------ actions
    function runAction(item, action) {
        if (!item || !action) return;
        const ck = item.key + "|" + action.label;
        if (action.confirm && confirmKey !== ck) {
            confirmKey = ck;
            confirmTimer.restart();
            return;
        }
        confirmKey = "";
        action.run();
        if (!action.keepOpen) dismiss();
    }

    function confirmPendingAction() {
        if (!confirmKey) return;
        const split = confirmKey.indexOf("|");
        const itemKey = split >= 0 ? confirmKey.slice(0, split) : confirmKey;
        const actionLabel = split >= 0 ? confirmKey.slice(split + 1) : "";
        if (actionLabel.indexOf("Clear All History") === 0) {
            confirmKey = "";
            if (confirmTimer.running) confirmTimer.stop();
            clearClipboardHistory();
            return;
        }
        let item = null;
        for (let i = 0; i < results.length; i++) if (results[i].key === itemKey) { item = results[i]; break; }
        if (!item) { confirmKey = ""; return; }
        const actions = item.actions || [];
        for (let i = 0; i < actions.length; i++) {
            if (actions[i].label !== actionLabel) continue;
            const action = actions[i];
            confirmKey = "";
            if (confirmTimer.running) confirmTimer.stop();
            action.run();
            if (!action.keepOpen) dismiss();
            return;
        }
        confirmKey = "";
    }

    function move(delta) {
        if (actionsOpen) {
            const n = current ? current.actions.length : 0;
            if (n > 0) actionIndex = (actionIndex + delta + n) % n;
            return;
        }
        const n = results.length;
        if (n === 0) return;
        if (grid) selected = Math.max(0, Math.min(n - 1, selected + delta));
        else selected = (selected + delta + n) % n;
    }

    function handleKey(ev) {
        const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0;
        const alt = (ev.modifiers & Qt.AltModifier) !== 0;
        ev.accepted = true;
        if (confirmKey.length > 0) {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Y) confirmPendingAction();
            else if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_N) confirmKey = "";
            return;
        }
        switch (ev.key) {
        case Qt.Key_Delete:
            if (!actionsOpen && mode === "clipboard" && current && current.rawLine) {
                deleteClipboardEntry(current.rawLine);
                return;
            }
            break;
        case Qt.Key_D:
            if (ctrl && mode === "clipboard" && clipLines.length > 0) {
                actionsOpen = false;
                runAction(current || { key: "clip:all" }, {
                    label: "Clear All History (Ctrl+D)",
                    confirm: true,
                    keepOpen: true,
                    run: () => root.clearClipboardHistory()
                });
                return;
            }
            break;
        case Qt.Key_Escape:
            if (actionsOpen) actionsOpen = false; else dismiss();
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (current) {
                if (actionsOpen) {
                    const a = current.actions[actionIndex];
                    actionsOpen = false;
                    runAction(current, a);
                } else {
                    const idx = ctrl ? 1 : (alt ? 2 : 0);
                    runAction(current, current.actions[idx] || current.actions[0]);
                }
            }
            return;
        case Qt.Key_Down: move(grid ? gridCols : 1); return;
        case Qt.Key_Up: move(grid ? -gridCols : -1); return;
        case Qt.Key_PageDown: move(8); return;
        case Qt.Key_PageUp: move(-8); return;
        case Qt.Key_Left: if (grid && !actionsOpen) { move(-1); return; } break;
        case Qt.Key_Right: if (grid && !actionsOpen) { move(1); return; } break;
        case Qt.Key_Tab: cycleMode(1); return;
        case Qt.Key_Backtab: cycleMode(-1); return;
        case Qt.Key_O:
            if (ctrl && current && current.preview) {
                if (current.preview.type === "clip" && current.preview.image) {
                    actionsOpen = false;
                    ocrClipboardImage(current.preview.id);
                    dismiss();
                    return;
                }
                if (current.preview.type === "file" && !current.preview.isDir && isImageName(current.preview.path)) {
                    actionsOpen = false;
                    ocrImageFile(current.preview.path);
                    dismiss();
                    return;
                }
            }
            break;
        case Qt.Key_B:
        case Qt.Key_K:
            if (ctrl) { actionsOpen = !actionsOpen; actionIndex = 0; return; }
            break;
        case Qt.Key_N: if (ctrl) { move(1); return; } break;
        case Qt.Key_P: if (ctrl) { move(-1); return; } break;
        case Qt.Key_1: case Qt.Key_2: case Qt.Key_3: case Qt.Key_4: case Qt.Key_5: case Qt.Key_6:
            if (alt && mode !== "dmenu" && (ev.key - Qt.Key_1) < modeOrder.length) {
                setMode(modeOrder[ev.key - Qt.Key_1]);
                return;
            }
            break;
        case Qt.Key_Backspace:
            if (searchInput.text.length === 0 && mode !== "all" && mode !== "dmenu") { setMode("all"); return; }
            break;
        }
        ev.accepted = false;
    }

    // ------------------------------------------------------------------ richer preview
    function loadPreview() {
        const it = current;
        if (!showPreview || !it || !it.preview) return;
        if (previewData.key === it.key) return;
        const pv = it.preview;
        const my = ++previewSeq;
        const set = (d) => { if (my === root.previewSeq) root.previewData = d; };

        if (pv.type === "snippet") {
            const tokens = [];
            if (pv.raw.indexOf("{date}") >= 0) tokens.push("{date}");
            if (pv.raw.indexOf("{time}") >= 0) tokens.push("{time}");
            if (pv.raw.indexOf("{datetime}") >= 0) tokens.push("{datetime}");
            if (pv.raw.indexOf("{uuid}") >= 0) tokens.push("{uuid}");
            if (pv.raw.indexOf("{clipboard}") >= 0) tokens.push("{clipboard}");
            set({
                kind: "text",
                key: it.key,
                text: pv.expanded,
                meta: [
                    ["Trigger", pv.trigger ? ("," + pv.trigger) : "—"],
                    ["Characters", String(pv.expanded.length)],
                    ["Tokens", tokens.length > 0 ? tokens.join(", ") : "Static"]
                ]
            });
            return;
        }

        if (pv.type === "clip") {
            if (pv.image) {
                const m = pv.meta;
                runCapture(["sh", "-c",
                    "d=\"$XDG_RUNTIME_DIR/qs-launcher\"; mkdir -p \"$d\"; f=\"$d/clip-$1.img\"; [ -f \"$f\" ] || cliphist decode \"$1\" > \"$f\"; echo \"$f\"",
                    "_", pv.id], function (t) {
                    set({ kind: "image", key: it.key, source: "file://" + t.trim(),
                          meta: [["Type", "Image"], ["Format", m[2].toUpperCase()], ["Dimensions", m[3]], ["Size", m[1]]] });
                });
            } else {
                runCapture(["sh", "-c", "cliphist decode \"$1\" | head -c 8000", "_", pv.id], function (t) {
                    set({ kind: "text", key: it.key, text: t,
                          meta: [["Type", "Text"], ["Characters", String(pv.len)], ["Lines", String(t.split("\n").length)]] });
                });
            }
        } else if (pv.type === "file") {
            const name = pv.path.slice(pv.path.lastIndexOf("/") + 1);
            const script =
                "p=\"$1\"; " +
                "m=$(file -b --mime-type -- \"$p\" 2>/dev/null); " +
                "st=$(stat -c '%s|%Y' -- \"$p\" 2>/dev/null); " +
                "if [ -d \"$p\" ]; then " +
                "  printf 'TEXT\\n%s\\n%s\\n\\n' \"$m\" \"$st\"; " +
                "  ls -1Fp -- \"$p\" | head -40; " +
                "elif [ \"$m\" = \"application/pdf\" ]; then " +
                "  pages=$(pdfinfo \"$p\" 2>/dev/null | awk '/^Pages:/ {print $2}'); " +
                "  d=\"$XDG_RUNTIME_DIR/qs-launcher\"; mkdir -p \"$d\"; " +
                "  h=$(printf '%s|%s' \"$p\" \"$st\" | sha256sum | cut -c1-16); " +
                "  out=\"$d/pdf-$h\"; " +
                "  if [ ! -f \"$out.png\" ] && command -v pdftoppm >/dev/null 2>&1; then " +
                "    pdftoppm -png -f 1 -l 1 -scale-to 600 \"$p\" \"$out\" >/dev/null 2>&1 || true; " +
                "  fi; " +
                "  if [ -f \"$out.png\" ]; then " +
                "    printf 'PDF_IMG\\n%s\\n%s\\nPages: %s\\n%s' \"$m\" \"$st\" \"${pages:-?}\" \"$out.png\"; " +
                "  else " +
                "    printf 'TEXT\\n%s\\n%s\\nPages: %s\\n' \"$m\" \"$st\" \"${pages:-?}\"; " +
                "    pdftotext -q -f 1 -l 2 \"$p\" - 2>/dev/null | head -c 5000; " +
                "  fi; " +
                "else " +
                "  case \"$p\" in " +
                "    *.zip|*.tar|*.tar.gz|*.tgz|*.tar.zst|*.tar.xz|*.tar.bz2|*.7z|*.rar) " +
                "      printf 'TEXT\\n%s\\n%s\\nArchive Contents\\n' \"$m\" \"$st\"; " +
                "      bsdtar -tf \"$p\" 2>/dev/null | head -60; exit 0 ;; " +
                "  esac; " +
                "  case \"$m\" in " +
                "    video/*|audio/*) " +
                "      info=$(ffprobe -v error -show_entries format=duration -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1:nokey=1 \"$p\" 2>/dev/null | tr '\\n' ' '); " +
                "      printf 'INFO\\n%s\\n%s\\n%s\\n' \"$m\" \"$st\" \"$info\"; exit 0 ;; " +
                "  esac; " +
                "  printf 'TEXT\\n%s\\n%s\\n\\n' \"$m\" \"$st\"; " +
                "  case \"$m\" in " +
                "    text/*|application/json|application/xml|application/javascript|application/x-shellscript|application/toml|inode/x-empty) " +
                "      head -c 6000 -- \"$p\" ;; " +
                "  esac; " +
                "fi";

            runCapture(["sh", "-c", script, "_", pv.path], function (t) {
                const lines = t.split("\n");
                const modeTag = lines[0] || "TEXT";
                const mime = lines[1] || "";
                const st = (lines[2] || "").split("|");
                const extra = lines[3] || "";
                const body = lines.slice(4).join("\n");

                const meta = [
                    ["Kind", pv.isDir ? "Folder" : mime],
                    ["Size", pv.isDir ? "—" : humanSize(parseInt(st[0]) || 0)],
                    ["Modified", st[1] ? new Date(parseInt(st[1]) * 1000).toLocaleString() : "—"]
                ];
                if (extra) {
                    const sp = extra.indexOf(": ");
                    if (sp > 0) meta.push([extra.slice(0, sp), extra.slice(sp + 2)]);
                    else meta.push(["Media", extra]);
                }
                meta.push(["Path", tilde(pv.path)]);

                if (modeTag === "PDF_IMG" && body.trim().length > 0) {
                    set({ kind: "image", key: it.key, source: "file://" + body.trim(), meta: meta });
                } else if (!pv.isDir && isImageName(name)) {
                    set({ kind: "image", key: it.key, source: "file://" + pv.path, meta: meta });
                } else if (body.length > 0) {
                    set({ kind: "text", key: it.key, text: body, meta: meta });
                } else {
                    set({ kind: "info", key: it.key, meta: meta });
                }
            });
        }
    }

    // ------------------------------------------------------------------ UI
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    // Constant 760x520 sharp-cornered frame across all modes
    Rectangle {
        id: card
        width: 760
        height: 520
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.14)
        radius: 0
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline_variant
        clip: true

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.98
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 130 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- search row
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 54

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Text {
                        text: root.mode === "dmenu" ? "󰘳"
                            : (root.query.charAt(0) === "!" ? ((["cmd", "command", "sh", "shell"].indexOf(root.currentBangType()) >= 0) ? "󰆍" : "󰖟") : "󰍉")
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        color: Theme.primary
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Theme.on_surface
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.on_primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        clip: true

                        onTextChanged: {
                            if (root.mode === "all" && text.length === 1 && root.sigils[text] !== undefined) {
                                const m = root.sigils[text];
                                text = "";
                                root.setMode(m);
                                return;
                            }
                            root.query = text;
                            root.selected = 0;
                            root.actionsOpen = false;
                            if (root.mode === "files" || root.mode === "all") {
                                contentSearchTimer.restart();
                            }
                        }
                        Keys.onPressed: (ev) => root.handleKey(ev)

                        Text {
                            visible: searchInput.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.mode === "dmenu" ? root.dmenuPrompt : root.modeMeta[root.mode].hint
                            color: Theme.on_surface_variant
                            font: searchInput.font
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Rectangle {
                        visible: searchInput.text.length > 0
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 0
                        color: clearMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.14) : Theme.surface_variant
                        border.width: 1
                        border.color: Theme.outline_variant
                        Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 10; color: Theme.on_surface_variant }
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { searchInput.text = ""; searchInput.forceActiveFocus(); }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.outline_variant }

            // ---- body
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: listView
                        anchors.fill: parent
                        anchors.margins: 6
                        visible: !root.grid && root.results.length > 0
                        clip: true
                        model: root.results
                        boundsBehavior: Flickable.StopAtBounds
                        reuseItems: false

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool cur: index === root.selected
                            readonly property bool head: index === 0 || root.results[index - 1].section !== modelData.section

                            width: listView.width
                            height: (head ? 24 : 0) + 44

                            Text {
                                visible: row.head
                                x: 8
                                y: 6
                                text: row.modelData.section
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.5
                                color: Theme.on_surface_variant
                            }

                            Rectangle {
                                id: rowBg
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 44
                                radius: 0
                                color: row.cur ? Theme.alpha(Theme.primary, 0.14) : "transparent"
                                border.width: row.cur ? 1 : 0
                                border.color: Theme.alpha(Theme.primary, 0.50)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    Item {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30

                                        readonly property string resolvedIcon: row.modelData.icon ? root.iconSrc(row.modelData.icon, row.modelData.iconFb) : ""
                                        readonly property bool showImage: resolvedIcon !== "" && iconImg.status !== Image.Error

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !parent.showImage
                                            radius: 0
                                            color: row.cur ? Theme.alpha(Theme.primary, 0.20) : Theme.surface_variant
                                            border.width: 1
                                            border.color: Theme.outline_variant
                                            Text {
                                                anchors.centerIn: parent
                                                text: row.modelData.glyph !== "" ? row.modelData.glyph : "󰈔"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 16
                                                color: row.cur ? Theme.primary : Theme.on_surface_variant
                                            }
                                        }
                                        Image {
                                            id: iconImg
                                            anchors.fill: parent
                                            visible: parent.showImage
                                            source: parent.resolvedIcon
                                            sourceSize.width: 64
                                            sourceSize.height: 64
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            smooth: true
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            textFormat: Text.StyledText
                                            text: root.highlight(row.modelData.title, row.modelData.hits, String(Theme.primary))
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            color: Theme.on_surface
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: row.modelData.subtitle
                                            elide: Text.ElideMiddle
                                            color: Theme.on_surface_variant
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }

                                    Text {
                                        visible: row.modelData.badge !== "" && !row.cur
                                        text: row.modelData.badge
                                        color: (row.modelData.badge === "Phrase" || row.modelData.badge.indexOf("Match") === 0 || row.modelData.badge.indexOf("Vision") === 0) ? Theme.primary : Theme.on_surface_variant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                    Rectangle {
                                        visible: row.cur
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 20
                                        radius: 0
                                        color: Theme.alpha(Theme.foreground, 0.10)
                                        border.width: 1
                                        border.color: Theme.outline_variant
                                        Text { anchors.centerIn: parent; text: "↵"; font.pixelSize: 12; color: Theme.on_surface_variant }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onPositionChanged: root.selected = row.index
                                    onClicked: (m) => {
                                        root.selected = row.index;
                                        if (m.button === Qt.RightButton) { root.actionsOpen = true; root.actionIndex = 0; }
                                        else root.runAction(row.modelData, row.modelData.actions[0]);
                                    }
                                }
                            }
                        }
                    }

                    GridView {
                        id: gridView
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.grid && root.results.length > 0
                        clip: true
                        model: root.results
                        boundsBehavior: Flickable.StopAtBounds
                        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 54)))
                        cellHeight: 52
                        onWidthChanged: root.gridCols = Math.max(1, Math.floor(width / 54))

                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            width: gridView.cellWidth
                            height: gridView.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: 0
                                color: index === root.selected ? Theme.alpha(Theme.primary, 0.20) : "transparent"
                                border.width: index === root.selected ? 1 : 0
                                border.color: Theme.alpha(Theme.primary, 0.6)
                                Text {
                                    anchors.centerIn: parent
                                    text: cell.modelData.glyph
                                    font.pixelSize: 26
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onPositionChanged: root.selected = cell.index
                                    onClicked: { root.selected = cell.index; root.runAction(cell.modelData, cell.modelData.actions[0]); }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.results.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: root.emptyText()
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                // ---- preview pane
                Rectangle {
                    visible: root.showPreview
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    color: "transparent"

                    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Theme.outline_variant }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        Rectangle {
                            visible: root.previewData.kind === "image"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 190
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                source: root.previewData.kind === "image" ? root.previewData.source : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                sourceSize.width: 640
                                sourceSize.height: 400
                            }
                        }

                        Rectangle {
                            visible: root.previewData.kind === "text"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 0
                            color: Theme.surface_variant
                            border.width: 1
                            border.color: Theme.outline_variant
                            clip: true
                            Text {
                                anchors.fill: parent
                                anchors.margins: 10
                                text: root.previewData.kind === "text" ? root.previewData.text : ""
                                wrapMode: Text.WrapAnywhere
                                elide: Text.ElideRight
                                color: Theme.on_surface
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        Item { visible: root.previewData.kind !== "text"; Layout.fillHeight: true }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.outline_variant }

                        Repeater {
                            model: root.previewData.meta || []
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    Layout.preferredWidth: 74
                                    text: parent.modelData[0]
                                    color: Theme.on_surface_variant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: parent.modelData[1]
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    color: Theme.on_surface
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.outline_variant }

            // ---- footer
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.grid && root.current ? (root.current.glyph + "  " + root.current.title)
                          : (root.results.length + (root.results.length === 1 ? " result" : " results")
                             + (root.fileIndexing ? " · indexing…" : (root.imageIndexing ? " · indexing images…" : "")))
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    visible: root.current !== null
                    text: "↵  " + (root.current ? root.current.actions[0].label : "")
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    visible: root.current !== null && root.current.actions.length > 1
                    text: "⌃B  Options"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    visible: root.mode !== "dmenu"
                    text: "⇥  Mode"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // ---- actions panel (Ctrl+B / Ctrl+K / right click)
        Rectangle {
            visible: root.actionsOpen && root.current !== null
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 14
            anchors.bottomMargin: 44
            width: 280
            height: actionCol.implicitHeight + 12
            radius: 0
            color: Theme.surface_variant
            border.width: 1
            border.color: Theme.outline

            Column {
                id: actionCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: root.current ? root.current.actions : []
                    delegate: Rectangle {
                        id: act
                        required property var modelData
                        required property int index
                        width: actionCol.width
                        height: 30
                        radius: 0
                        color: index === root.actionIndex ? Theme.alpha(Theme.primary, 0.22) : "transparent"
                        border.width: index === root.actionIndex ? 1 : 0
                        border.color: Theme.alpha(Theme.primary, 0.5)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            text: act.modelData.label
                            color: act.modelData.confirm ? Theme.warning : Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: root.actionIndex = act.index
                            onClicked: { root.actionsOpen = false; root.runAction(root.current, act.modelData); }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: launcherConfirmOverlay
        anchors.fill: parent
        visible: root.open && root.confirmKey.length > 0
        z: 1000
        color: Qt.rgba(0, 0, 0, 0.58)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 130 } }
        MouseArea { anchors.fill: parent; onClicked: root.confirmKey = "" }

        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: confirmColumn.implicitHeight + 34
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline
            scale: launcherConfirmOverlay.visible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: confirmColumn
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12
                Text { Layout.alignment: Qt.AlignHCenter; text: "󰀦"; font.family: Theme.fontFamily; font.pixelSize: 28; color: Theme.warning }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Confirm action?"
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; color: Theme.foreground
                }
                Text {
                    Layout.fillWidth: true
                    text: "" + root.confirmKey.slice(root.confirmKey.indexOf("|") + 1)
                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.on_surface_variant
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 100; Layout.preferredHeight: 32
                        color: Theme.surface_variant; border.width: 1; border.color: Theme.outline_variant
                        Text { anchors.centerIn: parent; text: "Cancel"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.foreground }
                        MouseArea { anchors.fill: parent; onClicked: root.confirmKey = "" }
                    }
                    Rectangle {
                        Layout.preferredWidth: 100; Layout.preferredHeight: 32
                        color: Theme.alpha(Theme.error, 0.18); border.width: 1; border.color: Theme.error
                        Text { anchors.centerIn: parent; text: "Confirm"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; color: Theme.error }
                        MouseArea { anchors.fill: parent; onClicked: root.confirmPendingAction() }
                    }
                }
            }
        }
    }
}