# V40 Physical-Board Throughput Limits

Status: required throughput campaign complete; optional strict-zero-loss UDP Echo confirmation remains  
Test dates: 2026-09-19 to 2026-09-20  
Project: `RISC-V_version40_handin`

## Common test configuration

- CPU clock: 25 MHz
- I/O mode: SGDMA
- Checksum mode: hardware IP/UDP/TCP offload
- FPGA address: `192.168.1.50`
- PC address: `192.168.1.10`
- UART performance-quiet mode enabled during measured traffic
- PC full-payload byte-by-byte verification disabled during limit searches
- The PC still checks packet/chunk length, sequence information, loss, duplicates,
  ordering, and socket errors as supported by each script.
- Payload correctness is covered separately by the UDP boundary test and the
  lower-rate full-payload regression tests.

## Result definitions

- **Highest short test**: highest completed 10-second point so far. This is not
  automatically the sustainable limit.
- **Sustainable limit**: highest selected point that subsequently completes the
  60-second confirmation run. Exact loss is always reported; a nonzero-loss run
  is never described as lossless.
- All throughput values below are application-payload throughput, excluding
  Ethernet, IP, UDP/TCP, preamble, IFG, and FCS overhead.

## Limit summary

| Mode | Payload/chunk | Highest short test | 60-second confirmed result | Status |
|---|---:|---:|---:|---|
| UDP Echo | 1472 B | 5000 pps offered; peak observed reply 4385.8 pps at the 4400-point, 51.6471808 Mbps | 4300 pps, 50.6307157 Mbps, 31/258000 lost (0.012016%) | Near-lossless confirmed; strict zero-loss point pending |
| UDP RX-only | 1472 B | 8100 pps offered and accepted, 95.3856000 Mbps, 0 application loss | 8100 pps, 95.3856000 Mbps, 486000/486000 accepted, 0 application loss | Physical-link ceiling confirmed |
| UDP TX-only | 1472 B | 1718.4 pps, 20.2358784 Mbps, sequences 0-17183 contiguous | 1718.0667 pps, 20.2319531 Mbps, sequences 0-103083 contiguous | Sustainable maximum-rate result confirmed |
| TCP Echo | 1460 B | 1590.4 chunks/s, 18.5758720 Mbps, magic/sequence validation | Best 60-second run: 1560.6833 chunks/s, 18.2287813 Mbps, full-payload validation; independent light-validation run: 1527.15 chunks/s, 17.8371120 Mbps | Sustainable zero-copy operation confirmed; run-to-run spread retained |
| TCP RX-only | 1460 B | Not separately swept | 244224 chunks, 356567040 bytes, 47.5422720 Mbps; PC submission exactly matched UART `TCP_RX`, `TCP_TX=0` | Sustainable receive-only result confirmed |
| TCP TX-only | 1460 B | 1375.8 chunks/s, 16.069344 Mbps, 0 validation errors | 1375.3667 chunks/s, 16.0642827 Mbps, 82522/82522 contiguous chunks | Sustainable maximum-rate result confirmed |

## UDP Echo limit sweep

Configuration: SGDMA, hardware checksum, 1472-byte UDP payload,
`FullPayloadCheck=False`.

| Target pps | Duration | Sent | Unique replies | Lost | Loss | Late schedules | Reply pps | Payload Mbps |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1600 | 10 s | 16000 | 15999 | 1 | 0.006250% | 0 | 1599.9 | 18.8404224 |
| 1700 | 10 s | 17000 | 17000 | 0 | 0% | 1 | 1700.0 | 20.0192000 |
| 1800 | 10 s | 18000 | 18000 | 0 | 0% | 0 | 1800.0 | 21.1968000 |
| 2000 | 10 s | 20000 | 20000 | 0 | 0% | 8 | 2000.0 | 23.5520000 |
| 2200 | 10 s | 22000 | 21999 | 1 | 0.004545% | 15 | 2199.9 | 25.9060224 |
| 2400 | 10 s | 24000 | 23999 | 1 | 0.004167% | 36 | 2399.9 | 28.2612224 |
| 2600 | 10 s | 26000 | 26000 | 0 | 0% | 63 | 2600.0 | 30.6176000 |
| 2800 | 10 s | 28000 | 27998 | 2 | 0.007143% | 77 | 2799.8 | 32.9704448 |
| 3000 | 10 s | 30000 | 29998 | 2 | 0.006667% | 86 | 2999.8 | 35.3256448 |
| 3200 | 10 s | 32000 | 32000 | 0 | 0% | 109 | 3200.0 | 37.6832000 |
| 3400 | 10 s | 34000 | 33998 | 2 | 0.005882% | 136 | 3399.8 | 40.0360448 |
| 3600 | 10 s | 36000 | 35997 | 3 | 0.008333% | 160 | 3599.7 | 42.3900672 |
| 3600 (repeat) | 10 s | 36000 | 36000 | 0 | 0% | 164 | 3600.0 | 42.3936000 |
| 3800 | 10 s | 38000 | 37986 | 14 | 0.036842% | 215 | 3798.6 | 44.7323136 |
| 4000 | 10 s | 40000 | 40000 | 0 | 0% | 6 | 4000.0 | 47.1040000 |
| 4200 | 10 s | 42000 | 41997 | 3 | 0.007143% | 96 | 4199.7 | 49.4556672 |
| 4300 | 10 s | 43000 | 43000 | 0 | 0% | 93 | 4300.0 | 50.6368000 |
| 4300 | 60 s | 258000 | 257969 | 31 | 0.012016% | 181 | 4299.4833 | 50.6307157 |
| 4400 | 10 s | 44000 | 43858 | 142 | 0.322727% | 11 | 4385.8 | 51.6471808 |
| 5000 | 10 s | 50000 | 43835 | 6165 | 12.330000% | 191 | 4383.5 | 51.6200960 |

Current interpretation: 5000 pps is the first clear overload point. Only 4383.5
pps was returned and loss rose to 12.33%, while PC late scheduling represented
only about 0.382% of sends. The 4400 pps test independently confirmed the reply
plateau at 4385.8 pps with only 11 late schedules. The saturation knee is
therefore between 4300 and 4400 pps. The 4300 pps point sustained 50.6307157
Mbps for 60 seconds with 0.012016% loss. It is the current near-lossless
sustained result, but a strict zero-loss 60-second point still needs to be found.

## UDP RX-only limit sweep

Configuration: SGDMA, hardware checksum, 1472-byte UDP payload. The board is an
RX sink and returns no UDP payload. Acceptance is determined from the UART
`UDP_SINK` counter rather than from PC replies.

| Target pps | Duration | PC sent | Board `UDP_SINK` delta | Application loss | PC late schedules | Accepted payload Mbps |
|---:|---:|---:|---:|---:|---:|---:|
| 5000 | 10 s | 50000 | 50000 (`0x0000C350`) | 0 | 99 | 58.8800000 |
| 6500 | 10 s | 65000 | 65000 (`0x0001C138 - 0x0000C350`) | 0 | 182 | 76.5440000 |
| 7500 | 10 s | 75000 | 75000 (`0x0002E630 - 0x0001C138`) | 0 | 123 | 88.3200000 |
| 8000 | 10 s | 80000 | 80000 (`0x00041EB0 - 0x0002E630`) | 0 | 216 | 94.2080000 |
| 8100 | 10 s | 81000 | 81000 (`0x00055B18 - 0x00041EB0`) | 0 | 475 | 95.3856000 |
| 8100 | 60 s | 486000 | 486000 (`0x00076A70 - 0x00000000`) | 0 | 1527 | 95.3856000 |

Current interpretation: the board accepted every application packet at 5000,
6500, 7500, 8000, and 8100 pps. At 8100 pps, `UDP_RX_BYTES` increased from
`0x17B07400` to `0x1ECBCA00`, exactly `81000 * 1472` bytes. `RX_DROP`, `RX_ERR`,
and `FF_DROP` did not increase in the 10-second sweep. The 60-second confirmation
also accepted all 486000 packets: `UDP_SINK=0x00076A70` and
`UDP_RX_BYTES=0x2AA40400`, exactly `486000 * 1472` bytes. `RX_ERR` and `FF_DROP`
remained unchanged. The generic `RX_DROP` counter increased by one, but this was
not a target UDP packet because both target packet and byte counters match the
PC transmission exactly. The application payload rate is 95.3856 Mbps and the
Ethernet wire rate, including MAC overhead, preamble, and IFG, is approximately
99.6624 Mbps. This is 99.66% of the 100 Mbps physical-link rate and is the
confirmed sustainable physical-link ceiling for this payload size.

## UDP TX-only maximum-rate test

Configuration: SGDMA, hardware checksum, 1472-byte real-time generated payload,
`FullPayloadCheck=False`. The script performs an unmeasured outbound warm-up,
stops and drains it, and then issues a second `V40TXGO` that resets the measured
sequence number to zero.

| Duration | Unique packets | Packet rate | Payload Mbps | First sequence | Last sequence | Leading gaps | Internal gaps | Bad | Duplicates | Out of order |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 s | 17184 | 1718.4/s | 20.2358784 | 0 | 17183 | 0 | 0 | 0 | 0 | 0 |
| 60 s | 103084 | 1718.0667/s | 20.2319531 | 0 | 103083 | 0 | 0 | 0 | 0 | 0 |

The clean short run received every sequence from 0 through 17183. The 60-second
confirmation received every sequence from 0 through 103083. Neither run had a
leading startup gap, internal sequence gap, malformed packet, duplicate,
ordering error, or socket receive error. During the 60-second run, the UART
reported no UDP retry/error, TX-pool-full event, TX state/generation error,
SGDMA TX error, or ring-consistency error. The cumulative `UDP_TX_GEN` counter
also includes the script's unmeasured ARP/warm-up burst and therefore is not
expected to equal the measured PC packet count. The sustainable UDP TX-only
maximum-rate result is 20.2319531 Mbps.

## TCP Echo throughput test

Configuration: SGDMA, hardware checksum, one persistent TCP connection,
1460-byte logical chunks, a 32-chunk host window, and the V40 zero-copy
ACK-lifetime path.

| Duration | Payload validation | Echoed chunks | Echoed bytes | Payload Mbps | All echoed | Outstanding at close | Bad/gap/duplicate/out-of-order | Read/write errors |
|---:|---|---:|---:|---:|---|---:|---:|---:|
| 60 s | Full payload | 93641 | 136715860 | 18.2287813 | Yes | 0 | 0/0/0/0 | 0/0 |
| 10 s | Magic and duplicate sequence fields | 15904 | 23219840 | 18.5758720 | Yes | 0 | 0/0/0/0 | 0/0 |
| 60 s | Magic and duplicate sequence fields | 91629 | 133778340 | 17.8371120 | Yes | 0 | 0/0/0/0 | 0/0 |

All three runs passed the physical-board criteria. The full-payload 60-second
run proves byte-exact echo correctness, while the two light-validation runs
measure the path without the PC's per-byte comparison. Disabling full-payload
validation did not produce a material systematic gain: the 10-second run was
slightly faster, but the independent 60-second run was slower. The difference
is retained as observed run-to-run variation instead of attributing it to the
validation switch.

The final light-validation UART snapshot matched the host result:
`TCP_ZEROCOPY CALLBACKS=0x165ED` (91629) and
`BYTES=0x07F94BA4` (133778340). It reported zero copy fallback/bytes,
zero owner exhaustion, zero free-before-ACK/payload-stability/consistency
errors, zero TCP `ERR_MEM`, and empty owner/ACK queues at completion. V40 TCP
Echo is therefore operating through the intended zero-copy ACK-lifetime path.

## TCP TX-only maximum-rate test

Configuration: SGDMA, hardware checksum, one persistent TCP connection,
1460-byte logical chunks, `FullPayloadCheck=False`. The board generates and
submits data as fast as its real-time TX pool and lwIP TCP path allow; the PC
does not impose a target rate.

| Duration | Complete chunks | Complete payload bytes | Chunk rate | Payload Mbps | Gaps | Bad | Duplicates | Out of order | Partial bytes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 s | 13758 | 20086680 | 1375.8/s | 16.069344 | 0 | 0 | 0 | 0 | 0 |
| 60 s | 82522 | 120482120 | 1375.3667/s | 16.0642827 | 0 | 0 | 0 | 0 | 0 |

The PC received exactly `13758 * 1460` bytes. Sequence numbers were contiguous
from 0 through 13757, and no framing, ordering, socket, or partial-chunk error
was observed. The 60-second confirmation produced 82522 contiguous chunks from
sequence 0 through 82521, with exactly 120482120 received payload bytes and no
validation, ordering, socket, or partial-chunk error. The sustainable TCP
TX-only maximum-rate result is therefore 16.0642827 Mbps.

## TCP RX-only throughput test

Configuration: SGDMA, hardware checksum, one persistent TCP connection,
1460-byte chunks, 32 chunks per PC write batch, and a 60-second measurement.
The sink consumes received application data and sends no application payload
back to the PC; normal TCP ACK frames are still transmitted.

| Duration | PC submitted chunks | PC submitted bytes | UART `TCP_RX` delta | UART `TCP_TX` delta | Accepted payload Mbps | Send errors | Unexpected application bytes | Receive errors |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 60 s | 244224 | 356567040 | 356567040 (`0x1540C800`) | 0 | 47.5422720 | 0 | 0 | 0 |

The baseline `TCP_RX` counter was zero and the final counter was
`0x1540C800`, exactly equal to all bytes submitted by the PC. The callback
count was `0x0003BA00` (244224), exactly equal to the submitted chunk count.
`TCP_TX=0` confirms that the sink returned no application payload; the
`PATH_TX` frames are normal TCP ACK/control traffic. `RX_ERR` and `FF_DROP`
were unchanged across the measured interval. The generic `RX_DROP` counter
included non-target/background traffic, but it does not represent target TCP
loss because the target byte and callback counts match the PC submission
exactly. The sustainable TCP RX-only payload throughput is therefore
47.5422720 Mbps with zero application loss.

## Campaign completion

Completed in this campaign: UDP Echo saturation/60-second confirmation, UDP
RX-only physical-link ceiling, UDP TX-only 60-second confirmation, TCP Echo
full/light-validation runs, TCP RX-only 60-second confirmation, and TCP TX-only
60-second confirmation. All required throughput directions have now been
measured on the physical board.

Optional follow-up:

1. Select and confirm a strict zero-loss UDP Echo fallback point for 60 seconds.

Raw CSV, JSON, TXT, and UART evidence remain in this directory. This file is a
summary and must not replace the raw evidence.
