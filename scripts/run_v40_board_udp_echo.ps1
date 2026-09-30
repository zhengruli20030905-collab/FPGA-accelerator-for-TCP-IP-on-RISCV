[CmdletBinding()]
param(
    [string]$TargetIp = '192.168.1.50',
    [ValidateRange(1,65535)][int]$Port = 1234,
    [ValidateRange(12,1472)][int]$PayloadBytes = 1472,
    [ValidateRange(1,100000)][int]$RatePps = 200,
    [ValidateRange(1,3600)][int]$DurationSeconds = 10,
    [ValidateRange(0,30)][double]$DrainSeconds = 3,
    [switch]$FullPayloadCheck,
    [switch]$NoPrompt,
    [ValidateSet('PIO','SGDMA')][string]$IoMode='SGDMA',
    [ValidateSet('SOFTWARE','HARDWARE')][string]$ChecksumMode='HARDWARE',
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
$base = Join-Path $OutputDirectory "v40_${IoMode}_${ChecksumMode}_udp_echo_${PayloadBytes}B_${RatePps}pps_$stamp"

Write-Host 'V40 UDP echo physical-board test (manual FPGA programming required)'
Write-Host "Label: $IoMode / $ChecksumMode. Set SW0 and SW5 before reset; verify UART banner. SW1=0 for throughput."
Write-Host 'Reset switches: SW4:SW3=00; SW0=0 PIO or 1 SGDMA; SW1=0 performance, 1 diagnostic profiling.'
Write-Host "Target=$TargetIp`:$Port Payload=$PayloadBytes Rate=$RatePps Duration=${DurationSeconds}s"
if (!$NoPrompt) { [void](Read-Host 'Set SW2=1, wait for UART ACTIVE, then press Enter') }

$socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,
    [Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$socket.SendBufferSize = 4MB
$socket.ReceiveBufferSize = 4MB
$socket.Blocking = $false
$socket.Connect([Net.IPEndPoint]::new([Net.IPAddress]::Parse($TargetIp),$Port))
$payload = New-Object byte[] $PayloadBytes
$receive = New-Object byte[] 2048
$seen = [Collections.Generic.HashSet[uint32]]::new()
for ($i=12; $i -lt $PayloadBytes; $i++) { $payload[$i] = [byte](($i*31+7)-band 0xff) }
$target = [int64]$RatePps*$DurationSeconds
$interval = 1.0/[double]$RatePps
$scheduled=0; $sent=0; $bad=0; $sendErrors=0; $receiveErrors=0; $late=0
$watch=[Diagnostics.Stopwatch]::StartNew(); $nextSend=0.0
try {
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $now=$watch.Elapsed.TotalSeconds
        if ($scheduled -lt $target -and $now -ge $nextSend) {
            $bytes=[BitConverter]::GetBytes([uint32]$scheduled)
            [Array]::Copy($bytes,0,$payload,0,4); [Array]::Copy($bytes,0,$payload,4,4)
            try { if ($socket.Send($payload) -eq $PayloadBytes) {$sent++} else {$sendErrors++} }
            catch [Net.Sockets.SocketException] {$sendErrors++}
            $scheduled++; if ($now -gt $nextSend+$interval) {$late++}; $nextSend += $interval
        }
        while ($socket.Poll(0,[Net.Sockets.SelectMode]::SelectRead)) {
            try {$n=$socket.Receive($receive)} catch [Net.Sockets.SocketException] {$receiveErrors++; break}
            if ($n -ne $PayloadBytes) {$bad++; continue}
            $seq=[BitConverter]::ToUInt32($receive,0)
            if ($seq -ne [BitConverter]::ToUInt32($receive,4)) {$bad++; continue}
            if ($FullPayloadCheck) {
                $ok=$true
                for ($i=12; $i -lt $PayloadBytes; $i++) {
                    if ($receive[$i] -ne [byte](($i*31+7)-band 0xff)) {$ok=$false; break}
                }
                if (!$ok) {$bad++; continue}
            }
            [void]$seen.Add($seq)
        }
        if (($nextSend-$watch.Elapsed.TotalSeconds) -gt 0.002) {Start-Sleep -Milliseconds 1}
        else {[Threading.Thread]::Sleep(0)}
    }
    $deadline=$watch.Elapsed.TotalSeconds+$DrainSeconds
    while ($watch.Elapsed.TotalSeconds -lt $deadline -and $seen.Count -lt $sent) {
        if ($socket.Poll(1000,[Net.Sockets.SelectMode]::SelectRead)) {
            try {$n=$socket.Receive($receive)} catch [Net.Sockets.SocketException] {$receiveErrors++; continue}
            if ($n -eq $PayloadBytes) {[void]$seen.Add([BitConverter]::ToUInt32($receive,0))} else {$bad++}
        }
    }
} finally {$watch.Stop(); $socket.Dispose()}
$lost=$sent-$seen.Count
$result=[pscustomobject]@{
    Timestamp=(Get-Date).ToString('o'); Mode='UDP_ECHO'; TargetIp=$TargetIp; Port=$Port
    IoMode=$IoMode; ChecksumMode=$ChecksumMode
    PayloadBytes=$PayloadBytes; TargetRatePps=$RatePps; DurationSeconds=$DurationSeconds
    Sent=$sent; UniqueReplies=$seen.Count; Lost=$lost
    LossPercent=if($sent){100.0*$lost/$sent}else{100.0}; BadReplies=$bad
    SendErrors=$sendErrors; ReceiveErrors=$receiveErrors; LateSchedules=$late
    ReplyPps=[double]$seen.Count/$DurationSeconds
    ReplyPayloadGoodputMbps=[double]$seen.Count*$PayloadBytes*8/$DurationSeconds/1e6
    FullPayloadCheck=$FullPayloadCheck.IsPresent
}
$result | Format-List
$result | Export-Csv "$base.csv" -NoTypeInformation
$result | ConvertTo-Json | Set-Content "$base.json" -Encoding utf8
($result | Format-List | Out-String) | Set-Content "$base.txt" -Encoding utf8
Write-Host "Results saved: $base.[csv|json|txt]"
if (!$NoPrompt) {[void](Read-Host 'Set SW2=0, wait for UART FINAL SNAPSHOT, save UART log, then press Enter')}
