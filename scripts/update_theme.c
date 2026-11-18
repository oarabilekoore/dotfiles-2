// update_theme.c - Ultra-fast Vercel Geist Adaptive Theme Controller in C
//
// FIX NOTES (GTK "one step behind" bug)
// -------------------------------------
// GTK3/GTK4/libadwaita apps reload ~/.config/gtk-*/gtk.css (and friends) the
// moment gtk-theme / color-scheme changes. Earlier versions flipped the
// gsettings keys BEFORE the templates were re-rendered, so apps reloaded the
// OLD files from disk. Result: toggle #1 looked like nothing happened, and
// toggle #2 showed the files written by toggle #1 (the opposite theme).
//
// Now: render every file first, notify the other clients, and flip the
// GSettings keys LAST (color-scheme is the very last write). The dbus-send /
// dconf / system() hacks are gone; plain gsettings is all that is needed.

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <dirent.h>
#include <signal.h>
#include <errno.h>
#include <limits.h>
#include <time.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_PSD
#define STBI_NO_TGA
#define STBI_NO_HDR
#define STBI_NO_PIC
#include <stb/stb_image.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define THUMB_SIZE 64
#define SUCCESS_SEED 0xFF22C55Eu
#define WARNING_SEED 0xFFF5A623u
#define ERROR_SEED 0xFFFF4D4Fu
#define VERCEL_BLUE 0xFF0070F3u
#define BUF_PATH (PATH_MAX + 256)

// ============================================================================
// 1. PERCEPTUAL COLOR ENGINE (CAM16 + HCT + VERCEL GEIST ADAPTATION)
// ============================================================================

static inline double sanitize_deg(double deg) {
    deg = fmod(deg, 360.0);
    if (deg < 0.0) deg += 360.0;
    return deg;
}

static inline double diff_deg(double a, double b) {
    return 180.0 - fabs(fabs(a - b) - 180.0);
}

static inline double rotation_dir(double from, double to) {
    double inc = sanitize_deg(to - from);
    return inc <= 180.0 ? 1.0 : -1.0;
}

static inline double signum_d(double x) {
    return (x > 0.0) - (x < 0.0);
}

static inline int clamp_i(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static inline double clamp_d(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static inline double linearized(int rgb_comp) {
    double norm = rgb_comp / 255.0;
    return norm <= 0.040449936 ? (norm / 12.92) * 100.0
                               : pow((norm + 0.055) / 1.055, 2.4) * 100.0;
}

static inline int delinearized(double lin) {
    double norm = lin / 100.0;
    double d = norm <= 0.0031308 ? norm * 12.92
                                 : 1.055 * pow(norm, 1.0 / 2.4) - 0.055;
    return clamp_i((int)round(d * 255.0), 0, 255);
}

static inline double y_from_lstar(double lstar) {
    double ke = (lstar + 16.0) / 116.0;
    double ke3 = ke * ke * ke;
    return (ke3 > 0.0088564516 ? ke3 : (lstar / 903.2962962)) * 100.0;
}

static inline double lstar_from_y(double y) {
    double yn = y / 100.0;
    return yn <= 0.0088564516 ? 903.2962962 * yn : 116.0 * cbrt(yn) - 16.0;
}

static inline double lstar_from_argb(uint32_t argb) {
    double r = linearized((argb >> 16) & 0xFF);
    double g = linearized((argb >> 8) & 0xFF);
    double b = linearized(argb & 0xFF);
    double y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return lstar_from_y(y);
}

// Standard Viewing Conditions (sRGB D65)
#define VC_N 0.18418651851244416
#define VC_AW 29.980997194447333
#define VC_NBB 1.0169191804458755
#define VC_NCB 1.0169191804458755
#define VC_C 0.69
#define VC_NC 1.0
#define VC_FL 0.3884814537800353
#define VC_FL_R 0.7894826179304937
#define VC_Z 1.909169568483652
#define VC_RGB_D0 1.02117770275752
#define VC_RGB_D1 0.9863077294280124
#define VC_RGB_D2 0.9339605082802299

typedef struct {
    double hue;
    double chroma;
    double j;
} Cam16;

static Cam16 cam16_from_argb(uint32_t argb) {
    double r = linearized((argb >> 16) & 0xFF);
    double g = linearized((argb >> 8) & 0xFF);
    double b = linearized(argb & 0xFF);

    double x = 0.41233895 * r + 0.35762064 * g + 0.18051042 * b;
    double y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    double z = 0.01932141 * r + 0.11916382 * g + 0.95034478 * b;

    double r_c = ( 0.401288 * x + 0.650173 * y - 0.051461 * z) * VC_RGB_D0;
    double g_c = (-0.250268 * x + 1.204414 * y + 0.045854 * z) * VC_RGB_D1;
    double b_c = (-0.002079 * x + 0.048952 * y + 0.953127 * z) * VC_RGB_D2;

    double r_af = pow(VC_FL * fabs(r_c) / 100.0, 0.42);
    double g_af = pow(VC_FL * fabs(g_c) / 100.0, 0.42);
    double b_af = pow(VC_FL * fabs(b_c) / 100.0, 0.42);

    double r_a = signum_d(r_c) * 400.0 * r_af / (r_af + 27.13);
    double g_a = signum_d(g_c) * 400.0 * g_af / (g_af + 27.13);
    double b_a = signum_d(b_c) * 400.0 * b_af / (b_af + 27.13);

    double a  = (11.0 * r_a - 12.0 * g_a + b_a) / 11.0;
    double bb = (r_a + g_a - 2.0 * b_a) / 9.0;
    double u  = (20.0 * r_a + 20.0 * g_a + 21.0 * b_a) / 20.0;
    double p2 = (40.0 * r_a + 20.0 * g_a + b_a) / 20.0;

    double rad = atan2(bb, a);
    double deg = rad * 180.0 / M_PI;
    double hue = sanitize_deg(deg);

    double ac = p2 * VC_NBB;
    double j = 100.0 * pow(ac / VC_AW, VC_C * VC_Z);

    double h_prime = (hue < 20.14) ? hue + 360.0 : hue;
    double et = 0.25 * (cos(h_prime * M_PI / 180.0 + 2.0) + 3.8);
    double p1 = 50000.0 / 13.0 * et * VC_NC * VC_NCB;
    double t = p1 * hypot(a, bb) / (u + 0.305);
    double alpha = pow(1.64 - pow(0.29, VC_N), 0.73) * pow(t, 0.9);
    double c = alpha * sqrt(j / 100.0);

    return (Cam16){ hue, c, j };
}

static const double Y_TO_LINRGB[3][3] = {
    {  3.2413774792388685, -1.5376652402851851, -0.49885366846268053 },
    { -0.9691452513005321,  1.8758853451067872,  0.04156585616912061 },
    {  0.05562093689691305,-0.20395524564742123, 1.0571799111220335  }
};

static uint32_t cam16_xyz_from_jch(double j, double c, double h,
                                   double *out_x, double *out_y, double *out_z) {
    if (c <= 0.0 || j <= 0.0) {
        *out_x = *out_y = *out_z = 0.0;
        return 0;
    }

    double alpha = c / sqrt(j / 100.0);
    double t = pow(alpha / pow(1.64 - pow(0.29, VC_N), 0.73), 1.0 / 0.9);
    double h_rad = h * M_PI / 180.0;
    double et = 0.25 * (cos(h_rad + 2.0) + 3.8);
    double ac = VC_AW * pow(j / 100.0, 1.0 / (VC_C * VC_Z));
    double p1 = 50000.0 / 13.0 * et * VC_NC * VC_NCB;
    double p2 = ac / VC_NBB;

    double h_sin = sin(h_rad);
    double h_cos = cos(h_rad);

    double gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * h_cos + 108.0 * t * h_sin);
    double a = gamma * h_cos;
    double b = gamma * h_sin;

    double r_a = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
    double g_a = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
    double b_a = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;

    double r_c = signum_d(r_a) * (100.0 / VC_FL) * pow(fmax(0.0, 27.13 * fabs(r_a) / (400.0 - fabs(r_a))), 1.0 / 0.42);
    double g_c = signum_d(g_a) * (100.0 / VC_FL) * pow(fmax(0.0, 27.13 * fabs(g_a) / (400.0 - fabs(g_a))), 1.0 / 0.42);
    double b_c = signum_d(b_a) * (100.0 / VC_FL) * pow(fmax(0.0, 27.13 * fabs(b_a) / (400.0 - fabs(b_a))), 1.0 / 0.42);

    double r_f = r_c / VC_RGB_D0;
    double g_f = g_c / VC_RGB_D1;
    double b_f = b_c / VC_RGB_D2;

    *out_x =  1.86206786 * r_f - 1.01125463 * g_f + 0.14918677 * b_f;
    *out_y =  0.38752654 * r_f + 0.62144744 * g_f - 0.00897398 * b_f;
    *out_z = -0.01584150 * r_f - 0.03412294 * g_f + 1.04996444 * b_f;
    return 1;
}

static uint32_t argb_from_xyz(double x, double y, double z) {
    double rL = Y_TO_LINRGB[0][0] * x + Y_TO_LINRGB[0][1] * y + Y_TO_LINRGB[0][2] * z;
    double gL = Y_TO_LINRGB[1][0] * x + Y_TO_LINRGB[1][1] * y + Y_TO_LINRGB[1][2] * z;
    double bL = Y_TO_LINRGB[2][0] * x + Y_TO_LINRGB[2][1] * y + Y_TO_LINRGB[2][2] * z;
    int r = delinearized(rL);
    int g = delinearized(gL);
    int b = delinearized(bL);
    return 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

static uint32_t hct_solve_to_argb(double hue, double chroma, double lstar) {
    if (chroma < 0.0001 || lstar < 0.0001 || lstar > 99.9999) {
        double y = y_from_lstar(lstar);
        int c = delinearized(y);
        return 0xFF000000u | ((uint32_t)c << 16) | ((uint32_t)c << 8) | (uint32_t)c;
    }

    hue = sanitize_deg(hue);
    double y_target = y_from_lstar(lstar);

    double j_lo = 0.0, j_hi = 100.0;
    uint32_t best_argb = 0xFF000000u;
    double best_d = 1e9;

    double c_lo = 0.0, c_hi = chroma;
    for (int ci = 0; ci < 12; ci++) {
        double c_mid = (ci == 0) ? chroma : 0.5 * (c_lo + c_hi);
        j_lo = 0.0; j_hi = 100.0;
        double x = 0, y = 0, z = 0;
        for (int ji = 0; ji < 14; ji++) {
            double j_mid = 0.5 * (j_lo + j_hi);
            cam16_xyz_from_jch(j_mid, c_mid, hue, &x, &y, &z);
            if (y < y_target) j_lo = j_mid;
            else j_hi = j_mid;
        }

        double rL = Y_TO_LINRGB[0][0] * x + Y_TO_LINRGB[0][1] * y + Y_TO_LINRGB[0][2] * z;
        double gL = Y_TO_LINRGB[1][0] * x + Y_TO_LINRGB[1][1] * y + Y_TO_LINRGB[1][2] * z;
        double bL = Y_TO_LINRGB[2][0] * x + Y_TO_LINRGB[2][1] * y + Y_TO_LINRGB[2][2] * z;

        bool in_gamut = (rL >= -0.05 && rL <= 100.05 &&
                         gL >= -0.05 && gL <= 100.05 &&
                         bL >= -0.05 && bL <= 100.05);

        if (in_gamut) {
            best_argb = argb_from_xyz(x, y, z);
            if (ci == 0) return best_argb;
            c_lo = c_mid;
        } else {
            c_hi = c_mid;
            uint32_t cand = argb_from_xyz(x, y, z);
            double d = fabs(lstar_from_argb(cand) - lstar);
            if (d < best_d) { best_d = d; best_argb = cand; }
        }
    }
    return best_argb;
}

static uint32_t blend_harmonize(uint32_t design_color, uint32_t source_color) {
    Cam16 from_cam = cam16_from_argb(design_color);
    Cam16 to_cam = cam16_from_argb(source_color);
    double from_l = lstar_from_argb(design_color);
    double diff = diff_deg(from_cam.hue, to_cam.hue);
    double rot = fmin(diff * 0.35, 12.0);
    double out_hue = sanitize_deg(from_cam.hue + rot * rotation_dir(from_cam.hue, to_cam.hue));
    return hct_solve_to_argb(out_hue, from_cam.chroma, from_l);
}

// Find the sRGB cusp lightness for a given hue so colors stay deep and rich
// (like Vercel's #be2b21, #0070f3, #528ca9, #933087, #2dd4bf) rather than
// washing out into Material-style pastels.
static double vercel_cusp_lstar(double hue) {
    hue = sanitize_deg(hue);
    double best_l = 52.0;
    double best_sat = -1.0;
    for (int l = 38; l <= 76; l += 2) {
        uint32_t argb = hct_solve_to_argb(hue, 80.0, (double)l);
        int r = (argb >> 16) & 0xFF;
        int g = (argb >> 8) & 0xFF;
        int b = argb & 0xFF;
        int mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
        int mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
        if (mx < 140) continue;
        // Prefer high chroma difference with low white wash-out (mn)
        double sat = (double)(mx - mn) - 0.65 * (double)mn;
        if (sat > best_sat) {
            best_sat = sat;
            best_l = (double)l;
        }
    }
    return best_l;
}

static uint32_t vercel_accent_solve(double hue, double chroma, double src_lstar, bool dark) {
    double cusp = vercel_cusp_lstar(hue);
    double clamped_src = clamp_d(src_lstar, 40.0, 68.0);
    double target_l;
    if (dark) {
        target_l = clamp_d(0.72 * cusp + 0.28 * clamped_src, 44.0, 72.0);
    } else {
        target_l = clamp_d(0.75 * cusp + 0.25 * clamped_src - 6.0, 36.0, 54.0);
    }
    return hct_solve_to_argb(hue, chroma, target_l);
}

static const char *contrast_on_color(uint32_t argb) {
    return (lstar_from_argb(argb) >= 62.0) ? "#050505" : "#fafafa";
}

typedef struct {
    uint32_t argb;
    uint32_t count;
    Cam16 cam;
    double lstar;
} Cluster;

typedef struct {
    uint32_t source_argb;
    double h1, c1, l1;
    double h2, c2, l2;
    double h3, c3, l3;
    bool is_monochrome;
} WallpaperProfile;

static WallpaperProfile extract_wallpaper_profile(const char *image_path) {
    WallpaperProfile wp = {
        .source_argb = VERCEL_BLUE,
        .h1 = 250.0, .c1 = 60.0, .l1 = 52.0,
        .h2 = 295.0, .c2 = 45.0, .l2 = 48.0,
        .h3 = 185.0, .c3 = 45.0, .l3 = 68.0,
        .is_monochrome = false
    };

    int w = 0, h = 0, ch = 0;
    unsigned char *img = stbi_load(image_path, &w, &h, &ch, 3);
    if (!img || w <= 0 || h <= 0) {
        if (img) stbi_image_free(img);
        return wp;
    }

    int tw = w < THUMB_SIZE ? w : THUMB_SIZE;
    int th = h < THUMB_SIZE ? h : THUMB_SIZE;
    int total_px = tw * th;

    static uint32_t bin_counts[32768];
    static uint64_t bin_r[32768], bin_g[32768], bin_b[32768];
    memset(bin_counts, 0, sizeof(bin_counts));
    memset(bin_r, 0, sizeof(bin_r));
    memset(bin_g, 0, sizeof(bin_g));
    memset(bin_b, 0, sizeof(bin_b));

    for (int y = 0; y < th; y++) {
        int sy = (y * h) / th;
        for (int x = 0; x < tw; x++) {
            int sx = (x * w) / tw;
            const unsigned char *p = img + ((size_t)sy * w + sx) * 3;
            int idx = ((p[0] >> 3) << 10) | ((p[1] >> 3) << 5) | (p[2] >> 3);
            bin_counts[idx]++;
            bin_r[idx] += p[0];
            bin_g[idx] += p[1];
            bin_b[idx] += p[2];
        }
    }
    stbi_image_free(img);

    Cluster clusters[128];
    int n_clusters = 0;
    for (int k = 0; k < 128; k++) {
        uint32_t max_c = 0;
        int best_idx = -1;
        for (int i = 0; i < 32768; i++) {
            if (bin_counts[i] > max_c) {
                max_c = bin_counts[i];
                best_idx = i;
            }
        }
        if (best_idx < 0 || max_c == 0) break;

        uint32_t c = bin_counts[best_idx];
        uint32_t r = (uint32_t)(bin_r[best_idx] / c);
        uint32_t g = (uint32_t)(bin_g[best_idx] / c);
        uint32_t b = (uint32_t)(bin_b[best_idx] / c);
        uint32_t argb = 0xFF000000u | (r << 16) | (g << 8) | b;

        clusters[n_clusters].argb = argb;
        clusters[n_clusters].count = c;
        clusters[n_clusters].cam = cam16_from_argb(argb);
        clusters[n_clusters].lstar = lstar_from_argb(argb);
        n_clusters++;

        bin_counts[best_idx] = 0;
    }
    if (n_clusters == 0) return wp;

    double hue_pop[360] = {0};
    double chromatic_pop_sum = 0.0;
    for (int i = 0; i < n_clusters; i++) {
        if (clusters[i].cam.chroma >= 8.0 && clusters[i].lstar >= 8.0 && clusters[i].lstar <= 95.0) {
            int hue = clamp_i((int)floor(clusters[i].cam.hue), 0, 359);
            hue_pop[hue] += clusters[i].count;
            chromatic_pop_sum += clusters[i].count;
        }
    }

    // If less than 1.5% of the image has chromatic color, treat as Vercel Monochrome
    if (chromatic_pop_sum < (double)total_px * 0.015) {
        wp.is_monochrome = true;
        wp.source_argb = 0xFFEDEDEDu;
        return wp;
    }

    double excited_prop[360] = {0};
    for (int h_idx = 0; h_idx < 360; h_idx++) {
        double prop = hue_pop[h_idx] / chromatic_pop_sum;
        for (int j = h_idx - 14; j < h_idx + 16; j++) {
            int nh = (j % 360 + 360) % 360;
            excited_prop[nh] += prop;
        }
    }

    int best_idx = -1;
    double best_score = -1e9;
    double scores[128];
    for (int i = 0; i < n_clusters; i++) {
        double c = clusters[i].cam.chroma;
        double l = clusters[i].lstar;
        if (c < 8.0 || l < 8.0 || l > 95.0) {
            scores[i] = -1e9;
            continue;
        }
        int hue = clamp_i((int)round(clusters[i].cam.hue), 0, 359);
        double prop = excited_prop[hue];
        double prop_score = prop * 100.0 * 0.68;
        double cw = (c < 42.0) ? 0.15 : 0.32;
        double chroma_score = (c - 38.0) * cw;
        double l_pen = (l < 16.0 || l > 88.0) ? -8.0 : 0.0;
        scores[i] = prop_score + chroma_score + l_pen;
        if (scores[i] > best_score) {
            best_score = scores[i];
            best_idx = i;
        }
    }

    if (best_idx < 0) {
        wp.is_monochrome = true;
        wp.source_argb = 0xFFEDEDEDu;
        return wp;
    }

    wp.source_argb = clusters[best_idx].argb;
    wp.h1 = clusters[best_idx].cam.hue;
    double j1 = fmax(12.0, clusters[best_idx].cam.j);
    wp.c1 = clamp_d(clusters[best_idx].cam.chroma * sqrt(50.0 / j1), 54.0, 76.0);
    wp.l1 = clusters[best_idx].lstar;

    // Find secondary accent cluster (distinct hue >= 28 deg away)
    int sec_idx = -1;
    double sec_score = -1e9;
    for (int i = 0; i < n_clusters; i++) {
        if (scores[i] <= -1e8) continue;
        if (diff_deg(clusters[i].cam.hue, wp.h1) >= 28.0 && scores[i] > sec_score) {
            sec_score = scores[i];
            sec_idx = i;
        }
    }
    if (sec_idx >= 0) {
        wp.h2 = clusters[sec_idx].cam.hue;
        double j2 = fmax(12.0, clusters[sec_idx].cam.j);
        wp.c2 = clamp_d(clusters[sec_idx].cam.chroma * sqrt(50.0 / j2), 42.0, 64.0);
        wp.l2 = clusters[sec_idx].lstar;
    } else {
        wp.h2 = sanitize_deg(wp.h1 + 32.0);
        wp.c2 = clamp_d(wp.c1 * 0.82, 42.0, 62.0);
        wp.l2 = wp.l1;
    }

    // Find tertiary accent cluster (distinct from both h1 and h2)
    int tert_idx = -1;
    double tert_score = -1e9;
    for (int i = 0; i < n_clusters; i++) {
        if (scores[i] <= -1e8) continue;
        if (diff_deg(clusters[i].cam.hue, wp.h1) >= 28.0 &&
            diff_deg(clusters[i].cam.hue, wp.h2) >= 28.0 &&
            scores[i] > tert_score) {
            tert_score = scores[i];
            tert_idx = i;
        }
    }
    if (tert_idx >= 0) {
        wp.h3 = clusters[tert_idx].cam.hue;
        double j3 = fmax(12.0, clusters[tert_idx].cam.j);
        wp.c3 = clamp_d(clusters[tert_idx].cam.chroma * sqrt(50.0 / j3), 42.0, 64.0);
        wp.l3 = clusters[tert_idx].lstar;
    } else {
        wp.h3 = sanitize_deg(wp.h1 - 45.0);
        wp.c3 = clamp_d(wp.c1 * 0.78, 42.0, 60.0);
        wp.l3 = wp.l1;
    }

    return wp;
}

// ============================================================================
// 2. THEME ROLE DEFINITIONS & VERCEL GEIST BUILDER
// ============================================================================

typedef struct {
    char color[8];
    char on_color[8];
    char container[8];
    char on_container[8];
} SupportColor;

typedef struct {
    char background[8], on_background[8];
    char surface[8], on_surface[8], surface_variant[8], on_surface_variant[8];
    char primary[8], on_primary[8], primary_container[8], on_primary_container[8];
    char secondary[8], on_secondary[8], secondary_container[8], on_secondary_container[8];
    char tertiary[8], on_tertiary[8], tertiary_container[8], on_tertiary_container[8];
    char error[8], on_error[8], error_container[8], on_error_container[8];
    char outline[8], outline_variant[8];
    char inverse_surface[8], inverse_on_surface[8], inverse_primary[8];
    char shadow[8], scrim[8];
    SupportColor success;
    SupportColor warning;
    char ansi[16][8];
    char _source[8];
    char _mode[16];
    char _cache_key[64];
} ThemeRoles;

static void hex6_str(uint32_t argb, char out[8]) {
    snprintf(out, 8, "#%02x%02x%02x",
             (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

static void hex_mix(const char *hex_a, const char *hex_b, double t, char out[8]) {
    unsigned int ar = 0, ag = 0, ab = 0, br = 0, bg = 0, bb = 0;
    sscanf(hex_a + 1, "%02x%02x%02x", &ar, &ag, &ab);
    sscanf(hex_b + 1, "%02x%02x%02x", &br, &bg, &bb);
    int r = clamp_i((int)round(ar + ((int)br - (int)ar) * t), 0, 255);
    int g = clamp_i((int)round(ag + ((int)bg - (int)ag) * t), 0, 255);
    int b = clamp_i((int)round(ab + ((int)bb - (int)ab) * t), 0, 255);
    snprintf(out, 8, "#%02x%02x%02x", r, g, b);
}

static void darken(const char *hex_c, double t, char out[8]) {
    hex_mix(hex_c, "#000000", t, out);
}

static SupportColor vercel_support_color(uint32_t seed_argb, uint32_t source_argb, bool is_mono, const char *mode) {
    uint32_t col = is_mono ? seed_argb : blend_harmonize(seed_argb, source_argb);
    Cam16 cam = cam16_from_argb(col);
    double seed_l = lstar_from_argb(seed_argb);
    SupportColor sc;

    if (strcmp(mode, "dark") == 0) {
        uint32_t c_argb = vercel_accent_solve(cam.hue, fmax(52.0, cam.chroma), seed_l, true);
        hex6_str(c_argb, sc.color);
        strcpy(sc.on_color, contrast_on_color(c_argb));
        hex6_str(hct_solve_to_argb(cam.hue, cam.chroma * 0.45, 18.0), sc.container);
        hex6_str(hct_solve_to_argb(cam.hue, fmax(42.0, cam.chroma), 88.0), sc.on_container);
    } else {
        uint32_t c_argb = vercel_accent_solve(cam.hue, fmax(52.0, cam.chroma), seed_l, false);
        hex6_str(c_argb, sc.color);
        strcpy(sc.on_color, "#ffffff");
        hex6_str(hct_solve_to_argb(cam.hue, cam.chroma * 0.35, 92.0), sc.container);
        hex6_str(hct_solve_to_argb(cam.hue, fmax(42.0, cam.chroma), 16.0), sc.on_container);
    }
    return sc;
}

static void build_roles_from_profile(const WallpaperProfile *wp_in, const char *mode, ThemeRoles *r) {
    memset(r, 0, sizeof(*r));
    snprintf(r->_mode, sizeof(r->_mode), "%s", mode);

    WallpaperProfile wp = *wp_in;
    hex6_str(wp.source_argb, r->_source);

    bool dark = (strcmp(mode, "dark") == 0);

    // 1. Neutral Vercel Geist surfaces (#050505-#141414 dark, #fafafa-#f4f4f5 light)
    if (dark) {
        strcpy(r->background, "#050505");
        strcpy(r->on_background, "#ededed");
        strcpy(r->surface, "#0a0a0a");
        strcpy(r->on_surface, "#fafafa");
        strcpy(r->surface_variant, "#141414");
        strcpy(r->on_surface_variant, "#a1a1aa");
        strcpy(r->outline, "#52525b");
        strcpy(r->outline_variant, "#262626");
        strcpy(r->inverse_surface, "#fafafa");
        strcpy(r->inverse_on_surface, "#09090b");
        strcpy(r->shadow, "#000000");
        strcpy(r->scrim, "#000000");
    } else {
        strcpy(r->background, "#fafafa");
        strcpy(r->on_background, "#09090b");
        strcpy(r->surface, "#ffffff");
        strcpy(r->on_surface, "#09090b");
        strcpy(r->surface_variant, "#f4f4f5");
        strcpy(r->on_surface_variant, "#52525b");
        strcpy(r->outline, "#71717a");
        strcpy(r->outline_variant, "#e4e4e7");
        strcpy(r->inverse_surface, "#18181b");
        strcpy(r->inverse_on_surface, "#fafafa");
        strcpy(r->shadow, "#000000");
        strcpy(r->scrim, "#000000");
    }

    // 2. Wallpaper-adjusted Vercel Accents (rich sRGB cusp saturation, never chalky pastel)
    if (wp.is_monochrome) {
        if (dark) {
            strcpy(r->primary, "#ededed");
            strcpy(r->on_primary, "#050505");
            strcpy(r->primary_container, "#262626");
            strcpy(r->on_primary_container, "#fafafa");
            strcpy(r->secondary, "#a1a1aa");
            strcpy(r->on_secondary, "#09090b");
            strcpy(r->secondary_container, "#1f1f22");
            strcpy(r->on_secondary_container, "#e4e4e7");
            strcpy(r->tertiary, "#3291ff");
            strcpy(r->on_tertiary, "#fafafa");
            strcpy(r->tertiary_container, "#102a4c");
            strcpy(r->on_tertiary_container, "#d6e8ff");
            strcpy(r->inverse_primary, "#171717");
        } else {
            strcpy(r->primary, "#171717");
            strcpy(r->on_primary, "#fafafa");
            strcpy(r->primary_container, "#e4e4e7");
            strcpy(r->on_primary_container, "#09090b");
            strcpy(r->secondary, "#52525b");
            strcpy(r->on_secondary, "#ffffff");
            strcpy(r->secondary_container, "#e4e4e7");
            strcpy(r->on_secondary_container, "#18181b");
            strcpy(r->tertiary, "#0070f3");
            strcpy(r->on_tertiary, "#ffffff");
            strcpy(r->tertiary_container, "#dbeafe");
            strcpy(r->on_tertiary_container, "#0c2d6b");
            strcpy(r->inverse_primary, "#ededed");
        }
    } else {
        uint32_t p_argb = vercel_accent_solve(wp.h1, wp.c1, wp.l1, dark);
        uint32_t s_argb = vercel_accent_solve(wp.h2, wp.c2, wp.l2, dark);
        uint32_t t_argb = vercel_accent_solve(wp.h3, wp.c3, wp.l3, dark);

        hex6_str(p_argb, r->primary);
        strcpy(r->on_primary, contrast_on_color(p_argb));
        hex6_str(s_argb, r->secondary);
        strcpy(r->on_secondary, contrast_on_color(s_argb));
        hex6_str(t_argb, r->tertiary);
        strcpy(r->on_tertiary, contrast_on_color(t_argb));

        if (dark) {
            hex6_str(hct_solve_to_argb(wp.h1, wp.c1 * 0.45, 18.0), r->primary_container);
            hex6_str(hct_solve_to_argb(wp.h1, wp.c1 * 0.80, 90.0), r->on_primary_container);
            hex6_str(hct_solve_to_argb(wp.h2, wp.c2 * 0.40, 18.0), r->secondary_container);
            hex6_str(hct_solve_to_argb(wp.h2, wp.c2 * 0.75, 90.0), r->on_secondary_container);
            hex6_str(hct_solve_to_argb(wp.h3, wp.c3 * 0.40, 18.0), r->tertiary_container);
            hex6_str(hct_solve_to_argb(wp.h3, wp.c3 * 0.75, 90.0), r->on_tertiary_container);
            hex6_str(vercel_accent_solve(wp.h1, wp.c1, wp.l1, false), r->inverse_primary);
        } else {
            hex6_str(hct_solve_to_argb(wp.h1, wp.c1 * 0.35, 92.0), r->primary_container);
            hex6_str(hct_solve_to_argb(wp.h1, wp.c1 * 0.80, 16.0), r->on_primary_container);
            hex6_str(hct_solve_to_argb(wp.h2, wp.c2 * 0.30, 92.0), r->secondary_container);
            hex6_str(hct_solve_to_argb(wp.h2, wp.c2 * 0.75, 16.0), r->on_secondary_container);
            hex6_str(hct_solve_to_argb(wp.h3, wp.c3 * 0.30, 92.0), r->tertiary_container);
            hex6_str(hct_solve_to_argb(wp.h3, wp.c3 * 0.75, 16.0), r->on_tertiary_container);
            hex6_str(vercel_accent_solve(wp.h1, wp.c1, wp.l1, true), r->inverse_primary);
        }
    }

    // 3. Semantic Support Colors (Error, Warning, Success)
    SupportColor err = vercel_support_color(ERROR_SEED, wp.source_argb, wp.is_monochrome, mode);
    strcpy(r->error, err.color);
    strcpy(r->on_error, err.on_color);
    strcpy(r->error_container, err.container);
    strcpy(r->on_error_container, err.on_container);

    r->success = vercel_support_color(SUCCESS_SEED, wp.source_argb, wp.is_monochrome, mode);
    r->warning = vercel_support_color(WARNING_SEED, wp.source_argb, wp.is_monochrome, mode);

    // 4. 16-Color Vercel ANSI Palette (harmonized with wallpaper)
    if (dark) {
        strcpy(r->ansi[0], "#0a0a0a");
        hex6_str(wp.is_monochrome ? 0xFF6E0E0Au : blend_harmonize(0xFF6E0E0Au, wp.source_argb), r->ansi[1]);
        hex6_str(wp.is_monochrome ? 0xFF0F6657u : blend_harmonize(0xFF0F6657u, wp.source_argb), r->ansi[2]);
        hex6_str(wp.is_monochrome ? 0xFFDCA842u : blend_harmonize(0xFFDCA842u, wp.source_argb), r->ansi[3]);
        if (wp.is_monochrome) {
            strcpy(r->ansi[4], "#37667e");
            strcpy(r->ansi[5], "#6c2266");
            strcpy(r->ansi[6], "#1a8c77");
        } else {
            darken(r->primary, 0.25, r->ansi[4]);
            darken(r->secondary, 0.25, r->ansi[5]);
            darken(r->tertiary, 0.25, r->ansi[6]);
        }
        strcpy(r->ansi[7], "#a1a1aa");
        strcpy(r->ansi[8], "#262626");
        hex6_str(wp.is_monochrome ? 0xFFBE2B21u : blend_harmonize(0xFFBE2B21u, wp.source_argb), r->ansi[9]);
        strcpy(r->ansi[10], r->success.color);
        strcpy(r->ansi[11], r->warning.color);
        if (wp.is_monochrome) {
            strcpy(r->ansi[12], "#528ca9");
            strcpy(r->ansi[13], "#933087");
            strcpy(r->ansi[14], "#2dd4bf");
        } else {
            strcpy(r->ansi[12], r->primary);
            strcpy(r->ansi[13], r->secondary);
            strcpy(r->ansi[14], r->tertiary);
        }
        strcpy(r->ansi[15], "#f5f7fa");
    } else {
        strcpy(r->ansi[0], "#f4f4f5");
        strcpy(r->ansi[1], r->error);
        strcpy(r->ansi[2], r->success.color);
        strcpy(r->ansi[3], r->warning.color);
        if (wp.is_monochrome) {
            strcpy(r->ansi[4], "#0070f3");
            strcpy(r->ansi[5], "#7928ca");
            strcpy(r->ansi[6], "#0d9488");
        } else {
            strcpy(r->ansi[4], r->primary);
            strcpy(r->ansi[5], r->secondary);
            strcpy(r->ansi[6], r->tertiary);
        }
        strcpy(r->ansi[7], "#52525b");
        strcpy(r->ansi[8], "#71717a");
        hex6_str(wp.is_monochrome ? 0xFFDC2626u : blend_harmonize(0xFFDC2626u, wp.source_argb), r->ansi[9]);
        hex6_str(wp.is_monochrome ? 0xFF16A34Au : blend_harmonize(0xFF16A34Au, wp.source_argb), r->ansi[10]);
        hex6_str(wp.is_monochrome ? 0xFFD97706u : blend_harmonize(0xFFD97706u, wp.source_argb), r->ansi[11]);
        if (wp.is_monochrome) {
            strcpy(r->ansi[12], "#2563eb");
            strcpy(r->ansi[13], "#9333ea");
            strcpy(r->ansi[14], "#0f766e");
        } else {
            darken(r->primary, 0.15, r->ansi[12]);
            darken(r->secondary, 0.15, r->ansi[13]);
            darken(r->tertiary, 0.15, r->ansi[14]);
        }
        strcpy(r->ansi[15], "#09090b");
    }
}

static void build_roles(const char *wallpaper, const char *mode, ThemeRoles *r) {
    WallpaperProfile wp = extract_wallpaper_profile(wallpaper);
    build_roles_from_profile(&wp, mode, r);
}

// ============================================================================
// 3. FILE SYSTEM, ATOMIC I/O, CACHING, AND SUBPROCESS UTILITIES
// ============================================================================

static char g_home[PATH_MAX];
static char g_cache_dir[BUF_PATH];
static char g_cache_file[BUF_PATH + 64];
static char g_mode_file[BUF_PATH];
static char g_apply_lock[BUF_PATH + 64];
static char g_watch_lock[BUF_PATH + 64];
static char g_theme_dir[BUF_PATH];
static char g_theme_config[BUF_PATH + 64];
static char g_theme_templates_dir[BUF_PATH + 64];
static char g_theme_schemes_dir[BUF_PATH + 64];
static char g_wallust_config[BUF_PATH];
static char g_wallust_templates_dir[BUF_PATH];

static void init_paths(void) {
    const char *h = getenv("HOME");
    if (!h) h = "/tmp";
    snprintf(g_home, sizeof(g_home), "%s", h);
    snprintf(g_cache_dir, sizeof(g_cache_dir), "%s/.cache/material_theme", g_home);
    snprintf(g_cache_file, sizeof(g_cache_file), "%s/colors.json", g_cache_dir);
    snprintf(g_mode_file, sizeof(g_mode_file), "%s/.config/hypr/theme-mode", g_home);
    snprintf(g_apply_lock, sizeof(g_apply_lock), "%s/apply.lock", g_cache_dir);
    snprintf(g_watch_lock, sizeof(g_watch_lock), "%s/watch.lock", g_cache_dir);
    snprintf(g_theme_dir, sizeof(g_theme_dir), "%s/.config/theme", g_home);
    snprintf(g_theme_config, sizeof(g_theme_config), "%s/config.toml", g_theme_dir);
    snprintf(g_theme_templates_dir, sizeof(g_theme_templates_dir), "%s/templates", g_theme_dir);
    snprintf(g_theme_schemes_dir, sizeof(g_theme_schemes_dir), "%s/themes", g_theme_dir);
    snprintf(g_wallust_config, sizeof(g_wallust_config), "%s/.config/wallust/wallust.toml", g_home);
    snprintf(g_wallust_templates_dir, sizeof(g_wallust_templates_dir), "%s/.config/wallust/templates", g_home);
}

static void mkdir_p(const char *dir_path) {
    char tmp[BUF_PATH + 128];
    snprintf(tmp, sizeof(tmp), "%s", dir_path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    mkdir(tmp, 0755);
}

static void mkdir_parent(const char *file_path) {
    char tmp[BUF_PATH + 128];
    snprintf(tmp, sizeof(tmp), "%s", file_path);
    char *slash = strrchr(tmp, '/');
    if (slash) {
        *slash = '\0';
        mkdir_p(tmp);
    }
}

static char *read_file_str(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    buf[rd] = '\0';
    fclose(f);
    return buf;
}

static bool atomic_write(const char *path, const char *content) {
    mkdir_parent(path);
    char tmp[BUF_PATH];
    const char *slash = strrchr(path, '/');
    if (slash) {
        size_t dir_len = (size_t)(slash - path);
        snprintf(tmp, sizeof(tmp), "%.*s/.%s.tmp.%d", (int)dir_len, path, slash + 1, getpid());
    } else {
        snprintf(tmp, sizeof(tmp), ".%s.tmp.%d", path, getpid());
    }
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return false;
    size_t len = strlen(content);
    ssize_t wr = write(fd, content, len);
    close(fd);
    if (wr < 0 || (size_t)wr != len) {
        unlink(tmp);
        return false;
    }
    if (rename(tmp, path) != 0) {
        unlink(tmp);
        return false;
    }
    return true;
}

static void compute_cache_key(const char *wallpaper, const char *mode, char out[64]) {
    struct stat st;
    if (stat(wallpaper, &st) != 0) {
        out[0] = '\0';
        return;
    }
    char raw[BUF_PATH + 128];
    snprintf(raw, sizeof(raw), "vercel-v8|%s|%ld|%ld|%ld|%s",
             wallpaper, (long)st.st_mtim.tv_sec, (long)st.st_mtim.tv_nsec, (long)st.st_size, mode);

    uint64_t h1 = 14695981039346656037ULL;
    uint64_t h2 = 1099511628211ULL;
    for (const char *p = raw; *p; p++) {
        h1 ^= (uint8_t)(*p);
        h1 *= 1099511628211ULL;
        h2 ^= (uint8_t)(*p);
        h2 = (h2 << 13) | (h2 >> 51);
        h2 *= 14695981039346656037ULL;
    }
    snprintf(out, 64, "%016llx%016llx", (unsigned long long)h1, (unsigned long long)h2);
}

static bool json_extract_str(const char *json, const char *key, char *out, size_t out_sz) {
    char pat[128];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(json, pat);
    if (!p) return false;
    p += strlen(pat);
    while (*p && (*p == ' ' || *p == ':' || *p == '\t' || *p == '\n')) p++;
    if (*p != '"') return false;
    p++;
    const char *end = strchr(p, '"');
    if (!end) return false;
    size_t len = (size_t)(end - p);
    if (len >= out_sz) len = out_sz - 1;
    memcpy(out, p, len);
    out[len] = '\0';
    return true;
}

static bool json_extract_nested(const char *json, const char *parent, const char *key, char *out, size_t out_sz) {
    char pat[128];
    snprintf(pat, sizeof(pat), "\"%s\"", parent);
    const char *p = strstr(json, pat);
    if (!p) return false;
    const char *brace = strchr(p, '{');
    if (!brace) return false;
    return json_extract_str(brace, key, out, out_sz);
}

static bool load_cached_roles(const char *key, ThemeRoles *r) {
    char *txt = read_file_str(g_cache_file);
    if (!txt) return false;

    char ck[64] = {0};
    if (!json_extract_str(txt, "_cache_key", ck, sizeof(ck)) || strcmp(ck, key) != 0) {
        free(txt);
        return false;
    }

    memset(r, 0, sizeof(*r));
#define LOAD_F(f) json_extract_str(txt, #f, r->f, sizeof(r->f))
    LOAD_F(background); LOAD_F(on_background);
    LOAD_F(surface); LOAD_F(on_surface); LOAD_F(surface_variant); LOAD_F(on_surface_variant);
    LOAD_F(primary); LOAD_F(on_primary); LOAD_F(primary_container); LOAD_F(on_primary_container);
    LOAD_F(secondary); LOAD_F(on_secondary); LOAD_F(secondary_container); LOAD_F(on_secondary_container);
    LOAD_F(tertiary); LOAD_F(on_tertiary); LOAD_F(tertiary_container); LOAD_F(on_tertiary_container);
    LOAD_F(error); LOAD_F(on_error); LOAD_F(error_container); LOAD_F(on_error_container);
    LOAD_F(outline); LOAD_F(outline_variant);
    LOAD_F(inverse_surface); LOAD_F(inverse_on_surface); LOAD_F(inverse_primary);
    LOAD_F(shadow); LOAD_F(scrim);
    LOAD_F(_source); LOAD_F(_mode); LOAD_F(_cache_key);
#undef LOAD_F

    for (int i = 0; i < 16; i++) {
        char k[16];
        snprintf(k, sizeof(k), "ansi%d", i);
        json_extract_str(txt, k, r->ansi[i], 8);
    }

    json_extract_nested(txt, "success", "color", r->success.color, 8);
    json_extract_nested(txt, "success", "on_color", r->success.on_color, 8);
    json_extract_nested(txt, "success", "container", r->success.container, 8);
    json_extract_nested(txt, "success", "on_container", r->success.on_container, 8);
    json_extract_nested(txt, "warning", "color", r->warning.color, 8);
    json_extract_nested(txt, "warning", "on_color", r->warning.on_color, 8);
    json_extract_nested(txt, "warning", "container", r->warning.container, 8);
    json_extract_nested(txt, "warning", "on_container", r->warning.on_container, 8);

    free(txt);
    return r->primary[0] == '#' && r->background[0] == '#' && r->ansi[0][0] == '#';
}

static void save_cached_roles(const ThemeRoles *r) {
    char buf[8192];
    snprintf(buf, sizeof(buf),
        "{\n"
        "  \"background\": \"%s\",\n"
        "  \"on_background\": \"%s\",\n"
        "  \"surface\": \"%s\",\n"
        "  \"on_surface\": \"%s\",\n"
        "  \"surface_variant\": \"%s\",\n"
        "  \"on_surface_variant\": \"%s\",\n"
        "  \"primary\": \"%s\",\n"
        "  \"on_primary\": \"%s\",\n"
        "  \"primary_container\": \"%s\",\n"
        "  \"on_primary_container\": \"%s\",\n"
        "  \"secondary\": \"%s\",\n"
        "  \"on_secondary\": \"%s\",\n"
        "  \"secondary_container\": \"%s\",\n"
        "  \"on_secondary_container\": \"%s\",\n"
        "  \"tertiary\": \"%s\",\n"
        "  \"on_tertiary\": \"%s\",\n"
        "  \"tertiary_container\": \"%s\",\n"
        "  \"on_tertiary_container\": \"%s\",\n"
        "  \"error\": \"%s\",\n"
        "  \"on_error\": \"%s\",\n"
        "  \"error_container\": \"%s\",\n"
        "  \"on_error_container\": \"%s\",\n"
        "  \"outline\": \"%s\",\n"
        "  \"outline_variant\": \"%s\",\n"
        "  \"inverse_surface\": \"%s\",\n"
        "  \"inverse_on_surface\": \"%s\",\n"
        "  \"inverse_primary\": \"%s\",\n"
        "  \"shadow\": \"%s\",\n"
        "  \"scrim\": \"%s\",\n"
        "  \"ansi0\": \"%s\", \"ansi1\": \"%s\", \"ansi2\": \"%s\", \"ansi3\": \"%s\",\n"
        "  \"ansi4\": \"%s\", \"ansi5\": \"%s\", \"ansi6\": \"%s\", \"ansi7\": \"%s\",\n"
        "  \"ansi8\": \"%s\", \"ansi9\": \"%s\", \"ansi10\": \"%s\", \"ansi11\": \"%s\",\n"
        "  \"ansi12\": \"%s\", \"ansi13\": \"%s\", \"ansi14\": \"%s\", \"ansi15\": \"%s\",\n"
        "  \"success\": {\n"
        "    \"color\": \"%s\",\n"
        "    \"on_color\": \"%s\",\n"
        "    \"container\": \"%s\",\n"
        "    \"on_container\": \"%s\"\n"
        "  },\n"
        "  \"warning\": {\n"
        "    \"color\": \"%s\",\n"
        "    \"on_color\": \"%s\",\n"
        "    \"container\": \"%s\",\n"
        "    \"on_container\": \"%s\"\n"
        "  },\n"
        "  \"_source\": \"%s\",\n"
        "  \"_mode\": \"%s\",\n"
        "  \"_cache_key\": \"%s\"\n"
        "}\n",
        r->background, r->on_background,
        r->surface, r->on_surface, r->surface_variant, r->on_surface_variant,
        r->primary, r->on_primary, r->primary_container, r->on_primary_container,
        r->secondary, r->on_secondary, r->secondary_container, r->on_secondary_container,
        r->tertiary, r->on_tertiary, r->tertiary_container, r->on_tertiary_container,
        r->error, r->on_error, r->error_container, r->on_error_container,
        r->outline, r->outline_variant,
        r->inverse_surface, r->inverse_on_surface, r->inverse_primary,
        r->shadow, r->scrim,
        r->ansi[0], r->ansi[1], r->ansi[2], r->ansi[3],
        r->ansi[4], r->ansi[5], r->ansi[6], r->ansi[7],
        r->ansi[8], r->ansi[9], r->ansi[10], r->ansi[11],
        r->ansi[12], r->ansi[13], r->ansi[14], r->ansi[15],
        r->success.color, r->success.on_color, r->success.container, r->success.on_container,
        r->warning.color, r->warning.on_color, r->warning.container, r->warning.on_container,
        r->_source, r->_mode, r->_cache_key);
    atomic_write(g_cache_file, buf);
}

// ============================================================================
// 4. TEMPLATE CONFIGURATION PORTING & GENERIC TEMPLATE ENGINE
// ============================================================================

static bool write_vercel_scheme(const ThemeRoles *r, char scheme_out[BUF_PATH + 128]) {
    snprintf(scheme_out, BUF_PATH + 128, "%s/vercel.json", g_theme_schemes_dir);
    char buf[2048];
    snprintf(buf, sizeof(buf),
        "{\n"
        "  \"special\": {\n"
        "    \"background\": \"%s\",\n"
        "    \"foreground\": \"%s\",\n"
        "    \"cursor\": \"%s\"\n"
        "  },\n"
        "  \"colors\": {\n"
        "    \"color0\": \"%s\",\n"
        "    \"color1\": \"%s\",\n"
        "    \"color2\": \"%s\",\n"
        "    \"color3\": \"%s\",\n"
        "    \"color4\": \"%s\",\n"
        "    \"color5\": \"%s\",\n"
        "    \"color6\": \"%s\",\n"
        "    \"color7\": \"%s\",\n"
        "    \"color8\": \"%s\",\n"
        "    \"color9\": \"%s\",\n"
        "    \"color10\": \"%s\",\n"
        "    \"color11\": \"%s\",\n"
        "    \"color12\": \"%s\",\n"
        "    \"color13\": \"%s\",\n"
        "    \"color14\": \"%s\",\n"
        "    \"color15\": \"%s\"\n"
        "  }\n"
        "}\n",
        r->background, r->on_background, r->primary,
        r->ansi[0],
        r->error,
        r->success.color,
        r->warning.color,
        r->primary,
        r->secondary,
        r->tertiary,
        r->on_surface_variant,
        r->outline,
        r->ansi[9],
        r->ansi[10],
        r->ansi[11],
        r->ansi[12],
        r->ansi[13],
        r->ansi[14],
        r->on_surface);
    return atomic_write(scheme_out, buf);
}

static char *trim_ws(char *s) {
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    size_t len = strlen(s);
    while (len > 0 && (s[len - 1] == ' ' || s[len - 1] == '\t' || s[len - 1] == '\r' || s[len - 1] == '\n')) {
        s[--len] = '\0';
    }
    return s;
}

// Detect ~/.config/wallust/templates and ~/.config/wallust/wallust.toml and port them
// into ~/.config/theme/templates and ~/.config/theme/config.toml.
static void port_wallust_templates(bool force_overwrite) {
    mkdir_p(g_theme_dir);
    mkdir_p(g_theme_templates_dir);
    mkdir_p(g_theme_schemes_dir);

    DIR *d = opendir(g_wallust_templates_dir);
    if (d) {
        struct dirent *ent;
        while ((ent = readdir(d)) != NULL) {
            if (ent->d_name[0] == '.') continue;
            char src[BUF_PATH + 512], dst[BUF_PATH + 512];
            snprintf(src, sizeof(src), "%s/%s", g_wallust_templates_dir, ent->d_name);
            snprintf(dst, sizeof(dst), "%s/%s", g_theme_templates_dir, ent->d_name);
            struct stat st;
            if (stat(src, &st) != 0 || !S_ISREG(st.st_mode)) continue;
            if (!force_overwrite && access(dst, R_OK) == 0) continue;
            char *content = read_file_str(src);
            if (content) {
                atomic_write(dst, content);
                free(content);
            }
        }
        closedir(d);
    }

    char *w_conf = read_file_str(g_wallust_config);
    char *t_conf = read_file_str(g_theme_config);

    if (!t_conf || force_overwrite) {
        if (w_conf) {
            atomic_write(g_theme_config, w_conf);
        } else {
            const char *init_toml =
                "# ~/.config/theme/config.toml - Theme CLI template configuration\n"
                "[templates]\n";
            atomic_write(g_theme_config, init_toml);
        }
    } else if (w_conf && t_conf) {
        // Merge any newly added template entries from wallust.toml into config.toml
        char *w_copy = strdup(w_conf);
        size_t cap = strlen(t_conf) + strlen(w_conf) + 512;
        char *merged = malloc(cap);
        if (w_copy && merged) {
            strcpy(merged, t_conf);
            bool modified = false;
            bool in_templates = false;
            char *saveptr = NULL;
            for (char *line = strtok_r(w_copy, "\n", &saveptr); line; line = strtok_r(NULL, "\n", &saveptr)) {
                char *trimmed = trim_ws(line);
                if (trimmed[0] == '[') {
                    in_templates = (strncmp(trimmed, "[templates]", 11) == 0);
                    continue;
                }
                if (!in_templates || trimmed[0] == '#' || trimmed[0] == '\0') continue;

                char *eq = strchr(trimmed, '=');
                if (!eq || !strstr(trimmed, "template") || !strstr(trimmed, "target")) continue;

                char key[128] = {0};
                size_t klen = (size_t)(eq - trimmed);
                if (klen >= sizeof(key)) klen = sizeof(key) - 1;
                memcpy(key, trimmed, klen);
                key[klen] = '\0';
                char *ktrim = trim_ws(key);

                char needle1[160], needle2[160];
                snprintf(needle1, sizeof(needle1), "\n%s =", ktrim);
                snprintf(needle2, sizeof(needle2), "\n%s=", ktrim);

                if (!strstr(merged, needle1) && !strstr(merged, needle2)) {
                    size_t mlen = strlen(merged);
                    if (mlen > 0 && merged[mlen - 1] != '\n') strcat(merged, "\n");
                    strcat(merged, trimmed);
                    strcat(merged, "\n");
                    modified = true;
                }
            }
            if (modified) {
                atomic_write(g_theme_config, merged);
            }
            free(merged);
        } else {
            free(merged);
        }
        free(w_copy);
    }

    free(w_conf);
    free(t_conf);
}

static const char *resolve_template_var(const ThemeRoles *r, const char *name) {
    if (strcmp(name, "mode") == 0 || strcmp(name, "base") == 0) return r->_mode;
    if (strcmp(name, "background") == 0) return r->background;
    if (strcmp(name, "foreground") == 0 || strcmp(name, "on_background") == 0) return r->on_background;
    if (strcmp(name, "cursor") == 0 || strcmp(name, "primary") == 0) return r->primary;
    if (strcmp(name, "color0") == 0) return r->ansi[0];
    if (strcmp(name, "color1") == 0 || strcmp(name, "error") == 0) return r->error;
    if (strcmp(name, "color2") == 0 || strcmp(name, "success") == 0) return r->success.color;
    if (strcmp(name, "color3") == 0 || strcmp(name, "warning") == 0) return r->warning.color;
    if (strcmp(name, "color4") == 0) return r->primary;
    if (strcmp(name, "color5") == 0 || strcmp(name, "secondary") == 0) return r->secondary;
    if (strcmp(name, "color6") == 0 || strcmp(name, "tertiary") == 0) return r->tertiary;
    if (strcmp(name, "color7") == 0 || strcmp(name, "on_surface_variant") == 0) return r->on_surface_variant;
    if (strcmp(name, "color8") == 0 || strcmp(name, "outline") == 0) return r->outline;
    if (strcmp(name, "color9") == 0) return r->ansi[9];
    if (strcmp(name, "color10") == 0) return r->ansi[10];
    if (strcmp(name, "color11") == 0) return r->ansi[11];
    if (strcmp(name, "color12") == 0) return r->ansi[12];
    if (strcmp(name, "color13") == 0) return r->ansi[13];
    if (strcmp(name, "color14") == 0) return r->ansi[14];
    if (strcmp(name, "color15") == 0 || strcmp(name, "on_surface") == 0) return r->on_surface;
    if (strcmp(name, "surface") == 0) return r->surface;
    if (strcmp(name, "surface_variant") == 0) return r->surface_variant;
    if (strcmp(name, "outline_variant") == 0) return r->outline_variant;
    if (strcmp(name, "on_primary") == 0) return r->on_primary;
    if (strcmp(name, "primary_container") == 0) return r->primary_container;
    if (strcmp(name, "on_primary_container") == 0) return r->on_primary_container;
    if (strcmp(name, "on_secondary") == 0) return r->on_secondary;
    if (strcmp(name, "secondary_container") == 0) return r->secondary_container;
    if (strcmp(name, "on_secondary_container") == 0) return r->on_secondary_container;
    if (strcmp(name, "on_tertiary") == 0) return r->on_tertiary;
    if (strcmp(name, "tertiary_container") == 0) return r->tertiary_container;
    if (strcmp(name, "on_tertiary_container") == 0) return r->on_tertiary_container;
    if (strcmp(name, "on_error") == 0) return r->on_error;
    if (strcmp(name, "error_container") == 0) return r->error_container;
    if (strcmp(name, "on_error_container") == 0) return r->on_error_container;
    if (strcmp(name, "warning_container") == 0) return r->warning.container;
    if (strcmp(name, "on_warning") == 0) return r->warning.on_color;
    if (strcmp(name, "on_warning_container") == 0) return r->warning.on_container;
    if (strcmp(name, "success_container") == 0) return r->success.container;
    if (strcmp(name, "on_success") == 0) return r->success.on_color;
    if (strcmp(name, "on_success_container") == 0) return r->success.on_container;
    if (strcmp(name, "inverse_surface") == 0) return r->inverse_surface;
    if (strcmp(name, "inverse_on_surface") == 0) return r->inverse_on_surface;
    if (strcmp(name, "inverse_primary") == 0) return r->inverse_primary;
    if (strcmp(name, "shadow") == 0) return r->shadow;
    if (strcmp(name, "scrim") == 0) return r->scrim;
    if (name[0] == '#' && strlen(name) == 7) return name;
    return NULL;
}

static bool eval_template_expr(const ThemeRoles *r, const char *raw_expr, char out[64]) {
    char buf[256];
    snprintf(buf, sizeof(buf), "%s", raw_expr);

    char *saveptr = NULL;
    char *tok = strtok_r(buf, "|", &saveptr);
    if (!tok) return false;

    char *var_name = trim_ws(tok);
    const char *init_val = resolve_template_var(r, var_name);
    if (!init_val) return false;

    snprintf(out, 64, "%s", init_val);
    bool stripped = false;

    while ((tok = strtok_r(NULL, "|", &saveptr)) != NULL) {
        char *f = trim_ws(tok);
        if (strcmp(f, "strip") == 0) {
            if (out[0] == '#') {
                memmove(out, out + 1, strlen(out));
            }
            stripped = true;
        } else if (strncmp(f, "lighten(", 8) == 0) {
            double amt = atof(f + 8);
            char hex_in[8], hex_out[8];
            snprintf(hex_in, sizeof(hex_in), "%s%s", out[0] == '#' ? "" : "#", out);
            hex_mix(hex_in, "#ffffff", clamp_d(amt, 0.0, 1.0), hex_out);
            snprintf(out, 64, "%s", stripped ? hex_out + 1 : hex_out);
        } else if (strncmp(f, "darken(", 7) == 0) {
            double amt = atof(f + 7);
            char hex_in[8], hex_out[8];
            snprintf(hex_in, sizeof(hex_in), "%s%s", out[0] == '#' ? "" : "#", out);
            hex_mix(hex_in, "#000000", clamp_d(amt, 0.0, 1.0), hex_out);
            snprintf(out, 64, "%s", stripped ? hex_out + 1 : hex_out);
        } else if (strncmp(f, "blend(", 6) == 0) {
            char args[128];
            snprintf(args, sizeof(args), "%s", f + 6);
            char *rparen = strchr(args, ')');
            if (rparen) *rparen = '\0';
            char *comma = strchr(args, ',');
            double weight = 0.5;
            if (comma) {
                *comma = '\0';
                weight = atof(comma + 1);
            }
            char *other_name = trim_ws(args);
            const char *other_val = resolve_template_var(r, other_name);
            if (other_val && other_val[0] == '#') {
                char hex_in[8], hex_out[8];
                snprintf(hex_in, sizeof(hex_in), "%s%s", out[0] == '#' ? "" : "#", out);
                hex_mix(hex_in, other_val, clamp_d(weight, 0.0, 1.0), hex_out);
                snprintf(out, 64, "%s", stripped ? hex_out + 1 : hex_out);
            }
        }
    }
    return true;
}

static char *render_template_content(const ThemeRoles *r, const char *tpl) {
    size_t tpl_len = strlen(tpl);
    size_t cap = tpl_len * 2 + 256;
    char *out = malloc(cap);
    if (!out) return NULL;
    size_t len = 0;

    const char *p = tpl;
    while (*p) {
        if (p[0] == '{' && p[1] == '{') {
            const char *end = strstr(p + 2, "}}");
            if (end && (end - (p + 2)) < 200) {
                char expr[256];
                size_t elen = (size_t)(end - (p + 2));
                memcpy(expr, p + 2, elen);
                expr[elen] = '\0';

                char val[64];
                if (eval_template_expr(r, expr, val)) {
                    size_t vlen = strlen(val);
                    if (len + vlen + 1 >= cap) {
                        cap = (cap + vlen) * 2;
                        char *nb = realloc(out, cap);
                        if (!nb) { free(out); return NULL; }
                        out = nb;
                    }
                    memcpy(out + len, val, vlen);
                    len += vlen;
                    p = end + 2;
                    continue;
                }
            }
        }
        if (len + 2 >= cap) {
            cap *= 2;
            char *nb = realloc(out, cap);
            if (!nb) { free(out); return NULL; }
            out = nb;
        }
        out[len++] = *p++;
    }
    out[len] = '\0';
    return out;
}

static bool extract_toml_quoted(const char *line, const char *field, char *out, size_t out_sz) {
    const char *p = strstr(line, field);
    while (p) {
        const char *after = p + strlen(field);
        while (*after == ' ' || *after == '\t') after++;
        if (*after == '=') {
            after++;
            while (*after == ' ' || *after == '\t') after++;
            char quote = (*after == '"' || *after == '\'') ? *after : '\0';
            if (quote) {
                after++;
                const char *end = strchr(after, quote);
                if (end) {
                    size_t len = (size_t)(end - after);
                    if (len >= out_sz) len = out_sz - 1;
                    memcpy(out, after, len);
                    out[len] = '\0';
                    return true;
                }
            }
        }
        p = strstr(p + 1, field);
    }
    return false;
}

static void expand_home_path(const char *raw, char out[BUF_PATH]) {
    if (raw[0] == '~' && raw[1] == '/') {
        snprintf(out, BUF_PATH, "%.*s/%.*s", 2048, g_home, 2048, raw + 2);
    } else {
        snprintf(out, BUF_PATH, "%.*s", BUF_PATH - 1, raw);
    }
}

static bool render_configured_templates(const ThemeRoles *r) {
    port_wallust_templates(false);

    char *conf = read_file_str(g_theme_config);
    if (!conf) return false;

    int rendered_count = 0;
    bool in_templates = false;
    char *saveptr = NULL;

    for (char *line = strtok_r(conf, "\n", &saveptr); line; line = strtok_r(NULL, "\n", &saveptr)) {
        char *trimmed = trim_ws(line);
        if (trimmed[0] == '#' || trimmed[0] == '\0') continue;
        if (trimmed[0] == '[') {
            in_templates = (strncmp(trimmed, "[templates]", 11) == 0);
            continue;
        }
        if (!in_templates) continue;

        char tpl_name[256] = {0}, raw_target[BUF_PATH] = {0};
        if (extract_toml_quoted(trimmed, "template", tpl_name, sizeof(tpl_name)) &&
            extract_toml_quoted(trimmed, "target", raw_target, sizeof(raw_target))) {
            char tpl_path[BUF_PATH + 256], target_path[BUF_PATH];
            snprintf(tpl_path, sizeof(tpl_path), "%s/%s", g_theme_templates_dir, tpl_name);
            expand_home_path(raw_target, target_path);

            char *tpl_str = read_file_str(tpl_path);
            if (!tpl_str) continue;
            char *rendered = render_template_content(r, tpl_str);
            if (rendered) {
                if (atomic_write(target_path, rendered)) {
                    rendered_count++;
                }
                free(rendered);
            }
            free(tpl_str);
        }
    }
    free(conf);
    return rendered_count > 0;
}

// ============================================================================
// 5. STATE & SYSTEM INTEGRATION
// ============================================================================

static void read_mode(char out[16]) {
    char *txt = read_file_str(g_mode_file);
    if (!txt) {
        strcpy(out, "dark");
        return;
    }
    for (char *p = txt; *p; p++) {
        if (*p == '\n' || *p == '\r' || *p == ' ') { *p = '\0'; break; }
    }
    if (strcmp(txt, "dark") == 0 || strcmp(txt, "light") == 0) {
        snprintf(out, 16, "%s", txt);
    } else {
        strcpy(out, "dark");
    }
    free(txt);
}

static void save_mode(const char *mode) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%s\n", mode);
    atomic_write(g_mode_file, buf);
}

static bool run_cmd(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return false;
    if (pid == 0) {
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execvp(argv[0], argv);
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static char *run_cmd_capture(const char *cmd) {
    FILE *fp = popen(cmd, "r");
    if (!fp) return NULL;
    size_t cap = 4096, len = 0;
    char *buf = malloc(cap);
    if (!buf) { pclose(fp); return NULL; }
    size_t n;
    while ((n = fread(buf + len, 1, cap - len - 1, fp)) > 0) {
        len += n;
        if (len + 1 >= cap) {
            cap *= 2;
            char *nb = realloc(buf, cap);
            if (!nb) { free(buf); pclose(fp); return NULL; }
            buf = nb;
        }
    }
    buf[len] = '\0';
    pclose(fp);
    return buf;
}

// Flip the GTK / libadwaita / portal appearance.
//
// IMPORTANT: this must run AFTER every template file has been written to disk.
// GTK reloads gtk.css the instant these keys change; if the files are still
// stale at that moment the apps render the PREVIOUS theme ("one step behind").
//
// gtk-theme goes first, color-scheme goes LAST: color-scheme is the key that
// libadwaita and xdg-desktop-portal react to, so it is the final trigger.
static void set_desktop_preference(const char *mode) {
    bool is_dark = (strcmp(mode, "dark") == 0);
    const char *cs    = is_dark ? "prefer-dark" : "prefer-light";
    const char *gtk_t = is_dark ? "Adwaita-dark" : "Adwaita";

    char *args_gtk[] = {"gsettings", "set", "org.gnome.desktop.interface",
                        "gtk-theme", (char *)gtk_t, NULL};
    run_cmd(args_gtk);

    char *args_cs[] = {"gsettings", "set", "org.gnome.desktop.interface",
                       "color-scheme", (char *)cs, NULL};
    run_cmd(args_cs);
}

static bool query_wallpaper(char out[PATH_MAX]) {
    out[0] = '\0';
    char *json = run_cmd_capture("awww query json 2>/dev/null");
    if (json && json[0]) {
        const char *img = strstr(json, "\"image\"");
        if (img) {
            const char *colon = strchr(img, ':');
            if (colon) {
                const char *q1 = strchr(colon, '"');
                if (q1) {
                    q1++;
                    const char *q2 = strchr(q1, '"');
                    if (q2) {
                        size_t len = (size_t)(q2 - q1);
                        if (len < PATH_MAX) {
                            memcpy(out, q1, len);
                            out[len] = '\0';
                        }
                    }
                }
            }
        }
    }
    if (json) free(json);
    if (out[0] && access(out, R_OK) == 0) return true;

    char *txt = run_cmd_capture("awww query 2>/dev/null");
    if (txt) {
        const char *p = strstr(txt, "image: ");
        if (p) {
            p += 7;
            while (*p == ' ') p++;
            const char *nl = strpbrk(p, "\r\n");
            size_t len = nl ? (size_t)(nl - p) : strlen(p);
            if (len < PATH_MAX) {
                memcpy(out, p, len);
                out[len] = '\0';
            }
        }
        free(txt);
    }
    return out[0] && access(out, R_OK) == 0;
}

static void touch_inplace_for_gio(const char *path) {
    char *content = read_file_str(path);
    if (!content) return;
    int fd = open(path, O_WRONLY | O_TRUNC);
    if (fd >= 0) {
        size_t len = strlen(content);
        ssize_t wr = write(fd, content, len);
        (void)wr;
        close(fd);
    }
    free(content);
}

static void reload_ghostty_instances(void) {
    DIR *d = opendir("/proc");
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] < '1' || ent->d_name[0] > '9') continue;
        pid_t pid = (pid_t)atoi(ent->d_name);
        if (pid <= 0) continue;

        char comm_path[128];
        snprintf(comm_path, sizeof(comm_path), "/proc/%d/comm", (int)pid);
        FILE *f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[64] = {0};
        if (fgets(comm, sizeof(comm), f)) {
            if (strncmp(comm, "ghostty", 7) == 0 && (comm[7] == '\n' || comm[7] == '\0')) {
                kill(pid, SIGUSR2);
            }
        }
        fclose(f);
    }
    closedir(d);
}

// Terminate any stale update_theme watch daemon running an older/deleted binary
// and spawn a fresh watcher if one was replaced.
static void cleanup_stale_watchers(void) {
    struct stat self_st;
    bool have_self = (stat("/proc/self/exe", &self_st) == 0);
    pid_t my_pid = getpid();
    bool killed_stale_watcher = false;

    DIR *d = opendir("/proc");
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] < '1' || ent->d_name[0] > '9') continue;
        pid_t pid = (pid_t)atoi(ent->d_name);
        if (pid <= 0 || pid == my_pid) continue;

        char comm_path[128];
        snprintf(comm_path, sizeof(comm_path), "/proc/%d/comm", (int)pid);
        FILE *f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[64] = {0};
        bool is_ut = (fgets(comm, sizeof(comm), f) && strncmp(comm, "update_theme", 12) == 0);
        fclose(f);
        if (!is_ut) continue;

        char exe_link[128], exe_target[PATH_MAX];
        snprintf(exe_link, sizeof(exe_link), "/proc/%d/exe", (int)pid);
        ssize_t rlen = readlink(exe_link, exe_target, sizeof(exe_target) - 1);
        bool is_deleted = false;
        if (rlen > 0) {
            exe_target[rlen] = '\0';
            if (strstr(exe_target, "(deleted)") != NULL) is_deleted = true;
        }

        struct stat pst;
        bool diff_inode = (have_self && stat(exe_link, &pst) == 0 && pst.st_ino != self_st.st_ino);

        if (is_deleted || diff_inode) {
            kill(pid, SIGTERM);
            killed_stale_watcher = true;
        }
    }
    closedir(d);

    if (killed_stale_watcher) {
        pid_t pid = fork();
        if (pid == 0) {
            setsid();
            int devnull = open("/dev/null", O_RDWR);
            if (devnull >= 0) {
                dup2(devnull, STDIN_FILENO);
                dup2(devnull, STDOUT_FILENO);
                dup2(devnull, STDERR_FILENO);
                close(devnull);
            }
            char bin_path[BUF_PATH];
            snprintf(bin_path, sizeof(bin_path), "%s/.local/bin/update_theme", g_home);
            execl(bin_path, bin_path, "watch", (char *)NULL);
            _exit(0);
        }
    }
}

static void notify_clients(void) {
    char colors_css[BUF_PATH], style_path[BUF_PATH];
    snprintf(colors_css, sizeof(colors_css), "%s/.config/waybar/colors.css", g_home);
    snprintf(style_path, sizeof(style_path), "%s/.config/waybar/style.css", g_home);
    touch_inplace_for_gio(colors_css);
    touch_inplace_for_gio(style_path);

    reload_ghostty_instances();

    // Quickshell watches the generated palette file. Ask it to reload now so
    // the bar, popups, launcher and native notification cards update together.
    char *args2[] = {"quickshell", "ipc", "call", "theme", "reload", NULL};
    run_cmd(args2);

    char *args3[] = {"hyprctl", "reload", NULL};
    run_cmd(args3);

    char *args4[] = {"spotifast", "reload-themes", NULL};
    run_cmd(args4);

    char *args5[] = {"vicinae", "theme", "set", "vercel-geist", NULL};
    run_cmd(args5);
}

static bool generate_vercel_theme(const char *wallpaper, const char *mode) {
    char key[64];
    compute_cache_key(wallpaper, mode, key);
    if (!key[0]) return false;

    ThemeRoles roles;
    bool from_cache = load_cached_roles(key, &roles);
    if (!from_cache) {
        build_roles(wallpaper, mode, &roles);
        snprintf(roles._cache_key, sizeof(roles._cache_key), "%s", key);
        save_cached_roles(&roles);
    }

    char scheme_path[BUF_PATH + 128];
    if (!write_vercel_scheme(&roles, scheme_path)) {
        return false;
    }

    if (!render_configured_templates(&roles)) {
        fprintf(stderr, "[theme] Failed to render templates from %s\n", g_theme_config);
        return false;
    }

    printf("[theme] Vercel Geist %s (templates: %s), accent %s, bg %s%s\n",
           mode, g_theme_dir, roles.primary, roles.background, from_cache ? " (cached)" : "");
    return true;
}

// Order of operations matters:
//   1. render every file to disk
//   2. notify the non-GTK clients
//   3. flip GSettings LAST so GTK apps reload up-to-date files
static bool apply_theme(const char *wallpaper, const char *mode, bool force) {
    // Cache hit: files on disk already match (wallpaper, mode); just re-assert prefs.
    if (!force && wallpaper && wallpaper[0] && access(g_theme_config, R_OK) == 0) {
        char key[64] = {0};
        compute_cache_key(wallpaper, mode, key);
        ThemeRoles cached;
        if (key[0] && load_cached_roles(key, &cached)) {
            set_desktop_preference(mode);
            return true;
        }
    }

    if (!wallpaper || !wallpaper[0]) {
        printf("[theme] %s mode saved. No active awww image; wallpaper-based Vercel palette will apply when one appears.\n", mode);
        set_desktop_preference(mode);
        return true;
    }

    if (access(wallpaper, R_OK) != 0) {
        fprintf(stderr, "[theme] Wallpaper not found: %s\n", wallpaper);
        set_desktop_preference(mode);
        return false;
    }

    bool ok = generate_vercel_theme(wallpaper, mode);   // 1. files on disk
    if (ok) {
        notify_clients();                               // 2. other clients
    }
    set_desktop_preference(mode);                       // 3. GTK trigger, LAST
    return ok;
}

static int acquire_lock(const char *path, bool blocking) {
    mkdir_parent(path);
    int fd = open(path, O_CREAT | O_RDWR, 0644);
    if (fd < 0) return -1;
    int flags = LOCK_EX | (blocking ? 0 : LOCK_NB);
    if (flock(fd, flags) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static bool apply_current(const char *explicit_wp, bool force) {
    cleanup_stale_watchers();
    int lock_fd = acquire_lock(g_apply_lock, true);

    char mode[16];
    read_mode(mode);

    char wp[PATH_MAX] = {0};
    if (explicit_wp && explicit_wp[0]) {
        if (!realpath(explicit_wp, wp)) snprintf(wp, sizeof(wp), "%s", explicit_wp);
    } else {
        query_wallpaper(wp);
    }

    bool ok = apply_theme(wp[0] ? wp : NULL, mode, force);
    if (lock_fd >= 0) close(lock_fd);
    return ok;
}

static int select_mode(const char *cmd) {
    cleanup_stale_watchers();
    int lock_fd = acquire_lock(g_apply_lock, true);

    char current[16], mode[16];
    read_mode(current);

    if (strcmp(cmd, "toggle") == 0) {
        strcpy(mode, strcmp(current, "light") == 0 ? "dark" : "light");
    } else {
        snprintf(mode, sizeof(mode), "%s", cmd);
    }

    save_mode(mode);
    printf("[theme] Saved appearance: %s\n", mode);

    char wp[PATH_MAX] = {0};
    query_wallpaper(wp);
    bool ok = apply_theme(wp[0] ? wp : NULL, mode, true);
    if (lock_fd >= 0) close(lock_fd);
    return ok ? 0 : 1;
}

static int watch_loop(void) {
    cleanup_stale_watchers();
    int wlock = acquire_lock(g_watch_lock, false);
    if (wlock < 0) {
        printf("[theme] A wallpaper watcher is already running.\n");
        return 0;
    }

    printf("[theme] Watching wallpaper and saved Vercel light/dark mode.\n");
    fflush(stdout);

    struct stat self_st;
    bool have_self = (stat("/proc/self/exe", &self_st) == 0);
    char bin_path[BUF_PATH];
    snprintf(bin_path, sizeof(bin_path), "%s/.local/bin/update_theme", g_home);

    char prev_sig[BUF_PATH] = {0};
    while (1) {
        struct stat disk_st;
        if (have_self && stat(bin_path, &disk_st) == 0 && disk_st.st_ino != self_st.st_ino) {
            close(wlock);
            execl(bin_path, bin_path, "watch", (char *)NULL);
        }

        char wp[PATH_MAX] = {0};
        bool has_wp = query_wallpaper(wp);
        bool ok = true;
        char sig[BUF_PATH] = {0};

        int alock = acquire_lock(g_apply_lock, true);
        char mode[16];
        read_mode(mode);

        if (!has_wp) {
            snprintf(sig, sizeof(sig), "NONE|%s", mode);
        } else {
            compute_cache_key(wp, mode, sig);
        }

        if (sig[0] && strcmp(sig, prev_sig) != 0) {
            ok = apply_theme(has_wp ? wp : NULL, mode, false);
            snprintf(prev_sig, sizeof(prev_sig), "%s", sig);
        }
        if (alock >= 0) close(alock);

        if (!ok) sleep(5);
        usleep(1000000); // 1.0s poll
    }
    close(wlock);
    return 0;
}

int main(int argc, char **argv) {
    init_paths();

    const char *cmd = "status";
    const char *extra = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--toggle") == 0) {
            return select_mode("toggle");
        } else if (strcmp(argv[i], "--set-mode") == 0 && i + 1 < argc) {
            return select_mode(argv[i + 1]);
        } else if (argv[i][0] != '-') {
            if (strcmp(cmd, "status") == 0 && i == 1) cmd = argv[i];
            else if (!extra) extra = argv[i];
        }
    }

    if (strcmp(cmd, "toggle") == 0 || strcmp(cmd, "light") == 0 || strcmp(cmd, "dark") == 0) {
        return select_mode(cmd);
    }

    if (strcmp(cmd, "status") == 0) {
        char mode[16];
        read_mode(mode);
        printf("%s\n", mode);
        return 0;
    }

    if (strcmp(cmd, "info") == 0) {
        char mode[16];
        read_mode(mode);
        printf("%s (Vercel Geist Adaptive, config: ~/.config/theme)\n", mode);
        return 0;
    }

    if (strcmp(cmd, "setup") == 0) {
        port_wallust_templates(false);
        printf("[theme] Initialized %s\n", g_theme_dir);
        return 0;
    }

    if (strcmp(cmd, "import-wallust") == 0) {
        port_wallust_templates(true);
        printf("[theme] Ported wallust templates and config into %s\n", g_theme_dir);
        return apply_current(extra, true) ? 0 : 1;
    }

    if (strcmp(cmd, "watch") == 0) {
        return watch_loop();
    }

    if (strcmp(cmd, "apply") == 0) {
        return apply_current(extra, true) ? 0 : 1;
    }

    if (access(cmd, R_OK) == 0) {
        if (extra && (strcmp(extra, "light") == 0 || strcmp(extra, "dark") == 0 || strcmp(extra, "vercel") == 0)) {
            fprintf(stderr, "[theme] Ignoring legacy per-wallpaper mode argument; preserving the saved preference.\n");
        }
        return apply_current(cmd, true) ? 0 : 1;
    }

    fprintf(stderr, "Unknown command or image file: %s\n", cmd);
    return 2;
}
