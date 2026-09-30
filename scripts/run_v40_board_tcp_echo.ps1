[CmdletBinding()]
param([string]$TargetIp='192.168.1.50',[int]$Port=5001,[int]$Iterations=1000,[int]$PayloadBytes=256,
 [ValidateSet('PIO','SGDMA')][string]$IoMode='SGDMA',
 [ValidateSet('SOFTWARE','HARDWARE')][string]$ChecksumMode='HARDWARE',[switch]$NoPrompt)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($Iterations -le 0 -or $PayloadBytes -le 0 -or $PayloadBytes -gt 65536){throw 'Invalid test size'}
Write-Host "V40 TCP Echo $IoMode $ChecksumMode; manually program and reset SW4:3=00. SW0=IO, SW5=checksum."
Write-Host 'SW1=0 throughput baseline. UART banner is authoritative; script labels do not switch hardware.'
if(!$NoPrompt){[void](Read-Host 'Set SW2=1, wait ACTIVE, then Enter')}
$client=[Net.Sockets.TcpClient]::new();$client.ReceiveTimeout=3000;$client.SendTimeout=3000
$bytes=[byte[]]::new($PayloadBytes);$reply=[byte[]]::new($PayloadBytes)
for($i=0;$i -lt $PayloadBytes;$i++){$bytes[$i]=[byte]($i%251)}
$count=0;$watch=[Diagnostics.Stopwatch]::new()
try{
 $client.Connect($TargetIp,$Port);$stream=$client.GetStream();$watch.Start()
 for($iteration=0;$iteration -lt $Iterations;$iteration++){
  $stream.Write($bytes,0,$bytes.Length);$offset=0
  while($offset -lt $reply.Length){$got=$stream.Read($reply,$offset,$reply.Length-$offset);if($got -eq 0){throw 'Peer disconnected'};$offset+=$got}
  for($i=0;$i -lt $PayloadBytes;$i++){if($reply[$i] -ne $bytes[$i]){throw "Payload mismatch iteration=$iteration byte=$i"}}
  $count++
 }
 $watch.Stop()
 $result=[pscustomobject]@{Timestamp=(Get-Date -Format o);IoMode=$IoMode;ChecksumMode=$ChecksumMode;Target=$TargetIp;Port=$Port;
  Iterations=$count;PayloadBytes=$PayloadBytes;Bytes=[long]$count*$PayloadBytes;Seconds=$watch.Elapsed.TotalSeconds;
  EchoPayloadGoodputMbps=$count*$PayloadBytes*8.0/$watch.Elapsed.TotalSeconds/1e6;PhysicalBoardPass=$true}
 $log="$root\logs\physical_board";New-Item -ItemType Directory -Force -Path $log | Out-Null
 $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $log ("v40_tcp_"+$IoMode+'_'+$ChecksumMode+'_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.json'))
 $result | Format-List
}finally{$client.Close();if(!$NoPrompt){[void](Read-Host 'Set SW2=0, save FINAL SNAPSHOT, then Enter')}}
