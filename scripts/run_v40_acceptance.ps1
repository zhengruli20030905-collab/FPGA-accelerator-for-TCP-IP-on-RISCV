param(
    [switch]$SkipQuartus,
    [switch]$ReuseQuartusReports
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_acceptance'
New-Item -ItemType Directory -Force -Path $log | Out-Null
$commands = [Collections.Generic.List[string]]::new()

function Invoke-Step([string]$description,[scriptblock]$action) {
    Write-Host "=== $description ==="
    $commands.Add($description)
    & $action
}

Push-Location $root
try {
    Invoke-Step 'scripts\audit_v40_timing_structure.ps1' { & "$PSScriptRoot\audit_v40_timing_structure.ps1" }
    Invoke-Step 'scripts\audit_v40_independence.ps1' { & "$PSScriptRoot\audit_v40_independence.ps1" }
    Invoke-Step 'scripts\build_v40_firmware.ps1' { & "$PSScriptRoot\build_v40_firmware.ps1" -Quiet }
    Invoke-Step 'scripts\run_v40_tx_pool_host_test.ps1' {
        & "$PSScriptRoot\run_v40_tx_pool_host_test.ps1"
    }
    Invoke-Step 'scripts\run_v40_tcp_zero_copy_host_test.ps1' {
        & "$PSScriptRoot\run_v40_tcp_zero_copy_host_test.ps1"
    }
    Invoke-Step 'scripts\run_v40_peripheral_timing_sim.ps1' {
        & "$PSScriptRoot\run_v40_peripheral_timing_sim.ps1"
    }
    Invoke-Step 'scripts\run_v40_cpu_sim.ps1 -Seed 3701 -SkipBuild' {
        & "$PSScriptRoot\run_v40_cpu_sim.ps1" -Seed 3701 -SkipBuild
    }
    Invoke-Step 'scripts\run_v40_dma_sim.ps1 -Seeds 3701,3702,3718' {
        & "$PSScriptRoot\run_v40_dma_sim.ps1" -Seeds 3701,3702,3718
    }
    Invoke-Step 'PIO network regression' {
        & "$PSScriptRoot\run_v40_network_sim.ps1" -Seeds 3703 -Modes 0 -ChecksumModes 0 `
            -Profiles 0 -TestModes 0,1,2,3 -SkipBuild
    }
    Invoke-Step 'SGDMA software-checksum network regression' {
        & "$PSScriptRoot\run_v40_network_sim.ps1" -Seeds 3704 -Modes 1 -ChecksumModes 0 `
            -Profiles 0 -TestModes 0,1,2,3 -SkipBuild
    }
    Invoke-Step 'SGDMA hardware-checksum network regression' {
        & "$PSScriptRoot\run_v40_network_sim.ps1" -Seeds 3705 -Modes 1 -ChecksumModes 1 `
            -Profiles 0 -TestModes 0,1,2,3 -SkipBuild
    }
    Invoke-Step 'SGDMA hardware-checksum TCP RX-only regression' {
        & "$PSScriptRoot\run_v40_network_sim.ps1" -Seeds 3706 -Modes 1 -ChecksumModes 1 `
            -Profiles 0 -TestModes 0 -TcpRxSink -SkipBuild
    }
    if (!$SkipQuartus) {
        if ($ReuseQuartusReports) {
            Invoke-Step 'scripts\run_v40_quartus.ps1 -ReportsOnly' {
                & "$PSScriptRoot\run_v40_quartus.ps1" -ReportsOnly
            }
        } else {
            Invoke-Step 'scripts\run_v40_quartus.ps1 -SkipBuild' {
                & "$PSScriptRoot\run_v40_quartus.ps1" -SkipBuild
            }
        }
    }
    Invoke-Step 'final v39 hash and v40 independence audit' { & "$PSScriptRoot\audit_v40_independence.ps1" }

    $commands | Set-Content -LiteralPath (Join-Path $log 'commands.txt')
    @(
        'V40 AUTOMATED ACCEPTANCE PASSED',
        "QUARTUS_SKIPPED=$([int]$SkipQuartus.IsPresent)",
        "QUARTUS_REPORTS_REUSED=$([int]$ReuseQuartusReports.IsPresent)",
        'CPU_POSEDGE_AND_SYNC_MEMORY=PASS',
        'RANDOM_MEMORY_WAIT=PASS',
        'PERIPHERAL_25MHZ_TIMING=PASS',
        'DMA_SGDMA_CHECKSUM=PASS',
        'TX_BUFFER_POOL_HOST_TEST=PASS',
        'TCP_ZERO_COPY_ACK_LIFETIME_HOST_TEST=PASS',
        'PIO_SGDMA_NETWORK=PASS',
        'TCP_ECHO_ZERO_COPY_PARTIAL_ACK_SIM=PASS',
        'TCP_RX_ONLY_SIM=PASS',
        'V39_HASH_UNCHANGED=PASS',
        'INTEL_IP_AND_LWIP_UNCHANGED=PASS',
        'AUTOMATED_SIMULATION=PASS',
        "QUARTUS_25MHZ=$(if ($SkipQuartus) {'NOT_RUN'} else {'PASS'})",
        "SOF_GENERATED=$(if ($SkipQuartus) {'NOT_CHECKED'} else {'YES'})",
        'PHYSICAL_BOARD=NOT_RUN; MANUAL_PROGRAMMING_REQUIRED',
        'FPGA_PROGRAMMING=NOT_PERFORMED',
        'NETWORK_THROUGHPUT=NOT_CLAIMED_UNTIL_MANUAL_BOARD_TEST'
    ) | Tee-Object -FilePath (Join-Path $log 'summary.txt')
} catch {
    $commands | Set-Content -LiteralPath (Join-Path $log 'commands.txt')
    @('V40 AUTOMATED ACCEPTANCE FAILED',"ERROR=$($_.Exception.Message)") |
        Set-Content -LiteralPath (Join-Path $log 'summary.txt')
    throw
} finally {
    Pop-Location
}
