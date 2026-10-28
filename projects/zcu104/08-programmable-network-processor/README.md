# Project 08 — Programmable Network Processor

**Platform:** AMD ZCU104 / Zynq UltraScale+ MPSoC

Project 08 implements a programmable FPGA network-processing accelerator.

Packets enter a 64-bit streaming datapath, are parsed and classified entirely
in programmable logic, matched against runtime-programmable rules, and then
forwarded, dropped, redirected, queued or modified.

Linux acts as the control plane. It programs rules, reads counters and
diagnostics, and manages the physical network interfaces. Packet decisions
remain in FPGA hardware.

## Core Datapath

    Packet Input
         |
         v
    Ingress Buffer / CDC
         |
         v
    Ethernet / VLAN Parser
         |
         v
    IPv4 Parser
         |
         +--> UDP Parser
         |
         +--> TCP Recognition
         |
         v
    Metadata + 5-Tuple
         |
         v
    Programmable Match Engine
         |
         v
    Action Engine
      /   |    \
     /    |     \
 FORWARD DROP REDIRECT
         |
         +--> MODIFY
         |
         v
    Header / Checksum Update
         |
         v
    Four Egress Queues
         |
         v
    QoS / Arbitration
         |
         v
    Packet Output

## Target

- 64-bit AXI4-Stream datapath
- 125 MHz datapath clock
- 8 Gb/s raw internal streaming capacity
- one beat/cycle steady-state forward path
- Ethernet II / VLAN / IPv4
- UDP parsing
- TCP header recognition
- programmable 5-tuple filtering
- forward / drop / redirect / modify actions
- four egress queues
- weighted arbitration
- rate control
- packet / byte / drop / error / stall counters
- timestamps
- malformed-packet detection
- full TVALID/TREADY backpressure handling
- runtime Linux configuration
- physical Ethernet qualification
- physical GPIO status indication

The 8 Gb/s figure is an internal datapath capacity target, not a claim about
the ZCU104 onboard RJ45, which is a 1 GbE PS interface.
