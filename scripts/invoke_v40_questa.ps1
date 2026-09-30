param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Top,
 [Parameter(Mandatory)][string[]]$Sources,[int[]]$Seeds=@(3501,3502,3518),[string[]]$Plusargs=@())
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log=Join-Path $root "logs\$Name"
$work=Join-Path $root "build\$Name"
$ini=Join-Path $root "build\${Name}.ini"
$questa='D:\year3\win64'
$previous=$env:MODELSIM
New-Item -ItemType Directory -Force -Path $log,(Split-Path $work) | Out-Null
Push-Location $root
try {
 & "$questa\vlib.exe" $work 2>&1 | Tee-Object "$log\vlib.log"
 if($LASTEXITCODE){throw 'vlib failed'}
 Copy-Item -LiteralPath 'D:\year3\modelsim.ini' -Destination $ini -Force
 Set-ItemProperty -LiteralPath $ini -Name IsReadOnly -Value $false
 $ErrorActionPreference='Continue'
 & "$questa\vmap.exe" -modelsimini $ini $Name $work 2>&1 | Tee-Object "$log\vmap.log"
 $rc=$LASTEXITCODE; $ErrorActionPreference='Stop'; if($rc){throw 'vmap failed'}
 $env:MODELSIM=$ini
 & "$questa\vlog.exe" -sv -work $Name '+incdir+rtl/include' @Sources 2>&1 | Tee-Object "$log\compile.log"
 if($LASTEXITCODE){throw 'vlog failed'}
 foreach($seed in $Seeds){
  & "$questa\vsim.exe" -c -l "$log\transcript_$seed.log" -sv_seed $seed -lib $Name $Top @Plusargs -do 'run -all; quit -f' 2>&1 | Tee-Object "$log\seed_$seed.log"
  if($LASTEXITCODE -or !(Select-String -LiteralPath "$log\seed_$seed.log" -SimpleMatch 'V40 TEST PASSED') -or (Select-String -LiteralPath "$log\seed_$seed.log" -Pattern '\*\* (Error:|Fatal:)')){throw "$Name seed $seed failed"}
 }
 "PASS $Name seeds=$($Seeds -join ',')" | Tee-Object "$log\summary.txt"
} finally { $env:MODELSIM=$previous; Pop-Location }
