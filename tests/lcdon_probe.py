import sys; sys.path.insert(0,'tools')
from gbpy import GB
path='/home/claude/ext/mgba/cinema/gb/mooneye-gb/acceptance/ppu/lcdon_timing-GS/test.gb'
rom=open(path,'rb').read()
tables={'LY':0x4AE1,'STAT0':0x4AFC,'STAT1':0x4B1F,'OAM':0x4B42,'VRAM':0x4B65}
names=list(tables)
gb=GB(rom); only_bad=len(sys.argv)>1
t0=None; res=[]; cur=[]
for i in range(3000000):
    pc=gb.pc()
    if pc==0x47F5: cur=[]
    op=rom[pc] if pc<0x8000 else 0
    l0=gb.peek(0xFF40)&0x80
    gb.step()
    if not l0 and gb.peek(0xFF40)&0x80: t0=gb.cycles()
    if op==0x1A and 0x47F0<=pc<0x4AE0 and t0 is not None:
        cur.append(((gb.cycles()-t0)//4, gb.reg(7)))
        if len(cur)==24: res.append(cur); cur=[]
    if len(res)==5 or gb.breakpoint(): break
for n,r in zip(names,res):
    exp=rom[tables[n]:tables[n]+24]
    print(n)
    for k,((cyc,v),e) in enumerate(zip(r,exp)):
        if only_bad and v==e: continue
        print(f"  cyc {cyc:5d} (line {cyc*4//456} dot {cyc*4%456:3d}) got {v:02X} exp {e:02X} {'' if v==e else '<<<<'}")
