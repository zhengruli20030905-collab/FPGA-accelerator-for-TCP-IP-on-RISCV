# V40 Physical-Board PowerShell Commands

This file is the concise command sheet for programming and testing the v40 hand-in project.

## 1. Open the project

Run PowerShell and enter:

```powershell
$r = 'E:\RISC-V\RISC-V_version40_handin'
Set-Location $r
```

PC Ethernet configuration:

```text
PC IPv4     192.168.1.10
Netmask     255.255.255.0
Board IPv4  192.168.1.50
UDP port    1234
TCP port    5001
```

## 2. Program the FPGA

Use Quartus Programmer to load:

```text
E:\RISC-V\RISC-V_version40_handin\board\output_files\de2_115_v40_25mhz_tcp_zero_copy_time_limited.sof
```

Common reset-latched switch settings for SGDMA tests:

```text
SW0=1  SGDMA
SW1=0  profiling disabled
SW2=0  periodic UART output before the test
SW5=1  hardware checksum
```

After changing `SW0`, `SW1`, `SW3`, `SW4`, `SW5`, or `SW6`, reset the FPGA and verify the UART banner. During measured traffic, set `SW2=1`; after the test, return `SW2=0` and save the final UART snapshot.

## 3. Basic connectivity

Use `SW6=0`, `SW4:SW3=00` and reset the board.

```powershell
ping 192.168.1.50 -n 10

& .\scripts\run_v40_board_udp_boundary.ps1 `
  -TargetIp 192.168.1.50
```

## 4. UDP Echo

Switches before reset:

```text
SW6=0  SW4:SW3=00  SW0=1  SW1=0  SW5=1
```

Quick test:

```powershell
& .\scripts\run_v40_board_udp_echo.ps1 `
  -TargetIp 192.168.1.50 -PayloadBytes 1472 `
  -RatePps 100 -DurationSeconds 10 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

60-second throughput test:

```powershell
& .\scripts\run_v40_board_udp_echo.ps1 `
  -TargetIp 192.168.1.50 -PayloadBytes 1472 `
  -RatePps 1500 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

## 5. UDP RX-only

Switches before reset:

```text
SW6=0  SW4:SW3=01  SW0=1  SW1=0  SW5=1
```

```powershell
& .\scripts\run_v40_board_udp_rx_only.ps1 `
  -TargetIp 192.168.1.50 -PayloadBytes 1472 `
  -RatePps 3600 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE
```

Use the UART baseline/final delta of `UDP_SINK` and `UDP_RX_BYTES` as the board-side acceptance evidence.

## 6. UDP TX-only

Switches before reset:

```text
SW6=0  SW4:SW3=10  SW0=1  SW1=0  SW5=1
```

```powershell
& .\scripts\run_v40_board_udp_tx_only.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -ExpectedPayloadBytes 1472 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

## 7. TCP TX-only

Switches before reset:

```text
SW6=0  SW4:SW3=11  SW0=1  SW1=0  SW5=1
```

```powershell
& .\scripts\run_v40_board_tcp_tx_only.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -Port 5001 -ChunkBytes 1460 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

## 8. TCP RX-only

Switches before reset:

```text
SW6=1  SW4:SW3=00  SW0=1  SW1=0  SW5=1
```

```powershell
& .\scripts\run_v40_board_tcp_rx_only.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -Port 5001 -ChunkBytes 1460 -BatchChunks 32 `
  -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE
```

Use the UART baseline/final delta of `TCP_RX` as the board-side accepted-byte evidence. `TCP_TX` should not contain application echo payload in this mode.

## 9. TCP Echo

Switches before reset:

```text
SW6=0  SW4:SW3=00  SW0=1  SW1=0  SW5=1
```

Basic functional test:

```powershell
& .\scripts\run_v40_board_tcp_echo.ps1 `
  -TargetIp 192.168.1.50 -Port 5001 `
  -Iterations 1000 -PayloadBytes 256 `
  -IoMode SGDMA -ChecksumMode HARDWARE
```

Formal pipelined throughput test:

```powershell
& .\scripts\run_v40_board_tcp_echo_throughput.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -Port 5001 -ChunkBytes 1460 -WindowChunks 32 `
  -DurationSeconds 60 -DrainSeconds 10 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

## 10. TCP zero-copy lifetime stress

Keep the TCP Echo switch configuration:

```powershell
& .\scripts\run_v40_board_tcp_echo_lifetime_stress.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -Port 5001 -ChunkBytes 1460 -WindowChunks 32 `
  -RoundSeconds 10
```

The final UART snapshot should show:

```text
TCP_ZEROCOPY COPY_FALLBACK=00000000 COPY_BYTES=00000000
TCP_OWNER CURRENT=00000000 ACKQ_CURRENT=00000000
TCP_OWNER_SAFETY FREE_BEFORE_ACK=00000000
TCP_OWNER_SAFETY PAYLOAD_STABILITY=00000000 CONSISTENCY=00000000
```

## 11. Run the complete board sequence

Short sequence:

```powershell
& .\scripts\run_v40_board_acceptance.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 -Short
```

Full sequence:

```powershell
& .\scripts\run_v40_board_acceptance.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10
```

The acceptance script pauses when the reset-latched switch configuration must be changed.

## 12. Result location

Board-test CSV, JSON, and TXT files are saved under:

```text
E:\RISC-V\RISC-V_version40_handin\logs\physical_board
```

For each formal result, retain the PC-side result files and the matching UART baseline/final snapshot.

