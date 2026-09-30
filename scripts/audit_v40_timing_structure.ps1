$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$log = Join-Path $root 'logs\v40_structure_audit'
New-Item -ItemType Directory -Force -Path $log | Out-Null

$cpuFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'rtl\cpu') -Recurse -File)
$cpuFiles += @(Get-Item -LiteralPath (Join-Path $root 'rtl\memory\data_ram.sv'))
$functionalNegedge = @($cpuFiles | Select-String -Pattern '@\s*\(\s*negedge\s+clk')
$invertedClock = @($cpuFiles | Select-String -Pattern '=\s*~\s*clk|\.clock\w*\s*\(\s*~\s*clk')
if ($functionalNegedge.Count -or $invertedClock.Count) {
    @($functionalNegedge + $invertedClock) | ForEach-Object ToString |
        Set-Content -LiteralPath (Join-Path $log 'illegal_cpu_clocking.txt')
    throw 'CPU/RAM still contains functional negedge or inverted-clock logic'
}

$rtlText = ($cpuFiles | Get-Content -Raw) -join "`n"
foreach ($required in @('if_id_valid','id_ex_valid','EX_MEM_valid','MEM_WB_valid','request_fire','response_valid')) {
    if ($rtlText -notmatch [regex]::Escape($required)) {
        throw "Missing pipeline/protocol marker: $required"
    }
}

$constraints = Get-Content -LiteralPath (Join-Path $root 'board\de2_115_v40_25m.sdc') -Raw
if ($constraints -match '(?i)set_multicycle_path') {
    throw 'CPU timing is masked by a multicycle exception'
}
if ($constraints -match '(?i)set_false_path[^\r\n]*(u_rv32i_cpu|u_cpu|EX_|ID_|IF_|MEM_|WB_)') {
    throw 'CPU data path is masked by a false-path exception'
}

$requiredFiles = @(
    'scripts\build_v40_firmware.ps1',
    'scripts\run_v40_tcp_zero_copy_host_test.ps1',
    'scripts\run_v40_cpu_sim.ps1',
    'scripts\run_v40_dma_sim.ps1',
    'scripts\run_v40_network_sim.ps1',
    'scripts\run_v40_peripheral_timing_sim.ps1',
    'scripts\run_v40_quartus.ps1',
    'scripts\run_v40_acceptance.ps1',
    'software\net\tcp_zero_copy_lifetime.c',
    'software\net\tcp_zero_copy_lifetime.h',
    'rtl\common\cpu_pll_25m.v'
)
foreach ($relative in $requiredFiles) {
    if (!(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Missing v40 deliverable: $relative"
    }
}

$formalFiles = @(
    (Join-Path $root 'rtl\include\v40_clock_config.svh'),
    (Join-Path $root 'rtl\soc\board_top_de2115.sv'),
    (Join-Path $root 'rtl\soc\data_mem.sv'),
    (Join-Path $root 'board\de2_115_v40_25m.qsf'),
    (Join-Path $root 'software\app\main.c'),
    (Join-Path $root 'software\port\sys_now.c'),
    (Join-Path $root 'software\port\v28_profile.c')
)
$staleClock = @($formalFiles | Select-String -Pattern '12_500_000|12500000|CPU_12M5|cpu_pll_12m5|V39_CPU_25M')
if ($staleClock.Count) {
    $staleClock | ForEach-Object ToString |
        Set-Content -LiteralPath (Join-Path $log 'stale_clock.txt')
    throw 'Formal v40 path contains a stale clock selector/value'
}

$qsf = Get-Content -LiteralPath (Join-Path $root 'board\de2_115_v40_25m.qsf') -Raw
if ($qsf -notmatch 'cpu_pll_25m\.v' -or $qsf -match 'cpu_pll_12m5') {
    throw 'Formal QSF does not select only cpu_pll_25m'
}
$networkTb = Get-Content -LiteralPath (Join-Path $root 'sim\tb_v40_soc_network.sv') -Raw
if ($networkTb -notmatch 'forever #20 clk = ~clk') {
    throw 'SoC simulation is not using a 40 ns CPU period'
}

$commandChecks = @(
    @('software\net\udp_echo.c', 'V40TXGO'),
    @('software\net\udp_echo.c', 'V40TXSTOP'),
    @('software\net\tcp_echo.c', 'V40TCPGO'),
    @('software\net\tcp_echo.c', 'V40TCPSTOP'),
    @('scripts\run_v40_board_udp_tx_only.ps1', 'V40TXGO'),
    @('scripts\run_v40_board_udp_tx_only.ps1', 'V40TXSTOP'),
    @('scripts\run_v40_board_tcp_tx_only.ps1', 'V40TCPGO'),
    @('scripts\run_v40_board_tcp_tx_only.ps1', 'V40TCPSTOP'),
    @('software\net\tx_buffer_pool.c', "payload[1] = (uint8_t)'4'"),
    @('software\net\tx_buffer_pool.c', "payload[2] = (uint8_t)'0'"),
    @('sim\host_tx_pool\test_tx_buffer_pool.c', "offset == 1u) return (uint8_t)'4'"),
    @('sim\host_tx_pool\test_tx_buffer_pool.c', "offset == 2u) return (uint8_t)'0'"),
    @('sim\tb_v40_soc_network.sv', 'u_source.frame_bytes[43] = "4"'),
    @('sim\tb_v40_soc_network.sv', 'u_source.frame_bytes[55] = "4"'),
    @('sim\tb_v40_soc_network.sv', '1: expected_v40_tcp_byte = "4"'),
    @('sim\tb_v40_soc_network.sv', '2: expected_v40_tcp_byte = "0"'),
    @('scripts\run_v40_board_tcp_echo_throughput.ps1', "buffer[2] = (byte)'0'"),
    @('scripts\run_v40_board_tcp_echo_throughput.ps1', 'InitialReadDelayMilliseconds'),
    @('scripts\run_v40_board_tcp_echo_lifetime_stress.ps1', 'ABRUPT_DISCONNECT_RECOVERY')
)
foreach ($check in $commandChecks) {
    $text = Get-Content -LiteralPath (Join-Path $root $check[0]) -Raw
    if (!$text.Contains($check[1])) {
        throw "Version consistency check failed: $($check[0]) => $($check[1])"
    }
}

$lwipopts = Get-Content -LiteralPath (Join-Path $root 'software\port\lwipopts.h') -Raw
if ($lwipopts -notmatch '#define\s+PBUF_POOL_SIZE\s+24' -or
    $lwipopts -notmatch '#define\s+PBUF_POOL_BUFSIZE\s+1536' -or
    $lwipopts -notmatch '#define\s+TCP_WND\s+\(8\s*\*\s*TCP_MSS\)' -or
    $lwipopts -notmatch '#define\s+TCP_SND_BUF\s+\(8\s*\*\s*TCP_MSS\)' -or
    $lwipopts -notmatch 'PBUF_POOL_BUFSIZE\s*<\s*\(1514\s*\+\s*ETH_PAD_SIZE\)') {
    throw 'V40 pbuf/TCP window configuration or compile-time guard is missing'
}

$tcpEcho = Get-Content -LiteralPath (Join-Path $root 'software\net\tcp_echo.c') -Raw
if ($tcpEcho -match 'TCP_WRITE_FLAG_COPY') {
    throw 'V40 normal TCP Echo source still contains TCP_WRITE_FLAG_COPY'
}
if ($tcpEcho -notmatch 'tcp_write\s*\(pcb,\s*span\.payload,\s*span\.length,\s*0u\s*\)') {
    throw 'V40 TCP Echo no-copy tcp_write call is missing'
}
if ($tcpEcho -match 'pbuf_cat\s*\(') {
    throw 'V40 TCP Echo still concatenates pending pbuf chains'
}
$lifetimeHeader = Get-Content -LiteralPath (Join-Path $root 'software\net\tcp_zero_copy_lifetime.h') -Raw
if ($lifetimeHeader -notmatch 'V40_TCP_ZC_OWNER_CAPACITY\s+16u' -or
    $lifetimeHeader -notmatch 'V40_TCP_ZC_ACK_CAPACITY\s+32u') {
    throw 'V40 owner/ACK fixed queue capacities are wrong'
}
$lifetimeSource = Get-Content -LiteralPath (Join-Path $root 'software\net\tcp_zero_copy_lifetime.c') -Raw
foreach ($marker in @('v40_tcp_zc_commit_submit','v40_tcp_zc_ack','v40_tcp_zc_abort',
                      'partial_ack_events','cumulative_ack_events',
                      'payload_stability_violations')) {
    if ($lifetimeSource -notmatch [regex]::Escape($marker)) {
        throw "V40 ownership implementation marker missing: $marker"
    }
}
$buildScript = Get-Content -LiteralPath (Join-Path $root 'scripts\build_v40_firmware.ps1') -Raw
if (!$buildScript.Contains('net\tcp_zero_copy_lifetime.c')) {
    throw 'V40 lifetime manager is not compiled into firmware'
}

foreach ($relative in @(
    'README.md',
    'docs\V40_DESIGN_CN.md',
    'docs\V40_TCP_ZERO_COPY_LIFETIME_CN.md',
    'docs\V40_ACK_QUEUE_CN.md',
    'docs\V40_MEMORY_BUDGET.md',
    'docs\V40_VERIFICATION_REPORT.md',
    'docs\V40_BOARD_TEST_CN.md',
    'docs\V40_V38_V39_PERFORMANCE_COMPARISON.md',
    'docs\V40_PROJECT_FREEZE_AND_THESIS_PLAN.md'
)) {
    if (!(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Missing V40 documentation deliverable: $relative"
    }
}
$tcpBoard = Get-Content -LiteralPath (Join-Path $root 'scripts\run_v40_board_tcp_echo_throughput.ps1') -Raw
foreach ($required in @(
    '[int]$WindowChunks = 32',
    '[int]$DurationSeconds = 60',
    '[double]$DrainSeconds = 10',
    '[switch]$FullPayloadCheck = $true'
)) {
    if (!$tcpBoard.Contains($required)) {
        throw "V40 formal TCP Echo default missing: $required"
    }
}

@(
    'V40 TIMING AND OWNERSHIP STRUCTURE AUDIT PASSED',
    'CPU_FUNCTIONAL_NEGEDGE=0',
    'CPU_INVERTED_RAM_CLOCK=0',
    'ASYNC_RESET_NEGEDGE_RST_N=ALLOWED',
    'MII_AND_TSE_NON_CPU_CLOCKS=ALLOWED',
    'PIPELINE_VALID_MARKERS=PASS',
    'REQUEST_RESPONSE_MARKERS=PASS',
    'FORMAL_SOC_CLOCK_HZ=25000000',
    'SOC_SIM_PERIOD_NS=40',
    'FIRMWARE_TB_BOARD_COMMANDS=CONSISTENT',
    'REALTIME_PAYLOAD_SIGNATURE=V40',
    'PBUF_POOL_SIZE=24',
    'PBUF_POOL_BUFSIZE=1536',
    'TCP_WINDOW_MSS_MULTIPLIER=8',
    'TCP_ECHO_TCP_WRITE_COPY=0',
    'TCP_ECHO_PBUF_CAT=0',
    'OWNER_CAPACITY=16',
    'ACK_RECORD_CAPACITY=32',
    'TCP_ECHO_DEFAULT=1460B_WINDOW32_60S_DRAIN10_FULL_CHECK',
    'CPU_FALSE_PATH_EXCEPTIONS=0',
    'MULTICYCLE_EXCEPTIONS=0'
) | Tee-Object -FilePath (Join-Path $log 'summary.txt')
