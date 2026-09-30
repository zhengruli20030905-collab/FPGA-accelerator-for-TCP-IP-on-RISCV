[CmdletBinding()]
param(
    [string]$BoardIp = '192.168.1.50',
    [string]$LocalIp = '192.168.1.10',
    [switch]$Short
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\physical_board'
New-Item -ItemType Directory -Force -Path $log | Out-Null
$udpTxSeconds = if ($Short) { 10 } else { 60 }
$tcpTxSeconds = if ($Short) { 10 } else { 60 }
$rxSeconds = if ($Short) { 10 } else { 60 }

Write-Host 'V40 PHYSICAL BOARD ACCEPTANCE'
Write-Host 'This script does not program the FPGA or change the PC adapter.'
Write-Host 'Program board/output_files/de2_115_v40_25mhz_tcp_zero_copy_time_limited.sof manually.'

[void](Read-Host 'Set SW6=0 SW4:SW3=00 SW0=1 SW1=0 SW2=0 SW5=1, reset, verify V40/HARDWARE banner, then Enter')
if (-not (Test-Connection -ComputerName $BoardIp -Count 4 -Quiet)) {
    throw "Ping failed: $BoardIp"
}
& (Join-Path $PSScriptRoot 'run_v40_board_udp_boundary.ps1') `
    -TargetIp $BoardIp
& (Join-Path $PSScriptRoot 'run_v40_board_udp_echo.ps1') `
    -TargetIp $BoardIp -RatePps 100 -DurationSeconds 10 `
    -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck

[void](Read-Host 'Set SW6=0 SW4:SW3=01, reset, verify UDP_RX_ONLY/SGDMA/HARDWARE banner, then Enter')
& (Join-Path $PSScriptRoot 'run_v40_board_udp_rx_only.ps1') `
    -TargetIp $BoardIp -RatePps 2550 -DurationSeconds $rxSeconds `
    -IoMode SGDMA -ChecksumMode HARDWARE

[void](Read-Host 'Set SW6=0 SW4:SW3=10, reset, verify UDP_TX_ONLY/REALTIME_POOL banner, then Enter')
& (Join-Path $PSScriptRoot 'run_v40_board_udp_tx_only.ps1') `
    -BoardIp $BoardIp -LocalIp $LocalIp -DurationSeconds $udpTxSeconds `
    -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck

[void](Read-Host 'Set SW6=0 SW4:SW3=11, reset, verify TCP_TX_ONLY/REALTIME_POOL banner, then Enter')
& (Join-Path $PSScriptRoot 'run_v40_board_tcp_tx_only.ps1') `
    -BoardIp $BoardIp -LocalIp $LocalIp -DurationSeconds $tcpTxSeconds `
    -FullPayloadCheck

[void](Read-Host 'Set SW6=1 SW4:SW3=00, reset, verify TCP_RX_ONLY_SINK/SGDMA/HARDWARE banner, then Enter')
& (Join-Path $PSScriptRoot 'run_v40_board_tcp_rx_only.ps1') `
    -BoardIp $BoardIp -LocalIp $LocalIp -DurationSeconds $rxSeconds

[void](Read-Host 'Set SW6=0 SW4:SW3=00, reset, verify UDP_ECHO/SGDMA/HARDWARE banner, then Enter')
& (Join-Path $PSScriptRoot 'run_v40_board_tcp_echo.ps1') `
    -TargetIp $BoardIp -Iterations 1000 -PayloadBytes 256 `
    -IoMode SGDMA -ChecksumMode HARDWARE
& (Join-Path $PSScriptRoot 'run_v40_board_tcp_echo_throughput.ps1') `
    -BoardIp $BoardIp -LocalIp $LocalIp -Port 5001 -ChunkBytes 1460 `
    -WindowChunks 32 -DurationSeconds 60 -DrainSeconds 10 `
    -IoMode SGDMA -ChecksumMode HARDWARE -FullPayloadCheck

& (Join-Path $PSScriptRoot 'run_v40_board_tcp_echo_lifetime_stress.ps1') `
    -BoardIp $BoardIp -LocalIp $LocalIp -Port 5001 `
    -ChunkBytes 1460 -WindowChunks 32 `
    -RoundSeconds $(if ($Short) { 5 } else { 10 })

@(
    'V40 BOARD AUTOMATED-PC PORTION COMPLETED',
    "MODE=$(if($Short){'SHORT'}else{'60_SECOND_TX_RX'})",
    'MANUAL_UART_COUNTER_RECONCILIATION=REQUIRED',
    'FPGA_PROGRAMMING=NOT_PERFORMED_BY_SCRIPT'
) | Set-Content -LiteralPath (Join-Path $log 'v40_board_acceptance_status.txt')
Write-Host 'PC-side stages completed. Preserve every FINAL SNAPSHOT with the generated result files.'
