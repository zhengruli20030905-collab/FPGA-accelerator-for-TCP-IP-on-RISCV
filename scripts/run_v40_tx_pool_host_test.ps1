$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$build = Join-Path $root 'build\host_tx_pool'
$log = Join-Path $root 'logs\v40_tx_pool_host_test'
New-Item -ItemType Directory -Force -Path $build,$log | Out-Null
$exe = Join-Path $build 'test_tx_buffer_pool.exe'
$gcc = (Get-Command gcc -ErrorAction Stop).Source

Push-Location $root
try {
    & $gcc -std=c11 -O2 -Wall -Wextra -Werror `
        '-Isim/host_tx_pool' '-Isoftware' `
        'sim/host_tx_pool/lwip_stubs.c' `
        'software/net/tx_buffer_pool.c' `
        'sim/host_tx_pool/test_tx_buffer_pool.c' `
        -o $exe 2>&1 | Tee-Object -FilePath (Join-Path $log 'compile.log')
    if ($LASTEXITCODE) { throw 'V40 TX pool host compile failed' }
    & $exe 2>&1 | Tee-Object -FilePath (Join-Path $log 'run.log')
    if ($LASTEXITCODE -or
        !(Select-String -LiteralPath (Join-Path $log 'run.log') `
            -SimpleMatch 'V40 TX BUFFER POOL HOST TEST PASSED')) {
        throw 'V40 TX pool host test failed'
    }
    @(
        'V40 TX BUFFER POOL HOST TEST PASSED',
        'ACTUAL_SOURCE=software/net/tx_buffer_pool.c',
        'UDP_REUSE_GT_1000=PASS',
        'MAX_INFLIGHT_8=PASS',
        'UDP_DMA_REFERENCE_LIFETIME=PASS',
        'UDP_DMA_ERROR_RECOVERY=PASS',
        'TCP_ERR_MEM_SAME_READY_RETRY=PASS',
        'TCP_PARTIAL_ACK=PASS',
        'TCP_MULTI_SLOT_ACK=PASS',
        'TCP_ABORT_RECOVERY=PASS',
        'ERR_MEM_ACCOUNTING=PASS'
    ) | Set-Content -LiteralPath (Join-Path $log 'summary.txt')
} finally {
    Pop-Location
}
