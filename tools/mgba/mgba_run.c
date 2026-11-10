/* Reference harness: drives mGBA's Game Boy core (through its public mCore API only)
 * so the same ROM + input log can be replayed there and compared with our emulator.
 * Protocol: for every byte read from stdin (key mask in our GB_KEY_* layout) run one
 * frame and write 160*144 shade bytes (0..3) to stdout. */
#include <mgba/flags.h>
#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/core/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void quiet(struct mLogger *l, int cat, enum mLogLevel lvl, const char *fmt, va_list args) {
    (void)l; (void)cat; (void)lvl; (void)fmt; (void)args;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: mgba_run rom.gb < keys > shades\n"); return 2; }
    static struct mLogger logger = { .log = quiet };
    mLogSetDefaultLogger(&logger);

    struct mCore *core = mCoreFind(argv[1]);
    if (!core || !core->init(core)) { fprintf(stderr, "no core\n"); return 1; }
    mCoreInitConfig(core, NULL);
    mCoreConfigSetOverrideValue(&core->config, "gb.model", "DMG");
    mCoreConfigSetOverrideValue(&core->config, "sgb.model", "DMG");
    mCoreConfigSetOverrideValue(&core->config, "cgb.model", "DMG");
    mCoreConfigSetOverrideIntValue(&core->config, "sgb.borders", 0);
    static const unsigned pal[4] = { 0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000 };
    for (int i = 0; i < 12; i++) {
        char key[16];
        snprintf(key, sizeof key, "gb.pal[%d]", i);
        mCoreConfigSetOverrideUIntValue(&core->config, key, pal[i & 3]);
    }
    unsigned w, h;
    core->baseVideoSize(core, &w, &h);
    mColor *video = calloc(w * h, sizeof *video);
    core->setVideoBuffer(core, video, w);
    if (!mCoreLoadFile(core, argv[1])) { fprintf(stderr, "cannot load %s\n", argv[1]); return 1; }
    core->loadConfig(core, &core->config);
    core->reset(core);

    unsigned char out[160 * 144];
    int c;
    while ((c = getchar()) != EOF) {
        /* ours: R L U D A B Sel Start  ->  mGBA: A B Sel Start R L U D */
        unsigned k = (unsigned)c;
        unsigned keys = ((k >> 4) & 0x0F) | ((k & 0x0F) << 4);
        core->setKeys(core, keys);
        core->runFrame(core);
        for (unsigned y = 0; y < 144; y++) {
            for (unsigned x = 0; x < 160; x++) {
                unsigned v = video[y * w + x] & 0xFF; /* stride is the base (SGB-sized) width */
                out[y * 160 + x] = (unsigned char)(3 - (v + 42) / 85);
            }
        }
        fwrite(out, 1, sizeof out, stdout);
        fflush(stdout);
    }
    return 0;
}
