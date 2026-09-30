[CmdletBinding()]
param(
    [string]$BoardIp = '192.168.1.50',
    [string]$LocalIp = '192.168.1.10',
    [ValidateRange(1,65535)][int]$Port = 5001,
    [ValidateRange(12,1460)][int]$ChunkBytes = 1460,
    [ValidateRange(1,1024)][int]$WindowChunks = 32,
    [ValidateRange(1,3600)][int]$DurationSeconds = 60,
    [ValidateRange(1,60)][double]$DrainSeconds = 10,
    [ValidateRange(0,30000)][int]$InitialReadDelayMilliseconds = 0,
    [ValidateRange(0,3600)][double]$ReadPauseAtSeconds = 0,
    [ValidateRange(0,30000)][int]$ReadPauseMilliseconds = 0,
    [switch]$FullPayloadCheck = $true,
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
$base = Join-Path $OutputDirectory `
    "v40_tcp_echo_throughput_${ChunkBytes}B_w${WindowChunks}_$stamp"

# Keep payload generation and full validation out of the PowerShell byte loop.
# This helper is compiled before timing starts, so it does not affect throughput.
if (-not ('V40TcpEchoPatternCodec' -as [type])) {
    Add-Type -TypeDefinition @'
using System;

public static class V40TcpEchoPatternCodec
{
    private static void WriteUInt32LE(byte[] buffer, int offset, uint value)
    {
        buffer[offset + 0] = (byte)(value >> 0);
        buffer[offset + 1] = (byte)(value >> 8);
        buffer[offset + 2] = (byte)(value >> 16);
        buffer[offset + 3] = (byte)(value >> 24);
    }

    private static uint ReadUInt32LE(byte[] buffer, int offset)
    {
        return (uint)(buffer[offset + 0]
            | ((uint)buffer[offset + 1] << 8)
            | ((uint)buffer[offset + 2] << 16)
            | ((uint)buffer[offset + 3] << 24));
    }

    public static void Fill(byte[] buffer, int length, uint sequence)
    {
        if (buffer == null || length < 12 || length > buffer.Length)
            throw new ArgumentOutOfRangeException("length");

        buffer[0] = (byte)'V';
        buffer[1] = (byte)'3';
        buffer[2] = (byte)'0';
        buffer[3] = (byte)'E';
        WriteUInt32LE(buffer, 4, sequence);
        WriteUInt32LE(buffer, 8, sequence);
        for (int i = 12; i < length; i++)
            buffer[i] = unchecked((byte)(sequence + (uint)(i * 31 + 7)));
    }

    public static bool Validate(byte[] buffer, int length, bool full,
                                out uint sequence)
    {
        sequence = 0;
        if (buffer == null || length < 12 || length > buffer.Length)
            return false;
        if (buffer[0] != (byte)'V' || buffer[1] != (byte)'3' ||
            buffer[2] != (byte)'0' || buffer[3] != (byte)'E')
            return false;

        sequence = ReadUInt32LE(buffer, 4);
        if (sequence != ReadUInt32LE(buffer, 8))
            return false;
        if (!full)
            return true;

        for (int i = 12; i < length; i++) {
            byte expected = unchecked((byte)(sequence + (uint)(i * 31 + 7)));
            if (buffer[i] != expected)
                return false;
        }
        return true;
    }
}
'@
}

Write-Host 'V40 pipelined TCP Echo throughput test (manual FPGA programming required)'
Write-Host 'Required switches at reset: SW6=0, SW4:SW3=00, SW0=1, SW1=0, SW5=1.'
Write-Host 'UART must show SGDMA, HARDWARE checksum, and default UDP_ECHO mode.'
Write-Host 'TCP is a byte stream: this script reconstructs and validates fixed logical chunks.'
Write-Host "Board=$BoardIp`:$Port Local=$LocalIp Chunk=$ChunkBytes Window=$WindowChunks Duration=${DurationSeconds}s"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter')
}

$client = [Net.Sockets.TcpClient]::new(
    [Net.Sockets.AddressFamily]::InterNetwork)
$client.NoDelay = $true
$client.SendBufferSize = 4 * 1024 * 1024
$client.ReceiveBufferSize = 4 * 1024 * 1024
$client.Client.Bind([Net.IPEndPoint]::new(
    [Net.IPAddress]::Parse($LocalIp), 0))
$connect = $client.ConnectAsync([Net.IPAddress]::Parse($BoardIp), $Port)
try {
    if (-not $connect.Wait(5000)) {
        throw "TCP connect timeout: $BoardIp`:$Port"
    }
    [void]$connect.GetAwaiter().GetResult()
} catch {
    $detail = $_.Exception.GetBaseException().Message
    $client.Dispose()
    throw "TCP connect failed: $BoardIp`:$Port ($detail)"
}

$socket = $client.Client
$socket.Blocking = $false
$txChunk = New-Object byte[] $ChunkBytes
$rxChunk = New-Object byte[] $ChunkBytes
$rxBuffer = New-Object byte[] 65536

$txSequence = [uint32]0
$txOffset = 0
$txActive = $false
$bytesSent = [int64]0
$chunksSent = [int64]0

$rxFill = 0
$bytesReceived = [int64]0
$completeBytes = [int64]0
$chunksReceived = [int64]0
$badChunks = [int64]0
$sequenceGaps = [int64]0
$duplicates = [int64]0
$outOfOrder = [int64]0
$expectedSequence = [uint64]0
$readErrors = [int64]0
$writeErrors = [int64]0
$remoteClosed = $false
$maxOutstandingBytes = [int64]$WindowChunks * $ChunkBytes
$maxObservedOutstandingBytes = [int64]0
$lastReport = -1
$watch = [Diagnostics.Stopwatch]::new()

function Receive-V40EchoData {
    param([int]$ReadBudget = 8)

    while ($ReadBudget -gt 0 -and -not $script:remoteClosed -and
           $socket.Poll(0, [Net.Sockets.SelectMode]::SelectRead)) {
        try {
            $length = $socket.Receive($rxBuffer, 0, $rxBuffer.Length,
                [Net.Sockets.SocketFlags]::None)
        } catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq
                [Net.Sockets.SocketError]::WouldBlock) {
                return
            }
            $script:readErrors++
            throw
        }
        if ($length -eq 0) {
            $script:remoteClosed = $true
            return
        }

        $ReadBudget--
        $script:bytesReceived += $length
        $offset = 0
        while ($offset -lt $length) {
            $take = [Math]::Min($ChunkBytes - $script:rxFill,
                $length - $offset)
            [Buffer]::BlockCopy($rxBuffer, $offset, $rxChunk,
                $script:rxFill, $take)
            $script:rxFill += $take
            $offset += $take

            if ($script:rxFill -eq $ChunkBytes) {
                $sequence = [uint32]0
                $valid = [V40TcpEchoPatternCodec]::Validate(
                    $rxChunk, $ChunkBytes, $FullPayloadCheck.IsPresent,
                    [ref]$sequence)
                if (-not $valid) {
                    $script:badChunks++
                } else {
                    $sequence64 = [uint64]$sequence
                    if ($sequence64 -eq $script:expectedSequence) {
                        $script:expectedSequence++
                    } elseif ($sequence64 -gt $script:expectedSequence) {
                        $script:sequenceGaps +=
                            $sequence64 - $script:expectedSequence
                        $script:expectedSequence = $sequence64 + 1
                    } elseif (($script:expectedSequence - $sequence64) -eq 1) {
                        $script:duplicates++
                    } else {
                        $script:outOfOrder++
                    }
                    $script:chunksReceived++
                    $script:completeBytes += $ChunkBytes
                }
                $script:rxFill = 0
            }
        }
    }
}

function Test-V40ReadAllowed {
    $elapsedMs = $watch.Elapsed.TotalMilliseconds
    if ($elapsedMs -lt $InitialReadDelayMilliseconds) { return $false }
    if ($ReadPauseMilliseconds -ne 0) {
        $pauseStartMs = $ReadPauseAtSeconds * 1000.0
        if ($elapsedMs -ge $pauseStartMs -and
            $elapsedMs -lt ($pauseStartMs + $ReadPauseMilliseconds)) {
            return $false
        }
    }
    return $true
}

function Send-V40EchoData {
    param(
        [bool]$AllowNewChunks,
        [int]$WriteBudget = 8
    )

    while ($WriteBudget -gt 0 -and -not $script:remoteClosed) {
        if (-not $script:txActive) {
            if (-not $AllowNewChunks) { return }
            if (($script:bytesSent - $script:bytesReceived) -ge
                $maxOutstandingBytes) { return }

            [V40TcpEchoPatternCodec]::Fill(
                $txChunk, $ChunkBytes, $script:txSequence)
            $script:txOffset = 0
            $script:txActive = $true
        }

        if (-not $socket.Poll(0, [Net.Sockets.SelectMode]::SelectWrite)) {
            return
        }
        try {
            $sent = $socket.Send($txChunk, $script:txOffset,
                $ChunkBytes - $script:txOffset,
                [Net.Sockets.SocketFlags]::None)
        } catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq
                [Net.Sockets.SocketError]::WouldBlock) {
                return
            }
            $script:writeErrors++
            throw
        }
        if ($sent -le 0) { return }

        $WriteBudget--
        $script:txOffset += $sent
        $script:bytesSent += $sent
        $outstanding = $script:bytesSent - $script:bytesReceived
        if ($outstanding -gt $script:maxObservedOutstandingBytes) {
            $script:maxObservedOutstandingBytes = $outstanding
        }
        if ($script:txOffset -eq $ChunkBytes) {
            $script:chunksSent++
            $script:txSequence++
            $script:txOffset = 0
            $script:txActive = $false
        }
    }
}

try {
    $watch.Start()
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds -and
           -not $remoteClosed) {
        $before = $bytesSent + $bytesReceived
        if (Test-V40ReadAllowed) { Receive-V40EchoData -ReadBudget 8 }
        Send-V40EchoData -AllowNewChunks $true -WriteBudget 8
        if (Test-V40ReadAllowed) { Receive-V40EchoData -ReadBudget 8 }

        $second = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($second -gt $lastReport) {
            $lastReport = $second
            $outstanding = $bytesSent - $bytesReceived
            Write-Host "t=${second}s sent=$chunksSent echoed=$chunksReceived bad=$badChunks outstandingB=$outstanding"
        }
        if (($bytesSent + $bytesReceived) -eq $before) {
            Start-Sleep -Milliseconds 1
        } else {
            [Threading.Thread]::Sleep(0)
        }
    }

    $windowSeconds = $watch.Elapsed.TotalSeconds
    $windowEchoedBytes = $completeBytes
    $windowEchoedChunks = $chunksReceived

    # Do not leave a partial logical chunk in the TCP stream. Finish only the
    # chunk already started at the duration boundary, then half-close TX.
    while ($txActive -and -not $remoteClosed) {
        $before = $bytesSent + $bytesReceived
        Receive-V40EchoData -ReadBudget 16
        Send-V40EchoData -AllowNewChunks $false -WriteBudget 8
        if (($bytesSent + $bytesReceived) -eq $before) {
            Start-Sleep -Milliseconds 1
        }
    }
    try { $socket.Shutdown([Net.Sockets.SocketShutdown]::Send) } catch { }

    $drain = [Diagnostics.Stopwatch]::StartNew()
    while ($bytesReceived -lt $bytesSent -and
           $drain.Elapsed.TotalSeconds -lt $DrainSeconds -and
           -not $remoteClosed) {
        $before = $bytesReceived
        Receive-V40EchoData -ReadBudget 32
        if ($bytesReceived -eq $before) {
            Start-Sleep -Milliseconds 1
        }
    }
    $drain.Stop()
    Receive-V40EchoData -ReadBudget 64
    $watch.Stop()

    $allEchoed = ($bytesReceived -eq $bytesSent) -and
        ($chunksReceived -eq $chunksSent) -and ($rxFill -eq 0)
    $validationPassed = ($badChunks -eq 0) -and
        ($sequenceGaps -eq 0) -and ($duplicates -eq 0) -and
        ($outOfOrder -eq 0)

    $result = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Mode = 'TCP_ECHO_PIPELINED'
        IoMode = $IoMode
        ChecksumMode = $ChecksumMode
        BoardIp = $BoardIp
        LocalIp = $LocalIp
        Port = $Port
        ChunkBytes = $ChunkBytes
        WindowChunks = $WindowChunks
        InitialReadDelayMilliseconds = $InitialReadDelayMilliseconds
        ReadPauseAtSeconds = $ReadPauseAtSeconds
        ReadPauseMilliseconds = $ReadPauseMilliseconds
        DurationSeconds = $DurationSeconds
        ActualWindowSeconds = $windowSeconds
        SentChunks = $chunksSent
        SentBytes = $bytesSent
        EchoedChunks = $chunksReceived
        EchoedBytes = $completeBytes
        WindowEchoedChunks = $windowEchoedChunks
        WindowEchoedBytes = $windowEchoedBytes
        WindowGoodputMbps = [double]$windowEchoedBytes * 8.0 /
            $DurationSeconds / 1000000.0
        OfferedPayloadMbps = [double]$bytesSent * 8.0 /
            $DurationSeconds / 1000000.0
        EchoPayloadGoodputMbps = [double]$completeBytes * 8.0 /
            $DurationSeconds / 1000000.0
        CompletionGoodputMbps = [double]$completeBytes * 8.0 /
            $watch.Elapsed.TotalSeconds / 1000000.0
        TotalElapsedSeconds = $watch.Elapsed.TotalSeconds
        DrainElapsedSeconds = $drain.Elapsed.TotalSeconds
        OutstandingBytesAtClose = $bytesSent - $bytesReceived
        MaxObservedOutstandingBytes = $maxObservedOutstandingBytes
        BadChunks = $badChunks
        SequenceGaps = $sequenceGaps
        Duplicates = $duplicates
        OutOfOrder = $outOfOrder
        PartialBytesAtClose = $rxFill
        ReadErrors = $readErrors
        WriteErrors = $writeErrors
        RemoteClosed = $remoteClosed
        AllEchoed = $allEchoed
        PayloadValidation = if ($FullPayloadCheck) {
            'FULL_PAYLOAD'
        } else {
            'MAGIC_AND_SEQUENCE'
        }
        FullPayloadCheck = $FullPayloadCheck.IsPresent -and
            $validationPassed -and $allEchoed
        PhysicalBoardPass = $validationPassed -and $allEchoed -and
            ($readErrors -eq 0) -and ($writeErrors -eq 0)
        BoardCounterEvidence =
            'Read UART delta: TCP_RX/TCP_TX, PATH_RX/PATH_TX, SG TX/RX'
    }

    $result | Format-List
    $result | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation
    $result | ConvertTo-Json | Set-Content -LiteralPath "$base.json" `
        -Encoding UTF8
    ($result | Format-List | Out-String) |
        Set-Content -LiteralPath "$base.txt" -Encoding UTF8
    Write-Host "Results saved: $base.[csv|json|txt]"

    if (-not $result.PhysicalBoardPass) {
        throw 'V40 pipelined TCP Echo validation failed; inspect saved result and UART counters'
    }
} finally {
    try { $socket.Dispose() } catch { }
    $client.Dispose()
    if (-not $NoPrompt) {
        [void](Read-Host 'Set SW2=0, wait for UART FINAL SNAPSHOT, save UART log, then press Enter')
    }
}
