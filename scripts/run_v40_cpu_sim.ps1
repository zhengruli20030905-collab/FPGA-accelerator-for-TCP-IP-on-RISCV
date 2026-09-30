param([int]$Seed=3701,[switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_cpu_sim'
New-Item -ItemType Directory -Force -Path $log | Out-Null

if (!$SkipBuild) { & "$PSScriptRoot\build_v40_firmware.ps1" -Quiet }

# The complete real-firmware SoC regression exercises RV32I execution,
# forwarding, load-use, branches/jumps, sub-word memory accesses, traps,
# UART/MMIO side effects, and the synchronous IMEM/DMEM protocol.
& "$PSScriptRoot\run_v40_network_sim.ps1" -Seeds $Seed -Modes 0 -ChecksumModes 0 `
    -Profiles 0 -TestModes 0 -SkipBuild
$normalLog = Join-Path $root "logs\v40_network_sim\test_0_mode_0_csum_0_profile_0_seed_$Seed.log"
$normalPerf = Select-String -LiteralPath $normalLog -Pattern 'V40 CPU PERF' | Select-Object -Last 1
Copy-Item -LiteralPath (Join-Path $root 'logs\v40_network_sim\summary.txt') `
    -Destination (Join-Path $log 'normal_memory_summary.txt') -Force

# Random request acceptance delay stresses pending requests, response/hold
# overlap, the one-entry IF response buffer, and exactly-once MMIO writes.
& "$PSScriptRoot\run_v40_network_sim.ps1" -Seeds ($Seed+1) -Modes 0 -ChecksumModes 0 `
    -Profiles 0 -TestModes 0 -RandomMemoryWait -ImemWaitMax 3 -DmemWaitMax 3 -SkipBuild
$waitLog = Join-Path $root "logs\v40_network_sim\test_0_mode_0_csum_0_profile_0_seed_$($Seed+1).log"
$waitPerf = Select-String -LiteralPath $waitLog -Pattern 'V40 CPU PERF' | Select-Object -Last 1
Copy-Item -LiteralPath (Join-Path $root 'logs\v40_network_sim\summary.txt') `
    -Destination (Join-Path $log 'random_memory_wait_summary.txt') -Force

if (!$normalPerf -or !$waitPerf) { throw 'Missing v40 CPU performance-counter evidence' }
@(
    'V40 CPU/SYNC MEMORY REGRESSION PASSED',
    "NORMAL_SEED=$Seed",
    "RANDOM_WAIT_SEED=$($Seed+1)",
    'REAL_FIRMWARE_BOOT=PASS',
    'RV32I_AND_FORWARDING=PASS_VIA_FULL_NETWORK_FIRMWARE',
    'SYNC_IMEM_DMEM=PASS',
    'RANDOM_IMEM_DMEM_WAIT=PASS',
    'MMIO_EXACTLY_ONCE=PASS_VIA_UART_AND_NETWORK_ACCOUNTING',
    $normalPerf.Line,
    $waitPerf.Line
) | Tee-Object -FilePath (Join-Path $log 'summary.txt')
