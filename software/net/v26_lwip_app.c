#include "lwip/init.h"
#include "lwip/ip4_addr.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/sys.h"
#include "lwip/timeouts.h"
#include "netif/ethernet.h"
#include "net/ethernetif.h"
#include "net/tcp_echo.h"
#include "net/udp_echo.h"
#include "net/v25_platform.h"
#include "port/v25_time.h"
#ifdef V31_SGDMA
#include "port/v28_profile.h"
void v28_io_report(void);
#endif

#define LINK_POLL_MS 250u
#define REPORT_MS 1000u
#define PATH_REPORT_MS 10000u
#define UART_PERF_QUIET_SW_MASK (1u << 2)
#define V40_TCP_RX_SINK_SW_MASK (1u << 6)
#define V31_UDP_TEST_SW_SHIFT 3u
#define V31_UDP_TEST_SW_MASK  3u

static struct netif v26_netif;

static int pbuf_pool_self_test(void)
{
    struct pbuf *held[PBUF_POOL_SIZE];
    struct pbuf *extra;
    struct pbuf *chain;
    uint32_t i;
    int result = 1;

    for (i = 0u; i < PBUF_POOL_SIZE; i++) {
        held[i] = pbuf_alloc(PBUF_RAW, 1u, PBUF_POOL);
        if (held[i] == NULL) {
            result = 0;
            break;
        }
    }

    extra = pbuf_alloc(PBUF_RAW, 1u, PBUF_POOL);
    if (extra != NULL) {
        result = 0;
        pbuf_free(extra);
    }

    while (i != 0u) {
        i--;
        pbuf_free(held[i]);
    }

    chain = pbuf_alloc(PBUF_RAW, (u16_t)(1514u + ETH_PAD_SIZE), PBUF_POOL);
    if ((chain == NULL) || (chain->next != NULL) ||
        (chain->len != (u16_t)(1514u + ETH_PAD_SIZE)))
        result = 0;
    if (chain != NULL)
        pbuf_free(chain);

    return result;
}

static void print_counter(const char *name, uint32_t value)
{
    v25_platform_uart_puts(name);
    v25_platform_uart_hex32(value);
}

static void print_status(uint32_t link_up)
{
    const v25_ethernetif_stats_t *driver = v25_ethernetif_stats();
    const v26_tcp_echo_stats_t *tcp = v26_tcp_echo_stats();

    v25_platform_uart_puts("LWIP LINK=");
    v25_platform_uart_puts(link_up != 0u ? "UP" : "DOWN");
    print_counter(" RX=", driver->rx_frames);
    print_counter(" TX=", driver->tx_frames);
    print_counter(" RX_DROP=", driver->rx_drops);
    print_counter(" RX_ERR=", driver->rx_errors + driver->input_errors);
    print_counter(" TX_ERR=", driver->tx_errors + driver->tx_timeouts);
    print_counter(" UDP_RX=", v31_udp_rx_packets());
    print_counter(" UDP_ECHO=", v25_udp_echo_requests());
    print_counter(" UDP_SINK=", v31_udp_sink_packets());
    print_counter(" UDP_TX_GEN=", v31_udp_tx_generated_packets());
    print_counter(" UDP_ERR=", v25_udp_echo_errors());
    print_counter(" TCP_ACCEPT=", tcp->accept_count);
    print_counter(" TCP_RX=", tcp->rx_bytes);
    print_counter(" TCP_TX=", tcp->tx_bytes);
    print_counter(" TCP_ERR=", tcp->error_count + tcp->abort_count);
    print_counter(" STACK_USED=", v25_platform_stack_used_bytes());
    v25_platform_uart_puts("\n");
}

static void print_path_counters(void)
{
    const v25_ethernetif_stats_t *driver = v25_ethernetif_stats();
    const v26_tcp_echo_stats_t *tcp = v26_tcp_echo_stats();
    const v40_tcp_zc_stats_t *zc = v40_tcp_echo_zero_copy_stats();
    const v40_tx_pool_stats_t *tx_pool = v40_udp_tx_pool_stats();
    v25_platform_hw_counters_t hardware;

    v25_platform_read_hw_counters(&hardware);
    v25_platform_uart_puts("PATH_RX");
    print_counter(" MII=", hardware.mii_rx_frames);
    print_counter(" MII_NIBBLES=", hardware.mii_rx_active_nibbles);
    print_counter(" FF=", hardware.ff_rx_frames);
    print_counter(" DEQUEUE=", driver->rx_dequeues);
    print_counter(" NETIF_OK=", driver->input_ok);
    print_counter(" NETIF_ERR=", driver->input_errors);
    print_counter(" PBUF_FAIL=", driver->pbuf_alloc_failures);
    print_counter(" FF_DROP=", hardware.ff_rx_drops);
    print_counter(" FF_ERR=", hardware.ff_rx_errors);
    print_counter(" MII_ERR=", hardware.mii_rx_errors);
    v25_platform_uart_puts(hardware.mii_counters_valid != 0u ? "\n" :
                           " MII_COUNTERS=UNAVAILABLE\n");

    v25_platform_uart_puts("PATH_TX");
    print_counter(" LINKOUT=", driver->linkoutput_calls);
    print_counter(" BUSY_ENTRY=", driver->linkoutput_busy);
    print_counter(" LINK_TIMEOUT=", driver->tx_timeouts);
    print_counter(" FF=", hardware.ff_tx_frames);
    print_counter(" MII=", hardware.mii_tx_frames);
    print_counter(" MII_NIBBLES=", hardware.mii_tx_active_nibbles);
    print_counter(" MII_ERR=", hardware.mii_tx_errors);
    print_counter(" UDP_RX_BYTES=", v25_udp_echo_rx_bytes());
    print_counter(" UDP_TX_BYTES=", v25_udp_echo_tx_bytes());
    print_counter(" UDP_TX_RETRY=", v31_udp_tx_retry_count());
    print_counter(" UDP_CTRL=", v31_udp_control_packets());
    print_counter(" UDP_ERR=", v25_udp_echo_errors());
    print_counter(" TCP_CALLBACK=", tcp->recv_callback_count);
    print_counter(" TCP_WRITE=", tcp->echo_write_count);
    print_counter(" TCP_ERR_MEM=", tcp->write_err_mem_count);
    print_counter(" TCP_CLOSE=", tcp->close_count);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TCP_ECHO");
    print_counter(" CALLBACK=", tcp->recv_callback_count);
    print_counter(" PBUF_NODE=", tcp->echo_pbuf_nodes);
    print_counter(" SINGLE=", tcp->echo_single_pbuf_callbacks);
    print_counter(" MULTI=", tcp->echo_multi_pbuf_callbacks);
    print_counter(" MAX_NODE=", tcp->echo_max_pbuf_nodes);
    print_counter(" WRITE=", tcp->echo_write_count);
    print_counter(" COPY_BYTES=", tcp->echo_copy_bytes);
    print_counter(" OUTPUT=", tcp->echo_output_calls);
    print_counter(" ERR_MEM=", tcp->write_err_mem_count);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TCP_ZEROCOPY");
    print_counter(" CALLBACKS=", zc->zero_copy_callbacks);
    print_counter(" BYTES=", zc->zero_copy_bytes);
    print_counter(" NODES=", zc->zero_copy_nodes);
    print_counter(" COPY_FALLBACK=", tcp->echo_copy_fallback_calls);
    print_counter(" COPY_BYTES=", tcp->echo_copy_bytes);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TCP_ACK_LIFETIME");
    print_counter(" ACK_CALLBACKS=", zc->ack_callbacks);
    print_counter(" PARTIAL_ACK=", zc->partial_ack_events);
    print_counter(" CUMULATIVE_ACK=", zc->cumulative_ack_events);
    print_counter(" ACKED_BYTES=", zc->acked_bytes);
    print_counter(" RETRY=", zc->retry_count);
    print_counter(" CLOSE_WAIT=", zc->close_wait_count);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TCP_OWNER");
    print_counter(" CURRENT=", zc->owner_current);
    print_counter(" MAX=", zc->owner_max);
    print_counter(" EXHAUSTED=", zc->owner_exhausted);
    print_counter(" RELEASED=", zc->owner_released);
    print_counter(" ACKQ_CURRENT=", zc->ack_queue_current);
    print_counter(" ACKQ_MAX=", zc->ack_queue_max);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TCP_OWNER_SAFETY");
    print_counter(" FREE_BEFORE_ACK=", zc->free_before_ack_violations);
    print_counter(" PAYLOAD_STABILITY=", zc->payload_stability_violations);
    print_counter(" CONSISTENCY=", zc->consistency_errors);
    print_counter(" ABORT_RECOVERY=", zc->abort_recovery_count);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TCP_SOURCE");
    print_counter(" CHUNKS=", tcp->source_generated_chunks);
    print_counter(" BYTES=", tcp->source_generated_bytes);
    print_counter(" ACKED=", tcp->source_acked_bytes);
    print_counter(" CTRL=", tcp->source_control_count);
    print_counter(" OUTPUT=", tcp->source_output_calls);
    print_counter(" RETRY=", tcp->source_retry_count);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TX_POOL");
    print_counter(" INIT_OK=", tx_pool->init_ok);
    print_counter(" INIT_FAIL=", tx_pool->init_fail);
    print_counter(" FREE=", tx_pool->free_current);
    print_counter(" READY=", tx_pool->ready_current);
    print_counter(" INFLIGHT=", tx_pool->inflight_current);
    print_counter(" MIN_FREE=", tx_pool->min_free);
    print_counter(" MAX_READY=", tx_pool->max_ready);
    print_counter(" MAX_INFLIGHT=", tx_pool->max_inflight);
    print_counter(" REUSE=", tx_pool->reuse_count);
    print_counter(" NO_FREE=", tx_pool->no_free_events);
    print_counter(" STATE_ERR=", tx_pool->state_errors);
    print_counter(" GEN_ERR=", tx_pool->generation_errors);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TX_PRODUCER");
    print_counter(" CALLS=", tx_pool->producer_calls);
    print_counter(" FRAMES=", tx_pool->producer_frames);
    print_counter(" BYTES=", tx_pool->producer_bytes);
    print_counter(" TICKS_HI=", tx_pool->producer_ticks_hi);
    print_counter(" TICKS_LO=", tx_pool->producer_ticks_lo);
    print_counter(" MAX_BATCH=", tx_pool->producer_max_batch);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TX_SUBMIT");
    print_counter(" CALLS=", tx_pool->submit_calls);
    print_counter(" FRAMES=", tx_pool->submit_frames);
    print_counter(" RETRY=", tx_pool->submit_retry);
    print_counter(" ERR_MEM=", tx_pool->submit_err_mem);
    print_counter(" OTHER_ERR=", tx_pool->submit_other_error);
    print_counter(" MAX_BATCH=", tx_pool->submit_max_batch);
    print_counter(" PARTIAL_FLUSH=", tx_pool->partial_flush);
    print_counter(" UDP_DONE=", tx_pool->udp_complete);
    print_counter(" UDP_ERR=", tx_pool->udp_error);
    print_counter(" STALE=", tx_pool->udp_stale_complete);
    v25_platform_uart_puts("\n");

    v25_platform_uart_puts("TX_TCP_POOL");
    print_counter(" SUB_BYTES=", tx_pool->tcp_submitted_bytes);
    print_counter(" ACK_BYTES=", tx_pool->tcp_acked_bytes);
    print_counter(" UNACKED=", tx_pool->tcp_unacked_bytes);
    print_counter(" MAX_UNACKED=", tx_pool->tcp_max_unacked);
    print_counter(" ACK_CB=", tx_pool->tcp_ack_callbacks);
    print_counter(" ERR_MEM=", tx_pool->tcp_err_mem);
    print_counter(" RETRY=", tx_pool->tcp_retry);
    print_counter(" ABORT_RECOVER=", tx_pool->tcp_abort_recovery);
    v25_platform_uart_puts("\n");
}

#ifdef V31_SGDMA
static void print_runtime_snapshot(uint32_t link_up)
{
    print_status(link_up);
    print_path_counters();
    v28_io_report();
}
#endif

int v26_lwip_run(uint32_t initial_link_up)
{
    ip4_addr_t ip;
    ip4_addr_t mask;
    ip4_addr_t gateway;
    uint32_t link_up = initial_link_up != 0u;
    uint32_t last_link_poll;
    uint32_t last_report;
    uint32_t last_path_report;
#ifdef V31_SGDMA
    uint32_t uart_perf_quiet;
    uint32_t udp_test_mode;
    uint32_t tcp_rx_sink_mode;
    uint32_t board_switches;
#endif

    v25_platform_uart_puts("LWIP VERSION=2.2.1 NO_SYS=1 TCP RAW API\n");
    if (v25_time_wrap_self_test() == 0) {
        v25_platform_uart_puts("LWIP TIMER WRAP SELF-TEST FAIL\n");
        return -1;
    }
    v25_platform_uart_puts("LWIP TIMER WRAP SELF-TEST PASS\n");

    lwip_init();
    if (pbuf_pool_self_test() == 0) {
        v25_platform_uart_puts("LWIP PBUF POOL SELF-TEST FAIL\n");
        return -4;
    }
    v25_platform_uart_puts("V40 PBUF POOL EXHAUST/RECOVERY SELF-TEST PASS\n");
    v25_platform_uart_puts("V40 RX SINGLE-PBUF SELF-TEST PASS\n");
    if (v40_tcp_zc_self_test() == 0) {
        v25_platform_uart_puts("V40 TCP ZERO-COPY ACK LIFETIME SELF-TEST FAIL\n");
        return -6;
    }
    v25_platform_uart_puts(
        "V40 TCP ZERO-COPY ACK LIFETIME SELF-TEST PASS\n");

    IP4_ADDR(&ip, 192, 168, 1, 50);
    IP4_ADDR(&mask, 255, 255, 255, 0);
    IP4_ADDR(&gateway, 0, 0, 0, 0);
    if (netif_add(&v26_netif, &ip, &mask, &gateway, NULL,
                  v25_ethernetif_init, ethernet_input) == NULL) {
        v25_platform_uart_puts("LWIP NETIF ADD FAIL\n");
        return -2;
    }
    netif_set_default(&v26_netif);
    netif_set_up(&v26_netif);
    if (link_up != 0u)
        netif_set_link_up(&v26_netif);
    else
        netif_set_link_down(&v26_netif);
    v25_platform_set_link_led(link_up);

#ifdef V31_SGDMA
    board_switches = v25_platform_read_board_switches();
    udp_test_mode = (board_switches >>
                     V31_UDP_TEST_SW_SHIFT) & V31_UDP_TEST_SW_MASK;
    if (udp_test_mode > V40_TCP_TEST_TX_SOURCE) {
        v25_platform_uart_puts(
            "V40 TEST_MODE RESERVED SW4:SW3=11; FALLBACK=ECHO\n");
        udp_test_mode = V31_UDP_TEST_ECHO;
    }
    tcp_rx_sink_mode =
        ((board_switches & V40_TCP_RX_SINK_SW_MASK) != 0u) &&
        (udp_test_mode == V31_UDP_TEST_ECHO);
    v31_udp_test_select(udp_test_mode);
    v40_tcp_test_select(udp_test_mode == V40_TCP_TEST_TX_SOURCE,
                        tcp_rx_sink_mode);
#else
    v31_udp_test_select(V31_UDP_TEST_ECHO);
    v40_tcp_test_select(0u, 0u);
#endif
    if (v25_udp_echo_start() != ERR_OK) {
        v25_platform_uart_puts("LWIP UDP 1234 BIND FAIL\n");
        return -3;
    }
    if (v26_tcp_echo_start() != ERR_OK) {
        v25_platform_uart_puts("LWIP TCP 5001 LISTEN FAIL\n");
        return -5;
    }

    v25_platform_uart_puts("LWIP NETIF READY IP=192.168.1.50/24 ");
    v25_platform_uart_puts("MAC=02:12:34:56:78:9A UDP=1234 TCP=5001\n");
#ifdef V31_SGDMA
    v25_platform_uart_puts("V40 PIO/SGDMA NETWORK REGRESSION READY\n");
    if (tcp_rx_sink_mode != 0u)
        v25_platform_uart_puts(
            "V40 TEST_MODE=TCP_RX_ONLY_SINK SW6=1 SW4:SW3=00 PORT=5001\n");
    else if (udp_test_mode == V31_UDP_TEST_RX_SINK)
        v25_platform_uart_puts(
            "V40 TEST_MODE=UDP_RX_ONLY_SINK SW4:SW3=01 PORT=1234\n");
    else if (udp_test_mode == V31_UDP_TEST_TX_SOURCE)
        v25_platform_uart_puts(
            "V40 TEST_MODE=UDP_TX_ONLY_SOURCE SW4:SW3=10 CTRL=V40TXGO/V40TXSTOP PAYLOAD=1472 REALTIME_POOL=8\n");
    else if (udp_test_mode == V40_TCP_TEST_TX_SOURCE)
        v25_platform_uart_puts(
            "V40 TEST_MODE=TCP_TX_ONLY_SOURCE SW4:SW3=11 CTRL=V40TCPGO/V40TCPSTOP CHUNK=1460 REALTIME_POOL=8\n");
    else
        v25_platform_uart_puts(
            "V40 TEST_MODE=UDP_ECHO SW4:SW3=00 PORT=1234\n");
    v25_platform_uart_puts(
        "V40 UART PERF QUIET: SW2 0=PERIODIC 1=QUIET; TOGGLE FOR BASELINE/FINAL\n");
#elif defined(V27_SYNC_IMEM)
    v25_platform_uart_puts("V27 SYNC IMEM PHYSICAL BOARD RETEST PENDING\n");
#else
    v25_platform_uart_puts("V26 TCP PHYSICAL BOARD TEST PENDING\n");
#endif
    v25_platform_mark_ready();
    last_link_poll = sys_now();
    last_report = last_link_poll;
    last_path_report = last_link_poll;
#ifdef V31_SGDMA
    uart_perf_quiet =
        (v25_platform_read_board_switches() & UART_PERF_QUIET_SW_MASK) != 0u;
    if (uart_perf_quiet != 0u) {
        v25_platform_uart_puts("UART PERF QUIET INITIAL BASELINE BEGIN\n");
        print_runtime_snapshot(link_up);
        v25_platform_uart_puts("UART PERF QUIET=ACTIVE; START TRAFFIC NOW\n");
    } else {
        v25_platform_uart_puts("UART PERF QUIET=OFF; SET SW2=1 BEFORE TRAFFIC\n");
    }
#endif

    while (1) {
        uint32_t now;
        v25_ethernetif_poll(&v26_netif);
#ifdef V31_SGDMA
        {
            uint64_t tx_before = v28_tx_inclusive_ticks;
            uint32_t start = v28_profile_begin(), elapsed, nested;
            sys_check_timeouts();
            elapsed = v28_profile_elapsed(start);
            nested = (uint32_t)(v28_tx_inclusive_ticks - tx_before);
            v28_profile_add(PROF_STACK_EXCL, elapsed >= nested ? elapsed-nested : 0u);
        }
        /* sys_check_timeouts() may enqueue frames through linkoutput. */
        v34_ethernetif_service(&v26_netif);
#else
        sys_check_timeouts();
#endif
        now = sys_now();

#ifdef V31_SGDMA
        {
            uint32_t requested_quiet =
                (v25_platform_read_board_switches() &
                 UART_PERF_QUIET_SW_MASK) != 0u;

            if (requested_quiet != uart_perf_quiet) {
                if (requested_quiet != 0u) {
                    v25_platform_uart_puts(
                        "UART PERF QUIET BASELINE BEGIN\n");
                    print_runtime_snapshot(link_up);
                    v25_platform_uart_puts(
                        "UART PERF QUIET=ACTIVE; START TRAFFIC NOW\n");
                } else {
                    v25_platform_uart_puts(
                        "UART PERF QUIET FINAL SNAPSHOT BEGIN\n");
                    print_runtime_snapshot(link_up);
                    v25_platform_uart_puts(
                        "UART PERF QUIET=OFF; PERIODIC REPORTS RESUMED\n");
                }
                uart_perf_quiet = requested_quiet;
                last_report = now;
                last_path_report = now;
            }
        }
#endif

        if ((uint32_t)(now - last_link_poll) >= LINK_POLL_MS) {
            uint32_t current_link = link_up;
            if (v25_platform_read_link(&current_link) == 0) {
                current_link = current_link != 0u;
                if (current_link != link_up) {
                    link_up = current_link;
                    if (link_up != 0u)
                        netif_set_link_up(&v26_netif);
                    else {
                        v40_tcp_link_down();
                        netif_set_link_down(&v26_netif);
                    }
                    v25_platform_set_link_led(link_up);
#ifdef V31_SGDMA
                    if (uart_perf_quiet == 0u)
#endif
                        v25_platform_uart_puts(link_up != 0u ?
                                               "LWIP LINK CHANGE=UP\n" :
                                               "LWIP LINK CHANGE=DOWN\n");
                }
            }
            last_link_poll = now;
        }

#ifdef V31_SGDMA
        if ((uart_perf_quiet == 0u) &&
            ((uint32_t)(now - last_report) >= REPORT_MS)) {
#else
        if ((uint32_t)(now - last_report) >= REPORT_MS) {
#endif
            print_status(link_up);
            last_report = now;
        }
#ifdef V31_SGDMA
        if ((uart_perf_quiet == 0u) &&
            ((uint32_t)(now - last_path_report) >= PATH_REPORT_MS)) {
#else
        if ((uint32_t)(now - last_path_report) >= PATH_REPORT_MS) {
#endif
            print_path_counters();
#ifdef V31_SGDMA
            v28_io_report();
#endif
            last_path_report = now;
        }
#ifdef V31_SGDMA
        v34_ethernetif_service(&v26_netif);
        v31_udp_tx_generator_service(link_up);
        v40_tcp_tx_generator_service(link_up);
#endif
    }
}
