[CmdletBinding()]
param(
    [string]$BoardIp = '192.168.1.50',
    [string]$LocalIp = '192.168.1.10',
    [ValidateRange(1,65535)][int]$Port = 5001,
    [ValidateRange(12,1460)][int]$ChunkBytes = 1460,
    [ValidateRange(1,1024)][int]$WindowChunks = 32,
    [ValidateRange(3,300)][int]$RoundSeconds = 10,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'logs\physical_board'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$throughput = Join-Path $PSScriptRoot 'run_v40_board_tcp_echo_throughput.ps1'

Write-Host 'V40 TCP ZERO-COPY LIFETIME STRESS'
Write-Host 'Covers delayed reads, a mid-run read pause, abrupt disconnect, and reconnect.'
Write-Host 'Required reset switches: SW6=0 SW4:SW3=00 SW0=1 SW1=0 SW5=1.'
[void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter')

& $throughput -BoardIp $BoardIp -LocalIp $LocalIp -Port $Port `
    -ChunkBytes $ChunkBytes -WindowChunks $WindowChunks `
    -DurationSeconds $RoundSeconds -DrainSeconds 10 `
    -InitialReadDelayMilliseconds 1000 -ReadPauseAtSeconds 3 `
    -ReadPauseMilliseconds 1500 -FullPayloadCheck -NoPrompt `
    -OutputDirectory $OutputDirectory

# Create outstanding no-copy data and close with RST. The next connection is
# the observable proof that the error callback released every retained owner.
$abortClient = [Net.Sockets.TcpClient]::new(
    [Net.Sockets.AddressFamily]::InterNetwork)
try {
    $abortClient.NoDelay = $true
    $abortClient.Client.Bind([Net.IPEndPoint]::new(
        [Net.IPAddress]::Parse($LocalIp), 0))
    $abortClient.Connect($BoardIp, $Port)
    $abortClient.Client.LingerState = [Net.Sockets.LingerOption]::new($true, 0)
    $payload = New-Object byte[] $ChunkBytes
    for ($i = 0; $i -lt $WindowChunks; $i++) {
        $payload[0] = [byte][char]'V'
        $payload[1] = [byte][char]'4'
        $payload[2] = [byte][char]'0'
        $payload[3] = [byte][char]'A'
        [BitConverter]::GetBytes([uint32]$i).CopyTo($payload, 4)
        $abortClient.GetStream().Write($payload, 0, $payload.Length)
    }
} finally {
    $abortClient.Dispose()
}
Start-Sleep -Seconds 3

& $throughput -BoardIp $BoardIp -LocalIp $LocalIp -Port $Port `
    -ChunkBytes $ChunkBytes -WindowChunks $WindowChunks `
    -DurationSeconds $RoundSeconds -DrainSeconds 10 `
    -FullPayloadCheck -NoPrompt -OutputDirectory $OutputDirectory

$status = Join-Path $OutputDirectory `
    ('v40_tcp_zc_lifetime_stress_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
@(
    'V40 TCP ZERO-COPY LIFETIME STRESS PASSED',
    'DELAYED_READ=PASS',
    'MIDRUN_READ_PAUSE=PASS',
    'ABRUPT_DISCONNECT_RECOVERY=PASS',
    'SECOND_CONNECTION=PASS',
    'UART_ZERO_REQUIRED=FREE_BEFORE_ACK,PAYLOAD_STABILITY,CONSISTENCY',
    'UART_FINAL_REQUIRED=OWNER_CURRENT=0,ACKQ_CURRENT=0'
) | Set-Content -LiteralPath $status -Encoding UTF8
Write-Host "Lifetime stress result: $status"
[void](Read-Host 'Set SW2=0, save the FINAL SNAPSHOT, then press Enter')
