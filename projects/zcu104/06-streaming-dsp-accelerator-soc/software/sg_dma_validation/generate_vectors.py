#!/usr/bin/env python3

from pathlib import Path

HERE = Path(__file__).resolve().parent
P06 = HERE.parent.parent
VEC = P06 / "tb" / "vectors"
OUT = HERE / "src" / "impulse128_vectors.h"

def read_hex(path):
    return [
        int(x.strip(), 16)
        for x in path.read_text().splitlines()
        if x.strip()
    ]

def signed16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v

inp = read_hex(VEC / "impulse_input.hex")
fir = read_hex(VEC / "impulse_fir_expected.hex")
energy = read_hex(VEC / "impulse_energy_expected.hex")
event = read_hex(VEC / "impulse_event_expected.hex")

assert len(inp) == 128
assert len(fir) == 128
assert len(energy) == 128
assert len(event) == 128

inp = [signed16(v) for v in inp]
fir = [signed16(v) for v in fir]

def array(name, ctype, values, formatter, per_line=8):
    lines = [f"static const {ctype} {name}[IMPULSE_SAMPLE_COUNT] = {{"]
    for i in range(0, len(values), per_line):
        chunk = values[i:i + per_line]
        lines.append(
            "    " + ", ".join(formatter(v) for v in chunk) + ","
        )
    lines.append("};")
    return "\n".join(lines)

text = f"""\
#ifndef PROJECT06_IMPULSE128_VECTORS_H
#define PROJECT06_IMPULSE128_VECTORS_H

#include <stdint.h>

#define IMPULSE_SAMPLE_COUNT 128U
#define IMPULSE_EXPECTED_EVENT_COUNT {sum(event)}U

{array("impulse_input", "int16_t", inp, lambda v: str(v))}

{array("impulse_fir_expected", "int16_t", fir, lambda v: str(v))}

{array(
    "impulse_energy_expected",
    "uint64_t",
    energy,
    lambda v: f"UINT64_C(0x{v:010X})",
    4
)}

{array(
    "impulse_event_expected",
    "uint8_t",
    event,
    lambda v: str(v)
)}

#endif
"""

OUT.write_text(text)
print(f"WROTE: {OUT}")
print(f"SAMPLES: {len(inp)}")
print(f"EXPECTED EVENTS: {sum(event)}")
