param([switch]$ReuseFirmware)

$ErrorActionPreference = 'Stop'
$acceptance = Join-Path $PSScriptRoot 'run_v40_acceptance.ps1'

if ($ReuseFirmware) {
    # The acceptance script rebuilds firmware so the simulated memory image can
    # never silently lag the C sources. Keep this switch only as an explicit
    # reminder that reuse is intentionally not allowed for the formal run.
    Write-Host 'V40 formal full simulation always rebuilds firmware.'
}

& $acceptance -SkipQuartus
