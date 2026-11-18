// prgnotifier.c - Fast brightness, volume & microphone notifier in C
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <limits.h>
#include <ctype.h>
#include <sys/stat.h>

static void run_quiet(char *const argv[]) {
    pid_t pid = fork();
    if (pid == 0) {
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execvp(argv[0], argv);
        _exit(127);
    } else if (pid > 0) {
        waitpid(pid, NULL, 0);
    }
}

static int get_brightness_pct(void) {
    DIR *d = opendir("/sys/class/backlight");
    if (!d) return 0;

    struct dirent *ent;
    char base[PATH_MAX] = {0};
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] != '.') {
            snprintf(base, sizeof(base), "/sys/class/backlight/%s", ent->d_name);
            break;
        }
    }
    closedir(d);
    if (!base[0]) return 0;

    char p_cur[PATH_MAX], p_max[PATH_MAX];
    snprintf(p_cur, sizeof(p_cur), "%s/brightness", base);
    snprintf(p_max, sizeof(p_max), "%s/max_brightness", base);

    FILE *fc = fopen(p_cur, "r");
    FILE *fm = fopen(p_max, "r");
    long cur = 0, max = 1;
    if (fc) { fscanf(fc, "%ld", &cur); fclose(fc); }
    if (fm) { fscanf(fm, "%ld", &max); fclose(fm); }
    if (max <= 0) max = 1;

    return (int)((cur * 100) / max);
}

static const char *get_brightness_icon(int level) {
    if (level <= 30)
        return "/usr/share/icons/Papirus/48x48/status/notification-display-brightness-low.svg";
    if (level <= 70)
        return "/usr/share/icons/Papirus/48x48/status/notification-display-brightness-medium.svg";
    if (level <= 95)
        return "/usr/share/icons/Papirus/48x48/status/notification-display-brightness-high.svg";
    return "/usr/share/icons/Papirus/48x48/status/notification-display-brightness-full.svg";
}

// Reads volume % and mute state for either Sink (@DEFAULT_AUDIO_SINK@) or Source (@DEFAULT_AUDIO_SOURCE@)
static void get_audio_state(bool is_source, int *out_vol, bool *out_muted) {
    *out_vol = 0;
    *out_muted = false;

    const char *wp_cmd = is_source
        ? "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null"
        : "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null";

    FILE *fp = popen(wp_cmd, "r");
    if (fp) {
        char buf[128] = {0};
        if (fgets(buf, sizeof(buf), fp)) {
            double v = 0.0;
            if (sscanf(buf, "Volume: %lf", &v) == 1) {
                *out_vol = (int)(v * 100.0 + 0.5);
                if (strstr(buf, "[MUTED]")) *out_muted = true;
                pclose(fp);
                return;
            }
        }
        pclose(fp);
    }

    // Fallback to pactl
    const char *pa_vol = is_source
        ? "pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null"
        : "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null";
    const char *pa_mute = is_source
        ? "pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null"
        : "pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null";

    fp = popen(pa_vol, "r");
    if (fp) {
        char buf[256] = {0};
        if (fgets(buf, sizeof(buf), fp)) {
            char *pct = strchr(buf, '%');
            if (pct) {
                while (pct > buf && *(pct - 1) >= '0' && *(pct - 1) <= '9') pct--;
                *out_vol = atoi(pct);
            }
        }
        pclose(fp);
    }
    fp = popen(pa_mute, "r");
    if (fp) {
        char buf[128] = {0};
        if (fgets(buf, sizeof(buf), fp) && strstr(buf, "yes")) {
            *out_muted = true;
        }
        pclose(fp);
    }
}

static const char *get_volume_icon(int level, bool muted) {
    if (muted)       return "audio-volume-muted";
    if (level <= 30) return "audio-volume-low";
    if (level <= 70) return "audio-volume-medium";
    return "audio-volume-high";
}


/* ---------- theme-aware icon colouring ----------
 * Notification icons ship in one fixed colour (light for dark themes), so they vanish in
 * light mode. We read the live palette, recolour every colour in the SVG to the palette's
 * foreground and hand notify-send the recoloured copy. Works for dark mode too. */

#define PALETTE_DEFAULT "/.config/quickshell/palette.json"

static bool json_hex(const char *buf, const char *key, char out[8]) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(buf, pat);
    if (!p) return false;
    p = strchr(p + strlen(pat), '#');
    if (!p) return false;
    for (int i = 1; i <= 6; i++) if (!isxdigit((unsigned char)p[i])) return false;
    memcpy(out, p, 7);
    out[7] = 0;
    return true;
}

static double hex_luma(const char *h) {
    unsigned r, g, b;
    if (sscanf(h + 1, "%2x%2x%2x", &r, &g, &b) != 3) return 0.0;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
}

// Colour the icons should be drawn in: the palette foreground (falls back by background brightness).
static void icon_color(char out[8]) {
    snprintf(out, 8, "#ededed");
    const char *env = getenv("PRG_PALETTE");
    char path[PATH_MAX];
    if (env && *env) {
        snprintf(path, sizeof(path), "%s", env);
    } else {
        const char *home = getenv("HOME");
        if (!home) return;
        snprintf(path, sizeof(path), "%s" PALETTE_DEFAULT, home);
    }
    FILE *f = fopen(path, "r");
    if (!f) return;
    char buf[8192];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;

    char fg[8], bg[8];
    bool has_bg = json_hex(buf, "background", bg);
    if (json_hex(buf, "foreground", fg)) {
        // sanity: foreground must contrast with the background
        if (!has_bg || (hex_luma(fg) - hex_luma(bg) > 0.3 || hex_luma(bg) - hex_luma(fg) > 0.3)) {
            memcpy(out, fg, 8);
            return;
        }
    }
    if (has_bg) snprintf(out, 8, hex_luma(bg) > 0.5 ? "#1a1a1a" : "#fafafa");
}

static bool file_exists(const char *p) {
    struct stat st;
    return stat(p, &st) == 0 && S_ISREG(st.st_mode);
}

static bool find_icon(const char *name, char *out, size_t outsz) {
    static const char *dirs[] = {
        "/usr/share/icons/Papirus/48x48/status",
        "/usr/share/icons/Papirus/32x32/status",
        "/usr/share/icons/Papirus/24x24/status",
        "/usr/share/icons/Papirus/22x22/status",
        "/usr/share/icons/Papirus/symbolic/status",
        "/usr/share/icons/Papirus/16x16/symbolic/status",
        "/usr/share/icons/Adwaita/symbolic/status",
        NULL
    };
    bool symbolic = strstr(name, "-symbolic") != NULL;
    for (int i = 0; dirs[i]; i++) {
        snprintf(out, outsz, "%s/%s.svg", dirs[i], name);
        if (file_exists(out)) return true;
        if (!symbolic) {
            snprintf(out, outsz, "%s/%s-symbolic.svg", dirs[i], name);
            if (file_exists(out)) return true;
        }
    }
    return false;
}

// Writes a copy of `src` with every colour replaced by `color`. Returns false on any failure.
static bool recolor_svg(const char *src, const char *dst, const char *color) {
    FILE *f = fopen(src, "r");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    if (len <= 0 || len > 512 * 1024) { fclose(f); return false; }
    char *in = malloc((size_t)len + 1);
    char *outb = malloc((size_t)len * 2 + 64);
    if (!in || !outb) { fclose(f); free(in); free(outb); return false; }
    size_t n = fread(in, 1, (size_t)len, f);
    fclose(f);
    in[n] = 0;

    size_t o = 0;
    for (size_t i = 0; i < n; ) {
        if (in[i] == '#' && i + 6 < n + 0 &&
            isxdigit((unsigned char)in[i+1]) && isxdigit((unsigned char)in[i+2]) &&
            isxdigit((unsigned char)in[i+3]) && isxdigit((unsigned char)in[i+4]) &&
            isxdigit((unsigned char)in[i+5]) && isxdigit((unsigned char)in[i+6])) {
            memcpy(outb + o, color, 7); o += 7; i += 7;
        } else if (strncmp(in + i, "currentColor", 12) == 0) {
            memcpy(outb + o, color, 7); o += 7; i += 12;
        } else {
            outb[o++] = in[i++];
        }
    }
    FILE *w = fopen(dst, "w");
    bool ok = w && fwrite(outb, 1, o, w) == o;
    if (w) fclose(w);
    free(in);
    free(outb);
    return ok;
}

// Icon name or .svg path -> path of a copy drawn in the current theme's foreground colour.
// Anything we cannot find or rewrite is returned untouched so the notification daemon resolves it.
static const char *resolve_icon(const char *icon) {
    static char result[PATH_MAX + 256];
    char src[PATH_MAX], base[128], color[8];

    if (icon[0] == '/') {
        snprintf(src, sizeof(src), "%s", icon);
        const char *b = strrchr(icon, '/') + 1;
        snprintf(base, sizeof(base), "%s", b);
        char *dot = strrchr(base, '.');
        if (dot) *dot = 0;
    } else {
        if (!find_icon(icon, src, sizeof(src))) return icon;
        snprintf(base, sizeof(base), "%s", icon);
    }
    if (!file_exists(src)) return icon;

    icon_color(color);

    char dir[PATH_MAX];
    const char *rt = getenv("XDG_RUNTIME_DIR");
    snprintf(dir, sizeof(dir), "%s/prgnotifier-icons", (rt && *rt) ? rt : "/tmp");
    mkdir(dir, 0700);

    snprintf(result, sizeof(result), "%s/%s-%s.svg", dir, base, color + 1);
    if (file_exists(result)) return result;          // cached for this colour
    if (recolor_svg(src, result, color)) return result;
    return icon;
}

static void show_progress(int percent, const char *title, const char *icon) {
    char msg[32];
    if (strcmp(icon, "audio-volume-muted") == 0 ||
        strcmp(icon, "microphone-sensitivity-muted-symbolic") == 0) {
        snprintf(msg, sizeof(msg), "Muted");
        percent = 0;
    } else if (strcmp(title, "Microphone") == 0) {
        snprintf(msg, sizeof(msg), "Unmuted (%d%%)", percent);
    } else {
        snprintf(msg, sizeof(msg), "%d%%", percent);
    }

    const char *icon_path = resolve_icon(icon);

    char sync_hint[64], val_hint[32];
    snprintf(sync_hint, sizeof(sync_hint), "string:x-canonical-private-synchronous:%s", title);
    snprintf(val_hint, sizeof(val_hint), "int:value:%d", percent);

    char *args[] = {
        "notify-send",
        "-u", "normal",
        "-i", (char *)icon_path,
        "-h", sync_hint,
        "-h", val_hint,
        "-t", "1500",
        (char *)title,
        msg,
        NULL
    };
    execvp(args[0], args);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s {light up|light down|volume up|volume down|volume toggle|mic toggle}\n", argv[0]);
        return 1;
    }

    char cmd[64] = {0};
    if (argc >= 3) {
        snprintf(cmd, sizeof(cmd), "%s %s", argv[1], argv[2]);
    } else {
        snprintf(cmd, sizeof(cmd), "%s", argv[1]);
    }

    if (strcmp(cmd, "light up") == 0) {
        char *args[] = {"brightnessctl", "-q", "set", "+10%", NULL};
        run_quiet(args);
        int curr = get_brightness_pct();
        show_progress(curr, "Brightness", get_brightness_icon(curr));
    } else if (strcmp(cmd, "light down") == 0) {
        char *args[] = {"brightnessctl", "-q", "set", "10%-", NULL};
        run_quiet(args);
        int curr = get_brightness_pct();
        show_progress(curr, "Brightness", get_brightness_icon(curr));
    } else if (strcmp(cmd, "volume up") == 0) {
        char *unmute[] = {"pactl", "set-sink-mute", "@DEFAULT_SINK@", "0", NULL};
        char *volup[]  = {"pactl", "set-sink-volume", "@DEFAULT_SINK@", "+10%", NULL};
        run_quiet(unmute);
        run_quiet(volup);
        int curr = 0; bool muted = false;
        get_audio_state(false, &curr, &muted);
        show_progress(curr, "Volume", get_volume_icon(curr, muted));
    } else if (strcmp(cmd, "volume down") == 0) {
        char *unmute[]  = {"pactl", "set-sink-mute", "@DEFAULT_SINK@", "0", NULL};
        char *voldown[] = {"pactl", "set-sink-volume", "@DEFAULT_SINK@", "-10%", NULL};
        run_quiet(unmute);
        run_quiet(voldown);
        int curr = 0; bool muted = false;
        get_audio_state(false, &curr, &muted);
        show_progress(curr, "Volume", get_volume_icon(curr, muted));
    } else if (strcmp(cmd, "volume toggle") == 0) {
        char *toggle[] = {"pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle", NULL};
        run_quiet(toggle);
        int curr = 0; bool muted = false;
        get_audio_state(false, &curr, &muted);
        show_progress(curr, "Volume", get_volume_icon(curr, muted));
    } else if (strcmp(cmd, "mic toggle") == 0 || strcmp(cmd, "mic-toggle") == 0) {
        char *toggle[] = {"pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle", NULL};
        run_quiet(toggle);
        int curr = 0; bool muted = false;
        get_audio_state(true, &curr, &muted);
        const char *icon = muted
            ? "microphone-sensitivity-muted-symbolic"
            : "microphone-sensitivity-high-symbolic";
        show_progress(curr, "Microphone", icon);
    } else {
        fprintf(stderr, "Usage: %s {light up|light down|volume up|volume down|volume toggle|mic toggle}\n", argv[0]);
        return 1;
    }

    return 0;
}