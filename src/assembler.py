#!/usr/bin/env python3
import sys
import re
import os

# -----------------------------------------
# OPCODES  (3-bit in lowest bits)
# -----------------------------------------
OP = {
    "SET": 0x0,
    "LD":  0x1,
    "ST":  0x2,
    "AND": 0x3,
    "ADD": 0x4,
    "NOT": 0x5,
    "JP": 0x6,
    "CHG": 0x7,
}

# -----------------------------------------
# REGISTER MAP (upper nibble DI[7:4])
# -----------------------------------------
REG = {
    "PCL": 0x0,
    "PCH": 0x1,
    "A":   0x2,
    "B":   0x3,
    "C":   0x4,
    "D":   0x5,
    "POINTERL": 0x6,
    "POINTERH": 0x7,
    "STATUSL":  0x8,
    "STATUSH":  0x9,
    "IR":       0xA,
    "JUMPL":    0xC,
    "JUMPH":    0xD,
}

# allow R0–R15 as aliases
for i in range(16):
    REG[f"R{i}"] = i

# -----------------------------------------
# ASSEMBLER
# -----------------------------------------

def assemble_line(line, labels, pc):
    line = line.strip()

    if not line or line.startswith(";"):
        return []

    # Label-only line
    if line.endswith(":"):
        return []

    # split tokens
    parts = re.split(r"[,\s]+", line)
    instr = parts[0].upper()

    # -------------------------
    # SET A, imm8   --> 2 bytes
    # -------------------------
    if instr == "SET":
        regname = parts[1].upper()
        imm_token = parts[2]

        want_high = False

        # high/low suffix
        if len(parts) == 4:
            if parts[3].upper() == "H":
                want_high = True
            elif parts[3].upper() == "L":
                want_high = False
            else:
                raise ValueError(f"Invalid SET suffix: {parts[3]}")

        # number literal? 0x?? or decimal?
        if re.fullmatch(r"0x[0-9A-Fa-f]+", imm_token) or imm_token.isdigit():
            imm = int(imm_token, 0)
            if want_high:
                imm = (imm >> 8) & 0xFF
            else:
                imm = imm & 0xFF
        else:
            # it's a label – second pass will fix it
            imm = ("LABEL", imm_token, want_high)

        opcode = (REG[regname] << 4) | OP["SET"]
        return [opcode, imm]

    # -------------------------
    # JPZ label   → 1 byte
    # address loaded separately into JUMPL/JUMPH
    # -------------------------
    if instr == "JP":
        bitpos = int(parts[1], 0) & 0x07
        value = int(parts[2], 0) & 0x1
        opcode = OP["JP"]
        return [opcode | (value << 7) | (bitpos << 4)]

    # -------------------------
    # One-byte register operations:
    # LDA R
    # STA R
    # AND R
    # ADD R
    # NOT R
    # CHG R
    # -------------------------
    if instr in OP:
        regname = parts[1].upper()
        opcode = (REG[regname] << 4) | OP[instr]
        return [opcode]

    raise ValueError(f"Unknown instruction: {line}")


def assemble(source):
    lines = source.split("\n")

    # =================================
    # FIRST PASS – LABEL COLLECTION
    # =================================
    labels = {}
    pc = 0
    intermediate = []

    for line in lines:
        line = line.strip()

        if line.endswith(":"):
            lbl = line[:-1]
            labels[lbl] = pc
            intermediate.append([])
            continue

        result = assemble_line(line, labels, pc)
        for token in result:
            pc += 1
        intermediate.append(result)

    # =================================
    # SECOND PASS – FIXUP LABELS
    # =================================
    final = []
    pc = 0
    print("-------------------------------------")

    lcntr = 0

    for inst in intermediate:
        print(f"{pc:04X}: ", end="");
        bcntr = 0
        for item in inst:
            if isinstance(item, tuple) and item[0] == "LABEL":
                label = item[1]
                if label not in labels:
                    raise ValueError(f"Undefined label: {label}")
                addr = labels[label]
                if (item[2]):
                    v = (addr >> 8) & 0xFF
                else:
                    v = addr & 0xFF
                print(f"{v:02X} ", end="")
                final.append(v)        # low byte
                pc += 1
                bcntr += 1
            else:
                print(f"{item:02X} ", end="")
                final.append(item)
                pc += 1
                bcntr += 1
        if (bcntr > 0): 
            print(" " * (10 - bcntr * 3), end="")
        print(lines[lcntr].strip())
        lcntr = lcntr+1

    return final 

# -----------------------------------------
# CLI WRAPPER
# -----------------------------------------
if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: assembler.py file.asm")
        exit(1)

    with open(sys.argv[1]) as f:
        src = f.read()

    machine = assemble(src)

    #print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    #print(machine)

    #print("Assembled bytes:")
    #for i, b in enumerate(machine):
    #    print(f"{i:04X}: {b:02X}")
    # Write hex output
    out = os.path.splitext(sys.argv[1])[0] + ".hex"

    with open(out, "w") as f:
        for i in range(0, len(machine), 16):
            chunk = machine[i:i+16]
            line = " ".join(f"{b:02X}" for b in chunk)
            f.write(line + "\n")

    print(f"Done. Output written to: {out}")
