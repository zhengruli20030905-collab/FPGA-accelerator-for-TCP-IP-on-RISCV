$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$build = Join-Path $root 'build\host_tcp_zero_copy'
$log = Join-Path $root 'logs\v40_tcp_zero_copy_host_test'
New-Item -ItemType Directory -Force -Path $build,$log | Out-Null
$exe = Join-Path $build 'test_tcp_zero_copy.exe'
$gcc = (Get-Command gcc -ErrorAction Stop).Source

Push-Location $root
try {
    & $gcc -std=c11 -O2 -Wall -Wextra -Werror `
        '-Isim/host_tcp_zero_copy' '-Isoftware' `
        'software/net/tcp_zero_copy_lifetime.c' `
        'sim/host_tcp_zero_copy/test_tcp_zero_copy.c' `
        -o $exe 2>&1 | Tee-Object -FilePath (Join-Path $log 'compile.log')
    if ($LASTEXITCODE) { throw 'V40 TCP zero-copy host compile failed' }
    & $exe 2>&1 | Tee-Object -FilePath (Join-Path $log 'run.log')
    if ($LASTEXITCODE -or
        !(Select-String -LiteralPath (Join-Path $log 'run.log') `
            -SimpleMatch 'V40 TCP ZERO-COPY ACK LIFETIME HOST TEST PASSED')) {
        throw 'V40 TCP zero-copy host test failed'
    }
    @(
        'V40 TCP ZERO-COPY ACK LIFETIME HOST TEST PASSED',
        'ACTUAL_SOURCE=software/net/tcp_zero_copy_lifetime.c',
        'SINGLE_PBUF_PARTIAL_ACK=PASS',
        'MULTI_PBUF_NODE_CUMULATIVE_ACK=PASS',
        'MULTI_OWNER_ACK=PASS',
        'ERR_MEM_POINTER_RETRY=PASS',
        'PAYLOAD_STABILITY_GUARD=PASS',
        'OWNER_EXHAUSTION_RECOVERY=PASS',
        'ABORT_RELEASE=PASS',
        'QUEUE_WRAP_12000=PASS'
    ) | Set-Content -LiteralPath (Join-Path $log 'summary.txt')
} finally {
    Pop-Location
}
