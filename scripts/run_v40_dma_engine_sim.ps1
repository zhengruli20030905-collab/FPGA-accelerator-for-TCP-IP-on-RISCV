param([int[]]$Seeds=@(3401,3402,3418))

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_dma_engine_sim'
$work = Join-Path $root 'build\questa_v40_dma_engine'
$ini = Join-Path $root 'build\modelsim_v40_dma_engine.ini'
$library = 'v40_dma_engine'
$previousModelsim = $env:MODELSIM
New-Item -ItemType Directory -Force -Path $log,(Split-Path $work) | Out-Null
$questa = 'D:\year3\win64'
foreach ($tool in @('vlib.exe','vmap.exe','vlog.exe','vsim.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $questa $tool))) { throw "Missing Questa tool: $tool" }
}
$sources = @('rtl/eth/dma_transfer_engine.sv','sim/tb_v40_dma_transfer_engine.sv')

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
    & (Join-Path $questa 'vlog.exe') -sv -work $library @sources 2>&1 | Tee-Object -FilePath (Join-Path $log 'compile.log')
    if ($LASTEXITCODE) { throw 'engine vlog failed' }
    foreach ($seed in $Seeds) {
        $path = Join-Path $log "engine_$seed.log"
        $transcript = Join-Path $work "engine_${seed}_transcript.log"
        & (Join-Path $questa 'vsim.exe') -c -l $transcript -sv_seed $seed -lib $library tb_v40_dma_transfer_engine -do 'run -all; quit -f' 2>&1 | Tee-Object -FilePath $path
        if ($LASTEXITCODE -or !(Select-String -LiteralPath $path -SimpleMatch 'V40 DMA TRANSFER ENGINE PASSED') -or
            (Select-String -LiteralPath $path -Pattern '\*\* (Fatal:|Error:)')) { throw "Engine simulation failed for seed $seed" }
    }
    @('V40 DMA TRANSFER ENGINE REGRESSION PASSED',"SEEDS=$($Seeds -join ',')",'COVERAGE=TX,RX,all-source-offsets,all-destination-offsets,1,2,3,4,5,7,60,64,511,512,513,1472,byte-exact,adjacent-preservation,abort,timeout,DMEM-conflict,packet-conflict') |
        Tee-Object -FilePath (Join-Path $log 'summary.txt')
} finally { $env:MODELSIM = $previousModelsim; Pop-Location }
