# Project 07 — Gate 4A Physical RX Validation

RESULT: PASS

Platform: ZCU104
Clock: 100 MHz
Toolchain: Vivado / XSDB 2023.2

Descriptor: 0x10000000
RX DDR destination: 0x10002000
Length: 64 bytes

Physical DDR result:
11111111
22222222
33333333
44444444
55555555
66666666
77777777
88888888
99999999
AAAAAAAA
BBBBBBBB
CCCCCCCC
DDDDDDDD
EEEEEEEE
FFFFFFFF
12345678

Descriptor after:
CONTROL = 0x00000006
STATUS = 0x00000001
ACTUAL_LENGTH = 0x00000040

Ring / IRQ:
RX_TAIL = 1
RX_HEAD = 1
IRQ_STATUS = 0x00000002
IRQ_ENABLE = 0x00000002

Errors:
ERROR_STATUS = 0
ERROR_INFO = 0
ERROR_ADDR = 0

PHYSICAL CLAIM:
One RX descriptor was physically executed through the deterministic
AXI4-Stream source, custom RX engine, authored AXI4-MM write path,
PS HP0, and ZCU104 DDR. Descriptor completion writeback, OWN release,
RX head advancement, and RX completion IRQ were also physically proven.

Evidence:
- evidence/screenshots/04_gate4a_rx_before_launch.png
- evidence/screenshots/05_gate4a_rx_physical_pass.png

No Gate 4A video artifact is claimed.

Direct RX AXI4-Stream waveform observation is deferred to Gate 4B using ILA.

GATE 4A: PASS
