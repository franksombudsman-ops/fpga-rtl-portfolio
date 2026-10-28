# Project 08 Engineering Specification

## 1. Mission

Build a physically demonstrated programmable network firewall/router
accelerator on the AMD ZCU104.

The FPGA dataplane must inspect packet headers, classify flows, execute
programmable actions, maintain telemetry and sustain continuous streaming
without requiring Linux to make a per-packet forwarding decision.

## 2. Packet Interface

AXI4-Stream:

- DATA_WIDTH = 64 bits
- TKEEP = 8 bits
- TLAST = packet boundary
- TVALID/TREADY fully supported
- datapath clock target = 125 MHz

Frames presented to the packet engine exclude Ethernet preamble/SFD/FCS.

## 3. Protocol Recognition

Mandatory:

- Ethernet II
- 802.1Q VLAN
- IPv4
- UDP
- TCP header recognition
- unsupported EtherTypes
- malformed/truncated headers

## 4. Metadata

The parser shall generate:

- source MAC
- destination MAC
- EtherType
- VLAN ID
- source IPv4
- destination IPv4
- IP protocol
- source L4 port
- destination L4 port
- packet length
- timestamp
- flow hash
- malformed flag

## 5. Match-Action Engine

Minimum 32 programmable rules.

Match fields:

- source IPv4 + mask
- destination IPv4 + mask
- protocol + mask
- source port + mask
- destination port + mask
- VLAN ID + mask

Lowest-index matching rule has priority.

Actions:

- FORWARD
- DROP
- REDIRECT
- MODIFY
- COUNT

Rules must be updateable at runtime without rebuilding the FPGA image.

## 6. Packet Modification

Supported modification targets:

- IPv4 source address
- IPv4 destination address
- UDP/TCP source port
- UDP/TCP destination port
- output queue

Affected checksums must be updated correctly.

## 7. Queueing

Four hardware egress queues.

Required:

- independent packet/byte counters
- queue occupancy
- overflow detection
- weighted round-robin arbitration
- basic programmable rate limiting
- backpressure propagation

## 8. Clock Domains

Control plane and packet dataplane are separate clock domains.

Initial targets:

- AXI-Lite/control = 100 MHz
- packet dataplane = 125 MHz

All CDC boundaries must be explicit and independently verified.

## 9. Telemetry

Hardware counters shall include:

- received packets
- received bytes
- forwarded packets
- dropped packets
- redirected packets
- modified packets
- malformed packets
- rule hits
- per-queue packets/bytes
- ingress stalls
- egress stalls
- FIFO high-water marks
- datapath errors

## 10. Linux Control Plane

Linux shall provide a control utility capable of:

- adding rules
- deleting rules
- listing rules
- changing actions
- reading counters
- reading queue status
- reading errors
- clearing statistics
- configuring rate limits

Target command concept:

    p08ctl rule add ...
    p08ctl rule list
    p08ctl stats
    p08ctl queue
    p08ctl clear

Linux is management/control. FPGA hardware executes packet decisions.

## 11. Physical Validation Modes

### Mode A — Internal Performance Qualification

    PL Traffic Generator
            |
            v
       Packet Engine
            |
            v
       PL Checker

Purpose:

- prove one-beat-per-cycle architecture
- measure latency
- measure stalls
- stress backpressure
- prove internal datapath capacity

### Mode B — Real Ethernet Qualification

Real Ethernet frames shall traverse the physical ZCU104 network environment
and be submitted to the FPGA packet engine.

Tests shall demonstrate live:

- forwarding
- dropping
- redirecting
- header modification
- runtime rule changes
- hardware counters

Physical Ethernet throughput shall be reported separately from internal
datapath throughput.

## 12. Physical Sideband

Pmod/breadboard status outputs:

- GREEN LED  = forwarded packet activity
- RED LED    = dropped packet activity
- YELLOW LED = datapath/error condition

Optional pushbutton input:

- test/fault stimulus or counter snapshot

No high-speed Ethernet signals shall be routed through the breadboard.

## 13. Verification Requirements

Verification shall include:

- self-checking packet generation
- randomized packet lengths
- randomized backpressure
- back-to-back packets
- VLAN/non-VLAN traffic
- UDP/TCP traffic
- malformed/truncated frames
- rule priority
- runtime rule changes
- checksum modification
- queue congestion
- rate limiting
- CDC
- reset during idle
- recovery after fault
- long sustained streaming

Simulation-only results must never be represented as physical evidence.

## 14. Performance Acceptance

Internal datapath:

- 64-bit
- 125 MHz
- raw capacity = 8 Gb/s
- one accepted beat/cycle after pipeline fill when unstalled
- no unexplained packet loss
- no packet corruption

Physical Ethernet:

- measured independently
- limited by actual interfaces and software/transport architecture
- never represented as equivalent to internal datapath capacity

## 15. Completion Definition

Project 08 is complete only when:

1. architecture is documented;
2. RTL verification passes;
3. CDC/backpressure tests pass;
4. synthesis and implementation complete;
5. timing closes;
6. Linux control works;
7. real packets are processed physically;
8. live rules change hardware behavior;
9. breadboard/Pmod indicators operate;
10. internal sustained throughput is measured;
11. physical Ethernet throughput is measured separately;
12. fault/error behavior is demonstrated;
13. evidence is preserved;
14. final release is tagged.

Project 08 closes the major FPGA/SoC capstone stage before the roadmap moves
into ASIC verification, synthesis, STA and physical implementation.
