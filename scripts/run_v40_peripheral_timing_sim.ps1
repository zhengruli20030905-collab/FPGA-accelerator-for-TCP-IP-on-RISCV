param([int]$Seed=3808)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_peripheral_timing_sim'
$work = Join-Path $root 'build\questa_v40_peripheral_timing'
$ini = Join-Path $root 'build\modelsim_v40_peripheral_timing.ini'
$questa = 'D:\year3\win64'
$previousModelsim = $env:MODELSIM
New-Item -ItemType Directory -Force -Path $log,(Split-Path $work) | Out-Null

foreach ($tool in @('vlib.exe','vmap.exe','vlog.exe','vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $questa $tool))) { throw "Missing Questa tool: $tool" }
}

$sources = @(
    'rtl/common/debounce.sv',
    'rtl/peripherals/uart_tx_hw.sv',
    'rtl/peripherals/uart_mmio.sv',
    'rtl/peripherals/timer_mmio.sv',
    'rtl/peripherals/mdio_master.sv',
    'rtl/peripherals/phy_mdio_mmio.sv',
    'sim/tb_v40_peripheral_timing.sv'
)

Push-Location $root
try {
    & (Join-Path $questa 'vlib.exe') $work 2>&1 | Tee-Object -FilePath (Join-Path $log 'vlib.log')
    if ($LASTEXITCODE) { throw 'vlib failed' }
    $masterIni = Join-Path (Split-Path $questa) 'modelsim.ini'
    if (!(Test-Path -LiteralPath $masterIni)) { throw "Missing Questa modelsim.ini: $masterIni" }
    Copy-Item -LiteralPath $masterIni -Destination $ini -Force
    Set-ItemProperty -LiteralPath $ini -Name IsReadOnly -Value $false
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & (Join-Path $questa 'vmap.exe') -modelsimini $ini v40_peripheral_timing $work 2>&1 |
        Tee-Object -FilePath (Join-Path $log 'vmap.log')
    $mapExit = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    if ($mapExit) { throw 'vmap failed' }
    $env:MODELSIM = $ini
    & (Join-Path $questa 'vlog.exe') -sv -work v40_peripheral_timing '+incdir+rtl/include' `
        '+define+BOARD_DE2115' @sources 2>&1 |
        Tee-Object -FilePath (Join-Path $log 'compile.log')
    if ($LASTEXITCODE) { throw 'Peripheral timing vlog failed' }
    $runLog = Join-Path $log "seed_$Seed.log"
    & (Join-Path $questa 'vsim.exe') -c -sv_seed $Seed -lib v40_peripheral_timing `
        tb_v40_peripheral_timing -do 'run -all; quit -f' 2>&1 | Tee-Object -FilePath $runLog
    if ($LASTEXITCODE -or
        !(Select-String -LiteralPath $runLog -SimpleMatch 'V40 PERIPHERAL TIMING SIMULATION PASSED') -or
        (Select-String -LiteralPath $runLog -Pattern '\*\* (Fatal:|Error:)')) {
        throw 'V40 peripheral timing simulation failed'
    }
    @(
        'V40 PERIPHERAL TIMING SIMULATION PASSED',
        'SOC_CLOCK_HZ=25000000',
        'CPU_PERIOD_NS=40',
        'UART_BAUD=115200',
        'UART_CLKS_PER_BIT=217',
        'UART_BAUD_ERROR_PERCENT=0.0064',
        'UART_MMIO_FIFO_FULL_EMPTY=PASS',
        'UART_MMIO_EXACTLY_ONCE=PASS',
        'UART_MMIO_VALID_READY_SERIAL_SEQUENCE=ABCDE_PASS',
        'TIMER_CYCLES_PER_MS=25000',
        'PHY_RESET_CYCLES=250000',
        'PHY_RESET_MS=10',
        'MDC_HALF_DIV=13',
        'MDC_ACTUAL_HZ=961538',
        'DEBOUNCE_CYCLES=125000',
        'DEBOUNCE_MS=5'
    ) | Tee-Object -FilePath (Join-Path $log 'summary.txt')
} finally {
    $env:MODELSIM = $previousModelsim
    Pop-Location
}
