# AXI-Lite Control Peripheral Register Map

## Interface Contract

- Bus: AXI4-Lite
- Data width: 32 bits
- Address alignment: 32-bit / 4-byte
- Byte order: little-endian
- Reserved bits: write as 0, read as 0
- Configuration registers retain their value until reset or software write
- Status and sensor registers are read-only

| Offset | Register | Access | Reset | Description |
|---|---|---|---|---|
| 0x00 | CONTROL | RW | 0x00000000 | Peripheral control |
| 0x04 | STATUS | RO | 0x00000000 | Live hardware status |
| 0x08 | THRESHOLD_HIGH | RW | 0x00000C00 | Hysteresis upper threshold |
| 0x0C | THRESHOLD_LOW | RW | 0x00000B80 | Hysteresis lower threshold |
| 0x10 | PWM_DUTY | RW | 0x00000099 | RUN-state PWM duty command |
| 0x14 | SENSOR_RAW | RO | 0x00000000 | Latest raw 12-bit ADC sample |
| 0x18 | SENSOR_FILTERED | RO | 0x00000000 | Latest filtered 12-bit ADC sample |
| 0x1C | VERSION | RO | 0x00010000 | Peripheral version 1.0 |

## CONTROL — 0x00

| Bits | Name | Access | Description |
|---|---|---|---|
| 0 | ENGINE_ENABLE | RW | 1 enables control engine |
| 31:1 | RESERVED | - | Read as zero |

## STATUS — 0x04

| Bits | Name | Description |
|---|---|---|
| 0 | CONTROL_REQUEST | Hysteresis control request |
| 1 | ACTUATOR_ENABLE | FSM actuator enable |
| 3:2 | STATE_CODE | 00=OFF, 01=STARTUP, 10=RUN |
| 4 | OVERRUN | Acquisition overrun indication |
| 31:5 | RESERVED | Read as zero |

## THRESHOLD_HIGH — 0x08

Bits [11:0] contain the programmable upper hysteresis threshold.

## THRESHOLD_LOW — 0x0C

Bits [11:0] contain the programmable lower hysteresis threshold.

## PWM_DUTY — 0x10

Bits [7:0] contain the programmable RUN-state PWM duty command.

- 0x00 = 0%
- 0x99 = approximately 60%
- 0xFF = 100%

## SENSOR_RAW — 0x14

Bits [11:0] contain the latest raw ADC sample.

## SENSOR_FILTERED — 0x18

Bits [11:0] contain the latest filtered ADC sample.

## VERSION — 0x1C

Fixed value:

0x00010000 = version 1.0
