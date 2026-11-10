"""Tiny SM83 disassembler for debugging test ROMs. Usage: dis.py rom start end"""
import sys
R = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
RP = ["BC", "DE", "HL", "SP"]
RP2 = ["BC", "DE", "HL", "AF"]
CC = ["NZ", "Z", "NC", "C"]
ALU = ["ADD A,", "ADC A,", "SUB ", "SBC A,", "AND ", "XOR ", "OR ", "CP "]
ROT = ["RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL"]
MISC = {0x00: "NOP", 0x07: "RLCA", 0x0F: "RRCA", 0x17: "RLA", 0x1F: "RRA", 0x27: "DAA", 0x2F: "CPL", 0x37: "SCF",
        0x3F: "CCF", 0x76: "HALT", 0xC9: "RET", 0xD9: "RETI", 0xE9: "JP HL", 0xF9: "LD SP,HL", 0xF3: "DI", 0xFB: "EI",
        0x02: "LD (BC),A", 0x12: "LD (DE),A", 0x22: "LD (HL+),A", 0x32: "LD (HL-),A", 0x0A: "LD A,(BC)",
        0x1A: "LD A,(DE)", 0x2A: "LD A,(HL+)", 0x3A: "LD A,(HL-)", 0xE2: "LD (FF00+C),A", 0xF2: "LD A,(FF00+C)"}

def dis1(m, pc):
    op = m[pc]
    n8 = m[(pc + 1) & 0xFFFF]
    n16 = n8 | m[(pc + 2) & 0xFFFF] << 8
    rel = (pc + 2 + (n8 - 256 if n8 > 127 else n8)) & 0xFFFF
    if op in MISC: return MISC[op], 1
    if op == 0xCB:
        x, y, z = n8 >> 6, (n8 >> 3) & 7, n8 & 7
        return ([f"{ROT[y]} {R[z]}", f"BIT {y},{R[z]}", f"RES {y},{R[z]}", f"SET {y},{R[z]}"][x]), 2
    if 0x40 <= op < 0x80: return f"LD {R[(op >> 3) & 7]},{R[op & 7]}", 1
    if 0x80 <= op < 0xC0: return ALU[(op >> 3) & 7] + R[op & 7], 1
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    if x == 0:
        if z == 0:
            if y == 1: return f"LD (${n16:04X}),SP", 3
            if y == 2: return "STOP", 2
            if y == 3: return f"JR ${rel:04X}", 2
            return f"JR {CC[y - 4]},${rel:04X}", 2
        if z == 1: return (f"LD {RP[y >> 1]},${n16:04X}", 3) if not y & 1 else (f"ADD HL,{RP[y >> 1]}", 1)
        if z == 3: return ("INC " if not y & 1 else "DEC ") + RP[y >> 1], 1
        if z == 4: return f"INC {R[y]}", 1
        if z == 5: return f"DEC {R[y]}", 1
        if z == 6: return f"LD {R[y]},${n8:02X}", 2
    if x == 3:
        if z == 0:
            if y < 4: return f"RET {CC[y]}", 1
            return [f"LDH ($FF{n8:02X}),A", f"ADD SP,${n8:02X}", f"LDH A,($FF{n8:02X})", f"LD HL,SP+${n8:02X}"][y - 4], 2
        if z == 1: return f"POP {RP2[y >> 1]}", 1
        if z == 2:
            if y < 4: return f"JP {CC[y]},${n16:04X}", 3
            if y == 5: return f"LD (${n16:04X}),A", 3
            if y == 7: return f"LD A,(${n16:04X})", 3
        if z == 3 and y == 0: return f"JP ${n16:04X}", 3
        if z == 4 and y < 4: return f"CALL {CC[y]},${n16:04X}", 3
        if z == 5: return (f"PUSH {RP2[y >> 1]}", 1) if not y & 1 else (f"CALL ${n16:04X}", 3)
        if z == 6: return ALU[y] + f"${n8:02X}", 2
        if z == 7: return f"RST ${y * 8:02X}", 1
    return f"DB ${op:02X}", 1

def dis(m, start, end):
    pc = start
    out = []
    while pc < end:
        s, n = dis1(m, pc)
        if s == "NOP":
            k = 0
            while pc + k < end and m[pc + k] == 0: k += 1
            if k > 2:
                out.append(f"{pc:04X}: NOP x{k}"); pc += k; continue
        out.append(f"{pc:04X}: {' '.join(f'{m[pc + i]:02X}' for i in range(n)):<9} {s}")
        pc += n
    return "\n".join(out)

if __name__ == "__main__":
    data = open(sys.argv[1], "rb").read()
    print(dis(data, int(sys.argv[2], 16), int(sys.argv[3], 16)))
