param([int[]]$Seeds=@(3701,3702,3718))

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_dma_sim'
New-Item -ItemType Directory -Force -Path $log | Out-Null

& "$PSScriptRoot\run_v40_dma_engine_sim.ps1" -Seeds $Seeds
& "$PSScriptRoot\run_v40_checksum_sim.ps1" -Seeds $Seeds
& "$PSScriptRoot\run_v40_sgdma_sim.ps1" -Seeds $Seeds
& "$PSScriptRoot\run_v40_tx_pool_host_test.ps1"

@(
    'V40 DMA/SGDMA REGRESSION PASSED',
    "SEEDS=$($Seeds -join ',')",
    'DMA_TRANSFER_ENGINE=PASS',
    'DUAL_RING_GATHER_SCATTER=PASS',
    'HARDWARE_CHECKSUM=PASS',
    'TX_BUFFER_POOL_HOST_TEST=PASS'
) | Tee-Object -FilePath (Join-Path $log 'summary.txt')
