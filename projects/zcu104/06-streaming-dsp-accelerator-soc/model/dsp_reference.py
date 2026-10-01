#!/usr/bin/env python3

"""
Project 06 - Streaming DSP Accelerator SoC
Bit-accurate fixed-point reference model

Author: Frank Ouma
"""

from collections import deque
import math
import random
from pathlib import Path

TAPS = 32
FRAC_BITS = 15
Q15_SCALE = 1 << FRAC_BITS

Q15_MIN = -(1 << 15)
Q15_MAX = (1 << 15) - 1

ENERGY_WINDOW = 64
ENERGY_MAX = 1 << 36

ROOT = Path(__file__).resolve().parents[1]
VECTOR_DIR = ROOT / "tb" / "vectors"


def saturate_q15(value: int) -> int:
    if value > Q15_MAX:
        return Q15_MAX
    if value < Q15_MIN:
        return Q15_MIN
    return value


def round_q30_to_q15(acc: int) -> int:
    """
    Convert signed integer with 30 fractional bits to
    signed Q1.15.

    Rounding:
        nearest, ties away from zero
    """
    half = 1 << (FRAC_BITS - 1)

    if acc >= 0:
        value = (acc + half) >> FRAC_BITS
    else:
        value = -(((-acc) + half) >> FRAC_BITS)

    return saturate_q15(value)


def generate_coefficients():
    """
    Deterministic 32-tap Hamming-windowed low-pass FIR.

    Cutoff:
        0.10 cycles/sample

    Coefficients are normalized for unity DC gain,
    quantized into signed Q1.15, then corrected so
    their integer sum is exactly 32768.
    """
    fc = 0.10
    m = TAPS - 1
    floating = []

    for n in range(TAPS):
        x = n - m / 2.0

        if abs(x) < 1e-15:
            sinc = 2.0 * fc
        else:
            sinc = math.sin(2.0 * math.pi * fc * x) / (math.pi * x)

        window = 0.54 - 0.46 * math.cos(2.0 * math.pi * n / m)
        floating.append(sinc * window)

    total = sum(floating)
    floating = [v / total for v in floating]

    q = [int(round(v * Q15_SCALE)) for v in floating]

    correction = Q15_SCALE - sum(q)

    # Keep symmetry: split correction across the two center coefficients.
    left = (TAPS // 2) - 1
    right = TAPS // 2

    q[left] += correction // 2
    q[right] += correction - (correction // 2)

    assert len(q) == TAPS
    assert sum(q) == Q15_SCALE
    assert all(Q15_MIN <= x <= Q15_MAX for x in q)

    return q


COEFFICIENTS = generate_coefficients()


class Fir32Reference:
    def __init__(self, coefficients=None):
        self.coefficients = list(
            COEFFICIENTS if coefficients is None else coefficients
        )

        if len(self.coefficients) != TAPS:
            raise ValueError("Exactly 32 coefficients required")

        self.history = deque([0] * TAPS, maxlen=TAPS)

    def process(self, sample: int) -> int:
        if not Q15_MIN <= sample <= Q15_MAX:
            raise ValueError("Input is outside signed Q1.15 raw range")

        self.history.appendleft(sample)

        acc = 0

        for x, h in zip(self.history, self.coefficients):
            acc += x * h

        # 32-bit products summed into a conceptual signed 37-bit accumulator.
        assert -(1 << 36) <= acc <= (1 << 36) - 1

        return round_q30_to_q15(acc)


class MovingEnergyReference:
    def __init__(self):
        self.values = deque([0] * ENERGY_WINDOW, maxlen=ENERGY_WINDOW)
        self.energy = 0

    def process(self, sample: int) -> int:
        squared = sample * sample

        oldest = self.values[0]
        self.energy -= oldest
        self.values.append(squared)
        self.energy += squared

        assert 0 <= self.energy <= ENERGY_MAX

        return self.energy


class ThresholdEventReference:
    def __init__(self, threshold: int):
        self.threshold = threshold
        self.was_above = False

    def process(self, energy: int) -> bool:
        above = energy >= self.threshold

        event = above and not self.was_above

        self.was_above = above
        return event


class DspReference:
    def __init__(self, threshold=(1 << 30)):
        self.fir = Fir32Reference()
        self.energy = MovingEnergyReference()
        self.event = ThresholdEventReference(threshold)

    def process(self, sample: int):
        filtered = self.fir.process(sample)
        energy = self.energy.process(filtered)
        event = self.event.process(energy)

        return filtered, energy, event


def to_hex16(value):
    return f"{value & 0xFFFF:04X}"


def to_hex37(value):
    return f"{value & ((1 << 37) - 1):010X}"


def write_hex(path, values, formatter):
    with open(path, "w", encoding="ascii") as f:
        for value in values:
            f.write(formatter(value) + "\n")


def run_stream(samples):
    dut = DspReference()

    filtered = []
    energies = []
    events = []

    for sample in samples:
        y, energy, event = dut.process(sample)
        filtered.append(y)
        energies.append(energy)
        events.append(1 if event else 0)

    return filtered, energies, events


def self_test():
    assert sum(COEFFICIENTS) == 32768

    # Exact rounding checks.
    assert round_q30_to_q15(1 << 15) == 1
    assert round_q30_to_q15(-(1 << 15)) == -1

    # Halfway: ties away from zero.
    assert round_q30_to_q15(1 << 14) == 1
    assert round_q30_to_q15(-(1 << 14)) == -1

    # Saturation.
    assert round_q30_to_q15(1 << 50) == 32767
    assert round_q30_to_q15(-(1 << 50)) == -32768

    # Zero response.
    y, e, ev = run_stream([0] * 128)
    assert all(v == 0 for v in y)
    assert all(v == 0 for v in e)
    assert not any(ev)

    # Impulse.
    impulse = [32767] + [0] * 95
    y, _, _ = run_stream(impulse)

    assert any(v != 0 for v in y)
    assert all(Q15_MIN <= v <= Q15_MAX for v in y)

    # Long randomized stream.
    rng = random.Random(0x06062026)
    samples = [rng.randint(Q15_MIN, Q15_MAX) for _ in range(4096)]

    y, energies, _ = run_stream(samples)

    assert len(y) == len(samples)
    assert all(Q15_MIN <= v <= Q15_MAX for v in y)
    assert all(0 <= v <= ENERGY_MAX for v in energies)

    print("PROJECT06 REFERENCE MODEL SELF-TEST")
    print("-----------------------------------")
    print(f"FIR taps                 : {TAPS}")
    print(f"Coefficient sum          : {sum(COEFFICIENTS)}")
    print(f"Energy window            : {ENERGY_WINDOW}")
    print("Q1.15 rounding           : nearest, ties away from zero")
    print("FIR arithmetic           : PASS")
    print("Rounding                 : PASS")
    print("Saturation               : PASS")
    print("Moving energy            : PASS")
    print("Randomized stream        : PASS")
    print("REFERENCE MODEL          : PASS")


def generate_vectors():
    VECTOR_DIR.mkdir(parents=True, exist_ok=True)

    write_hex(
        VECTOR_DIR / "coefficients_q15.hex",
        COEFFICIENTS,
        to_hex16,
    )

    cases = {}

    cases["impulse"] = [32767] + [0] * 127

    cases["positive_step"] = [0] * 32 + [16384] * 160

    cases["alternating_fullscale"] = [
        32767 if i % 2 == 0 else -32768
        for i in range(256)
    ]

    rng = random.Random(0x06062026)
    cases["random"] = [
        rng.randint(Q15_MIN, Q15_MAX)
        for _ in range(4096)
    ]

    for name, samples in cases.items():
        filtered, energies, events = run_stream(samples)

        write_hex(
            VECTOR_DIR / f"{name}_input.hex",
            samples,
            to_hex16,
        )

        write_hex(
            VECTOR_DIR / f"{name}_fir_expected.hex",
            filtered,
            to_hex16,
        )

        write_hex(
            VECTOR_DIR / f"{name}_energy_expected.hex",
            energies,
            to_hex37,
        )

        write_hex(
            VECTOR_DIR / f"{name}_event_expected.hex",
            events,
            lambda x: f"{x:X}",
        )

    print()
    print("Golden vectors generated:")
    for path in sorted(VECTOR_DIR.glob("*.hex")):
        print(f"  {path.relative_to(ROOT)}")


if __name__ == "__main__":
    self_test()
    generate_vectors()
