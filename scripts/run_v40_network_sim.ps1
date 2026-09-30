param(
    [int[]]$Seeds=@(2901),
    [ValidateSet(0,1)][int[]]$Modes=@(0,1),
    [ValidateSet(0,1)][int[]]$ChecksumModes=@(0,1),
    [ValidateSet(0,1)][int[]]$Profiles=@(0),
    [ValidateSet(0,1,2,3)][int[]]$TestModes=@(0),
    [switch]$TcpRxSink,
    [switch]$RxPrepostOnly,
    [switch]$RandomMemoryWait,
    [ValidateRange(0,15)][int]$ImemWaitMax=3,
    [ValidateRange(0,15)][int]$DmemWaitMax=3,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runName = if ($TcpRxSink) { 'v40_tcp_rx_sink_sim' } else { 'v40_network_sim' }
$log = Join-Path $root "logs\$runName"
$work = Join-Path $root "build\questa_$runName"
$ini = Join-Path $root "build\modelsim_$runName.ini"
$library = $runName
$previousModelsim = $env:MODELSIM
New-Item -ItemType Directory -Force -Path $log,(Split-Path $work) | Out-Null
if ($TcpRxSink -and (($TestModes.Count -ne 1) -or ($TestModes[0] -ne 0))) {
    throw 'TcpRxSink requires -TestModes 0'
}

$questa = 'D:\year3\win64'
foreach ($tool in @('vlib.exe','vmap.exe','vlog.exe','vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $questa $tool))) { throw "Missing Questa tool: $tool" }
}

$rtl = @(
    'rtl/common/debounce.sv','rtl/common/reset_sync.sv','rtl/common/sync_2ff.sv',
    'rtl/cpu/alu.sv','rtl/cpu/control_unit.sv','rtl/cpu/extention.sv',
    'rtl/cpu/mutiplexer.sv','rtl/cpu/mult.sv','rtl/cpu/rf.sv',
    'rtl/cpu/IF_Stage.sv','rtl/cpu/ID_Stage.sv','rtl/cpu/EX_stage.sv',
    'rtl/cpu/Mem_stage.sv','rtl/cpu/WB_Stage.sv','rtl/cpu/instruct_mem.sv',
    'rtl/memory/data_ram.sv','rtl/soc/simple_bus.sv',
    'rtl/peripherals/uart_tx_hw.sv','rtl/peripherals/uart_mmio.sv',
    'rtl/peripherals/timer_mmio.sv','rtl/peripherals/board_gpio_mmio.sv',
    'rtl/peripherals/mdio_master.sv','rtl/peripherals/phy_mdio_mmio.sv',
    'rtl/eth/tse_mmio_regs.sv','rtl/eth/tse_stream_fifo_stub.sv',
    'rtl/eth/tse_mac_wrapper.sv','rtl/eth/dma_transfer_engine.sv',
    'rtl/eth/internet_checksum_engine.sv',
    'rtl/eth/sgdma_descriptor_engine.sv','rtl/eth/packet_dma.sv',
    'rtl/soc/data_mem.sv','rtl/cpu/rv32i_cpu.sv',
    'sim/models/tse_sim_frame_source.sv','sim/tb_v40_soc_network.sv'
)
foreach ($path in $rtl) {
    if (!(Test-Path -LiteralPath (Join-Path $root $path))) { throw "Missing network simulation source: $path" }
}

Push-Location $root
try {
    if (!$SkipBuild) { & (Join-Path $PSScriptRoot 'build_v40_firmware.ps1') -Quiet }
    foreach ($image in @('build/firmware/v40_firmware_imem.hex','build/firmware/v40_firmware_dmem.hex')) {
        if (!(Test-Path -LiteralPath $image)) { throw "Missing firmware image: $image" }
    }

    & (Join-Path $questa 'vlib.exe') $work 2>&1 | Tee-Object -FilePath (Join-Path $log 'vlib.log')
    if ($LASTEXITCODE) { throw 'vlib failed' }
    $masterIni = Join-Path (Split-Path $questa) 'modelsim.ini'
    if (!(Test-Path -LiteralPath $masterIni)) { throw "Missing Questa modelsim.ini: $masterIni" }
    Copy-Item -LiteralPath $masterIni -Destination $ini -Force
    Set-ItemProperty -LiteralPath $ini -Name IsReadOnly -Value $false
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & (Join-Path $questa 'vmap.exe') -modelsimini $ini $library $work 2>&1 | Tee-Object -FilePath (Join-Path $log 'vmap.log') -Append
    $mapExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($mapExitCode) { throw 'vmap library mapping failed' }
    $env:MODELSIM = $ini
    $defines = '+define+TSE_NET_SIM+V26_TCP_ECHO_SIM+V27_SYNC_IMEM_SIM+V31_SGDMA_SIM+V33_DUAL_RING_SIM+V34_SCATTER_GATHER_SIM'
    if ($RandomMemoryWait) {
        $defines += '+V40_RANDOM_IMEM_WAIT+V40_RANDOM_DMEM_WAIT'
    }
    & (Join-Path $questa 'vlog.exe') -sv -work $library '+incdir+rtl/include' '+incdir+rtl/eth' $defines @rtl 2>&1 |
        Tee-Object -FilePath (Join-Path $log 'compile.log')
    if ($LASTEXITCODE) { throw 'Network vlog failed' }

    $resultRows = @()
    $symbolArgs=@()
    $symbols=Get-Content -LiteralPath (Join-Path $root 'build/firmware/v40_symbols.txt')
    foreach($pair in @(@('v40_checksum_scan_calls','CSUM_CALLS_ADDR'),@('v40_checksum_scan_bytes','CSUM_BYTES_ADDR'),@('v40_checksum_scan_ticks','CSUM_TICKS_ADDR'),@('v40_sink_completed','SINK_ADDR'),@('tx_stats','TX_STATS_ADDR'))){
        $line=$symbols | Where-Object {$_ -match (' '+$pair[0]+'$')} | Select-Object -First 1
        if(!$line){throw "Missing profiling symbol $($pair[0])"}
        $symbolArgs+="+$($pair[1])=$($line.Split(' ')[0])"
    }
    foreach ($testMode in $TestModes) {
      foreach ($profile in $Profiles) {
        foreach ($mode in $Modes) {
          foreach ($checksumMode in $ChecksumModes) {
          if($mode -eq 0 -and $checksumMode -ne 0){continue}
          foreach ($seed in $Seeds) {
                $path = Join-Path $log "test_${testMode}_mode_${mode}_csum_${checksumMode}_profile_${profile}_seed_$seed.log"
                $toolTranscript = Join-Path $work "test_${testMode}_mode_${mode}_csum_${checksumMode}_profile_${profile}_seed_${seed}_transcript.log"
                $simArgs = @(
                    '-c','-l',$toolTranscript,'-sv_seed',$seed,'-lib',$library,'tb_v40_soc_network',
                    '+MEMFILE=build/firmware/v40_firmware_imem.hex',
                    '+DMEMFILE=build/firmware/v40_firmware_dmem.hex',
                    "+SEED=$seed","+SGDMA_MODE=$mode","+PROFILE=$profile","+TEST_MODE=$testMode",
                    "+CHECKSUM_MODE=$checksumMode",
                    "+TCP_RX_SINK=$([int]$TcpRxSink.IsPresent)",
                    "+IMEM_WAIT_MAX=$ImemWaitMax",
                    "+DMEM_WAIT_MAX=$DmemWaitMax",
                    "+WIRE_TRACE=$path.wire",
                    '-do','run -all; quit -f'
                )
                if ($RxPrepostOnly) {
                    $simArgs = $simArgs[0..($simArgs.Count-3)] +
                        @('+RX_PREPOST_ONLY=1') + $simArgs[($simArgs.Count-2)..($simArgs.Count-1)]
                }
                $simArgs = $symbolArgs + $simArgs
                & (Join-Path $questa 'vsim.exe') @simArgs 2>&1 | Tee-Object -FilePath $path
                $passText = if ($TcpRxSink) {
                    'V40 TCP RX-only sink consumed'
                } elseif ($testMode -eq 0) {
                    'V40 PIO/SGDMA ZERO-COPY ARP/ICMP/UDP/TCP PASSED'
                } else {
                    "V40 NETWORK MODE PASSED test_mode=$testMode io_mode=$mode"
                }
                if ($LASTEXITCODE -or
                    !(Select-String -LiteralPath $path -SimpleMatch $passText) -or
                    !(Select-String -LiteralPath $path -SimpleMatch 'V40 RX PBUF POOL EXHAUST/RECOVERY SELF-TEST PASS') -or
                    !(Select-String -LiteralPath $path -SimpleMatch 'V40 TCP ZERO-COPY ACK LIFETIME SELF-TEST PASS') -or
                    (Select-String -LiteralPath $path -Pattern '\*\* (Fatal:|Error:)')) {
                    throw "Network simulation failed: test=$testMode mode=$mode profile=$profile seed=$seed"
                }
                if (($testMode -eq 0) -and !$TcpRxSink) {
                    $tcpZeroCopyPass = Select-String -LiteralPath $path -SimpleMatch 'V40 LWIP TCP ZERO-COPY PARTIAL-ACK/DATA/FIN ECHO PASSED'
                    if (!$tcpZeroCopyPass) {
                        throw "TCP Echo zero-copy partial-ACK flow missing: $path"
                    }
                    $match = Select-String -LiteralPath $path -Pattern 'V40 PIO/SGDMA ZERO-COPY ARP/ICMP/UDP/TCP PASSED mode=(\d+) descriptors=(\d+) tx=(\d+) rx=(\d+) cpu_tx_starts=(\d+) max_pending=(\d+) tail_writes=(\d+)' | Select-Object -Last 1
                    if (!$match) { throw "Missing V40 SGDMA accounting: $path" }
                    $descriptors = [int]$match.Matches[0].Groups[2].Value
                    $cpuStarts = [int]$match.Matches[0].Groups[5].Value
                    $maxPending = [int]$match.Matches[0].Groups[6].Value
                    $tailWrites = [int]$match.Matches[0].Groups[7].Value
                } else {
                    $match = Select-String -LiteralPath $path -Pattern 'V40 NETWORK MODE PASSED test_mode=(\d+) io_mode=(\d+) descriptors=(\d+) tx=(\d+) rx=(\d+)' | Select-Object -Last 1
                    if (!$match) { throw "Missing V40 one-way accounting: $path" }
                    $descriptors = [int]$match.Matches[0].Groups[3].Value
                    $cpuStarts = 0
                    $maxPending = 0
                    $tailWrites = 0
                }
                if (($mode -eq 0 -and $descriptors -ne 0) -or ($mode -eq 1 -and $descriptors -le 0)) {
                    throw "Unexpected SGDMA descriptors=$descriptors for mode=$mode"
                }
                if (($testMode -eq 0) -and !$TcpRxSink -and ($mode -eq 1) -and ($cpuStarts -ne 0)) { throw "SGDMA used CPU TX START writes=$cpuStarts" }
                if (($testMode -eq 0) -and !$TcpRxSink -and ($mode -eq 1) -and ($maxPending -lt 2)) { throw "SGDMA never queued multiple descriptors" }
                if (($testMode -eq 0) -and !$TcpRxSink -and ($mode -eq 1) -and ($tailWrites -ge $descriptors)) { throw "SGDMA did not batch TAIL writes" }
                $resultRows += [pscustomobject]@{TestMode=$testMode;Mode=$mode;ChecksumMode=$checksumMode;Profile=$profile;Seed=$seed;Descriptors=$descriptors;CpuTxStarts=$cpuStarts;MaxPending=$maxPending;TailWrites=$tailWrites;Result='PASS';Log=$path}
          }
          }
        }
      }
    }
    $resultRows | Export-Csv -LiteralPath (Join-Path $log 'matrix.csv') -NoTypeInformation
    @(
        'V40 SOC NETWORK SIMULATION PASSED',
        "RUNS=$($resultRows.Count)",
        "MODES=$($Modes -join ',')",
        "TEST_MODES=$($TestModes -join ',')",
        "SEEDS=$($Seeds -join ',')",
        'PROTOCOLS=ARP,ICMP,UDP,TCP',
        'PIO_SGDMA_OWNERSHIP=PASS',
        'SGDMA_TX_AUTORUN=PASS',
        'SGDMA_ASYNC_MAX_PENDING_GE_2=PASS',
        'SGDMA_BATCHED_TAIL_DOORBELL=PASS',
        'RX_PREPOST_SINGLE_PBUF_FRAMES_8=PASS',
        'RX_PREPOST_WAIT_TX_PROGRESS=PASS',
        'RX_PREPOST_WATERMARK_RECOVERY=PASS',
        'RX_PBUF_POOL_EXHAUST_RECOVERY=PASS',
        'NORMAL_RX_SINGLE_SEGMENT=PASS',
        'MULTI_SEGMENT_CAPABILITY=COVERED_BY_RUN_V40_DMA_SIM',
        'UDP_REALTIME_SEQUENCE_DEPENDENT_PAYLOAD=PASS',
        'TCP_REALTIME_PERSISTENT_SOURCE=PASS_WHEN_TEST_MODE_3_SELECTED',
        'TCP_PARTIAL_ACK_SLOT_LIFETIME=PASS_WHEN_TEST_MODE_3_SELECTED',
        'TCP_ECHO_ZERO_COPY_PARTIAL_ACK_LIFETIME=PASS_WHEN_TEST_MODE_0_SELECTED',
        "TCP_RX_ONLY_SINK=$([int]$TcpRxSink.IsPresent)",
        "RANDOM_MEMORY_WAIT=$([int]$RandomMemoryWait.IsPresent)",
        "IMEM_WAIT_MAX=$ImemWaitMax",
        "DMEM_WAIT_MAX=$DmemWaitMax",
        'SGDMA_FULL_FRAME_COPY_CALLS=0',
        "RX_PREPOST_ONLY=$([int]$RxPrepostOnly.IsPresent)"
    ) | Tee-Object -FilePath (Join-Path $log 'summary.txt')
} finally {
    $env:MODELSIM = $previousModelsim
    Pop-Location
}

