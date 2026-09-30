[CmdletBinding()]
param(
    [string]$BoardIp = '192.168.1.50',
    [string]$LocalIp = '192.168.1.10',
    [ValidateRange(1,65535)][int]$Port = 5001,
    [ValidateRange(64,1460)][int]$ChunkBytes = 1460,
    [ValidateRange(1,128)][int]$BatchChunks = 32,
    [ValidateRange(1,3600)][int]$DurationSeconds = 60,
    [ValidateRange(0,30)][double]$DrainSeconds = 3,
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
    "v40_SGDMA_HARDWARE_tcp_rx_only_${ChunkBytes}B_$stamp"

Write-Host 'V40 TCP RX-only board test (manual FPGA programming required)'
Write-Host 'Required switches at reset: SW6=1, SW4:SW3=00, SW0=1, SW1=0, SW5=1.'
Write-Host 'UART must show: V40 TEST_MODE=TCP_RX_ONLY_SINK.'
Write-Host "Target=$BoardIp`:$Port Local=$LocalIp Chunk=$ChunkBytes Duration=${DurationSeconds}s"
if (-not $NoPrompt) {
    [void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter')
}

$client = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
$client.NoDelay = $true
$client.SendBufferSize = 65536
$client.ReceiveBufferSize = 65536
$client.SendTimeout = 5000
$client.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Parse($LocalIp), 0))
$connect = $client.ConnectAsync([Net.IPAddress]::Parse($BoardIp), $Port)
if (-not $connect.Wait(5000)) {
    $client.Dispose()
    throw "TCP connect timeout: $BoardIp`:$Port"
}

$stream = $client.GetStream()
$sendBuffer = New-Object byte[] ($ChunkBytes * $BatchChunks)
for ($i = 0; $i -lt $sendBuffer.Length; $i++) {
    $sendBuffer[$i] = [byte](($i * 31 + 7) -band 0xff)
}
$readBuffer = New-Object byte[] 65536
$sentBytes = [int64]0
$sentBatches = [int64]0
$sendErrors = 0
$unexpectedBytes = [int64]0
$receiveErrors = 0
$lastReport = -1
$watch = [Diagnostics.Stopwatch]::new()

function Read-UnexpectedApplicationData {
    while ($stream.DataAvailable) {
        try {
            $length = $stream.Read($readBuffer, 0, $readBuffer.Length)
        } catch {
            $script:receiveErrors++
            return
        }
        if ($length -le 0) { return }
        $script:unexpectedBytes += $length
    }
}

try {
    $watch.Start()
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        try {
            $stream.Write($sendBuffer, 0, $sendBuffer.Length)
            $sentBytes += $sendBuffer.Length
            $sentBatches++
        } catch {
            $sendErrors++
            break
        }
        Read-UnexpectedApplicationData
        if ($unexpectedBytes -ne 0) { break }
        $second = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($second -gt $lastReport) {
            $lastReport = $second
            Write-Host "t=${second}s bytes=$sentBytes unexpected=$unexpectedBytes"
        }
    }
    try { $client.Client.Shutdown([Net.Sockets.SocketShutdown]::Send) } catch { }
    $deadline = $watch.Elapsed.TotalSeconds + $DrainSeconds
    while ($watch.Elapsed.TotalSeconds -lt $deadline) {
        Read-UnexpectedApplicationData
        if (($client.Client.Poll(1000, [Net.Sockets.SelectMode]::SelectRead)) -and
            ($client.Client.Available -eq 0)) { break }
        Start-Sleep -Milliseconds 1
    }
} finally {
    $watch.Stop()
    try { $stream.Dispose() } catch { }
    $client.Dispose()
}

$result = [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Mode = 'TCP_RX_ONLY'
    IoMode = $IoMode
    ChecksumMode = $ChecksumMode
    BoardIp = $BoardIp
    LocalIp = $LocalIp
    Port = $Port
    ChunkBytes = $ChunkBytes
    BatchChunks = $BatchChunks
    DurationSeconds = $DurationSeconds
    SocketSubmittedBytes = $sentBytes
    SocketSubmittedChunks = [int64]($sentBytes / $ChunkBytes)
    SourcePayloadGoodputMbps = [double]$sentBytes * 8.0 /
        $DurationSeconds / 1000000.0
    SendErrors = $sendErrors
    UnexpectedApplicationBytes = $unexpectedBytes
    ReceiveErrors = $receiveErrors
    BoardAcceptedBytes = 'Read UART delta: TCP_RX'
    BoardTransmittedPayloadBytes = 'Read UART delta: TCP_TX; expected 0'
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
if ($unexpectedBytes -ne 0) {
    throw "TCP RX-only mode guard failed: received $unexpectedBytes application bytes; board is probably still in TCP Echo mode"
}
if ($sendErrors -ne 0 -or $receiveErrors -ne 0) {
    throw "TCP RX-only host errors: send=$sendErrors receive=$receiveErrors"
}
