# RISC-V v40 Hand-in Package

This package contains the v40 RTL, firmware, simulation sources, test scripts,
Quartus project, final FPGA image, and retained verification logs.

It intentionally excludes tutorial documents and regenerable build databases.

For a board-only command sheet, see [`BOARD_TEST_COMMANDS.md`](BOARD_TEST_COMMANDS.md).

## 1. Project path

```powershell
$r = 'E:\RISC-V\RISC-V_version40_handin'
Set-Location $r
```

## 2. Required tools

- Windows PowerShell 5.1 or later
- RISC-V cross compiler used by `scripts/build_v40_firmware.ps1`
- QuestaSim or ModelSim for RTL simulation
- Intel Quartus for FPGA compilation and programming

The scripts also contain the local fallback tool paths used during development.

## 3. Automated verification

Run the complete simulation suite:

```powershell
& .\scripts\run_v40_full_sim.ps1
```

Run formal acceptance while reusing the included Quartus reports:

```powershell
& .\scripts\run_v40_acceptance.ps1 -ReuseQuartusReports
```

Run acceptance with a new Quartus compilation:

```powershell
& .\scripts\run_v40_acceptance.ps1
```

Build firmware only:

```powershell
& .\scripts\build_v40_firmware.ps1
```

Build the FPGA project and run TimeQuest:

```powershell
& .\scripts\run_v40_quartus.ps1
```

## 4. Individual simulations

```powershell
& .\scripts\run_v40_cpu_sim.ps1
& .\scripts\run_v40_peripheral_timing_sim.ps1
& .\scripts\run_v40_dma_engine_sim.ps1
& .\scripts\run_v40_dma_sim.ps1 -Seeds 3701,3702,3718
& .\scripts\run_v40_sgdma_sim.ps1
& .\scripts\run_v40_checksum_sim.ps1
& .\scripts\run_v40_sgdma_checksum_sim.ps1
& .\scripts\run_v40_network_sim.ps1
& .\scripts\run_v40_tx_pool_host_test.ps1
& .\scripts\run_v40_tcp_zero_copy_host_test.ps1
```

Results are written below `logs/`.

## 5. FPGA programming

Program the following file manually with Quartus Programmer:

```text
board/output_files/de2_115_v40_25mhz_tcp_zero_copy_time_limited.sof
```

The PowerShell scripts do not program the FPGA and do not modify the PC network
adapter.

Recommended Ethernet settings:

```text
PC IPv4:    192.168.1.10
Netmask:    255.255.255.0
Board IPv4: 192.168.1.50
UDP port:   1234
TCP port:   5001
```

Common reset-latched switches:

```text
SW0=1  SGDMA
SW1=0  profiling disabled for throughput tests
SW2=0  periodic UART output
SW5=1  hardware checksum
```

Set `SW2=1` during measured traffic, then return it to `0` to print the final
UART snapshot.

| Test mode | SW6 | SW4:SW3 |
|---|---:|---:|
| UDP Echo / TCP Echo | 0 | 00 |
| UDP RX-only | 0 | 01 |
| UDP TX-only | 0 | 10 |
| TCP TX-only | 0 | 11 |
| TCP RX-only | 1 | 00 |

Reset the board after changing any reset-latched switch and verify the UART
banner before running a PC-side script.

## 6. Complete physical-board test

Short functional sequence:

```powershell
& .\scripts\run_v40_board_acceptance.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 -Short
```

Full sequence:

```powershell
& .\scripts\run_v40_board_acceptance.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10
```

The script pauses when the FPGA switch configuration must be changed.

## 7. Individual physical-board tests

UDP boundary:

```powershell
& .\scripts\run_v40_board_udp_boundary.ps1 -TargetIp 192.168.1.50
```

UDP Echo:

```powershell
& .\scripts\run_v40_board_udp_echo.ps1 `
  -TargetIp 192.168.1.50 -PayloadBytes 1472 `
  -RatePps 1500 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

UDP RX-only:

```powershell
& .\scripts\run_v40_board_udp_rx_only.ps1 `
  -TargetIp 192.168.1.50 -PayloadBytes 1472 `
  -RatePps 3600 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE
```

UDP TX-only:

```powershell
& .\scripts\run_v40_board_udp_tx_only.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -ExpectedPayloadBytes 1472 -DurationSeconds 60 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

TCP TX-only:

```powershell
& .\scripts\run_v40_board_tcp_tx_only.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -ChunkBytes 1460 -DurationSeconds 60 -FullPayloadCheck
```

TCP RX-only:

```powershell
& .\scripts\run_v40_board_tcp_rx_only.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -ChunkBytes 1460 -BatchChunks 32 -DurationSeconds 60
```

Basic TCP Echo:

```powershell
& .\scripts\run_v40_board_tcp_echo.ps1 `
  -TargetIp 192.168.1.50 -Iterations 1000 -PayloadBytes 256 `
  -IoMode SGDMA -ChecksumMode HARDWARE
```

Pipelined TCP Echo throughput:

```powershell
& .\scripts\run_v40_board_tcp_echo_throughput.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -Port 5001 -ChunkBytes 1460 -WindowChunks 32 `
  -DurationSeconds 60 -DrainSeconds 10 `
  -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck
```

TCP zero-copy lifetime stress:

```powershell
& .\scripts\run_v40_board_tcp_echo_lifetime_stress.ps1 `
  -BoardIp 192.168.1.50 -LocalIp 192.168.1.10 `
  -Port 5001 -ChunkBytes 1460 -WindowChunks 32 -RoundSeconds 10
```

Physical-board CSV, JSON, and TXT results are written to
`logs/physical_board/`.

## 8. Included status

- Automated simulation acceptance: passed
- Quartus 25 MHz build and TimeQuest: passed
- Final SOF: included
- FPGA programming: manual
- v40 physical-board throughput: must be measured on the target board
