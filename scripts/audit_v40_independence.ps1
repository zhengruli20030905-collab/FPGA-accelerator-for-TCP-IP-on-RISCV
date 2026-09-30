$ErrorActionPreference = 'Stop'
$v40 = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$v39 = 'E:\RISC-V\RISC-V_version39_single_pbuf_tcp_echo'
$audit = Join-Path $v40 'audit'
$baselinePath = Join-Path $audit 'V39_BASELINE_SHA256.csv'
$hashMismatchPath = Join-Path $audit 'V39_HASH_MISMATCH.csv'
$pathReferencePath = Join-Path $audit 'v39_path_references.txt'
New-Item -ItemType Directory -Force -Path $audit | Out-Null

Remove-Item -LiteralPath $hashMismatchPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $pathReferencePath -Force -ErrorAction SilentlyContinue

if (!(Test-Path -LiteralPath $v39 -PathType Container)) {
    throw "Missing v39 source: $v39"
}
if (!(Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
    throw "Missing v39 baseline: $baselinePath"
}

$baseline = @(Import-Csv -LiteralPath $baselinePath | ForEach-Object {
    [pscustomobject]@{
        Path = $_.Path
        Length = $_.Length.ToString()
        SHA256 = $_.SHA256
    }
})
$current = @(Get-ChildItem -LiteralPath $v39 -Recurse -File |
    Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName.Substring($v39.Length + 1)
            Length = $_.Length.ToString()
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
$changes = @(Compare-Object $baseline $current -Property Path,Length,SHA256)
if ($changes.Count) {
    $changes | Export-Csv -LiteralPath $hashMismatchPath -NoTypeInformation
    throw "v39 source changed after baseline: $($changes.Count) differences"
}

function Assert-IdenticalSubtree([string]$relative,[string]$label) {
    $sourceBase = Join-Path $v39 $relative
    $targetBase = Join-Path $v40 $relative
    $source = @(Get-ChildItem -LiteralPath $sourceBase -Recurse -File |
        Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                Path=$_.FullName.Substring($sourceBase.Length).TrimStart('\')
                Length=$_.Length
                SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
    $target = @(Get-ChildItem -LiteralPath $targetBase -Recurse -File |
        Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                Path=$_.FullName.Substring($targetBase.Length).TrimStart('\')
                Length=$_.Length
                SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
    $delta = @(Compare-Object $source $target -Property Path,Length,SHA256)
    if ($delta.Count) {
        $delta | Export-Csv -LiteralPath (Join-Path $audit "$label`_HASH_MISMATCH.csv") -NoTypeInformation
        throw "$label differs between v39 and v40"
    }
    return "$label=IDENTICAL FILES=$($source.Count)"
}

$reparse = @(Get-ChildItem -LiteralPath $v40 -Recurse -Force | Where-Object {
    ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
})
if ($reparse.Count) {
    throw "v40 contains reparse points/symbolic links: $($reparse.FullName -join ', ')"
}

$oldPathRefs = @(rg -n -i --glob '!audit/**' --glob '!docs/**' `
    --glob '!logs/**' --glob '!build/**' `
    --glob '!scripts/audit_v40_independence.ps1' `
    'RISC-V_version39_single_pbuf_tcp_echo|\\version39\\|/version39/' $v40 2>$null)
if ($LASTEXITCODE -gt 1) { throw 'rg path audit failed' }
if ($oldPathRefs.Count) {
    $oldPathRefs | Set-Content -LiteralPath $pathReferencePath
    throw 'v40 contains an active dependency on the v39 path'
}

$summary = @(
    'V40 INDEPENDENCE AUDIT PASSED',
    "V39_BASELINE_FILES=$($baseline.Count)",
    "V39_CURRENT_FILES=$($current.Count)",
    'V39_HASH_CHANGES=0',
    (Assert-IdenticalSubtree 'ip' 'INTEL_IP'),
    (Assert-IdenticalSubtree 'software\third_party\lwip' 'THIRD_PARTY_LWIP'),
    'REPARSE_OR_SYMBOLIC_LINKS=0',
    'ACTIVE_V39_PATH_REFERENCES=0',
    'V39_WRITE_OPERATION=NONE'
)
$summary | Tee-Object -FilePath (Join-Path $audit 'v40_independence_summary.txt')
