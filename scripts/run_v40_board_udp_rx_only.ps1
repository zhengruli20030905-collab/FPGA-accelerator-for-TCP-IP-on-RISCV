[CmdletBinding()]
param(
    [string]$TargetIp = '192.168.1.50',
    [ValidateRange(1,65535)][int]$Port = 1234,
    [ValidateRange(12,1472)][int]$PayloadBytes = 1472,
    [ValidateRange(1,100000)][int]$RatePps = 200,
    [ValidateRange(1,3600)][int]$DurationSeconds = 10,
    [switch]$NoPrompt,
    [ValidateSet('PIO','SGDMA')][string]$IoMode='SGDMA',
    [ValidateSet('SOFTWARE','HARDWARE')][string]$ChecksumMode='HARDWARE',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'logs\physical_board'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$base = Join-Path $OutputDirectory "v40_${IoMode}_${ChecksumMode}_udp_rx_only_${PayloadBytes}B_${RatePps}pps_$stamp"

Write-Host 'V40 UDP RX-only board test (manual FPGA programming required)'
Write-Host "Label: $IoMode / $ChecksumMode; set SW0/SW5 before reset and check UART."
Write-Host 'Required switches at reset: SW4:SW3=01; SW0=0 PIO or 1 SGDMA.'
Write-Host 'SW1 selects profiling. SW2 is the runtime UART quiet switch.'
Write-Host "Target       : $TargetIp`:$Port"
Write-Host "Payload      : $PayloadBytes bytes"
Write-Host "Target rate  : $RatePps packets/s"
Write-Host "Duration     : $DurationSeconds s"
Write-Host 'Mode guard   : any UDP reply is an error because RX-only sink must not echo'
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter')
}

$socket = [Net.Sockets.Socket]::new(
    [Net.Sockets.AddressFamily]::InterNetwork,
    [Net.Sockets.SocketType]::Dgram,
    [Net.Sockets.ProtocolType]::Udp)
$socket.SendBufferSize = 4 * 1024 * 1024
$socket.ReceiveBufferSize = 4 * 1024 * 1024
$socket.Blocking = $false
$socket.Connect([Net.IPEndPoint]::new([Net.IPAddress]::Parse($TargetIp), $Port))

$payload = New-Object byte[] $PayloadBytes
$payload[0] = 0x56 # V
$payload[1] = 0x33 # 3
$payload[2] = 0x34 # 4
$payload[3] = 0x52 # R
for ($i = 12; $i -lt $PayloadBytes; $i++) {
    $payload[$i] = [byte](($i * 31 + 7) -band 0xff)
}

$targetPackets = [int64]$RatePps * $DurationSeconds
$interval = 1.0 / [double]$RatePps
$nextSend = 0.0
$scheduled = 0
$sent = 0
$sendErrors = 0
$unexpectedReplies = 0
$receiveErrors = 0
$receiveBuffer = New-Object byte[] ($PayloadBytes + 64)
$lateSchedules = 0
$lastReport = -1
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $now = $watch.Elapsed.TotalSeconds
        if (($scheduled -lt $targetPackets) -and ($now -ge $nextSend)) {
            $sequenceBytes = [BitConverter]::GetBytes([uint32]$scheduled)
            [Array]::Copy($sequenceBytes, 0, $payload, 4, 4)
            [Array]::Copy($sequenceBytes, 0, $payload, 8, 4)
            try {
                if ($socket.Send($payload) -eq $PayloadBytes) { $sent++ }
                else { $sendErrors++ }
            } catch [Net.Sockets.SocketException] {
                $sendErrors++
            }
            $scheduled++
            if ($now -gt ($nextSend + $interval)) { $lateSchedules++ }
            $nextSend += $interval
        }

        $receiveBudget = 8
        while (($receiveBudget -gt 0) -and
               $socket.Poll(0, [Net.Sockets.SelectMode]::SelectRead)) {
            try {
                [void]$socket.Receive($receiveBuffer)
                $unexpectedReplies++
            } catch [Net.Sockets.SocketException] {
                $receiveErrors++
                break
            }
            $receiveBudget--
        }

        $second = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($second -gt $lastReport) {
            $lastReport = $second
            Write-Host "t=${second}s sent=$sent"
        }
        if (($nextSend - $watch.Elapsed.TotalSeconds) -gt 0.002) {
            Start-Sleep -Milliseconds 1
        } else {
            [Threading.Thread]::Sleep(0)
        }
    }
} finally {
    $watch.Stop()
    $socket.Dispose()
}

$result = [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Mode = 'UDP_RX_ONLY'
    IoMode=$IoMode; ChecksumMode=$ChecksumMode
    TargetIp = $TargetIp
    Port = $Port
    PayloadBytes = $PayloadBytes
    TargetRatePps = $RatePps
    DurationSeconds = $DurationSeconds
    TargetPackets = $targetPackets
    Scheduled = $scheduled
    Sent = $sent
    SendErrors = $sendErrors
    UnexpectedReplies = $unexpectedReplies
    ReceiveErrors = $receiveErrors
    LateSchedules = $lateSchedules
    ActualSendPps = [double]$sent / $DurationSeconds
    OfferedPayloadMbps = [double]$sent * $PayloadBytes * 8.0 /
        $DurationSeconds / 1000000.0
    BoardAcceptedPackets = 'Read UART delta: UDP_SINK'
    BoardAcceptedBytes = 'Read UART delta: UDP_RX_BYTES'
}
$result | Format-List
$result | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation
$result | ConvertTo-Json | Set-Content -LiteralPath "$base.json" -Encoding UTF8
($result | Format-List | Out-String) | Set-Content -LiteralPath "$base.txt" -Encoding UTF8
Write-Host "Results saved: $base.[csv|json|txt]"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=0, wait for UART FINAL SNAPSHOT, then press Enter')
}
if ($unexpectedReplies -ne 0) {
    throw "RX-only mode guard failed: received $unexpectedReplies UDP replies; verify SW4=0 SW3=1 and reset"
}

