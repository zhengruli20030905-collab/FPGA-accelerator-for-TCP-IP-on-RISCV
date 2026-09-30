[CmdletBinding()]
param(
    [string]$BoardIp = '192.168.1.50',
    [string]$LocalIp = '192.168.1.10',
    [ValidateRange(1,65535)][int]$Port = 5001,
    [ValidateRange(12,1460)][int]$ChunkBytes = 1460,
    [ValidateRange(1,3600)][int]$DurationSeconds = 10,
    [ValidateRange(0,10)][double]$DrainSeconds = 1,
    [switch]$FullPayloadCheck,
    [switch]$NoPrompt,
    [ValidateSet('SGDMA')][string]$IoMode = 'SGDMA',
    [ValidateSet('HARDWARE')][string]$ChecksumMode = 'HARDWARE',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'logs\physical_board'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$base = Join-Path $OutputDirectory "v40_tcp_tx_only_realtime_${ChunkBytes}B_$stamp"

Write-Host 'V40 realtime TCP TX-only board test (manual FPGA programming required)'
Write-Host 'Required switches at reset: SW4:SW3=11, SW0=1, SW1=0, SW5=1.'
Write-Host 'This uses one persistent TCP connection and validates 1460-byte logical chunks.'
Write-Host "Board=$BoardIp`:$Port Local=$LocalIp Duration=${DurationSeconds}s"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter')
}

$client = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
$client.NoDelay = $true
$client.ReceiveBufferSize = 4 * 1024 * 1024
$client.ReceiveTimeout = 1000
$client.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Parse($LocalIp), 0))
$connect = $client.ConnectAsync([Net.IPAddress]::Parse($BoardIp), $Port)
if (-not $connect.Wait(5000)) {
    $client.Dispose()
    throw "TCP connect timeout: $BoardIp`:$Port"
}
$stream = $client.GetStream()
$readBuffer = New-Object byte[] 65536
$chunk = New-Object byte[] $ChunkBytes
$chunkFill = 0
$receivedBytes = [int64]0
$completeBytes = [int64]0
$chunks = 0
$bad = 0
$duplicates = 0
$outOfOrder = 0
$readErrors = 0
$highest = [int64]-1
$lowest = [int64]::MaxValue
$seen = [Collections.Generic.HashSet[uint32]]::new()
$lastReport = -1
$go = [Text.Encoding]::ASCII.GetBytes('V40TCPGO')
$stop = [Text.Encoding]::ASCII.GetBytes('V40TCPSTOP')
$watch = [Diagnostics.Stopwatch]::new()

function Receive-V40TcpData {
    # A fast board can keep DataAvailable asserted continuously. Do not drain
    # the socket without a bound here, otherwise this function never returns
    # to the outer duration/progress loop and V40TCPSTOP is never transmitted.
    $readBudget = 4
    while ($stream.DataAvailable -and $readBudget -gt 0) {
        try {
            $length = $stream.Read($readBuffer, 0, $readBuffer.Length)
        } catch {
            $script:readErrors++
            return
        }
        if ($length -le 0) { return }
        $readBudget--
        $script:receivedBytes += $length
        $offset = 0
        while ($offset -lt $length) {
            $take = [Math]::Min($ChunkBytes - $script:chunkFill, $length - $offset)
            [Buffer]::BlockCopy($readBuffer, $offset, $chunk, $script:chunkFill, $take)
            $script:chunkFill += $take
            $offset += $take
            if ($script:chunkFill -eq $ChunkBytes) {
                $valid = ($chunk[0] -eq 0x56) -and
                         ($chunk[1] -eq 0x34) -and
                         ($chunk[2] -eq 0x30) -and
                         ($chunk[3] -eq 0x43)
                $sequence = [BitConverter]::ToUInt32($chunk, 4)
                $valid = $valid -and
                    ($sequence -eq [BitConverter]::ToUInt32($chunk, 8))
                if ($valid -and $FullPayloadCheck) {
                    for ($i = 12; $i -lt $ChunkBytes; $i++) {
                        if ($chunk[$i] -ne
                            [byte](($sequence + $i * 31 + 7) -band 0xff)) {
                            $valid = $false
                            break
                        }
                    }
                }
                if (-not $valid) {
                    $script:bad++
                } elseif ($seen.Add($sequence)) {
                    if (($script:highest -ge 0) -and
                        ([int64]$sequence -lt $script:highest)) {
                        $script:outOfOrder++
                    }
                    if ([int64]$sequence -gt $script:highest) {
                        $script:highest = $sequence
                    }
                    if ([int64]$sequence -lt $script:lowest) {
                        $script:lowest = $sequence
                    }
                    $script:chunks++
                    $script:completeBytes += $ChunkBytes
                } else {
                    $script:duplicates++
                }
                $script:chunkFill = 0
            }
        }
    }
}

try {
    $stream.Write($go, 0, $go.Length)
    $stream.Flush()
    $watch.Start()
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        Receive-V40TcpData
        $second = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($second -gt $lastReport) {
            $lastReport = $second
            Write-Host "t=${second}s chunks=$chunks bad=$bad bytes=$completeBytes"
        }
        [Threading.Thread]::Sleep(0)
    }
    $stream.Write($stop, 0, $stop.Length)
    $stream.Flush()
    $deadline = $watch.Elapsed.TotalSeconds + $DrainSeconds
    while ($watch.Elapsed.TotalSeconds -lt $deadline) {
        Receive-V40TcpData
        Start-Sleep -Milliseconds 1
    }
} finally {
    $watch.Stop()
    try { $stream.Dispose() } catch { }
    $client.Dispose()
}

$sequenceSpan = if ($chunks -eq 0) { 0 } else { $highest - $lowest + 1 }
$sequenceGaps = [Math]::Max(0, $sequenceSpan - $chunks)
$result = [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Mode = 'TCP_TX_ONLY'
    IoMode = $IoMode
    ChecksumMode = $ChecksumMode
    BoardIp = $BoardIp
    LocalIp = $LocalIp
    Port = $Port
    ChunkBytes = $ChunkBytes
    DurationSeconds = $DurationSeconds
    CompleteChunks = $chunks
    CompletePayloadBytes = $completeBytes
    SocketReceivedBytes = $receivedBytes
    ReceivePps = [double]$chunks / $DurationSeconds
    PayloadGoodputMbps = [double]$completeBytes * 8.0 /
        $DurationSeconds / 1000000.0
    FirstSequence = if ($chunks -eq 0) { $null } else { $lowest }
    LastSequence = if ($chunks -eq 0) { $null } else { $highest }
    SequenceGaps = $sequenceGaps
    BadChunks = $bad
    Duplicates = $duplicates
    OutOfOrder = $outOfOrder
    PartialBytesAtClose = $chunkFill
    ReceiveErrors = $readErrors
    FullPayloadCheck = $FullPayloadCheck.IsPresent -and ($bad -eq 0)
    ConnectionMode = 'ONE_PERSISTENT_CONNECTION'
    SlotReleaseEvidence = 'Read UART delta: TX_TCP_POOL ACK_BYTES/UNACKED/ACK_CB'
}
$result | Format-List
$result | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation
$result | ConvertTo-Json | Set-Content -LiteralPath "$base.json" -Encoding UTF8
($result | Format-List | Out-String) |
    Set-Content -LiteralPath "$base.txt" -Encoding UTF8
Write-Host "Results saved: $base.[csv|json|txt]"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=0, wait for UART FINAL SNAPSHOT, save UART log, then press Enter')
}
