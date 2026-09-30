[CmdletBinding()]
param(
    [string]$BoardIp = '192.168.1.50',
    [string]$LocalIp = '192.168.1.10',
    [ValidateRange(1,65535)][int]$ControlPort = 1234,
    [ValidateRange(1,65535)][int]$ListenPort = 4321,
    [ValidateRange(12,1472)][int]$ExpectedPayloadBytes = 1472,
    [ValidateRange(1,3600)][int]$DurationSeconds = 10,
    [ValidateRange(0,10)][double]$DrainSeconds = 0.25,
    [ValidateRange(1,4096)][int]$ReceiveBatchPackets = 64,
    [switch]$FullPayloadCheck,
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
$base = Join-Path $OutputDirectory "v40_${IoMode}_${ChecksumMode}_udp_tx_only_realtime_${ExpectedPayloadBytes}B_$stamp"

$socket = [Net.Sockets.Socket]::new(
    [Net.Sockets.AddressFamily]::InterNetwork,
    [Net.Sockets.SocketType]::Dgram,
    [Net.Sockets.ProtocolType]::Udp)
$socket.ReceiveBufferSize = 4 * 1024 * 1024
$socket.SendBufferSize = 1024 * 1024
$socket.Blocking = $false
$socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Parse($LocalIp), $ListenPort))
$boardEndpoint = [Net.IPEndPoint]::new([Net.IPAddress]::Parse($BoardIp), $ControlPort)
$remote = [Net.EndPoint][Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
$buffer = New-Object byte[] 2048
$seen = [Collections.Generic.HashSet[uint32]]::new()

Write-Host 'V40 realtime UDP TX-only board test (manual FPGA programming required)'
Write-Host "Label: $IoMode / $ChecksumMode; set SW0/SW5 before reset and check UART."
Write-Host 'Required switches at reset: SW4:SW3=10; SW0=0 PIO or 1 SGDMA.'
Write-Host 'The script sends V40TXGO/V40TXSTOP; every payload is generated during the run.'
Write-Host "Board        : $BoardIp`:$ControlPort"
Write-Host "PC listener  : $LocalIp`:$ListenPort"
Write-Host "Payload      : $ExpectedPayloadBytes bytes"
Write-Host "Duration     : $DurationSeconds s"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter')
}

$received = 0
$bad = 0
$duplicate = 0
$outOfOrder = 0
$highest = [int64]-1
$lowest = [int64]::MaxValue
$receiveErrors = 0
$lastReport = -1
$go = [Text.Encoding]::ASCII.GetBytes('V40TXGO')
$stop = [Text.Encoding]::ASCII.GetBytes('V40TXSTOP')
$watch = [Diagnostics.Stopwatch]::new()

function Receive-Available {
    param([int]$MaxPackets = 64)

    # Do not drain an unbounded stream in one call. At high board TX rates the
    # socket can remain readable forever, which would starve the outer timer,
    # progress reporting, and—most importantly—the V40TXSTOP command.
    $processed = 0
    while (($processed -lt $MaxPackets) -and
           $socket.Poll(0, [Net.Sockets.SelectMode]::SelectRead)) {
        try {
            $length = $socket.ReceiveFrom($buffer, [ref]$remote)
        } catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::WouldBlock) { break }
            $script:receiveErrors++
            break
        }
        $processed++
        if (($length -ne $ExpectedPayloadBytes) -or
            ($buffer[0] -ne 0x56) -or ($buffer[1] -ne 0x34) -or
            ($buffer[2] -ne 0x30) -or ($buffer[3] -ne 0x54)) {
            $script:bad++
            continue
        }
        $sequence = [BitConverter]::ToUInt32($buffer, 4)
        if ($sequence -ne [BitConverter]::ToUInt32($buffer, 8)) {
            $script:bad++
            continue
        }
        if ($FullPayloadCheck) {
            $payloadGood = $true
            for ($i = 12; $i -lt $ExpectedPayloadBytes; $i++) {
                if ($buffer[$i] -ne [byte](($sequence + $i * 31 + 7) -band 0xff)) {
                    $payloadGood = $false
                    break
                }
            }
            if (-not $payloadGood) {
                $script:bad++
                continue
            }
        }
        if ($seen.Add($sequence)) {
            if (($script:highest -ge 0) -and ([int64]$sequence -lt $script:highest)) {
                $script:outOfOrder++
            }
            if ([int64]$sequence -gt $script:highest) { $script:highest = $sequence }
            if ([int64]$sequence -lt $script:lowest) { $script:lowest = $sequence }
            $script:received++
        } else {
            $script:duplicate++
        }
    }
}

try {
    # A control datagram alone does not prove that the board TX path has
    # resolved the PC MAC address.  Run a short, unmeasured source burst and
    # wait until one real V40T packet reaches this socket.  With ARP_QUEUEING=0
    # this prevents the first seven packets of the measured run from being
    # replaced while ARP is still pending (the TX pool contains eight slots).
    [void]$socket.SendTo($stop, $boardEndpoint)
    Start-Sleep -Milliseconds 100
    [void]$socket.SendTo($go, $boardEndpoint)
    $warmWatch = [Diagnostics.Stopwatch]::StartNew()
    $warmPacketSeen = $false
    while (($warmWatch.Elapsed.TotalSeconds -lt 2.0) -and (-not $warmPacketSeen)) {
        if (-not $socket.Poll(1000, [Net.Sockets.SelectMode]::SelectRead)) {
            [Threading.Thread]::Sleep(0)
            continue
        }
        try {
            $warmLength = $socket.ReceiveFrom($buffer, [ref]$remote)
        } catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq
                [Net.Sockets.SocketError]::WouldBlock) { continue }
            throw
        }
        $warmPacketSeen = ($warmLength -eq $ExpectedPayloadBytes) -and
            ($buffer[0] -eq 0x56) -and ($buffer[1] -eq 0x34) -and
            ($buffer[2] -eq 0x30) -and ($buffer[3] -eq 0x54)
    }
    $warmWatch.Stop()
    [void]$socket.SendTo($stop, $boardEndpoint)
    if (-not $warmPacketSeen) {
        throw 'UDP TX warm-up failed: no V40T packet arrived within 2 seconds.'
    }

    # Discard every packet belonging to the unmeasured warm-up.  Require a
    # 50 ms quiet interval so none can be mistaken for sequence zero of the
    # measured run.
    $quietWatch = [Diagnostics.Stopwatch]::StartNew()
    while ($quietWatch.Elapsed.TotalMilliseconds -lt 50.0) {
        if (-not $socket.Poll(1000, [Net.Sockets.SelectMode]::SelectRead)) {
            [Threading.Thread]::Sleep(0)
            continue
        }
        try {
            [void]$socket.ReceiveFrom($buffer, [ref]$remote)
            $quietWatch.Restart()
        } catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq
                [Net.Sockets.SocketError]::WouldBlock) { continue }
            throw
        }
    }
    $quietWatch.Stop()

    # V40TXGO resets the firmware sequence counter to zero.  Only packets
    # emitted after this command contribute to the measured result.
    [void]$socket.SendTo($go, $boardEndpoint)
    $watch.Start()
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        Receive-Available -MaxPackets $ReceiveBatchPackets
        $second = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($second -gt $lastReport) {
            $lastReport = $second
            Write-Host "t=${second}s received=$received bad=$bad"
        }
        [Threading.Thread]::Sleep(0)
    }
    [void]$socket.SendTo($stop, $boardEndpoint)
    $drainDeadline = $watch.Elapsed.TotalSeconds + $DrainSeconds
    while ($watch.Elapsed.TotalSeconds -lt $drainDeadline) {
        Receive-Available -MaxPackets $ReceiveBatchPackets
        Start-Sleep -Milliseconds 1
    }
} finally {
    try { [void]$socket.SendTo($stop, $boardEndpoint) } catch { }
    $watch.Stop()
    $socket.Dispose()
}

$sequenceSpan = if ($received -eq 0) { 0 } else { $highest - $lowest + 1 }
$internalSequenceGaps = [Math]::Max(0, $sequenceSpan - $received)
$leadingSequenceGaps = if ($received -eq 0) { 0 } else { $lowest }
$sequenceGaps = $leadingSequenceGaps + $internalSequenceGaps
$result = [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Mode = 'UDP_TX_ONLY'
    IoMode=$IoMode; ChecksumMode=$ChecksumMode
    BoardIp = $BoardIp
    LocalIp = $LocalIp
    ListenPort = $ListenPort
    PayloadBytes = $ExpectedPayloadBytes
    DurationSeconds = $DurationSeconds
    UniquePackets = $received
    ReceivePps = [double]$received / $DurationSeconds
    PayloadGoodputMbps = [double]$received * $ExpectedPayloadBytes * 8.0 /
        $DurationSeconds / 1000000.0
    FirstSequence = if ($received -eq 0) { $null } else { $lowest }
    LastSequence = if ($received -eq 0) { $null } else { $highest }
    SequenceGaps = $sequenceGaps
    LeadingSequenceGaps = $leadingSequenceGaps
    InternalSequenceGaps = $internalSequenceGaps
    BadPackets = $bad
    Duplicates = $duplicate
    OutOfOrder = $outOfOrder
    ReceiveErrors = $receiveErrors
    FullPayloadCheck = $FullPayloadCheck.IsPresent -and ($bad -eq 0)
    PayloadMode = 'REALTIME_SEQUENCE_DEPENDENT'
    BoardGeneratedPackets = 'Read UART delta: UDP_TX_GEN'
    BoardWireFrames = 'Read UART delta: PATH_TX MII'
}
$result | Format-List
$result | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation
$result | ConvertTo-Json | Set-Content -LiteralPath "$base.json" -Encoding UTF8
($result | Format-List | Out-String) | Set-Content -LiteralPath "$base.txt" -Encoding UTF8
Write-Host "Results saved: $base.[csv|json|txt]"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=0, wait for UART FINAL SNAPSHOT, then press Enter')
}

