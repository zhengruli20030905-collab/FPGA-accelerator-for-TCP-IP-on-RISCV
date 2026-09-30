param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$software = Join-Path $root 'software'
$build = Join-Path $root 'build\firmware'
$log = Join-Path $root 'logs\v40_firmware_build'
New-Item -ItemType Directory -Force -Path $build,$log | Out-Null

$pathParts = @($env:PATH -split ';')
$pathParts += @([Environment]::GetEnvironmentVariable('Path','User') -split ';')
$pathParts += @([Environment]::GetEnvironmentVariable('Path','Machine') -split ';')
$env:PATH = ($pathParts | Where-Object { $_ } | Select-Object -Unique) -join ';'

function Find-RiscvTool([string]$name) {
    foreach ($prefix in @('riscv-none-elf-','riscv32-unknown-elf-','riscv64-unknown-elf-')) {
        $tool = Get-Command "$prefix$name" -ErrorAction SilentlyContinue
        if ($tool) { return $tool.Source }
    }
    throw "Missing RISC-V tool: $name"
}

$gcc = Find-RiscvTool 'gcc'
$objcopy = Find-RiscvTool 'objcopy'
$objdump = Find-RiscvTool 'objdump'
$nm = Find-RiscvTool 'nm'
$sizeTool = Find-RiscvTool 'size'

$elf = Join-Path $build 'v40_firmware.elf'
$map = Join-Path $build 'v40_firmware.map'
$bin = Join-Path $build 'v40_firmware.bin'
$dis = Join-Path $build 'v40_firmware.dis'
$imemHex = Join-Path $build 'v40_firmware_imem.hex'
$imemMif = Join-Path $build 'v40_firmware_imem.mif'
$dmemHex = Join-Path $build 'v40_firmware_dmem.hex'
$dmemMif = Join-Path $build 'v40_firmware_dmem.mif'
$lwip = Join-Path $software 'third_party\lwip'

$lwipSources = @(
    'src/core/init.c','src/core/def.c','src/core/inet_chksum.c',
    'src/core/ip.c','src/core/mem.c','src/core/memp.c','src/core/netif.c',
    'src/core/pbuf.c','src/core/stats.c','src/core/sys.c','src/core/timeouts.c',
    'src/core/udp.c','src/core/tcp.c','src/core/tcp_in.c','src/core/tcp_out.c',
    'src/core/ipv4/etharp.c','src/core/ipv4/icmp.c','src/core/ipv4/ip4.c',
    'src/core/ipv4/ip4_addr.c','src/netif/ethernet.c'
) | ForEach-Object { Join-Path $lwip $_ }

$projectSources = @(
    (Join-Path $software 'start.S'),
    (Join-Path $software 'app\main.c'),
    (Join-Path $software 'net\ethernetif.c'),
    (Join-Path $software 'net\packet_sgdma.c'),
    (Join-Path $software 'net\tx_buffer_pool.c'),
    (Join-Path $software 'net\udp_echo.c'),
    (Join-Path $software 'net\tcp_zero_copy_lifetime.c'),
    (Join-Path $software 'net\tcp_echo.c'),
    (Join-Path $software 'net\v26_lwip_app.c'),
    (Join-Path $software 'port\sys_now.c'),
    (Join-Path $software 'port\v28_profile.c'),
    (Join-Path $software 'port\v40_checksum_profile.c'),
    (Join-Path $software 'lib\minilibc.c')
)

$allSources = @($projectSources + $lwipSources)
foreach ($source in $allSources) {
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing firmware source: $source" }
}

$gccArgs = @(
    '-march=rv32i','-mabi=ilp32','-Oz','-g','-nostdlib','-nostartfiles',
    '-ffreestanding','-fno-builtin','-fno-pic','-fno-asynchronous-unwind-tables',
    '-fno-unwind-tables','-msmall-data-limit=0','-mstrict-align','-mno-relax',
    '-ffunction-sections','-fdata-sections','-flto',
    '-DBOARD_BRINGUP_TEST','-DV26_TCP_ECHO','-DV27_SYNC_IMEM',
    '-DV31_SGDMA','-DV31_DESCRIPTOR_RING','-DV32_DUAL_RING',
    '-DV34_SCATTER_GATHER','-DV34_ZERO_COPY',
    '-DV40_CPU_25M',
    "-I$software","-I$(Join-Path $software 'port')", "-I$(Join-Path $lwip 'src\include')",
    '-Wl,--no-relax','-Wl,--gc-sections','-Wl,--no-check-sections',
    "-Wl,-Map,$map",'-T',(Join-Path $software 'linker.ld'),'-o',$elf
) + $allSources + @('-lgcc')

Push-Location $root
try {
    $savedErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $gccOutput = @(& $gcc @gccArgs 2>&1)
    $gccExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorPreference
    $gccOutput | Tee-Object -FilePath (Join-Path $log 'gcc.log')
    if ($gccExitCode) { throw "RISC-V GCC failed: $gccExitCode" }

    & $objdump -d -s $elf 2>&1 | Tee-Object -FilePath $dis | Out-Null
    if ($LASTEXITCODE) { throw 'objdump failed' }
    $unsupported = Select-String -LiteralPath $dis -Pattern '^\s*[0-9a-f]+:\s+[0-9a-f]+\s+(mul|mulh|mulhsu|mulhu|div|divu|rem|remu)\b'
    if ($unsupported) { throw 'Firmware contains unsupported RV32M instructions' }
    $undefined = @(& $nm -u $elf)
    if ($LASTEXITCODE -or $undefined.Count) { throw 'Firmware has unresolved symbols' }

    $sectionLines = @(& $objdump -h $elf)
    if ($LASTEXITCODE) { throw 'objdump section query failed' }
    $sections = @{}
    foreach ($line in $sectionLines) {
        if ($line -match '^\s*\d+\s+(\S+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+') {
            $sections[$Matches[1]] = [pscustomobject]@{
                Name=$Matches[1]
                Size=[Convert]::ToUInt32($Matches[2],16)
                Vma=[Convert]::ToUInt32($Matches[3],16)
                Lma=[Convert]::ToUInt32($Matches[4],16)
            }
        }
    }
    if (!$sections.ContainsKey('.text') -or $sections['.text'].Vma -ne 0x3000) {
        throw 'Expected .text at 0x00003000'
    }
    if ($sections['.text'].Size -gt 0x10000) { throw 'Firmware exceeds 64 KiB IMEM' }
    if ($sections.ContainsKey('.bss') -and ($sections['.bss'].Vma + $sections['.bss'].Size) -gt 0x1f000) {
        throw '.bss overlaps the reserved stack region'
    }

    & $objcopy -O binary -j .text $elf $bin
    if ($LASTEXITCODE) { throw 'objcopy .text failed' }

    [byte[]]$textBytes = [IO.File]::ReadAllBytes($bin)
    [byte[]]$imemBytes = New-Object byte[] 0x10000
    for ($offset=0; $offset -lt $imemBytes.Length; $offset+=4) { $imemBytes[$offset] = 0x13 }
    [Array]::Copy($textBytes,0,$imemBytes,0,$textBytes.Length)

    [byte[]]$dmemBytes = New-Object byte[] 0x20000
    foreach ($sectionName in @('.rodata','.data')) {
        if (!$sections.ContainsKey($sectionName) -or $sections[$sectionName].Size -eq 0) { continue }
        $section = $sections[$sectionName]
        if (($section.Vma + $section.Size) -gt 0x1f000) { throw "$sectionName exceeds initialized DMEM" }
        $sectionBin = Join-Path $build ("v40_firmware_" + $sectionName.TrimStart('.') + '.bin')
        & $objcopy -O binary -j $sectionName $elf $sectionBin
        if ($LASTEXITCODE) { throw "objcopy $sectionName failed" }
        [byte[]]$sectionBytes = [IO.File]::ReadAllBytes($sectionBin)
        [Array]::Copy($sectionBytes,0,$dmemBytes,[int]$section.Vma,$sectionBytes.Length)
        Remove-Item -LiteralPath $sectionBin -Force
    }

    function Write-Hex([byte[]]$bytes,[string]$path) {
        $lines = New-Object 'System.Collections.Generic.List[string]'
        for ($offset=0; $offset -lt $bytes.Length; $offset+=4) {
            [uint32]$word = [uint32]$bytes[$offset] -bor
                ([uint32]$bytes[$offset+1] -shl 8) -bor
                ([uint32]$bytes[$offset+2] -shl 16) -bor
                ([uint32]$bytes[$offset+3] -shl 24)
            $lines.Add(('{0:x8}' -f $word))
        }
        Set-Content -LiteralPath $path -Value $lines -Encoding ASCII
    }

    function Write-Mif([byte[]]$bytes,[string]$path) {
        $depth = [int]($bytes.Length / 4)
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add('WIDTH=32;'); $lines.Add("DEPTH=$depth;"); $lines.Add('')
        $lines.Add('ADDRESS_RADIX=HEX;'); $lines.Add('DATA_RADIX=HEX;'); $lines.Add('')
        $lines.Add('CONTENT BEGIN')
        for ($wordIndex=0; $wordIndex -lt $depth; $wordIndex++) {
            $offset = $wordIndex * 4
            [uint32]$word = [uint32]$bytes[$offset] -bor
                ([uint32]$bytes[$offset+1] -shl 8) -bor
                ([uint32]$bytes[$offset+2] -shl 16) -bor
                ([uint32]$bytes[$offset+3] -shl 24)
            $lines.Add(('    {0:x4} : {1:x8};' -f $wordIndex,$word))
        }
        $lines.Add('END;')
        Set-Content -LiteralPath $path -Value $lines -Encoding ASCII
    }

    Write-Hex $imemBytes $imemHex
    Write-Mif $imemBytes $imemMif
    Write-Hex $dmemBytes $dmemHex
    Write-Mif $dmemBytes $dmemMif

    $aliases = @{
        $imemHex=(Join-Path $software 'boardprep_imem.hex')
        $imemMif=(Join-Path $software 'boardprep_imem.mif')
        $dmemHex=(Join-Path $software 'boardprep_dmem.hex')
        $dmemMif=(Join-Path $software 'boardprep_dmem.mif')
    }
    foreach ($entry in $aliases.GetEnumerator()) {
        Copy-Item -LiteralPath $entry.Key -Destination $entry.Value -Force
        if ((Get-FileHash $entry.Key -Algorithm SHA256).Hash -ne
            (Get-FileHash $entry.Value -Algorithm SHA256).Hash) { throw 'Firmware alias hash mismatch' }
    }

    & $sizeTool -A $elf | Tee-Object -FilePath (Join-Path $log 'size.txt') | Out-Null
    $nmLines = @(& $nm -n -S $elf)
    $nmLines | Set-Content -LiteralPath (Join-Path $build 'v40_symbols.txt') -Encoding ASCII
    $nmLines | Select-String 'descriptor_ring|descriptor_meta|pio_tx_words|pio_rx_words|rx_frames|memp_memory_PBUF_POOL|ram_heap|__stack|__bss|__heap' |
        Set-Content -LiteralPath (Join-Path $log 'memory_layout.txt') -Encoding ASCII
    $symbols = @{}
    foreach ($line in $nmLines) {
        if ($line -match '^([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+[A-Za-z]\s+(\S+)$') {
            $symbols[$Matches[3]] = [pscustomobject]@{
                Name=$Matches[3]
                Start=[Convert]::ToUInt32($Matches[1],16)
                Size=[Convert]::ToUInt32($Matches[2],16)
            }
        }
    }
    $regionNames = @('rx_descriptor_meta','rx_descriptor_ring','tx_descriptor_meta',
                     'tx_descriptor_ring','pio_tx_words','pio_rx_words','rx_frames',
                     'tx_slots')
    $regions = @()
    foreach ($name in $regionNames) {
        if (!$symbols.ContainsKey($name)) { throw "Missing firmware memory symbol: $name" }
        $symbol = $symbols[$name]
        $regions += [pscustomobject]@{
            Name=$name
            Start=('0x{0:x8}' -f $symbol.Start)
            EndExclusive=('0x{0:x8}' -f ($symbol.Start+$symbol.Size))
            Bytes=$symbol.Size
        }
    }
    $ordered = @($regionNames | ForEach-Object { $symbols[$_] } | Sort-Object Start)
    for ($index=1; $index -lt $ordered.Count; $index++) {
        if ($ordered[$index].Start -lt ($ordered[$index-1].Start+$ordered[$index-1].Size)) {
            throw "Firmware memory objects overlap: $($ordered[$index-1].Name) and $($ordered[$index].Name)"
        }
    }
    $regions | Export-Csv -LiteralPath (Join-Path $log 'memory_regions.csv') -NoTypeInformation

    Get-ChildItem -LiteralPath $build -File | Get-FileHash -Algorithm SHA256 |
        Export-Csv -LiteralPath (Join-Path $log 'firmware_sha256.csv') -NoTypeInformation

    $rodataBytes = if($sections.ContainsKey('.rodata')){$sections['.rodata'].Size}else{0}
    $dataBytes = if($sections.ContainsKey('.data')){$sections['.data'].Size}else{0}
    $bssBytes = if($sections.ContainsKey('.bss')){$sections['.bss'].Size}else{0}
    $bssEnd = if($sections.ContainsKey('.bss')){$sections['.bss'].Vma+$sections['.bss'].Size}else{0}
    $dmemFreeBeforeStack = 0x1f000-$bssEnd
    $summary = @(
        'V40 FIRMWARE BUILD PASSED',
        "ELF=$elf",
        "TEXT_BYTES=$($sections['.text'].Size)",
        "RODATA_BYTES=$rodataBytes",
        "DATA_BYTES=$dataBytes",
        "BSS_BYTES=$bssBytes",
        ('BSS_END=0x{0:x8}' -f $bssEnd),
        "DMEM_FREE_BEFORE_STACK=$dmemFreeBeforeStack",
        'SGDMA_TX_STAGING_BYTES=0',
        'SGDMA_RX_STAGING_BYTES=0',
        'PIO_TX_STAGING_BYTES=2048',
        'PIO_RX_STAGING_BYTES=2048',
        'RX_PBUF_FRAME_COUNT=8',
        'RX_PREPOST_TARGET=8',
        'TX_BUFFER_POOL_SIZE=8',
        'TX_BUFFER_SLOT_STORAGE_BYTES=1600',
        'PBUF_POOL_SIZE=24',
        'PBUF_POOL_BUFSIZE=1536',
        "PBUF_POOL_OBJECT_BYTES=$($symbols['memp_memory_PBUF_POOL_base'].Size)",
        ('PIO_TX_RANGE=0x{0:x8}-0x{1:x8}' -f $symbols['pio_tx_words'].Start,($symbols['pio_tx_words'].Start+$symbols['pio_tx_words'].Size-1)),
        ('PIO_RX_RANGE=0x{0:x8}-0x{1:x8}' -f $symbols['pio_rx_words'].Start,($symbols['pio_rx_words'].Start+$symbols['pio_rx_words'].Size-1)),
        ('RX_CONTEXT_RANGE=0x{0:x8}-0x{1:x8}' -f $symbols['rx_frames'].Start,($symbols['rx_frames'].Start+$symbols['rx_frames'].Size-1)),
        ('TX_BUFFER_POOL_RANGE=0x{0:x8}-0x{1:x8}' -f $symbols['tx_slots'].Start,($symbols['tx_slots'].Start+$symbols['tx_slots'].Size-1)),
        ('TX_DESCRIPTOR_RING_RANGE=0x{0:x8}-0x{1:x8}' -f $symbols['tx_descriptor_ring'].Start,($symbols['tx_descriptor_ring'].Start+$symbols['tx_descriptor_ring'].Size-1)),
        ('RX_DESCRIPTOR_RING_RANGE=0x{0:x8}-0x{1:x8}' -f $symbols['rx_descriptor_ring'].Start,($symbols['rx_descriptor_ring'].Start+$symbols['rx_descriptor_ring'].Size-1)),
        'MEMORY_OBJECT_OVERLAP=NONE',
        'SGDMA_TX_DESCRIPTOR_RING_BYTES=512',
        'SGDMA_RX_DESCRIPTOR_RING_BYTES=512',
        "IMEM_WORDS=$($imemBytes.Length/4)",
        "DMEM_WORDS=$($dmemBytes.Length/4)",
        'ISA=RV32I (no RV32M instructions found)'
    )
    $summary | Set-Content -LiteralPath (Join-Path $log 'summary.txt') -Encoding ASCII
    if (!$Quiet) { $summary | Write-Host }
} finally {
    Pop-Location
}


