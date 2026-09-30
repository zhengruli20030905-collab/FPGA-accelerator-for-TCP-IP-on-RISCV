param(
    [string]$TargetIp = '192.168.1.50',
    [int]$Port = 1234,
    [int[]]$Lengths = @(1,2,3,4,5,60,64,511,512,513,1472),
    [ValidateRange(1,100)][int]$Iterations = 3,
    [ValidateRange(100,30000)][int]$ReceiveTimeoutMs = 3000,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'logs\physical_board'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

foreach ($length in $Lengths) {
    if ($length -lt 1 -or $length -gt 1472) {
        throw "Invalid UDP payload length: $length"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$base = Join-Path $OutputDirectory "v40_udp_boundary_$stamp"
$udp = [System.Net.Sockets.UdpClient]::new()
$udp.Client.ReceiveTimeout = $ReceiveTimeoutMs
$udp.Connect($TargetIp, $Port)
$results = [System.Collections.Generic.List[object]]::new()
$allPass = $true

Write-Host 'V40 UDP echo payload boundary test'
Write-Host "Target     : $TargetIp`:$Port"
Write-Host "Iterations : $Iterations per length"

try {
    foreach ($length in $Lengths) {
        $passed = 0
        $failure = ''
        for ($iteration = 0; $iteration -lt $Iterations; $iteration++) {
            $payload = [byte[]]::new($length)
            for ($index = 0; $index -lt $length; $index++) {
                $payload[$index] = [byte](($index * 31 + $length * 7 + $iteration * 17) -band 0xff)
            }

            try {
                $sent = $udp.Send($payload, $payload.Length)
                if ($sent -ne $length) {
                    $failure = "short send: $sent"
                    break
                }
                $remote = [System.Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
                $reply = $udp.Receive([ref]$remote)
                if ($reply.Length -ne $length) {
                    $failure = "reply length $($reply.Length)"
                    break
                }
                $mismatch = -1
                for ($index = 0; $index -lt $length; $index++) {
                    if ($reply[$index] -ne $payload[$index]) {
                        $mismatch = $index
                        break
                    }
                }
                if ($mismatch -ge 0) {
                    $failure = "payload mismatch at byte $mismatch"
                    break
                }
                $passed++
            } catch {
                $failure = $_.Exception.Message
                break
            }
        }

        $ok = ($passed -eq $Iterations)
        if (!$ok) { $allPass = $false }
        $results.Add([pscustomobject]@{
            Length = $length
            Iterations = $Iterations
            Passed = $passed
            Result = $(if ($ok) { 'PASS' } else { 'FAIL' })
            Failure = $failure
        })
        if ($ok) {
            Write-Host "LEN=$length PASS ($passed/$Iterations)"
        } else {
            Write-Host "LEN=$length FAIL ($passed/$Iterations) $failure"
        }
    }
} finally {
    $udp.Close()
}

$results | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json | Set-Content -LiteralPath "$base.json" -Encoding UTF8
$text = @(
    "Timestamp=$(Get-Date -Format o)",
    "Target=$TargetIp`:$Port",
    "Iterations=$Iterations",
    "Overall=$(if ($allPass) { 'PASS' } else { 'FAIL' })"
) + @($results | ForEach-Object {
    "LEN=$($_.Length) RESULT=$($_.Result) PASSED=$($_.Passed)/$($_.Iterations) FAILURE=$($_.Failure)"
})
$text | Set-Content -LiteralPath "$base.txt" -Encoding UTF8

Write-Host "Results saved: $base.[csv|json|txt]"
if (!$allPass) { throw 'V40 UDP boundary test failed' }
Write-Host 'V40 UDP BOUNDARY TEST PASSED'
