param([switch]$SkipBuild,[switch]$ReportsOnly)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$board = Join-Path $root 'board'
$log = Join-Path $root 'logs\v40_quartus'
$project = 'de2_115_v40_25m'
$output = Join-Path $board 'output_files'
New-Item -ItemType Directory -Force -Path $log | Out-Null

function Find-QuartusTool([string]$stage) {
    $command = Get-Command "quartus_$stage" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $fallback = "D:\softwaire_year3\quartus\bin64\quartus_$stage.exe"
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw "Missing Quartus $stage tool"
}

function Get-WorstSummarySlack([string]$report,[string]$kind) {
    $active = $false
    $sawRow = $false
    $values = [Collections.Generic.List[double]]::new()
    foreach ($line in ($report -split "`r?`n")) {
        if ($line -match ("^;\s*.+ Model " + [regex]::Escape($kind) + " Summary\s+;")) {
            $active = $true
            $sawRow = $false
            continue
        }
        if ($active -and $line -match '^;\s*([^;]+?)\s*;\s*(-?[0-9.]+)\s*;\s*(-?[0-9.]+)\s*;') {
            $values.Add([double]::Parse($matches[2],[Globalization.CultureInfo]::InvariantCulture))
            $sawRow = $true
            continue
        }
        if ($active -and $sawRow -and $line -match '^\+') { $active = $false }
    }
    if (!$values.Count) { throw "Missing $kind summary rows" }
    return ($values | Measure-Object -Minimum).Minimum
}

function Get-ClockSummarySlack([string]$report,[string]$corner,[string]$kind,[string]$clockPattern) {
    $heading = "$corner Model $kind Summary"
    $headingMatch = [regex]::Match($report,
        '(?m)^;\s*' + [regex]::Escape($heading) + '\s*;')
    if (!$headingMatch.Success) { throw "Missing timing section: $heading" }
    $length = [Math]::Min(20000, $report.Length - $headingMatch.Index)
    $tail = $report.Substring($headingMatch.Index, $length)
    $match = [regex]::Match($tail,
        ';\s*' + $clockPattern + '\s*;\s*(-?[0-9.]+)\s*;',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (!$match.Success) { throw "Missing $corner $kind clock row: $clockPattern" }
    return [double]::Parse($match.Groups[1].Value,
        [Globalization.CultureInfo]::InvariantCulture)
}

if (!$ReportsOnly) {
    if (!$SkipBuild) { & (Join-Path $PSScriptRoot 'build_v40_firmware.ps1') -Quiet }
    foreach ($image in @('software/boardprep_imem.mif','software/boardprep_dmem.mif')) {
        if (!(Test-Path -LiteralPath (Join-Path $root $image))) { throw "Missing board memory image: $image" }
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'rtl'),(Join-Path $root 'ip') -File -Recurse)
    $sourceFiles += @(Get-Item -LiteralPath (Join-Path $board 'de2_115_v40_25m.qsf'),
        (Join-Path $board 'de2_115_v40_25m.sdc'),
        (Join-Path $root 'software\boardprep_imem.mif'),
        (Join-Path $root 'software\boardprep_dmem.mif'))
    $sourceFiles | ForEach-Object {
        [pscustomobject]@{Path=$_.FullName;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    } | Export-Csv -LiteralPath (Join-Path $log 'build_input_sha256.csv') -NoTypeInformation
    Push-Location $board
    try {
        foreach ($stage in @('map','fit','asm','sta')) {
            $tool = Find-QuartusTool $stage
            $args = @($project,'-c',$project)
            if ($stage -eq 'map') {
                $args = @('--read_settings_files=on','--write_settings_files=off') + $args
            } elseif ($stage -ne 'sta') {
                $args = @('--read_settings_files=off','--write_settings_files=off') + $args
            }
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $tool @args 2>&1 | Tee-Object -FilePath (Join-Path $log "$stage.log")
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $oldPreference
            if ($exitCode) { throw "Quartus $stage failed: $exitCode" }
        }
    } finally {
        Pop-Location
    }
}

$inputManifest = Join-Path $log 'build_input_sha256.csv'
if (!(Test-Path -LiteralPath $inputManifest)) { throw 'Missing Quartus build-input manifest' }
foreach ($inputFile in Import-Csv -LiteralPath $inputManifest) {
    if ((Get-FileHash -LiteralPath $inputFile.Path -Algorithm SHA256).Hash -ne $inputFile.SHA256) {
        throw "Quartus input changed since compile: $($inputFile.Path)"
    }
}

$reports = @{}
foreach ($stage in @('map','fit','asm','sta','flow')) {
    $path = Join-Path $output "$project.$stage.rpt"
    if (!(Test-Path -LiteralPath $path)) { throw "Missing Quartus report: $path" }
    $reports[$stage] = Get-Content -LiteralPath $path -Raw
}
foreach ($stage in @('map','fit','asm','sta')) {
    if ($reports[$stage] -notmatch 'was successful\. 0 errors' -or
        $reports[$stage] -match '(?m)^\s*Critical Warning') {
        throw "Quartus $stage report acceptance failed"
    }
}
if($reports['map'] -match 'Warning \(10240\)|Warning \(10230\)|Inferred latch|[Cc]ombinational loop') {
        throw 'Unreviewed latch inference or implicit width truncation in v40 map report'
}

$sta = $reports['sta']
if ($sta -notmatch 'Design is fully constrained for setup requirements' -or
    $sta -notmatch 'Design is fully constrained for hold requirements' -or
    $sta -match 'Timing requirements not met') {
    throw 'V40 25 MHz design is not fully constrained'
}
foreach ($name in @('Illegal Clocks','Unconstrained Clocks','Unconstrained Input Ports',
                     'Unconstrained Input Port Paths','Unconstrained Output Ports','Unconstrained Output Port Paths')) {
    if ($sta -notmatch ('; '+[regex]::Escape($name)+'\s+;\s*0\s+;\s*0')) {
        throw "Nonzero or missing 25 MHz constraint row: $name"
    }
}
$slack = [regex]::Match($sta,'; Worst-case Slack\s+;\s*([-0-9.]+)\s+;\s*([-0-9.]+)')
if (!$slack.Success) { throw 'Missing setup/hold slack summary' }
$setup = [double]::Parse($slack.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
$hold = [double]::Parse($slack.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
$recovery = Get-WorstSummarySlack $sta 'Recovery'
$removal = Get-WorstSummarySlack $sta 'Removal'
$minimumPulseWidth = Get-WorstSummarySlack $sta 'Minimum Pulse Width'
$cpuFmaxMatch = [regex]::Match($sta,
    ';\s*([0-9.]+) MHz\s*;\s*[0-9.]+ MHz\s*;\s*u_cpu_pll_25m\|')
if (!$cpuFmaxMatch.Success) { throw 'Missing 25 MHz CPU clock Fmax summary' }
$cpuFmax = [double]::Parse($cpuFmaxMatch.Groups[1].Value,
    [Globalization.CultureInfo]::InvariantCulture)
$cpuClockPattern = 'u_cpu_pll_25m\|[^;]+'
$cpuSetup = Get-ClockSummarySlack $sta 'Slow 1200mV 85C' 'Setup' $cpuClockPattern
$cpuHold = Get-ClockSummarySlack $sta 'Slow 1200mV 85C' 'Hold' $cpuClockPattern
$timingPass = ($setup -gt 0 -and $hold -gt 0 -and $recovery -gt 0 -and
               $removal -gt 0 -and $minimumPulseWidth -gt 0 -and
               $cpuSetup -ge 0 -and $cpuHold -ge 0 -and
               $cpuFmax -ge 25.0)

$fit = $reports['fit']
$ramRows = @($fit -split "`r?`n" | Where-Object { $_ -match 'ALTSYNCRAM\s+; (M9K|AUTO)\s+;' } | ForEach-Object {
    $fields = @($_ -split ';' | ForEach-Object Trim)
    [pscustomobject]@{Name=$fields[1];Type=$fields[2];Mode=$fields[3];ClockMode=$fields[4];Bits=[int]$fields[18];Blocks=[int]$fields[19];Mif=$fields[20];Location=$fields[21]}
})
$ramRows | Export-Csv -LiteralPath (Join-Path $log 'ram_implementation.csv') -NoTypeInformation
foreach ($spec in @(
    @('u_tx_packet_ram',65536,'Simple Dual Port'),
    @('u_rx_packet_ram',65536,'Simple Dual Port'),
    @('u_board_imem_ram',524288,'Single Port'),
    @('u_board_dmem_ram',1048576,'True Dual Port')
)) {
    $rows = @($ramRows | Where-Object { $_.Name.Contains($spec[0]) })
    $bits = ($rows | Measure-Object Bits -Sum).Sum
    if ($bits -ne $spec[1] -or @($rows | Where-Object { $_.Mode -ne $spec[2] -or $_.Location -notmatch 'M9K_' }).Count) {
        throw "Incomplete M9K implementation for $($spec[0]): $bits bits"
    }
}

# The standard STA report already contains detailed per-clock setup paths.
# Extract the Slow 85 C setup-path region and sort its path rows by slack.
$setupHeading = [regex]::Match($sta, "(?m)^;\s*Slow 1200mV 85C Model Setup: '")
$holdHeading = [regex]::Match($sta, "(?m)^;\s*Slow 1200mV 85C Model Hold: '")
if (!$setupHeading.Success -or !$holdHeading.Success -or $holdHeading.Index -le $setupHeading.Index) {
    throw 'Missing detailed Slow 85C setup paths'
}
$setupStart = $setupHeading.Index
$holdStart = $holdHeading.Index
$setupRegion = $sta.Substring($setupStart, $holdStart - $setupStart)
$setupPaths = @($setupRegion -split "`r?`n" | ForEach-Object {
    if ($_ -match '^;\s*(-?[0-9.]+)\s*;\s*([^;]+?)\s*;\s*([^;]+?)\s*;') {
        [pscustomobject]@{SlackNs=[double]::Parse($matches[1],[Globalization.CultureInfo]::InvariantCulture);From=$matches[2].Trim();To=$matches[3].Trim()}
    }
} | Where-Object { $_ } | Sort-Object SlackNs | Select-Object -First 20)
if (!$setupPaths.Count) { throw 'No detailed setup path rows parsed' }
$setupPaths | Format-Table -AutoSize | Out-String -Width 500 |
    Set-Content -LiteralPath (Join-Path $log 'top20_setup_paths.txt')

$assemblerSof = Join-Path $output "$project`_time_limited.sof"
$namedSof = Join-Path $output 'de2_115_v40_25mhz_tcp_zero_copy_time_limited.sof'
if (!(Test-Path -LiteralPath $assemblerSof)) { throw "Missing v40 25 MHz SOF: $assemblerSof" }
Copy-Item -LiteralPath $assemblerSof -Destination $namedSof -Force
$assemblerSofHash = (Get-FileHash -LiteralPath $assemblerSof -Algorithm SHA256).Hash
$namedSofHash = (Get-FileHash -LiteralPath $namedSof -Algorithm SHA256).Hash
if ($assemblerSofHash -ne $namedSofHash) { throw 'Named SOF hash mismatch' }

$flow = $reports['flow']
$logic = [regex]::Match($flow,'Total logic elements\s+;\s*([0-9,]+)').Groups[1].Value
$registers = [regex]::Match($flow,'Total registers\s+;\s*([0-9,]+)').Groups[1].Value
$memoryBits = [regex]::Match($flow,'Total memory bits\s+;\s*([0-9,]+)').Groups[1].Value
$m9k = [regex]::Match($fit,'(?m)^; M9Ks\s+;\s*([0-9,]+)').Groups[1].Value
$pll = [regex]::Match($flow,'Total PLLs\s+;\s*([0-9,]+)').Groups[1].Value
if (!$logic -or !$registers -or !$memoryBits -or !$m9k -or !$pll) {
    throw 'Missing Quartus resource/M9K/PLL totals'
}
$summary = @(
    'V40 QUARTUS 25 MHZ BOARD BUILD PASSED',
    'BOARD_PROGRAMMING=NOT_PERFORMED',
    "TIMING_PASS=$($timingPass.ToString().ToUpperInvariant())",
    "WORST_SETUP_NS=$setup",
    "WORST_HOLD_NS=$hold",
    "WORST_RECOVERY_NS=$recovery",
    "WORST_REMOVAL_NS=$removal",
    "WORST_MIN_PULSE_WIDTH_NS=$minimumPulseWidth",
    "CPU_SLOW85_SETUP_NS=$cpuSetup",
    "CPU_SLOW85_HOLD_NS=$cpuHold",
    "CPU_FMAX_MHZ=$cpuFmax",
    "LOGIC_ELEMENTS=$logic",
    "REGISTERS=$registers",
    "MEMORY_BITS=$memoryBits",
    "M9K_BLOCKS=$m9k",
    "PLL_COUNT=$pll",
    'FULLY_CONSTRAINED=YES',
    'LATCH_INFERENCE=0',
    'COMBINATIONAL_LOOPS=0',
    'M9K_IMEM_DMEM_PACKET_RAM=PASS',
    "TOP20_SETUP_PATHS=$(Join-Path $log 'top20_setup_paths.txt')",
    "SOF=$namedSof",
    "SOF_SHA256=$namedSofHash",
    'PURPOSE=FORMAL_25MHZ_BOARD_IMAGE',
    'PHYSICAL_BOARD=NOT_RUN',
    'PROGRAMMING=NOT_PERFORMED'
)
$summary | Tee-Object -FilePath (Join-Path $log 'summary.txt')
if (!$timingPass) {
    throw "25 MHz timing failed: setup=$setup hold=$hold recovery=$recovery removal=$removal min_pulse=$minimumPulseWidth cpu_setup=$cpuSetup cpu_hold=$cpuHold CPU_Fmax=$cpuFmax"
}
Get-ChildItem -LiteralPath $output -File | Get-FileHash -Algorithm SHA256 |
    Export-Csv -LiteralPath (Join-Path $log 'output_sha256.csv') -NoTypeInformation
