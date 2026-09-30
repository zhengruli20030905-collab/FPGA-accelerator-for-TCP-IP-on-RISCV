typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;

#include "port/v40_clock_config.h"

#if defined(V25_LWIP_NOSYS) || defined(V26_TCP_ECHO)
typedef struct {
    uint32_t ff_tx_frames;
    uint32_t ff_rx_frames;
    uint32_t ff_rx_drops;
    uint32_t ff_rx_errors;
    uint32_t mii_tx_frames;
    uint32_t mii_tx_active_nibbles;
    uint32_t mii_tx_errors;
    uint32_t mii_rx_frames;
    uint32_t mii_rx_active_nibbles;
    uint32_t mii_rx_errors;
    uint32_t mii_counters_valid;
} v25_platform_hw_counters_t;
int v25_lwip_run(uint32_t initial_link_up);
int v26_lwip_run(uint32_t initial_link_up);
extern uint32_t __stack_limit;
extern uint32_t __stack_top;
#endif

#define RESULT_BASE ((volatile uint32_t *)0x00000100)
#define TEST_MEM32  ((volatile uint32_t *)0x00000200)
#define TEST_MEM8   ((volatile uint8_t  *)0x00000200)

#define UART_TX_DATA ((volatile uint32_t *)0x10000000)
#define UART_STATUS  ((volatile uint32_t *)0x10000004)
#define UART_TX_READY 0x00000001u

#define TIMER_COUNTER ((volatile uint32_t *)0x10000100)
#define TIMER_COMPARE ((volatile uint32_t *)0x10000104)
#define TIMER_STATUS  ((volatile uint32_t *)0x10000108)
#define TIMER_EXPIRED 0x00000001u

#define MDIO_ADDR       ((volatile uint32_t *)0x10001100)
#define MDIO_WDATA      ((volatile uint32_t *)0x10001104)
#define MDIO_CMD        ((volatile uint32_t *)0x10001108)
#define MDIO_RDATA      ((volatile uint32_t *)0x1000110C)
#define MDIO_STATUS     ((volatile uint32_t *)0x10001110)
#define PHY_RESET_CTRL  ((volatile uint32_t *)0x10001114)
#define MDIO_STATUS_BUSY  0x00000001u
#define MDIO_STATUS_DONE  0x00000002u
#define MDIO_STATUS_ERROR 0x00000004u
#define MDIO_CMD_START    0x00000001u
#define MDIO_CMD_WRITE    0x00000002u
#define PHY_RESET_PIN_UP  0x00000004u

#define BOARD_LEDR ((volatile uint32_t *)0x10002000)
#define BOARD_LEDG ((volatile uint32_t *)0x10002004)
#define BOARD_SW   ((volatile uint32_t *)0x10002008)
#define BOARD_KEY  ((volatile uint32_t *)0x1000200C)

#define TSE_ID            ((volatile uint32_t *)0x10003000)
#define TSE_VERSION       ((volatile uint32_t *)0x10003004)
#define TSE_CONTROL       ((volatile uint32_t *)0x10003008)
#define TSE_STATUS        ((volatile uint32_t *)0x1000300C)
#define TSE_SCRATCH       ((volatile uint32_t *)0x10003010)
#define TSE_CSR_ADDR      ((volatile uint32_t *)0x10003020)
#define TSE_CSR_WDATA     ((volatile uint32_t *)0x10003024)
#define TSE_CSR_RDATA     ((volatile uint32_t *)0x10003028)
#define TSE_CSR_CMD       ((volatile uint32_t *)0x1000302C)
#define TSE_CSR_STATUS    ((volatile uint32_t *)0x10003030)
#define TSE_STREAM_CTRL   ((volatile uint32_t *)0x10003040)
#define TSE_STREAM_STATUS ((volatile uint32_t *)0x10003044)
#define TSE_TX_DATA       ((volatile uint32_t *)0x10003050)
#define TSE_TX_LEN        ((volatile uint32_t *)0x10003054)
#define TSE_TX_CMD        ((volatile uint32_t *)0x10003058)
#define TSE_TX_STATUS     ((volatile uint32_t *)0x1000305C)
#define TSE_TX_COUNT      ((volatile uint32_t *)0x10003060)
#define TSE_TX_DEBUG_WORDS ((volatile uint32_t *)0x10003064)
#define TSE_TX_DEBUG_LAST ((volatile uint32_t *)0x10003068)
#define TSE_RX_DATA       ((volatile uint32_t *)0x10003070)
#define TSE_RX_LEN        ((volatile uint32_t *)0x10003074)
#define TSE_RX_CMD        ((volatile uint32_t *)0x10003078)
#define TSE_RX_STATUS     ((volatile uint32_t *)0x1000307C)
#define TSE_RX_COUNT      ((volatile uint32_t *)0x10003080)
#define TSE_RX_DEBUG_WORDS ((volatile uint32_t *)0x10003084)
#define TSE_RX_DEBUG_LAST ((volatile uint32_t *)0x10003088)
#define TSE_RX_DROP_COUNT ((volatile uint32_t *)0x1000308C)
#define TSE_RX_ERROR_COUNT ((volatile uint32_t *)0x10003090)
#define TSE_MII_DEBUG_CONTROL ((volatile uint32_t *)0x10003094)
#define TSE_MII_TX_FRAME_COUNT ((volatile uint32_t *)0x10003098)
#define TSE_MII_TX_ACTIVE_NIBBLE_COUNT ((volatile uint32_t *)0x1000309C)
#define TSE_MII_TX_ERROR_NIBBLE_COUNT ((volatile uint32_t *)0x100030A0)
#define TSE_MII_RX_FRAME_COUNT ((volatile uint32_t *)0x100030A4)
#define TSE_MII_RX_ACTIVE_NIBBLE_COUNT ((volatile uint32_t *)0x100030A8)
#define TSE_MII_RX_ERROR_NIBBLE_COUNT ((volatile uint32_t *)0x100030AC)
#define TSE_MII_DEBUG_STATUS ((volatile uint32_t *)0x100030B0)

#define TSE_ID_VALUE      0x54534531u
#define TSE_VERSION_VALUE 0x00001500u
#define TSE_CONTROL_PROBE_ENABLE 0x00000001u
#define TSE_CSR_CMD_READ  0x00000001u
#define TSE_CSR_CMD_WRITE 0x00000002u
#define TSE_CSR_PENDING   0x00000002u
#define TSE_CSR_WAITREQUEST 0x00000004u
#define TSE_MAC_LITE      1u
#define TSE_CSR_REG_REVISION       0u
#define TSE_CSR_REG_SCRATCH        1u
#define TSE_CSR_REG_COMMAND_CONFIG 2u
#define TSE_CSR_REG_MAC_ADDR_0     3u
#define TSE_CSR_REG_MAC_ADDR_1     4u
#define TSE_CSR_REG_FRAME_LENGTH   5u
#define TSE_CSR_REG_TX_IPG_LENGTH  23u
#define TSE_CSR_REG_TX_CMD_STAT    0x3Au
#define TSE_CSR_REG_RX_CMD_STAT    0x3Bu
#define TSE_TX_SHIFT16_BIT         0x00040000u
#define TSE_RX_SHIFT16_BIT         0x02000000u
#define TSE_MAC_COMMAND_CONFIG     0x04000033u
#define TSE_MAC_ADDR_LOW           0x3456789Au
#define TSE_MAC_ADDR_HIGH          0x00000212u
#define TSE_TX_CMD_START  0x00000001u
#define TSE_TX_CMD_CLEAR  0x00000002u
#define TSE_TX_CMD_LOOPBACK_EN 0x00000004u
#define TSE_TX_STATUS_DONE 0x00000002u
#define TSE_TX_STATUS_ERROR 0x00000004u
#define TSE_TX_STATUS_LOOPBACK_DONE 0x00000040u
#define TSE_RX_CMD_CLEAR  0x00000001u
#define TSE_RX_CMD_REWIND 0x00000002u
#define TSE_RX_CMD_FETCH  0x00000004u
#define TSE_RX_STATUS_READY 0x00000001u
#define TSE_RX_STATUS_OVERFLOW 0x00000004u
#define TSE_RX_STATUS_READ_DONE 0x00000020u
#define TSE_RX_STATUS_PROTOCOL_ERROR 0x00000080u
#define TSE_RX_STATUS_DROP 0x00000100u
#define TSE_RX_STATUS_DATA_READY 0x00000200u
#define TSE_RX_STATUS_READ_PENDING 0x00000400u
#define TSE_MII_DEBUG_CONTROL_CLEAR 0x00000001u
#define TSE_MII_DEBUG_STATUS_TX_CDC_VALID 0x00000001u
#define TSE_MII_DEBUG_STATUS_RX_CDC_VALID 0x00000002u
#define TSE_MII_DEBUG_STATUS_TX_CLEAR_PENDING 0x00000004u
#define TSE_MII_DEBUG_STATUS_RX_CLEAR_PENDING 0x00000008u
#define TSE_MII_DEBUG_STATUS_CDC_VALID_MASK \
    (TSE_MII_DEBUG_STATUS_TX_CDC_VALID | TSE_MII_DEBUG_STATUS_RX_CDC_VALID)
#define TSE_MII_DEBUG_STATUS_CLEAR_PENDING_MASK \
    (TSE_MII_DEBUG_STATUS_TX_CLEAR_PENDING | TSE_MII_DEBUG_STATUS_RX_CLEAR_PENDING)

#define BRINGUP_LED_ALIVE        0x001u
#define BRINGUP_LED_MDIO_OK      0x002u
#define BRINGUP_LED_LINK_UP      0x004u
#define BRINGUP_LED_FF_TX        0x008u
#define BRINGUP_LED_MII_TX       0x010u
#define BRINGUP_LED_RX           0x020u
#define BRINGUP_LED_STICKY_ERROR 0x040u
#define BRINGUP_LED_RUNNING      0x080u
#define BRINGUP_LED_FATAL        0x100u

#define PHY0_ADDR 0x10u
#define PHY_REG_BMCR 0u
#define PHY_REG_BMSR 1u
#define PHY_REG_ID1 2u
#define PHY_REG_ID2 3u
#define PHY_REG_ANAR 4u
#define PHY_REG_ANLPAR 5u
#define PHY_REG_STATUS 17u
#define PHY_BMSR_LINK_STATUS 0x0004u
#define BRINGUP_POLL_INTERVAL_MS 1000u

static uint32_t bss_guard;
static uint32_t bss_words[4];
static uint32_t data_guard = 0x13572468u;
static const char banner[] = "RV32I V15 TSE MII BOARDPREP\n";
#ifdef BOARD_BRINGUP_TEST
static uint32_t bringup_led_state;
static uint32_t bringup_mii_debug_available;

typedef struct {
    uint16_t bmcr;
    uint16_t bmsr_first;
    uint16_t bmsr_current;
    uint16_t id1;
    uint16_t id2;
    uint16_t anar;
    uint16_t anlpar;
    uint16_t status17;
} phy_snapshot_t;
#endif

// MMIO packet words use little-endian byte packing:
// word[7:0] is the earliest byte in the Ethernet frame.
static const uint32_t tx_frame_words[16] = {
    0xffffffffu, 0x1202ffffu, 0x9a785634u, 0x5652b588u,
    0x20493233u, 0x20343256u, 0x20455354u, 0x0049494du,
    0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u,
    0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u
};

static void uart_putc(uint32_t ch);
static void uart_puts(const char *s);
static void uart_put_hex8(uint8_t value);
static void uart_put_hex16(uint16_t value);
static void uart_put_hex32(uint32_t value);

static void stop_here(void)
{
    __asm__ volatile ("ebreak");
    while (1) {
    }
}

static void ledr_write(uint32_t value)
{
    BOARD_LEDR[0] = value;
}

static void ledg_write(uint32_t value)
{
    BOARD_LEDG[0] = value;
}

static void fail(uint32_t code)
{
    ledr_write(0x20000u | (code & 0x1ffffu));
#ifdef BOARD_BRINGUP_TEST
    bringup_led_state |= BRINGUP_LED_FATAL;
    ledg_write(bringup_led_state);
#else
    ledg_write(0x000u);
#endif
    RESULT_BASE[0] = 0xDEAD0000u | (code & 0xffffu);
    RESULT_BASE[1] = code;
    uart_puts("BOARDPREP FAIL ");
    uart_put_hex16((uint16_t)code);
    uart_putc('\n');
    stop_here();
}

static uint32_t timer_read(void)
{
    return TIMER_COUNTER[0];
}

static void delay_cycles(uint32_t cycles)
{
    uint32_t start = timer_read();

    while ((timer_read() - start) < cycles) {
    }
}

static void delay_ms(uint32_t ms)
{
    while (ms != 0u) {
        delay_cycles(V40_CYCLES_PER_MS);
        ms = ms - 1u;
    }
}

static uint32_t uart_status(void)
{
    return UART_STATUS[0];
}

static void uart_putc(uint32_t ch)
{
    while ((uart_status() & UART_TX_READY) == 0u) {
    }

    UART_TX_DATA[0] = ch;
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc((uint32_t)(uint8_t)*s);
        s = s + 1;
    }
}

static void uart_put_hex16(uint16_t value)
{
    int shift;

    for (shift = 12; shift >= 0; shift = shift - 4) {
        uint32_t nibble = ((uint32_t)value >> shift) & 0x0fu;
        if (nibble < 10u) {
            uart_putc('0' + nibble);
        } else {
            uart_putc('A' + (nibble - 10u));
        }
    }
}

static void uart_put_hex8(uint8_t value)
{
    uint32_t nibble = ((uint32_t)value >> 4) & 0x0fu;
    uart_putc((nibble < 10u) ? ('0' + nibble) : ('A' + nibble - 10u));
    nibble = (uint32_t)value & 0x0fu;
    uart_putc((nibble < 10u) ? ('0' + nibble) : ('A' + nibble - 10u));
}

static void uart_put_hex32(uint32_t value)
{
    uart_put_hex16((uint16_t)(value >> 16));
    uart_put_hex16((uint16_t)value);
}

static void uart_put_reg(const char *name, uint16_t value)
{
    uart_puts(name);
    uart_put_hex16(value);
    uart_putc('\n');
}

__attribute__((noinline)) static uint32_t stack_probe(uint32_t seed)
{
    volatile uint32_t local[8];
    uint32_t i;
    uint32_t acc = seed;

    for (i = 0u; i < 8u; i = i + 1u) {
        local[i] = acc ^ (0x11110000u + i);
        acc = acc + local[i];
    }

    return local[3] ^ local[7] ^ acc;
}

static void ram_test(void)
{
    uint32_t i;

    if (bss_guard != 0u)
        fail(0x0011u);
    if (bss_words[0] != 0u)
        fail(0x0012u);
    if (data_guard != 0x13572468u)
        fail(0x0013u);

    bss_guard = 0x24681357u;
    bss_words[0] = bss_guard + 1u;
    bss_words[1] = bss_words[0] + 1u;

    if (bss_words[1] != 0x24681359u)
        fail(0x0014u);

    for (i = 0u; i < 16u; i = i + 1u) {
        TEST_MEM32[i] = 0xA5000000u | i;
    }

    TEST_MEM8[5] = 0x5au;

    if (TEST_MEM32[1] != 0xA5005A01u)
        fail(0x0015u);

    for (i = 0u; i < 16u; i = i + 1u) {
        if (i == 1u) {
            if (TEST_MEM32[i] != 0xA5005A01u)
                fail(0x0016u);
        } else if (TEST_MEM32[i] != (0xA5000000u | i)) {
            fail(0x0017u);
        }
    }

    uart_puts("RAM OK\n");
}

static void stack_test(void)
{
    uint32_t value = stack_probe(0x12345678u);

    if (value == 0u)
        fail(0x0021u);

    RESULT_BASE[2] = value;
    uart_puts("STACK OK\n");
}

static void timer_test(void)
{
    uint32_t before;
    uint32_t after;
    uint32_t target;
    uint32_t guard;

    before = timer_read();
    delay_cycles(64u);
    after = timer_read();

    if ((after - before) < 64u)
        fail(0x0031u);

    target = timer_read() + 128u;
    TIMER_COMPARE[0] = target;
    guard = timer_read();

    while ((TIMER_STATUS[0] & TIMER_EXPIRED) == 0u) {
        if ((timer_read() - guard) > 4096u)
            fail(0x0032u);
    }

    uart_puts("TIMER OK\n");
}

static void led_blink_test(void)
{
    ledr_write(0x00055u);
    delay_ms(2u);
    ledr_write(0x000AAu);
    delay_ms(2u);
    ledr_write(0x0000Fu);
}

static void test_tse_soc_csr(void)
{
    uint32_t status;

    if (TSE_ID[0] != TSE_ID_VALUE)
        fail(0x1201u);

    if (TSE_VERSION[0] != TSE_VERSION_VALUE)
        fail(0x1202u);

    TSE_SCRATCH[0] = 0x1234ABCDu;
    if (TSE_SCRATCH[0] != 0x1234ABCDu)
        fail(0x1203u);

    TSE_CONTROL[0] = TSE_CONTROL_PROBE_ENABLE;
    if ((TSE_CONTROL[0] & TSE_CONTROL_PROBE_ENABLE) == 0u)
        fail(0x1204u);

    status = TSE_STATUS[0];
    if ((status & TSE_CONTROL_PROBE_ENABLE) == 0u)
        fail(0x1205u);

    if ((TSE_STREAM_STATUS[0] & 0x00000005u) != 0x00000005u)
        fail(0x1206u);

    uart_puts("TSE WRAP OK\n");
}

static void tse_csr_wait_idle(void)
{
    uint32_t guard;
    uint32_t status;

    guard = timer_read();
    do {
        status = TSE_CSR_STATUS[0];
        if ((timer_read() - guard) > 4096u)
            fail(0x1502u);
    } while ((status & (TSE_CSR_PENDING | TSE_CSR_WAITREQUEST)) != 0u);
}

static void tse_csr_write_reg(uint32_t reg, uint32_t value)
{
    tse_csr_wait_idle();
    TSE_CSR_ADDR[0] = reg;
    TSE_CSR_WDATA[0] = value;
    TSE_CSR_CMD[0] = TSE_CSR_CMD_WRITE;
    tse_csr_wait_idle();
}

static uint32_t tse_csr_read_reg(uint32_t reg)
{
    tse_csr_wait_idle();
    TSE_CSR_ADDR[0] = reg;
    TSE_CSR_CMD[0] = TSE_CSR_CMD_READ;
    tse_csr_wait_idle();

    return TSE_CSR_RDATA[0];
}

static void test_tse_csr_bridge(void)
{
    uint32_t core_version;
    uint32_t scratch_readback;

    TSE_CSR_ADDR[0] = 0x12u;
    if ((TSE_CSR_ADDR[0] & 0x3ffu) != 0x12u)
        fail(0x1207u);

    TSE_CSR_WDATA[0] = 0xA5A51234u;
    if (TSE_CSR_WDATA[0] != 0xA5A51234u)
        fail(0x1208u);

    tse_csr_write_reg(0x12u, 0xA5A51234u);
    if ((TSE_CSR_STATUS[0] & TSE_CSR_WAITREQUEST) != 0u)
        fail(0x1209u);

    core_version = tse_csr_read_reg(TSE_CSR_REG_REVISION);
    if (core_version == 0u)
        fail(0x120Au);
    uart_puts("TSE CORE=");
    uart_put_hex32(core_version);
    uart_putc('\n');

#if TSE_MAC_LITE
    // Intel's generated MAC Lite testbench skips the CSR 1 write/read test.
    // Keep one read-only sample so the board log still records the response.
    scratch_readback = tse_csr_read_reg(TSE_CSR_REG_SCRATCH);
    uart_puts("TSE SCRATCH=");
    uart_put_hex32(scratch_readback);
    uart_puts(" (MAC LITE, TEST SKIPPED)\n");
#else
    tse_csr_write_reg(TSE_CSR_REG_SCRATCH, 0xA5A55A5Au);
    scratch_readback = tse_csr_read_reg(TSE_CSR_REG_SCRATCH);
    uart_puts("TSE SCRATCH=");
    uart_put_hex32(scratch_readback);
    uart_putc('\n');
    if ((scratch_readback != 0xA5A55A5Au) &&
        (scratch_readback != 0x54530001u))
        fail(0x120Bu);
#endif

#if defined(V31_SGDMA) && defined(V27_SYNC_IMEM)
    uart_puts("RV32I V40 TSE CSR OK\n");
#elif defined(V24_WIRE_FORMAT_FIX)
    uart_puts("RV32I V24 TSE CSR OK\n");
#elif defined(V23_BOARD_DIAGNOSTICS)
    uart_puts("RV32I V23 TSE CSR OK\n");
#else
    uart_puts("RV32I V15 TSE CSR OK\n");
#endif
}

static void tse_configure_stream_alignment(void)
{
    uint32_t tx_before;
    uint32_t rx_before;
    uint32_t tx_after;
    uint32_t rx_after;

    // The generated IP has ENABLE_SHIFT16=1. Its reset values enable a
    // two-byte stream shift, which v23 exposed as a 62-byte wire frame. Keep
    // all unrelated command/status bits and clear only the alignment controls.
    tx_before = tse_csr_read_reg(TSE_CSR_REG_TX_CMD_STAT);
    rx_before = tse_csr_read_reg(TSE_CSR_REG_RX_CMD_STAT);
    uart_puts("TSE TX_CMD_STAT BEFORE=");
    uart_put_hex32(tx_before);
    uart_puts(" RX_CMD_STAT BEFORE=");
    uart_put_hex32(rx_before);
    uart_putc('\n');

    tse_csr_write_reg(TSE_CSR_REG_TX_CMD_STAT,
                      tx_before & ~TSE_TX_SHIFT16_BIT);
    tse_csr_write_reg(TSE_CSR_REG_RX_CMD_STAT,
                      rx_before & ~TSE_RX_SHIFT16_BIT);

    tx_after = tse_csr_read_reg(TSE_CSR_REG_TX_CMD_STAT);
    rx_after = tse_csr_read_reg(TSE_CSR_REG_RX_CMD_STAT);
    uart_puts("TSE TX_CMD_STAT AFTER=");
    uart_put_hex32(tx_after);
    uart_puts(" RX_CMD_STAT AFTER=");
    uart_put_hex32(rx_after);
    uart_putc('\n');

    if ((tx_after & TSE_TX_SHIFT16_BIT) != 0u)
        fail(0x2401u);
    if ((rx_after & TSE_RX_SHIFT16_BIT) != 0u)
        fail(0x2402u);

    uart_puts("TSE STREAM ALIGNMENT OK\n");
}

static void tse_init_mac(void)
{
    // Match the generated Intel testbench sequence for Small MAC/MAC Lite:
    // command_config, primary MAC address, then TX IPG length.
    tse_csr_write_reg(TSE_CSR_REG_COMMAND_CONFIG, TSE_MAC_COMMAND_CONFIG);
    tse_csr_write_reg(TSE_CSR_REG_MAC_ADDR_0, TSE_MAC_ADDR_LOW);
    tse_csr_write_reg(TSE_CSR_REG_MAC_ADDR_1, TSE_MAC_ADDR_HIGH);
    tse_csr_write_reg(TSE_CSR_REG_TX_IPG_LENGTH, 12u);
#if !TSE_MAC_LITE
    tse_csr_write_reg(TSE_CSR_REG_FRAME_LENGTH, 1518u);
#endif
    uart_puts("TSE MAC CFG OK\n");
}

static int tse_send_frame_once(uint32_t loopback_enable)
{
    uint32_t i;
    uint32_t status;
    uint32_t guard;

    TSE_TX_CMD[0] = TSE_TX_CMD_CLEAR;

    for (i = 0u; i < 16u; i = i + 1u) {
        TSE_TX_DATA[0] = tx_frame_words[i];
    }

    if (TSE_TX_DEBUG_WORDS[0] != 16u)
        return -1;

    if (TSE_TX_DEBUG_LAST[0] != tx_frame_words[15])
        return -2;

    TSE_TX_LEN[0] = 64u;
    if (TSE_TX_LEN[0] != 64u)
        return -3;

    TSE_TX_CMD[0] = TSE_TX_CMD_START |
                    (loopback_enable ? TSE_TX_CMD_LOOPBACK_EN : 0u);

    guard = timer_read();
    do {
        status = TSE_TX_STATUS[0];
        if ((status & TSE_TX_STATUS_ERROR) != 0u)
            return -4;
        if ((timer_read() - guard) > 4096u)
            return -5;
    } while ((status & TSE_TX_STATUS_DONE) == 0u);

    return 0;
}

static uint32_t tse_rx_read_word(void)
{
    uint32_t guard = 0u;

    // RX packet storage is synchronous block RAM. FETCH starts one read at the
    // current pointer; DATA_READY is asserted one clock later with RX_DATA held
    // stable until this load consumes it.
    TSE_RX_CMD[0] = TSE_RX_CMD_FETCH;
    while ((TSE_RX_STATUS[0] & TSE_RX_STATUS_DATA_READY) == 0u) {
        guard++;
        if (guard > 100000u)
            fail(0x13F0u);
    }
    return TSE_RX_DATA[0];
}

static void test_tse_txrx_mmio(void)
{
    uint32_t i;
    uint32_t status;
    uint32_t guard;
    uint32_t word;

    TSE_STREAM_CTRL[0] = 0x00000003u;
    TSE_RX_CMD[0] = TSE_RX_CMD_CLEAR;

    if (tse_send_frame_once(1u) != 0)
        fail(0x1314u);

    status = TSE_TX_STATUS[0];
    if ((status & TSE_TX_STATUS_LOOPBACK_DONE) == 0u)
        fail(0x1315u);

    if (TSE_TX_COUNT[0] != 1u)
        fail(0x1316u);

    guard = timer_read();
    do {
        status = TSE_RX_STATUS[0];
        if ((timer_read() - guard) > 4096u)
            fail(0x1317u);
    } while ((status & TSE_RX_STATUS_READY) == 0u);

    if (TSE_RX_LEN[0] != 64u)
        fail(0x1318u);

    if (TSE_RX_COUNT[0] != 1u)
        fail(0x1319u);

    if (TSE_RX_DEBUG_WORDS[0] != 16u)
        fail(0x131Au);

    TSE_RX_CMD[0] = TSE_RX_CMD_REWIND;

    for (i = 0u; i < 16u; i = i + 1u) {
        word = tse_rx_read_word();
        if (word != tx_frame_words[i])
            fail(0x1320u + i);
    }

    if ((TSE_RX_STATUS[0] & TSE_RX_STATUS_READ_DONE) == 0u)
        fail(0x1330u);

    uart_puts("RV32I V15 TSE MMIO LOOPBACK OK\n");
}

static int wait_phy_reset_release(void)
{
    uint32_t guard;

    PHY_RESET_CTRL[0] = 0x1u;
    guard = timer_read();

    while ((PHY_RESET_CTRL[0] & PHY_RESET_PIN_UP) == 0u) {
        if ((timer_read() - guard) > 1000000u)
            return -1;
    }

    delay_ms(5u);
    return 0;
}

static int mdio_read(uint32_t phy, uint32_t reg, uint16_t *value)
{
    uint32_t guard;
    uint32_t status;

    MDIO_ADDR[0] = ((phy & 0x1fu) << 5) | (reg & 0x1fu);
    MDIO_CMD[0] = MDIO_CMD_START;

    guard = timer_read();
    do {
        status = MDIO_STATUS[0];
        if ((status & MDIO_STATUS_ERROR) != 0u)
            return -1;
        if ((timer_read() - guard) > 1000000u)
            return -2;
    } while ((status & MDIO_STATUS_DONE) == 0u);

    *value = (uint16_t)(MDIO_RDATA[0] & 0xffffu);
    return 0;
}

#if defined(NET_SIM_TEST) || defined(BOARD_BRINGUP_TEST)

#define NET_MAX_FRAME 2048u
#define NET_MIN_FRAME_NO_FCS 60u
#define NET_LOCAL_IP 0xC0A80132u
#define NET_UDP_ECHO_PORT 1234u

static const uint8_t net_local_mac[6] = {0x02u, 0x12u, 0x34u,
                                         0x56u, 0x78u, 0x9au};
static uint8_t net_frame[NET_MAX_FRAME];

static uint16_t read_be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | (uint16_t)p[1]);
}

static uint32_t read_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void write_be16(uint8_t *p, uint16_t value)
{
    p[0] = (uint8_t)(value >> 8);
    p[1] = (uint8_t)value;
}

static void write_be32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)(value >> 24);
    p[1] = (uint8_t)(value >> 16);
    p[2] = (uint8_t)(value >> 8);
    p[3] = (uint8_t)value;
}

static uint16_t net_checksum(const uint8_t *p, uint32_t len)
{
    uint32_t sum = 0u;

    while (len >= 2u) {
        sum += read_be16(p);
        p += 2;
        len -= 2u;
    }
    if (len != 0u)
        sum += (uint32_t)p[0] << 8;

    while ((sum >> 16) != 0u)
        sum = (sum & 0xffffu) + (sum >> 16);

    return (uint16_t)~sum;
}

static void copy_bytes(uint8_t *dst, const uint8_t *src, uint32_t len)
{
    while (len != 0u) {
        *dst++ = *src++;
        len--;
    }
}

static void swap_bytes(uint8_t *a, uint8_t *b, uint32_t len)
{
    while (len != 0u) {
        uint8_t tmp = *a;
        *a++ = *b;
        *b++ = tmp;
        len--;
    }
}

static int bytes_equal(const uint8_t *a, const uint8_t *b, uint32_t len)
{
    while (len != 0u) {
        if (*a++ != *b++)
            return 0;
        len--;
    }
    return 1;
}

static int mac_is_broadcast(const uint8_t *mac)
{
    uint32_t i;

    for (i = 0u; i < 6u; i++) {
        if (mac[i] != 0xffu)
            return 0;
    }
    return 1;
}

static uint32_t net_receive_frame(void)
{
    uint32_t len;
    uint32_t words;
    uint32_t i;

    while ((TSE_RX_STATUS[0] & TSE_RX_STATUS_READY) == 0u) {
        if ((TSE_RX_STATUS[0] & TSE_RX_STATUS_OVERFLOW) != 0u)
            fail(0x1701u);
    }

    len = TSE_RX_LEN[0];
    if ((len == 0u) || (len > NET_MAX_FRAME)) {
        TSE_RX_CMD[0] = TSE_RX_CMD_CLEAR;
        fail(0x1702u);
    }

    words = (len + 3u) >> 2;
    for (i = 0u; i < words; i++) {
        uint32_t word = tse_rx_read_word();
        uint32_t base = i << 2;
        if (base < len)
            net_frame[base] = (uint8_t)word;
        if ((base + 1u) < len)
            net_frame[base + 1u] = (uint8_t)(word >> 8);
        if ((base + 2u) < len)
            net_frame[base + 2u] = (uint8_t)(word >> 16);
        if ((base + 3u) < len)
            net_frame[base + 3u] = (uint8_t)(word >> 24);
    }

    // Clearing transfers ownership of the single-frame RX buffer back to the
    // stream side. All bytes have already been copied into net_frame[].
    TSE_RX_CMD[0] = TSE_RX_CMD_CLEAR;
    return len;
}

static void net_send_frame(uint32_t len)
{
    uint32_t send_len = len;
    uint32_t words;
    uint32_t i;
    uint32_t guard;
    uint32_t status;

    if (send_len < NET_MIN_FRAME_NO_FCS) {
        for (i = send_len; i < NET_MIN_FRAME_NO_FCS; i++)
            net_frame[i] = 0u;
        send_len = NET_MIN_FRAME_NO_FCS;
    }

    TSE_TX_CMD[0] = TSE_TX_CMD_CLEAR;
    words = (send_len + 3u) >> 2;
    for (i = 0u; i < words; i++) {
        uint32_t base = i << 2;
        uint32_t word = (uint32_t)net_frame[base] |
                        ((uint32_t)net_frame[base + 1u] << 8) |
                        ((uint32_t)net_frame[base + 2u] << 16) |
                        ((uint32_t)net_frame[base + 3u] << 24);
        TSE_TX_DATA[0] = word;
    }

    TSE_TX_LEN[0] = send_len;
    TSE_TX_CMD[0] = TSE_TX_CMD_START;

    guard = 0u;
    do {
        status = TSE_TX_STATUS[0];
        if ((status & TSE_TX_STATUS_ERROR) != 0u)
            fail(0x1703u);
        guard++;
        if (guard > 100000u)
            fail(0x1704u);
    } while ((status & TSE_TX_STATUS_DONE) == 0u);
}

static uint32_t net_handle_arp(uint32_t len)
{
    uint8_t peer_mac[6];
    uint32_t peer_ip;

    if ((len < 42u) ||
        (!mac_is_broadcast(&net_frame[0]) &&
         !bytes_equal(&net_frame[0], net_local_mac, 6u)) ||
        (read_be16(&net_frame[12]) != 0x0806u) ||
        (read_be16(&net_frame[14]) != 1u) ||
        (read_be16(&net_frame[16]) != 0x0800u) ||
        (net_frame[18] != 6u) || (net_frame[19] != 4u) ||
        (read_be16(&net_frame[20]) != 1u) ||
        (read_be32(&net_frame[38]) != NET_LOCAL_IP))
        return 0u;

    copy_bytes(peer_mac, &net_frame[22], 6u);
    peer_ip = read_be32(&net_frame[28]);
    copy_bytes(&net_frame[0], peer_mac, 6u);
    copy_bytes(&net_frame[6], net_local_mac, 6u);
    write_be16(&net_frame[20], 2u);
    copy_bytes(&net_frame[22], net_local_mac, 6u);
    write_be32(&net_frame[28], NET_LOCAL_IP);
    copy_bytes(&net_frame[32], peer_mac, 6u);
    write_be32(&net_frame[38], peer_ip);
    return 42u;
}

static uint32_t net_handle_ipv4(uint32_t len)
{
    uint32_t ihl;
    uint32_t ip_len;
    uint32_t l4_len;
    uint32_t l4;

    if ((len < 34u) ||
        !bytes_equal(&net_frame[0], net_local_mac, 6u) ||
        (read_be16(&net_frame[12]) != 0x0800u) ||
        ((net_frame[14] >> 4) != 4u) ||
        (read_be32(&net_frame[30]) != NET_LOCAL_IP))
        return 0u;

    ihl = (uint32_t)(net_frame[14] & 0x0fu) << 2;
    ip_len = read_be16(&net_frame[16]);
    if ((ihl < 20u) || (ip_len < ihl) || ((14u + ip_len) > len))
        return 0u;
    if (net_checksum(&net_frame[14], ihl) != 0u)
        return 0u;
    if ((read_be16(&net_frame[20]) & 0x3fffu) != 0u)
        return 0u;

    l4 = 14u + ihl;
    l4_len = ip_len - ihl;
    if (net_frame[23] == 1u) {
        if ((l4_len < 8u) || (net_frame[l4] != 8u) ||
            (net_frame[l4 + 1u] != 0u) ||
            (net_checksum(&net_frame[l4], l4_len) != 0u))
            return 0u;
        net_frame[l4] = 0u;
        net_frame[l4 + 2u] = 0u;
        net_frame[l4 + 3u] = 0u;
        write_be16(&net_frame[l4 + 2u], net_checksum(&net_frame[l4], l4_len));
    } else if (net_frame[23] == 17u) {
        uint32_t udp_len;
        if (l4_len < 8u)
            return 0u;
        udp_len = read_be16(&net_frame[l4 + 4u]);
        if ((read_be16(&net_frame[l4 + 2u]) != NET_UDP_ECHO_PORT) ||
            (udp_len < 8u) || (udp_len != l4_len))
            return 0u;
        swap_bytes(&net_frame[l4], &net_frame[l4 + 2u], 2u);
        // IPv4 permits a UDP checksum of zero. v18 retains that explicit
        // simulation/bring-up convention; the IPv4 checksum is rebuilt.
        net_frame[l4 + 6u] = 0u;
        net_frame[l4 + 7u] = 0u;
    } else {
        return 0u;
    }

    swap_bytes(&net_frame[0], &net_frame[6], 6u);
    swap_bytes(&net_frame[26], &net_frame[30], 4u);
    net_frame[24] = 0u;
    net_frame[25] = 0u;
    write_be16(&net_frame[24], net_checksum(&net_frame[14], ihl));
    return 14u + ip_len;
}

static uint32_t net_dispatch_frame(uint32_t len)
{
    if ((len >= 14u) && (read_be16(&net_frame[12]) == 0x0806u))
        return net_handle_arp(len);
    return net_handle_ipv4(len);
}

static int net_sim_main(void)
{
    uint32_t replies = 0u;

    TSE_STREAM_CTRL[0] = 0x00000003u;
    TSE_RX_CMD[0] = TSE_RX_CMD_CLEAR;
    RESULT_BASE[1] = 0u;
    // Testbench injection starts only after this marker, so the initial RX
    // clear cannot discard a just-injected external frame.
    #ifdef V18_NET_ROBUST_TEST
    RESULT_BASE[0] = 0x18000000u;
    #else
    RESULT_BASE[0] = 0x17000000u;
    #endif

#ifdef V18_NET_ROBUST_TEST
    while (1) {
#else
    while (replies < 3u) {
#endif
        uint32_t len = net_receive_frame();
        uint32_t reply_len = net_dispatch_frame(len);

        if (reply_len != 0u) {
            net_send_frame(reply_len);
            replies++;
            RESULT_BASE[1] = replies;
        }
        RESULT_BASE[2] = TSE_RX_COUNT[0];
    }

#ifndef V18_NET_ROBUST_TEST
    RESULT_BASE[0] = 0xC017CAFEu;
    RESULT_BASE[2] = TSE_RX_COUNT[0];
    stop_here();
#endif
    return 0;
}

#endif

#ifdef BOARD_BRINGUP_TEST

#if defined(V25_LWIP_NOSYS) || defined(V26_TCP_ECHO)
#ifdef V27_SYNC_IMEM
#define BRINGUP_RESULT_MARKER 0xC027B00Bu
#elif defined(V26_TCP_ECHO)
#define BRINGUP_RESULT_MARKER 0xC026B00Bu
#else
#define BRINGUP_RESULT_MARKER 0xC025B00Bu
#endif
#elif defined(V24_WIRE_FORMAT_FIX)
#define BRINGUP_RESULT_MARKER 0xC024B00Bu
#elif defined(V23_BOARD_DIAGNOSTICS)
#define BRINGUP_RESULT_MARKER 0xC023B00Bu
#else
#define BRINGUP_RESULT_MARKER 0xC018B00Bu
#endif

static void bringup_led_set(uint32_t bits)
{
    bringup_led_state |= bits;
    ledg_write(bringup_led_state);
    RESULT_BASE[2] = bringup_led_state;
}

static void bringup_led_assign(uint32_t bits, uint32_t active)
{
    if (active != 0u)
        bringup_led_state |= bits;
    else
        bringup_led_state &= ~bits;
    ledg_write(bringup_led_state);
    RESULT_BASE[2] = bringup_led_state;
}

static void bringup_print_mac(const uint8_t *mac)
{
    uint32_t i;

    for (i = 0u; i < 6u; i++) {
        if (i != 0u)
            uart_putc(':');
        uart_put_hex8(mac[i]);
    }
}

static void bringup_print_tse_status(void)
{
    uint32_t tx_status = TSE_TX_STATUS[0];
    uint32_t rx_status = TSE_RX_STATUS[0];

    // These are self-authored FF-side adapter observations. They do not prove
    // PHY link or external packet reception by a PC.
    uart_puts("FF TX_COUNT=");
    uart_put_hex32(TSE_TX_COUNT[0]);
    uart_puts(" FF TX_STATUS=");
    uart_put_hex32(tx_status);
    uart_putc('\n');
    uart_puts("FF RX_COUNT=");
    uart_put_hex32(TSE_RX_COUNT[0]);
    uart_puts(" FF RX_STATUS=");
    uart_put_hex32(rx_status);
    uart_putc('\n');
    uart_puts("FF RX_DROP_COUNT=");
    uart_put_hex32(TSE_RX_DROP_COUNT[0]);
    uart_puts(" FF RX_ERROR_COUNT=");
    uart_put_hex32(TSE_RX_ERROR_COUNT[0]);
    uart_putc('\n');

    if (((tx_status & TSE_TX_STATUS_ERROR) != 0u) ||
        ((rx_status & (TSE_RX_STATUS_OVERFLOW |
                       TSE_RX_STATUS_PROTOCOL_ERROR |
                       TSE_RX_STATUS_DROP)) != 0u) ||
        (TSE_RX_DROP_COUNT[0] != 0u) || (TSE_RX_ERROR_COUNT[0] != 0u))
        bringup_led_set(BRINGUP_LED_STICKY_ERROR);
}

static void bringup_prepare_mii_debug(void)
{
    uint32_t status;
    uint32_t guard;

    // Read before clear so the board transcript records a pre-existing MII
    // observation without treating it as a PHY/link result.
    status = TSE_MII_DEBUG_STATUS[0];
    uart_puts("MII DEBUG STATUS BEFORE CLEAR=");
    uart_put_hex32(status);
    uart_putc('\n');

    if ((status & TSE_MII_DEBUG_STATUS_CDC_VALID_MASK) !=
        TSE_MII_DEBUG_STATUS_CDC_VALID_MASK) {
        bringup_mii_debug_available = 0u;
        uart_puts("MII DEBUG UNAVAILABLE: CDC STATUS INVALID\n");
        return;
    }

    uart_puts("MII PRECLEAR TX_FRAME=");
    uart_put_hex32(TSE_MII_TX_FRAME_COUNT[0]);
    uart_puts(" RX_FRAME=");
    uart_put_hex32(TSE_MII_RX_FRAME_COUNT[0]);
    uart_putc('\n');

    TSE_MII_DEBUG_CONTROL[0] = TSE_MII_DEBUG_CONTROL_CLEAR;
    guard = timer_read();
    do {
        status = TSE_MII_DEBUG_STATUS[0];
        if ((timer_read() - guard) > 4096u) {
            bringup_mii_debug_available = 0u;
            uart_puts("MII DEBUG CLEAR PENDING: CHECK MII CLOCKS\n");
            return;
        }
    } while ((status & TSE_MII_DEBUG_STATUS_CLEAR_PENDING_MASK) != 0u);

    // Allow the two CPU-domain Gray synchronizer stages to observe the zeros.
    delay_cycles(8u);
    bringup_mii_debug_available = 1u;
    uart_puts("MII DEBUG COUNTERS CLEARED\n");
}

static void bringup_print_mii_status(void)
{
    uint32_t status;
    uint32_t tx_frames;
    uint32_t tx_errors;
    uint32_t rx_errors;

    if (bringup_mii_debug_available == 0u) {
        uart_puts("MII COUNTERS UNAVAILABLE: NO VALID BOARD-SIDE OBSERVATION\n");
        return;
    }

    status = TSE_MII_DEBUG_STATUS[0];
    if ((status & TSE_MII_DEBUG_STATUS_CLEAR_PENDING_MASK) != 0u) {
        uart_puts("MII COUNTERS PENDING CLEAR: VALUES NOT VALID\n");
        return;
    }

    tx_frames = TSE_MII_TX_FRAME_COUNT[0];
    tx_errors = TSE_MII_TX_ERROR_NIBBLE_COUNT[0];
    rx_errors = TSE_MII_RX_ERROR_NIBBLE_COUNT[0];

    // These values observe the generated TSE MII pins at the FPGA boundary.
    // They still do not prove that the PHY or Wireshark received the frame.
    uart_puts("MII DEBUG_STATUS=");
    uart_put_hex32(status);
    uart_putc('\n');
    uart_puts("MII TX_FRAME=");
    uart_put_hex32(tx_frames);
    uart_puts(" MII TX_ACTIVE_NIBBLES=");
    uart_put_hex32(TSE_MII_TX_ACTIVE_NIBBLE_COUNT[0]);
    uart_puts(" MII TX_ERRORS=");
    uart_put_hex32(tx_errors);
    uart_putc('\n');
    uart_puts("MII RX_FRAME=");
    uart_put_hex32(TSE_MII_RX_FRAME_COUNT[0]);
    uart_puts(" MII RX_ACTIVE_NIBBLES=");
    uart_put_hex32(TSE_MII_RX_ACTIVE_NIBBLE_COUNT[0]);
    uart_puts(" MII RX_ERRORS=");
    uart_put_hex32(rx_errors);
    uart_putc('\n');

    if (tx_frames != 0u)
        bringup_led_set(BRINGUP_LED_MII_TX);
    if ((tx_errors != 0u) || (rx_errors != 0u))
        bringup_led_set(BRINGUP_LED_STICKY_ERROR);
}

static uint32_t bringup_decode_link(uint16_t bmcr, uint16_t bmsr,
                                    uint16_t phy_status)
{
    uint32_t speed_code = ((uint32_t)phy_status >> 14) & 3u;
    uint32_t link_up = (((uint32_t)bmsr & PHY_BMSR_LINK_STATUS) != 0u);

    uart_puts("LINK=");
    if (link_up != 0u) {
        uart_puts("UP");
    } else {
        uart_puts("DOWN");
    }
    bringup_led_assign(BRINGUP_LED_LINK_UP, link_up);

    uart_puts(" SPEED=");
    if (link_up == 0u)
        uart_puts("UNKNOWN");
    else if (speed_code == 2u)
        uart_puts("1000");
    else if (speed_code == 1u)
        uart_puts("100");
    else if (speed_code == 0u)
        uart_puts("10");
    else if (((uint32_t)bmcr & 0x2000u) != 0u)
        uart_puts("100");
    else
        uart_puts("UNKNOWN");

    uart_puts(" DUPLEX=");
    if (link_up == 0u)
        uart_puts("UNKNOWN\n");
    else if (((uint32_t)phy_status & 0x2000u) != 0u)
        uart_puts("FULL\n");
    else if (((uint32_t)bmcr & 0x0100u) != 0u)
        uart_puts("FULL(BMCR)\n");
    else
        uart_puts("HALF\n");

    return link_up;
}

static int bringup_read_phy_snapshot(phy_snapshot_t *snapshot)
{
    if (mdio_read(PHY0_ADDR, PHY_REG_BMCR, &snapshot->bmcr) != 0)
        return 1;
    // BMSR contains latch-low status bits. Keep the first sample as evidence,
    // then use the immediate second sample as the current link indication.
    if (mdio_read(PHY0_ADDR, PHY_REG_BMSR, &snapshot->bmsr_first) != 0)
        return 2;
    if (mdio_read(PHY0_ADDR, PHY_REG_BMSR, &snapshot->bmsr_current) != 0)
        return 3;
    if (mdio_read(PHY0_ADDR, PHY_REG_ID1, &snapshot->id1) != 0)
        return 4;
    if (mdio_read(PHY0_ADDR, PHY_REG_ID2, &snapshot->id2) != 0)
        return 5;
    if (mdio_read(PHY0_ADDR, PHY_REG_ANAR, &snapshot->anar) != 0)
        return 6;
    if (mdio_read(PHY0_ADDR, PHY_REG_ANLPAR, &snapshot->anlpar) != 0)
        return 7;
    if (mdio_read(PHY0_ADDR, PHY_REG_STATUS, &snapshot->status17) != 0)
        return 8;
    return 0;
}

static uint32_t bringup_print_phy_snapshot(const phy_snapshot_t *snapshot)
{
    uart_put_reg("PHY ID1=", snapshot->id1);
    uart_put_reg("PHY ID2=", snapshot->id2);
    uart_put_reg("BMCR=", snapshot->bmcr);
    uart_put_reg("BMSR FIRST=", snapshot->bmsr_first);
    uart_put_reg("BMSR CURRENT=", snapshot->bmsr_current);
    uart_put_reg("ANAR=", snapshot->anar);
    uart_put_reg("ANLPAR=", snapshot->anlpar);
    uart_put_reg("PHY STATUS=", snapshot->status17);
    return bringup_decode_link(snapshot->bmcr, snapshot->bmsr_current,
                               snapshot->status17);
}

#if defined(V25_LWIP_NOSYS) || defined(V26_TCP_ECHO)
uint32_t v25_platform_timer_cycles(void)
{
    return timer_read();
}

uint32_t v25_platform_read_board_switches(void)
{
    return BOARD_SW[0];
}

void v25_platform_uart_puts(const char *text)
{
    uart_puts(text);
}

void v25_platform_uart_hex32(uint32_t value)
{
    uart_put_hex32(value);
}

int v25_platform_read_link(uint32_t *link_up)
{
    phy_snapshot_t snapshot;
    int result = bringup_read_phy_snapshot(&snapshot);

    if (result != 0)
        return result;
    *link_up = ((uint32_t)snapshot.bmsr_current &
                PHY_BMSR_LINK_STATUS) != 0u;
    return 0;
}

void v25_platform_set_link_led(uint32_t link_up)
{
    bringup_led_assign(BRINGUP_LED_LINK_UP, link_up != 0u);
}

void v25_platform_mark_ready(void)
{
    RESULT_BASE[0] = BRINGUP_RESULT_MARKER;
    RESULT_BASE[1] = 0x01410cc2u;
    RESULT_BASE[2] = bringup_led_state;
}

uint32_t v25_platform_stack_used_bytes(void)
{
    volatile uint32_t *cursor = &__stack_limit;
    volatile uint32_t *top = &__stack_top;

    while ((cursor < top) && (*cursor == 0xa5a5a5a5u))
        cursor++;
    return (uint32_t)((uint32_t)top - (uint32_t)cursor);
}

void v25_platform_read_hw_counters(v25_platform_hw_counters_t *counters)
{
    if (counters == (v25_platform_hw_counters_t *)0)
        return;
    counters->ff_tx_frames = TSE_TX_COUNT[0];
    counters->ff_rx_frames = TSE_RX_COUNT[0];
    counters->ff_rx_drops = TSE_RX_DROP_COUNT[0];
    counters->ff_rx_errors = TSE_RX_ERROR_COUNT[0];
    counters->mii_counters_valid = bringup_mii_debug_available;
    if (bringup_mii_debug_available != 0u) {
        counters->mii_tx_frames = TSE_MII_TX_FRAME_COUNT[0];
        counters->mii_tx_active_nibbles =
            TSE_MII_TX_ACTIVE_NIBBLE_COUNT[0];
        counters->mii_tx_errors = TSE_MII_TX_ERROR_NIBBLE_COUNT[0];
        counters->mii_rx_frames = TSE_MII_RX_FRAME_COUNT[0];
        counters->mii_rx_active_nibbles =
            TSE_MII_RX_ACTIVE_NIBBLE_COUNT[0];
        counters->mii_rx_errors = TSE_MII_RX_ERROR_NIBBLE_COUNT[0];
    } else {
        counters->mii_tx_frames = 0u;
        counters->mii_tx_active_nibbles = 0u;
        counters->mii_tx_errors = 0u;
        counters->mii_rx_frames = 0u;
        counters->mii_rx_active_nibbles = 0u;
        counters->mii_rx_errors = 0u;
    }
}

void v25_platform_assert(const char *message, const char *file, int line)
{
    uart_puts("LWIP ASSERT: ");
    uart_puts(message);
    uart_puts(" FILE=");
    uart_puts(file);
    uart_puts(" LINE=");
    uart_put_hex32((uint32_t)line);
    uart_putc('\n');
#ifdef V27_SYNC_IMEM
    fail(0x27a0u);
#elif defined(V26_TCP_ECHO)
    fail(0x26a0u);
#else
    fail(0x25a0u);
#endif
}
#endif

static void bringup_print_periodic_summary(uint32_t link_up,
                                           uint32_t software_submit_count)
{
    uint32_t mii_tx = 0u;
    uint32_t mii_active = 0u;
    uint32_t mii_error = 0u;

    if (bringup_mii_debug_available != 0u) {
        mii_tx = TSE_MII_TX_FRAME_COUNT[0];
        mii_active = TSE_MII_TX_ACTIVE_NIBBLE_COUNT[0];
        mii_error = TSE_MII_TX_ERROR_NIBBLE_COUNT[0];
        if (mii_tx != 0u)
            bringup_led_set(BRINGUP_LED_MII_TX);
        if (mii_error != 0u)
            bringup_led_set(BRINGUP_LED_STICKY_ERROR);
    }

    uart_puts("LINK=");
    uart_puts(link_up ? "UP" : "DOWN");
    uart_puts(" SW_TX=");
    uart_put_hex32(software_submit_count);
    uart_puts(" FF_TX=");
    uart_put_hex32(TSE_TX_COUNT[0]);
    if (bringup_mii_debug_available != 0u) {
        uart_puts(" MII_TX=");
        uart_put_hex32(mii_tx);
        uart_puts(" MII_ACTIVE_NIBBLES=");
        uart_put_hex32(mii_active);
        uart_puts(" MII_ERR=");
        uart_put_hex32(mii_error);
    } else {
        uart_puts(" MII_TX=UNAVAILABLE MII_ERR=UNAVAILABLE");
    }
    uart_puts(" RX=");
    uart_put_hex32(TSE_RX_COUNT[0]);
    uart_putc('\n');
}

static int bringup_submit_raw_frame(uint32_t *software_submit_count)
{
    int rc = tse_send_frame_once(0u);

    if (rc != 0) {
        bringup_led_set(BRINGUP_LED_STICKY_ERROR);
        uart_puts("TX ADAPTER ERROR CODE=");
        uart_put_hex32((uint32_t)(-rc));
        uart_putc('\n');
        return rc;
    }

    *software_submit_count = *software_submit_count + 1u;
    bringup_led_set(BRINGUP_LED_FF_TX);
    uart_puts("RAW TX ETHERTYPE=88B5 SUBMITTED\n");
#if defined(V24_WIRE_FORMAT_FIX) || defined(V23_BOARD_DIAGNOSTICS)
    uart_puts("TX ADAPTER REQUEST ACCEPTED\n");
#endif
    return 0;
}

static void bringup_log_rx_metadata(uint32_t len)
{
    uart_puts("RX LEN=");
    uart_put_hex32(len);
    uart_puts(" ETHERTYPE=");
    if (len >= 14u)
        uart_put_hex16(read_be16(&net_frame[12]));
    else
        uart_puts("----");
    uart_puts(" DST=");
    if (len >= 6u)
        bringup_print_mac(&net_frame[0]);
    else
        uart_puts("--:--:--:--:--:--");
    uart_puts(" SRC=");
    if (len >= 12u)
        bringup_print_mac(&net_frame[6]);
    else
        uart_puts("--:--:--:--:--:--");
    uart_putc('\n');
}

static int board_bringup_main(void)
{
    phy_snapshot_t phy;
    uint32_t link_up;
    uint32_t previous_link_up;
    uint32_t software_submit_count = 0u;
    uint32_t poll_ticks = 0u;
    int mdio_result;

    RESULT_BASE[0] = 0u;
    RESULT_BASE[1] = 0u;
    RESULT_BASE[2] = 0u;
    bringup_led_state = 0u;
    ledr_write(0u);
    bringup_led_set(BRINGUP_LED_ALIVE);

#ifdef V27_SYNC_IMEM
    bringup_led_set(BRINGUP_LED_RUNNING);
#ifdef V31_SGDMA
    uart_puts("RV32I V40 TCP ZERO-COPY ACK LIFETIME\n");
#else
    uart_puts("RV32I V27 SYNC IMEM TCP ECHO AND PERFORMANCE\n");
#endif
#elif defined(V26_TCP_ECHO)
    bringup_led_set(BRINGUP_LED_RUNNING);
    uart_puts("RV32I V26 LWIP TCP ECHO AND PERFORMANCE\n");
#elif defined(V25_LWIP_NOSYS)
    bringup_led_set(BRINGUP_LED_RUNNING);
    uart_puts("RV32I V25 LWIP NO_SYS\n");
#elif defined(V24_WIRE_FORMAT_FIX)
    bringup_led_set(BRINGUP_LED_RUNNING);
    uart_puts("RV32I V24 TSE WIRE FORMAT FIX\n");
#elif defined(V23_BOARD_DIAGNOSTICS)
    bringup_led_set(BRINGUP_LED_RUNNING);
    uart_puts("RV32I V23 MII BOARD DIAGNOSTICS\n");
#else
    uart_puts("V18 BOARD_BRINGUP_TEST\n");
#endif
    uart_puts("CLOCK=CPU_25M RESET=RELEASED\n");

    if (wait_phy_reset_release() != 0)
        fail(0x2301u);

    mdio_result = bringup_read_phy_snapshot(&phy);
    if (mdio_result != 0)
        fail(0x2301u + (uint32_t)mdio_result);
    if (phy.id1 != 0x0141u)
        fail(0x2311u);
    if ((phy.id2 & 0xfff0u) != 0x0cc0u)
        fail(0x2312u);

    bringup_led_set(BRINGUP_LED_MDIO_OK);
    link_up = bringup_print_phy_snapshot(&phy);
    previous_link_up = link_up;

    test_tse_soc_csr();
    uart_puts("TSE WRAPPER ID=");
    uart_put_hex32(TSE_ID[0]);
    uart_puts(" TSE WRAPPER VERSION=");
    uart_put_hex32(TSE_VERSION[0]);
    uart_putc('\n');
    uart_puts("TSE MAC MODE=INTEL GENERATED 10/100 MAC LITE\n");
    test_tse_csr_bridge();
    uart_puts("TSE CSR_STATUS=");
    uart_put_hex32(TSE_CSR_STATUS[0]);
    uart_putc('\n');
    tse_configure_stream_alignment();
    // Must occur before generated-TSE MAC initialization so the raw 0x88b5
    // diagnostic has a well-defined monitor baseline where MII is available.
    bringup_prepare_mii_debug();
    tse_init_mac();
    TSE_STREAM_CTRL[0] = 0x00000003u;
    TSE_RX_CMD[0] = TSE_RX_CMD_CLEAR;

#ifdef V27_SYNC_IMEM
    RESULT_BASE[1] = ((uint32_t)phy.id1 << 16) | phy.id2;
    RESULT_BASE[2] = bringup_led_state;
#ifdef V31_SGDMA
    uart_puts("V40 TCP ZERO-COPY ACK LIFETIME HANDOFF TO LWIP; UDP=1234 TCP=5001\n");
#else
    uart_puts("V27 SYNC IMEM HANDOFF TO LWIP; UDP=1234 TCP=5001\n");
#endif
    return v26_lwip_run(link_up);
#elif defined(V26_TCP_ECHO)
    RESULT_BASE[1] = ((uint32_t)phy.id1 << 16) | phy.id2;
    RESULT_BASE[2] = bringup_led_state;
    uart_puts("V26 HANDOFF TO LWIP; UDP=1234 TCP=5001\n");
    return v26_lwip_run(link_up);
#elif defined(V25_LWIP_NOSYS)
    RESULT_BASE[1] = ((uint32_t)phy.id1 << 16) | phy.id2;
    RESULT_BASE[2] = bringup_led_state;
    uart_puts("V25 HANDOFF TO LWIP; RAW 88B5 PERIODIC TX DISABLED\n");
    return v25_lwip_run(link_up);
#else
    uart_puts("TX EXPECTED DST=FF:FF:FF:FF:FF:FF SRC=02:12:34:56:78:9A ");
    uart_puts("ETHERTYPE=88B5 LEN=00000040\n");
    if (bringup_submit_raw_frame(&software_submit_count) != 0)
        fail(0x2410u);
    delay_ms(1u);
    bringup_print_tse_status();
    bringup_print_mii_status();

    RESULT_BASE[1] = ((uint32_t)phy.id1 << 16) | phy.id2;
    RESULT_BASE[2] = bringup_led_state;
#ifdef V24_WIRE_FORMAT_FIX
    uart_puts("V24 WIRE FORMAT READY: PHYSICAL WIRESHARK TEST PENDING\n");
#elif defined(V23_BOARD_DIAGNOSTICS)
    uart_puts("V23 BOARD DIAGNOSTICS READY: PHYSICAL TEST PENDING\n");
#else
    uart_puts("V18 BRINGUP DIAGNOSTICS READY\n");
#endif
    // Publish the simulation/diagnostic-ready marker only after the complete
    // startup transcript has reached UART MMIO.
    RESULT_BASE[0] = BRINGUP_RESULT_MARKER;

    while (1) {
        if ((TSE_RX_STATUS[0] & TSE_RX_STATUS_READY) != 0u) {
            uint32_t len = net_receive_frame();
            uint32_t reply_len;

            bringup_led_set(BRINGUP_LED_RX);
            bringup_log_rx_metadata(len);
            reply_len = net_dispatch_frame(len);
            if (reply_len != 0u) {
                net_send_frame(reply_len);
                bringup_led_set(BRINGUP_LED_FF_TX);
            }
            bringup_print_tse_status();
        }

        poll_ticks++;
        if (poll_ticks >= BRINGUP_POLL_INTERVAL_MS) {
            mdio_result = bringup_read_phy_snapshot(&phy);
            if (mdio_result != 0) {
                uart_puts("PHY POLL ERROR CODE=");
                uart_put_hex32((uint32_t)mdio_result);
                uart_putc('\n');
                bringup_led_set(BRINGUP_LED_STICKY_ERROR);
            } else {
                link_up = ((uint32_t)phy.bmsr_current &
                           PHY_BMSR_LINK_STATUS) != 0u;
                if (link_up != previous_link_up) {
                    uart_puts("LINK CHANGE=");
                    uart_puts(previous_link_up ? "UP->DOWN\n" : "DOWN->UP\n");
                    previous_link_up = link_up;
                }
                bringup_led_assign(BRINGUP_LED_LINK_UP, link_up);
            }

            if (bringup_submit_raw_frame(&software_submit_count) != 0)
                bringup_led_set(BRINGUP_LED_STICKY_ERROR);
            delay_ms(1u);
            bringup_print_periodic_summary(link_up, software_submit_count);
            poll_ticks = 0u;
        }
        delay_ms(1u);
    }
#endif
}

#endif

int main(void)
{
#ifdef NET_SIM_TEST
    return net_sim_main();
#elif defined(BOARD_BRINGUP_TEST)
    return board_bringup_main();
#else
    uint16_t reg1;
    uint16_t reg2;
    uint16_t reg3;
    uint16_t reg17;
    int mdio_ok;
    uint32_t link_up;

    RESULT_BASE[0] = 0u;
    RESULT_BASE[1] = 0u;
    RESULT_BASE[2] = 0u;

    ledr_write(0x00001u);
    ledg_write(0x000u);

    uart_puts(banner);
    uart_puts("UART OK\n");

    ram_test();
    stack_test();
    timer_test();
    led_blink_test();

    if (wait_phy_reset_release() != 0)
        fail(0x0040u);

    mdio_ok = mdio_read(PHY0_ADDR, 2u, &reg2);
    if (mdio_ok != 0)
        fail(0x0042u);
    uart_put_reg("MDIO REG2=", reg2);

    mdio_ok = mdio_read(PHY0_ADDR, 3u, &reg3);
    if (mdio_ok != 0)
        fail(0x0043u);
    uart_put_reg("MDIO REG3=", reg3);

    mdio_ok = mdio_read(PHY0_ADDR, 1u, &reg1);
    if (mdio_ok != 0)
        fail(0x0041u);
    uart_put_reg("MDIO REG1=", reg1);

    mdio_ok = mdio_read(PHY0_ADDR, 17u, &reg17);
    if (mdio_ok != 0)
        fail(0x0051u);
    uart_put_reg("MDIO REG17=", reg17);

    if (reg2 != 0x0141u)
        fail(0x0141u);

    if ((reg3 & 0xfff0u) != 0x0cc0u)
        fail(0x0cc0u);

    uart_puts("PHY ID OK\n");

    link_up = ((uint32_t)reg1 & 0x0004u);
    if (link_up != 0u) {
        uart_puts("LINK UP\n");
    } else {
        uart_puts("LINK DOWN\n");
    }

    test_tse_soc_csr();
    test_tse_csr_bridge();
    tse_init_mac();
    test_tse_txrx_mmio();

    ledr_write(0x00000u);
    RESULT_BASE[0] = 0xC001CAFEu;
    RESULT_BASE[1] = 0x54534515u;
    RESULT_BASE[2] = TSE_VERSION_VALUE;

    uart_puts("RV32I V15 TSE MII TX LOOP\n");
    uart_puts("BOARDPREP PASS\n");

    while (1) {
        uint32_t count;
        if (tse_send_frame_once(0u) != 0)
            fail(0x1501u);

        count = TSE_TX_COUNT[0];
        ledg_write(0x080u | ((count & 1u) ? 0x040u : 0u));
        uart_puts("TX COUNT=");
        uart_put_hex32(count);
        uart_putc('\n');
        delay_ms(250u);
    }

    return 0;
#endif
}
