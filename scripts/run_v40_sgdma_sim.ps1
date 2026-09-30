param([int[]]$Seeds=@(3401,3402,3418))

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_sgdma_sim'
$work = Join-Path $root 'build\questa_v40_sgdma'
$ini = Join-Path $root 'build\modelsim_v40_sgdma.ini'
$library = 'v40_sgdma'
$previousModelsim = $env:MODELSIM
New-Item -ItemType Directory -Force -Path $log,(Split-Path $work) | Out-Null
$questa = 'D:\year3\win64'
foreach ($tool in @('vlib.exe','vmap.exe','vlog.exe','vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $questa $tool))) { throw "Missing Questa tool: $tool" }
}
$sources = @('rtl/eth/sgdma_descriptor_engine.sv','sim/tb_v40_sgdma_gather_scatter.sv')

Push-Location $root
try {
    & (Join-Path $questa 'vlib.exe') $work 2>&1 | Tee-Object -FilePath (Join-Path $log 'vlib.log')
    if ($LASTEXITCODE) { throw 'vlib failed' }
    Copy-Item -LiteralPath (Join-Path (Split-Path $questa) 'modelsim.ini') -Destination $ini -Force
    Set-ItemProperty -LiteralPath $ini -Name IsReadOnly -Value $false
    $oldPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & (Join-Path $questa 'vmap.exe') -modelsimini $ini $library $work 2>&1 | Tee-Object -FilePath (Join-Path $log 'vmap.log') -Append
    $mapExitCode = $LASTEXITCODE; $ErrorActionPreference = $oldPreference
    if ($mapExitCode) { throw 'vmap failed' }
    $env:MODELSIM = $ini
    & (Join-Path $questa 'vlog.exe') -sv -work $library '+incdir+rtl/include' @sources 2>&1 | Tee-Object -FilePath (Join-Path $log 'compile.log')
    if ($LASTEXITCODE) { throw 'SGDMA vlog failed' }
    foreach ($seed in $Seeds) {
        $path = Join-Path $log "sgdma_$seed.log"
        $transcript = Join-Path $work "sgdma_${seed}_transcript.log"
        & (Join-Path $questa 'vsim.exe') -c -l $transcript -sv_seed $seed -lib $library tb_v40_sgdma_gather_scatter -do 'run -all; quit -f' 2>&1 | Tee-Object -FilePath $path
        if ($LASTEXITCODE -or !(Select-String -LiteralPath $path -SimpleMatch 'V40 SGDMA GATHER/SCATTER PASSED') -or
            (Select-String -LiteralPath $path -Pattern '\*\* (Fatal:|Error:)')) { throw "SGDMA simulation failed for seed $seed" }
    }
    @('V40 SGDMA GATHER/SCATTER REGRESSION PASSED',"SEEDS=$($Seeds -join ',')",'COVERAGE=TX-gather,RX-scatter,nonword-segments,one-finalize-per-frame,short-RX,small-RX-drop,chain-wrap,frame-boundary-arbitration,missing-FIRST,middle-error-drain,capability-counters') |
        Tee-Object -FilePath (Join-Path $log 'summary.txt')
} finally { $env:MODELSIM = $previousModelsim; Pop-Location }
& "$PSScriptRoot\run_v40_sgdma_checksum_sim.ps1" -Seeds $Seeds
