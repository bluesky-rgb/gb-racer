/* PPU: dot-driven mode state machine with a line renderer that can be
 * caught up to the current beam position, so register writes take effect
 * at the pixel where they happen (mid-frame and mid-scanline effects). */
#include "gb.h"
#include <string.h>

/* Line timing (dots). Mode 2 is entered at dot 0 for interrupt purposes; the
 * STAT mode bits follow 4 dots later. Mode 3 starts at dot M3_START. */
#define M3_START 84
#define PIX_START (M3_START - 4 + 12) /* dot at which pixel 0 leaves the pixel pipeline */

static void stat_update(GB *g) {
    GBPpu *p = &g->ppu;
    /* the LY=LYC comparison result is frozen (and still drives the line) while the LCD is off */
    bool line = (p->stat & 0x40) && p->lyc_match;
    if (p->lcdc & 0x80) {
        if ((p->stat & 0x08) && p->imode == 0) line = true;
        if ((p->stat & 0x10) && p->imode == 1) line = true;
        if ((p->stat & 0x20) && p->imode == 2) line = true;
    }
    if (line && !p->stat_line) g->iflag |= GB_INT_STAT;
    p->stat_line = line;
}

bool ppu_oam_locked(const GB *g) {
    const GBPpu *p = &g->ppu;
    if (!(p->lcdc & 0x80)) return false;
    return p->mode == 2 || p->mode == 3 || p->imode == 2;
}

/* draw pixels [render_x, x1) of the current line with the registers as they are now */
static void render(GB *g, int x1) {
    GBPpu *p = &g->ppu;
    int x0 = p->render_x;
    if (x1 > GB_W) x1 = GB_W;
    if (x0 >= x1) return;
    p->render_x = x1;

    const uint8_t *vram = g->vram;
    uint8_t lcdc = p->lcdc;
    uint8_t *row = p->fb + p->line * GB_W;
    bool win_on = (lcdc & 0x20) && p->wy_trig && p->wx <= 166;
    int win_x0 = (int)p->wx - 7;
    int sprh = (lcdc & 4) ? 16 : 8;

    for (int x = x0; x < x1; x++) {
        uint8_t bgc = 0;
        bool in_win = win_on && x >= win_x0;
        if (in_win) p->win_drawn = true;
        if (lcdc & 1) {
            int xx, yy;
            unsigned map;
            if (in_win) { xx = x - win_x0; yy = p->win_line; map = (lcdc & 0x40) ? 0x1C00 : 0x1800; }
            else { xx = (x + p->scx) & 255; yy = (p->line + p->scy) & 255; map = (lcdc & 0x08) ? 0x1C00 : 0x1800; }
            uint8_t tile = vram[map + ((yy >> 3) & 31) * 32 + ((xx >> 3) & 31)];
            unsigned addr = (lcdc & 0x10) ? (unsigned)tile * 16 : (unsigned)(0x1000 + (int8_t)tile * 16);
            addr += (unsigned)(yy & 7) * 2;
            int bit = 7 - (xx & 7);
            bgc = (uint8_t)(((vram[addr + 1] >> bit) & 1) << 1 | ((vram[addr] >> bit) & 1));
        }
        uint8_t shade = (p->bgp >> (bgc * 2)) & 3;

        if ((lcdc & 2) && p->nspr) {
            int best_x = 256;
            uint8_t best_c = 0, best_attr = 0;
            for (int i = 0; i < p->nspr; i++) {
                const uint8_t *o = &g->oam[p->spr[i] * 4];
                int sx = (int)o[1] - 8;
                if (x < sx || x >= sx + 8 || o[1] >= best_x) continue;
                int sy = p->line - ((int)o[0] - 16);
                if (sy < 0 || sy >= sprh) continue;
                uint8_t attr = o[3];
                if (attr & 0x40) sy = sprh - 1 - sy;
                unsigned tile = o[2];
                if (sprh == 16) tile &= 0xFE;
                unsigned addr = tile * 16 + (unsigned)sy * 2;
                int bit = (attr & 0x20) ? (x - sx) : 7 - (x - sx);
                uint8_t col = (uint8_t)(((vram[addr + 1] >> bit) & 1) << 1 | ((vram[addr] >> bit) & 1));
                if (!col) continue;
                best_x = o[1]; best_c = col; best_attr = attr;
            }
            if (best_c && !((best_attr & 0x80) && bgc)) {
                uint8_t pal = (best_attr & 0x10) ? p->obp1 : p->obp0;
                shade = (pal >> (best_c * 2)) & 3;
            }
        }
        row[x] = shade;
    }
}

/* bring the line up to date with the beam before a register changes */
static void catch_up(GB *g) {
    GBPpu *p = &g->ppu;
    if ((p->lcdc & 0x80) && (p->mode == 3 || p->imode == 3) && p->line < GB_H)
        render(g, p->dot - PIX_START - (p->scx & 7));
}

static void oam_scan(GB *g) {
    GBPpu *p = &g->ppu;
    int h = (p->lcdc & 4) ? 16 : 8;
    p->nspr = 0;
    for (int i = 0; i < 40 && p->nspr < 10; i++) {
        int y = g->oam[i * 4];
        int ly16 = p->line + 16;
        if (ly16 >= y && ly16 < y + h) p->spr[p->nspr++] = (uint8_t)i;
    }
}

/* mode 3 duration: 172 dots plus fine-scroll, window and per-object penalties */
static int mode3_length(GB *g) {
    GBPpu *p = &g->ppu;
    int len = 172 + (p->scx & 7);
    if ((p->lcdc & 0x20) && p->wy_trig && p->wx <= 166) len += 6;
    if ((p->lcdc & 2) && p->nspr) {
        uint8_t order[10];
        int n = p->nspr;
        for (int i = 0; i < n; i++) order[i] = p->spr[i];
        for (int i = 1; i < n; i++) { /* stable insertion sort by X */
            uint8_t s = order[i];
            int j = i;
            while (j > 0 && g->oam[order[j - 1] * 4 + 1] > g->oam[s * 4 + 1]) { order[j] = order[j - 1]; j--; }
            order[j] = s;
        }
        uint32_t seen = 0;
        for (int i = 0; i < n; i++) {
            int x = g->oam[order[i] * 4 + 1];
            if (x >= 168) continue;
            int pos = x ? x + (p->scx & 7) : 0; /* X=0 is unaffected by fine scroll */
            int tile = pos >> 3, off = pos & 7;
            if (!(seen & (1u << tile))) {
                seen |= 1u << tile;
                if (5 - off > 0) len += 5 - off;
            }
            len += 6;
        }
    }
    return len;
}

static void frame_done(GB *g) {
    GBPpu *p = &g->ppu;
    if (p->skip_frame) { memset(p->front, 0, sizeof p->front); p->skip_frame = false; }
    else memcpy(p->front, p->fb, sizeof p->front);
    g->frame_ready = true;
}

static void ppu_dot(GB *g) {
    GBPpu *p = &g->ppu;
    if (++p->dot == 456) {
        p->dot = 0;
        if (p->line < GB_H) {
            if (p->win_drawn) p->win_line++;
            p->win_drawn = false;
        }
        p->first_line = false;
        if (++p->line == 154) { p->line = 0; p->win_line = 0; p->wy_trig = false; }
        if (p->line != 0) { p->ly = (uint8_t)p->line; p->lyc_match = false; }
        if (p->line < GB_H && p->line != 0) { p->imode = 2; p->mode = 0; }
        stat_update(g);
        return;
    }

    int d = p->dot;
    if (p->line < GB_H) {
        if (d == 4) {
            if (!p->first_line) { p->mode = 2; p->imode = 2; }
            p->lyc_match = p->ly == p->lyc;
            if (p->ly == p->wy) p->wy_trig = true;
            stat_update(g);
        } else if (d == M3_START - 4 && !p->first_line) {
            /* drawing starts (VRAM locks) one M-cycle before STAT reports mode 3 */
            if (p->ly == p->wy) p->wy_trig = true;
            oam_scan(g);
            p->imode = 3;
            p->render_x = 0;
            p->mode3_end = M3_START - 4 + mode3_length(g);
            stat_update(g);
        } else if (d == M3_START) {
            p->mode = 3;
            if (p->first_line) {
                if (p->ly == p->wy) p->wy_trig = true;
                oam_scan(g);
                p->imode = 3;
                p->render_x = 0;
                p->mode3_end = M3_START - 4 + mode3_length(g);
                stat_update(g);
            }
        } else if (d == p->mode3_end) {
            /* HBlank: the interrupt source rises one dot before the STAT mode bits change */
            render(g, GB_W);
            p->imode = 0;
            stat_update(g);
        } else if (d == p->mode3_end + 1) {
            p->mode = 0;
        }
    } else if (p->line == 144) {
        if (d == 4) {
            p->mode = 1; p->imode = 1;
            p->lyc_match = p->ly == p->lyc;
            g->iflag |= GB_INT_VBLANK;
            /* the OAM source also fires at the start of VBlank */
            if ((p->stat & 0x20) && !p->stat_line) g->iflag |= GB_INT_STAT;
            stat_update(g);
            frame_done(g);
        }
    } else if (p->line == 153) {
        if (d == 4) { p->ly = 0; p->lyc_match = p->lyc == 153; stat_update(g); }
        else if (d == 8) { p->lyc_match = false; stat_update(g); }
        else if (d == 12) { p->lyc_match = p->lyc == 0; stat_update(g); }
    } else if (d == 4) {
        p->lyc_match = p->ly == p->lyc;
        stat_update(g);
    }
}

void ppu_tick(GB *g) {
    if (!(g->ppu.lcdc & 0x80)) return;
    ppu_dot(g); ppu_dot(g); ppu_dot(g); ppu_dot(g);
}

uint8_t ppu_read(GB *g, uint16_t a) {
    GBPpu *p = &g->ppu;
    switch (a) {
    case 0xFF40: return p->lcdc;
    case 0xFF41: return (uint8_t)(0x80 | p->stat | (p->lyc_match ? 4 : 0) | ((p->lcdc & 0x80) ? p->mode : 0));
    case 0xFF42: return p->scy;
    case 0xFF43: return p->scx;
    case 0xFF44: return p->ly;
    case 0xFF45: return p->lyc;
    case 0xFF47: return p->bgp;
    case 0xFF48: return p->obp0;
    case 0xFF49: return p->obp1;
    case 0xFF4A: return p->wy;
    case 0xFF4B: return p->wx;
    default: return 0xFF;
    }
}

void ppu_write(GB *g, uint16_t a, uint8_t v) {
    GBPpu *p = &g->ppu;
    catch_up(g);
    switch (a) {
    case 0xFF40: {
        uint8_t old = p->lcdc;
        p->lcdc = v;
        if ((old & 0x80) && !(v & 0x80)) {
            p->line = 0; p->dot = 0; p->ly = 0;
            p->mode = 0; p->imode = 0;
            p->win_line = 0; p->wy_trig = false; p->win_drawn = false;
            p->imode = 0xFF;
            stat_update(g);
            memset(p->fb, 0, sizeof p->fb);
        } else if (!(old & 0x80) && (v & 0x80)) {
            p->line = 0; p->dot = 4; p->ly = 0; /* the first line is 4 dots short */
            p->mode = 0; p->imode = 0xFF;
            p->first_line = true; p->skip_frame = true;
            p->render_x = 0; p->nspr = 0; p->mode3_end = -1;
            p->lyc_match = p->lyc == 0;
            stat_update(g);
        }
        break;
    }
    case 0xFF41:
        if (p->lcdc & 0x80) { /* DMG quirk: all sources are briefly enabled during the write */
            uint8_t keep = p->imode;
            if (p->imode == 2) p->imode = 0xFF;
            p->stat = 0x78; stat_update(g);
            p->imode = keep;
        }
        p->stat = v & 0x78;
        stat_update(g);
        break;
    case 0xFF42: p->scy = v; break;
    case 0xFF43: p->scx = v; break;
    case 0xFF44: break;
    case 0xFF45:
        p->lyc = v;
        if (p->lcdc & 0x80) {
            if (!(p->line != 0 && p->dot < 4)) {
                if (p->line == 153 && p->dot >= 4 && p->dot < 12) p->lyc_match = p->dot < 8 && v == 153;
                else p->lyc_match = p->ly == v;
            }
            stat_update(g);
        }
        break;
    case 0xFF47: p->bgp = v; break;
    case 0xFF48: p->obp0 = v; break;
    case 0xFF49: p->obp1 = v; break;
    case 0xFF4A: p->wy = v; break;
    case 0xFF4B: p->wx = v; break;
    default: break;
    }
}

void ppu_reset(GB *g) {
    GBPpu *p = &g->ppu;
    p->lcdc = 0x91; p->stat = 0x00;
    p->bgp = 0xFC; p->obp0 = 0xFF; p->obp1 = 0xFF;
    /* the boot ROM hands over during VBlank */
    p->line = 153; p->dot = 400; p->ly = 0;
    p->mode = 1; p->imode = 1;
    p->lyc_match = true;
    p->mode3_end = -1;
}
