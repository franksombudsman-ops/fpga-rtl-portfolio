# SPI Mode 0 Timing Diagram

## Protocol summary

| Parameter | Value |
|-----------|-------|
| CPOL      | 0 — SCLK idles low |
| CPHA      | 0 — data captured on **rising** SCLK edge |
| Bit order | MSB first |
| CS_N      | Active-low; asserted for the full transfer |

## 8-bit transaction (DATA_WIDTH = 8)

```
         ←── half_period ──→←── half_period ──→
                                                              
CS_N  ‾‾\______________________________________________/‾‾‾‾‾
              ↑ assert                         ↑ deassert
                                                              
SCLK  ________/‾‾‾‾\____/‾‾‾‾\____/ · · · \____/‾‾‾‾\______
              1    2    3    4                7    8
              ↑                                        ↑ last
              first rising edge                  falling edge
                                                              
MOSI  ──<  D7  ><  D6  ><  D5  >< · · · ><  D1  ><  D0  >──
        ↑pre-drive
        on CS_N assert
        (changes on falling SCLK)
                                                              
MISO  ──<  Q7  ><  Q6  ><  Q5  >< · · · ><  Q1  ><  Q0  >──
        ↑pre-drive
        on CS_N assert
        (changes on falling SCLK, sampled on rising SCLK)
        
              ↑    ↑    ↑                   ↑    ↑
              │    │    │  capture points   │    │
              └────┴────┴── (rising SCLK) ─┴────┘
```

## Transfer sequence

```
Step  Event           Master action              Slave action
────  ──────────────  ─────────────────────────  ──────────────────────────────
 0    CS_N asserted   MOSI ← D7 (MSB)            MISO ← Q7 (MSB)
 1    SCLK ↑ edge 1  sample MISO → rx_reg        sample MOSI → sl_rx
 2    SCLK ↓ edge 1  MOSI ← D6                  MISO ← Q6
 3    SCLK ↑ edge 2  sample MISO → rx_reg        sample MOSI → sl_rx
 4    SCLK ↓ edge 2  MOSI ← D5                  MISO ← Q5
      ...             ...                        ...
N-1   SCLK ↑ edge 8  sample MISO (last bit)      sample MOSI (last bit)
 N    SCLK ↓ edge 8  state → DONE               (transaction ends)
N+1   CS_N deasserted data_out ← rx_reg          —
      done pulsed     busy ← 0                   —
```

## SCLK frequency derivation

```
    half_period = CLK_FREQ / (2 × SPI_FREQ)

    Example: CLK_FREQ = 100 MHz, SPI_FREQ = 1 MHz
    → half_period = 100_000_000 / 2_000_000 = 50 system clocks
    → SCLK period = 100 system clocks = 1 µs ✓
```

## AD7476A (Pmod AD1) frame format

The AD7476A returns 16 bits per SPI transaction.  With DATA_WIDTH=16 the
master captures the full frame in `data_out`:

```
bit  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
     ─────────────────────────────────────────────────────────────────
      0   0   0   0  D11 D10  D9  D8  D7  D6  D5  D4  D3  D2  D1  D0
      └──────────┘  └────────────────────────────────────────────────┘
      4 leading 0s     12-bit ADC result (MSB first)
```

`adc_data = data_out[11:0]` extracts the 12-bit result directly.
