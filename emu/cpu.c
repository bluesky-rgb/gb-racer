/* SM83 CPU. Every bus access advances the rest of the machine by one M-cycle
 * first, so peripherals observe reads/writes at the correct cycle. */
#include "gb.h"

#define FZ 0x80
#define FN 0x40
#define FH 0x20
#define FC 0x10

#define A (c->r[R_A])
#define F (c->r[R_F])
#define B (c->r[R_B])
#define C (c->r[R_C])
#define D (c->r[R_D])
#define E (c->r[R_E])
#define H (c->r[R_H])
#define L (c->r[R_L])

static inline uint8_t rd(GB *g, uint16_t a) { gb_tick(g); return gb_read(g, a); }
static inline void wr(GB *g, uint16_t a, uint8_t v) { gb_tick(g); gb_write(g, a, v); }
static inline void idle(GB *g) { gb_tick(g); }

static inline uint8_t imm8(GB *g) { return rd(g, g->cpu.pc++); }
static inline uint16_t imm16(GB *g) { uint8_t lo = imm8(g); return (uint16_t)(lo | (imm8(g) << 8)); }

static inline uint16_t get_bc(GBCpu *c) { return (uint16_t)(B << 8 | C); }
static inline uint16_t get_de(GBCpu *c) { return (uint16_t)(D << 8 | E); }
static inline uint16_t get_hl(GBCpu *c) { return (uint16_t)(H << 8 | L); }
static inline void set_bc(GBCpu *c, uint16_t v) { B = (uint8_t)(v >> 8); C = (uint8_t)v; }
static inline void set_de(GBCpu *c, uint16_t v) { D = (uint8_t)(v >> 8); E = (uint8_t)v; }
static inline void set_hl(GBCpu *c, uint16_t v) { H = (uint8_t)(v >> 8); L = (uint8_t)v; }

static inline void push16(GB *g, uint16_t v) {
    wr(g, --g->cpu.sp, (uint8_t)(v >> 8));
    wr(g, --g->cpu.sp, (uint8_t)v);
}
static inline uint16_t pop16(GB *g) {
    uint8_t lo = rd(g, g->cpu.sp++);
    return (uint16_t)(lo | (rd(g, g->cpu.sp++) << 8));
}

/* 16-bit register pair by 2-bit code: BC DE HL SP */
static uint16_t get_rp(GBCpu *c, int i) {
    switch (i) { case 0: return get_bc(c); case 1: return get_de(c); case 2: return get_hl(c); default: return c->sp; }
}
static void set_rp(GBCpu *c, int i, uint16_t v) {
    switch (i) { case 0: set_bc(c, v); break; case 1: set_de(c, v); break; case 2: set_hl(c, v); break; default: c->sp = v; }
}

static inline uint8_t get_r8(GB *g, int i) {
    GBCpu *c = &g->cpu;
    return i == 6 ? rd(g, get_hl(c)) : c->r[i];
}
static inline void set_r8(GB *g, int i, uint8_t v) {
    GBCpu *c = &g->cpu;
    if (i == 6) wr(g, get_hl(c), v); else c->r[i] = v;
}

static void alu(GBCpu *c, int op, uint8_t v) {
    uint8_t a = A;
    unsigned r;
    switch (op) {
    case 0: /* ADD */
        r = a + v;
        F = (uint8_t)(((r & 0xFF) ? 0 : FZ) | (((a & 15) + (v & 15)) > 15 ? FH : 0) | (r > 0xFF ? FC : 0));
        A = (uint8_t)r; break;
    case 1: { /* ADC */
        unsigned cy = (F & FC) ? 1 : 0;
        r = a + v + cy;
        F = (uint8_t)(((r & 0xFF) ? 0 : FZ) | (((a & 15) + (v & 15) + cy) > 15 ? FH : 0) | (r > 0xFF ? FC : 0));
        A = (uint8_t)r; break;
    }
    case 2: case 7: /* SUB, CP */
        r = (unsigned)(a - v);
        F = (uint8_t)(FN | ((r & 0xFF) ? 0 : FZ) | ((a & 15) < (v & 15) ? FH : 0) | (a < v ? FC : 0));
        if (op == 2) A = (uint8_t)r;
        break;
    case 3: { /* SBC */
        unsigned cy = (F & FC) ? 1 : 0;
        r = (unsigned)(a - v - cy);
        F = (uint8_t)(FN | ((r & 0xFF) ? 0 : FZ) | ((a & 15) < (v & 15) + cy ? FH : 0) | ((unsigned)a < (unsigned)v + cy ? FC : 0));
        A = (uint8_t)r; break;
    }
    case 4: A = a & v; F = (uint8_t)((A ? 0 : FZ) | FH); break;
    case 5: A = a ^ v; F = A ? 0 : FZ; break;
    case 6: A = a | v; F = A ? 0 : FZ; break;
    }
}

static inline uint8_t inc8(GBCpu *c, uint8_t v) {
    v++;
    F = (uint8_t)((F & FC) | (v ? 0 : FZ) | ((v & 15) == 0 ? FH : 0));
    return v;
}
static inline uint8_t dec8(GBCpu *c, uint8_t v) {
    v--;
    F = (uint8_t)((F & FC) | FN | (v ? 0 : FZ) | ((v & 15) == 15 ? FH : 0));
    return v;
}

static void add_hl(GBCpu *c, uint16_t v) {
    uint16_t hl = get_hl(c);
    unsigned r = hl + v;
    F = (uint8_t)((F & FZ) | (((hl & 0xFFF) + (v & 0xFFF)) > 0xFFF ? FH : 0) | (r > 0xFFFF ? FC : 0));
    set_hl(c, (uint16_t)r);
}

static uint16_t add_sp_e(GBCpu *c, int8_t e) {
    uint16_t sp = c->sp;
    F = (uint8_t)((((sp & 15) + ((uint8_t)e & 15)) > 15 ? FH : 0) | (((sp & 0xFF) + (uint8_t)e) > 0xFF ? FC : 0));
    return (uint16_t)(sp + e);
}

static inline bool cond(GBCpu *c, int i) {
    switch (i) { case 0: return !(F & FZ); case 1: return F & FZ; case 2: return !(F & FC); default: return F & FC; }
}

static uint8_t cb_shift(GBCpu *c, int op, uint8_t v) {
    uint8_t cy, r;
    switch (op) {
    case 0: cy = v >> 7; r = (uint8_t)(v << 1 | cy); break;                     /* RLC */
    case 1: cy = v & 1; r = (uint8_t)(v >> 1 | cy << 7); break;                 /* RRC */
    case 2: cy = v >> 7; r = (uint8_t)(v << 1 | ((F & FC) ? 1 : 0)); break;     /* RL */
    case 3: cy = v & 1; r = (uint8_t)(v >> 1 | ((F & FC) ? 0x80 : 0)); break;   /* RR */
    case 4: cy = v >> 7; r = (uint8_t)(v << 1); break;                          /* SLA */
    case 5: cy = v & 1; r = (uint8_t)((v >> 1) | (v & 0x80)); break;            /* SRA */
    case 6: cy = 0; r = (uint8_t)(v << 4 | v >> 4); break;                      /* SWAP */
    default: cy = v & 1; r = v >> 1; break;                                     /* SRL */
    }
    F = (uint8_t)((r ? 0 : FZ) | (cy ? FC : 0));
    return r;
}

static void exec_cb(GB *g) {
    GBCpu *c = &g->cpu;
    uint8_t op = imm8(g);
    int reg = op & 7, n = (op >> 3) & 7;
    switch (op >> 6) {
    case 0: set_r8(g, reg, cb_shift(c, n, get_r8(g, reg))); break;
    case 1: {
        uint8_t v = get_r8(g, reg);
        F = (uint8_t)((F & FC) | FH | ((v >> n) & 1 ? 0 : FZ));
        break;
    }
    case 2: set_r8(g, reg, (uint8_t)(get_r8(g, reg) & ~(1 << n))); break;
    default: set_r8(g, reg, (uint8_t)(get_r8(g, reg) | (1 << n))); break;
    }
}

static void daa(GBCpu *c) {
    unsigned a = A;
    if (F & FN) {
        if (F & FH) a = (a - 6) & 0xFF;
        if (F & FC) a -= 0x60;
    } else {
        if ((F & FH) || (a & 15) > 9) a += 6;
        if ((F & FC) || a > 0x9F) a += 0x60;
    }
    F = (uint8_t)(F & (FN | FC));
    if (a & 0x100) F |= FC;
    A = (uint8_t)a;
    if (!A) F |= FZ;
}

static void interrupt(GB *g) {
    GBCpu *c = &g->cpu;
    idle(g);
    idle(g);
    wr(g, --c->sp, (uint8_t)(c->pc >> 8));
    /* the vector is chosen after the high-byte push: a push that lands on IE can cancel it */
    uint8_t pend = g->ie & g->iflag & 0x1F;
    wr(g, --c->sp, (uint8_t)c->pc);
    uint16_t vec = 0;
    for (int i = 0; i < 5; i++) {
        if (pend & (1 << i)) { g->iflag &= (uint8_t)~(1 << i); vec = (uint16_t)(0x40 + i * 8); break; }
    }
    c->pc = vec;
    c->ime = false;
    idle(g);
}

void gb_cpu_step(GB *g) {
    GBCpu *c = &g->cpu;

    if (c->locked) { idle(g); return; }
    if (c->ime_pending && --c->ime_pending == 0) c->ime = true;

    if (c->halted) {
        idle(g);
        if (g->ie & g->iflag & 0x1F) c->halted = false;
        return;
    }
    if (c->ime && (g->ie & g->iflag & 0x1F)) { interrupt(g); return; }

    uint8_t op = rd(g, c->pc);
    if (c->halt_bug) c->halt_bug = false; else c->pc++;

    /* regular blocks first */
    if (op >= 0x40 && op < 0x80) {
        if (op == 0x76) { /* HALT */
            if (!c->ime && (g->ie & g->iflag & 0x1F)) {
                if (c->ime_pending) c->pc--; /* EI; HALT: the interrupt returns to the HALT */
                else c->halt_bug = true;
            } else c->halted = true;
            return;
        }
        if (op == 0x40) g->breakpoint = true;
        set_r8(g, (op >> 3) & 7, get_r8(g, op & 7));
        return;
    }
    if (op >= 0x80 && op < 0xC0) { alu(c, (op >> 3) & 7, get_r8(g, op & 7)); return; }

    switch (op) {
    case 0x00: break;
    case 0x10: imm8(g); break; /* STOP: treated as a 2-byte NOP */
    case 0x01: case 0x11: case 0x21: case 0x31: set_rp(c, op >> 4, imm16(g)); break;
    case 0x02: wr(g, get_bc(c), A); break;
    case 0x12: wr(g, get_de(c), A); break;
    case 0x22: { uint16_t hl = get_hl(c); wr(g, hl, A); set_hl(c, (uint16_t)(hl + 1)); break; }
    case 0x32: { uint16_t hl = get_hl(c); wr(g, hl, A); set_hl(c, (uint16_t)(hl - 1)); break; }
    case 0x0A: A = rd(g, get_bc(c)); break;
    case 0x1A: A = rd(g, get_de(c)); break;
    case 0x2A: { uint16_t hl = get_hl(c); A = rd(g, hl); set_hl(c, (uint16_t)(hl + 1)); break; }
    case 0x3A: { uint16_t hl = get_hl(c); A = rd(g, hl); set_hl(c, (uint16_t)(hl - 1)); break; }
    case 0x03: case 0x13: case 0x23: case 0x33: set_rp(c, op >> 4, (uint16_t)(get_rp(c, op >> 4) + 1)); idle(g); break;
    case 0x0B: case 0x1B: case 0x2B: case 0x3B: set_rp(c, op >> 4, (uint16_t)(get_rp(c, op >> 4) - 1)); idle(g); break;
    case 0x09: case 0x19: case 0x29: case 0x39: add_hl(c, get_rp(c, op >> 4)); idle(g); break;
    case 0x04: case 0x0C: case 0x14: case 0x1C: case 0x24: case 0x2C: case 0x34: case 0x3C: {
        int r = (op >> 3) & 7; set_r8(g, r, inc8(c, get_r8(g, r))); break;
    }
    case 0x05: case 0x0D: case 0x15: case 0x1D: case 0x25: case 0x2D: case 0x35: case 0x3D: {
        int r = (op >> 3) & 7; set_r8(g, r, dec8(c, get_r8(g, r))); break;
    }
    case 0x06: case 0x0E: case 0x16: case 0x1E: case 0x26: case 0x2E: case 0x36: case 0x3E:
        set_r8(g, (op >> 3) & 7, imm8(g)); break;
    case 0x07: { uint8_t cy = A >> 7; A = (uint8_t)(A << 1 | cy); F = cy ? FC : 0; break; }
    case 0x0F: { uint8_t cy = A & 1; A = (uint8_t)(A >> 1 | cy << 7); F = cy ? FC : 0; break; }
    case 0x17: { uint8_t cy = A >> 7; A = (uint8_t)(A << 1 | ((F & FC) ? 1 : 0)); F = cy ? FC : 0; break; }
    case 0x1F: { uint8_t cy = A & 1; A = (uint8_t)(A >> 1 | ((F & FC) ? 0x80 : 0)); F = cy ? FC : 0; break; }
    case 0x08: { uint16_t a = imm16(g); wr(g, a, (uint8_t)c->sp); wr(g, (uint16_t)(a + 1), (uint8_t)(c->sp >> 8)); break; }
    case 0x18: { int8_t e = (int8_t)imm8(g); c->pc = (uint16_t)(c->pc + e); idle(g); break; }
    case 0x20: case 0x28: case 0x30: case 0x38: {
        int8_t e = (int8_t)imm8(g);
        if (cond(c, (op >> 3) & 3)) { c->pc = (uint16_t)(c->pc + e); idle(g); }
        break;
    }
    case 0x27: daa(c); break;
    case 0x2F: A = (uint8_t)~A; F |= FN | FH; break;
    case 0x37: F = (uint8_t)((F & FZ) | FC); break;
    case 0x3F: F = (uint8_t)((F & FZ) | ((F & FC) ? 0 : FC)); break;

    case 0xC0: case 0xC8: case 0xD0: case 0xD8:
        idle(g);
        if (cond(c, (op >> 3) & 3)) { c->pc = pop16(g); idle(g); }
        break;
    case 0xC9: c->pc = pop16(g); idle(g); break;
    case 0xD9: c->pc = pop16(g); idle(g); c->ime = true; c->ime_pending = 0; break;
    case 0xC1: set_bc(c, pop16(g)); break;
    case 0xD1: set_de(c, pop16(g)); break;
    case 0xE1: set_hl(c, pop16(g)); break;
    case 0xF1: { uint16_t v = pop16(g); A = (uint8_t)(v >> 8); F = (uint8_t)(v & 0xF0); break; }
    case 0xC5: idle(g); push16(g, get_bc(c)); break;
    case 0xD5: idle(g); push16(g, get_de(c)); break;
    case 0xE5: idle(g); push16(g, get_hl(c)); break;
    case 0xF5: idle(g); push16(g, (uint16_t)(A << 8 | F)); break;
    case 0xC2: case 0xCA: case 0xD2: case 0xDA: {
        uint16_t a = imm16(g);
        if (cond(c, (op >> 3) & 3)) { c->pc = a; idle(g); }
        break;
    }
    case 0xC3: { uint16_t a = imm16(g); c->pc = a; idle(g); break; }
    case 0xE9: c->pc = get_hl(c); break;
    case 0xC4: case 0xCC: case 0xD4: case 0xDC: {
        uint16_t a = imm16(g);
        if (cond(c, (op >> 3) & 3)) { idle(g); push16(g, c->pc); c->pc = a; }
        break;
    }
    case 0xCD: { uint16_t a = imm16(g); idle(g); push16(g, c->pc); c->pc = a; break; }
    case 0xC7: case 0xCF: case 0xD7: case 0xDF: case 0xE7: case 0xEF: case 0xF7: case 0xFF:
        idle(g); push16(g, c->pc); c->pc = op & 0x38; break;
    case 0xC6: case 0xCE: case 0xD6: case 0xDE: case 0xE6: case 0xEE: case 0xF6: case 0xFE:
        alu(c, (op >> 3) & 7, imm8(g)); break;
    case 0xCB: exec_cb(g); break;
    case 0xE0: { uint8_t n = imm8(g); wr(g, (uint16_t)(0xFF00 | n), A); break; }
    case 0xF0: { uint8_t n = imm8(g); A = rd(g, (uint16_t)(0xFF00 | n)); break; }
    case 0xE2: wr(g, (uint16_t)(0xFF00 | C), A); break;
    case 0xF2: A = rd(g, (uint16_t)(0xFF00 | C)); break;
    case 0xEA: { uint16_t a = imm16(g); wr(g, a, A); break; }
    case 0xFA: { uint16_t a = imm16(g); A = rd(g, a); break; }
    case 0xE8: { int8_t e = (int8_t)imm8(g); c->sp = add_sp_e(c, e); idle(g); idle(g); break; }
    case 0xF8: { int8_t e = (int8_t)imm8(g); set_hl(c, add_sp_e(c, e)); idle(g); break; }
    case 0xF9: c->sp = get_hl(c); idle(g); break;
    case 0xF3: c->ime = false; c->ime_pending = 0; break;
    case 0xFB: if (!c->ime && !c->ime_pending) c->ime_pending = 2; break;
    default: c->locked = true; break; /* undefined opcode hangs the CPU */
    }
}
