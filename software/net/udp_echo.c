#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "net/udp_echo.h"
#include "net/tx_buffer_pool.h"

static struct udp_pcb *echo_pcb;
static ip_addr_t tx_destination;
static u16_t tx_destination_port;
static uint32_t test_mode;
static uint32_t tx_generator_enabled;
static uint32_t tx_sequence;
static uint32_t rx_packet_count;
static uint32_t echo_count;
static uint32_t sink_count;
volatile uint32_t v40_sink_completed;
static uint32_t tx_generated_count;
static uint32_t tx_retry_count;
static uint32_t control_count;
static uint32_t error_count;
static uint32_t rx_byte_count;
static uint32_t tx_byte_count;

static int payload_is_command(const struct pbuf *p, const char *command,
                              uint32_t length)
{
    uint8_t bytes[9];
    uint32_t i;

    if ((uint32_t)p->tot_len != length || length > sizeof(bytes) ||
        pbuf_copy_partial(p, bytes, (u16_t)length, 0u) != length)
        return 0;
    for (i = 0u; i < length; i++) {
        if (bytes[i] != (uint8_t)command[i])
            return 0;
    }
    return 1;
}

static void echo_receive(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                         const ip_addr_t *address, u16_t port)
{
    err_t result;
    LWIP_UNUSED_ARG(arg);

    if (p == NULL)
        return;

    rx_packet_count++;
    rx_byte_count += p->tot_len;
    if (test_mode == V31_UDP_TEST_ECHO) {
        echo_count++;
        result = udp_sendto(pcb, p, address, port);
        if (result != ERR_OK)
            error_count++;
        else
            tx_byte_count += p->tot_len;
    } else if (test_mode == V31_UDP_TEST_RX_SINK) {
        sink_count++;
    } else if (test_mode == V31_UDP_TEST_TX_SOURCE) {
        if (payload_is_command(p, "V40TXGO", 7u)) {
            ip_addr_set(&tx_destination, address);
            tx_destination_port = port;
            tx_sequence = 0u;
            tx_generator_enabled = 1u;
            control_count++;
        } else if (payload_is_command(p, "V40TXSTOP", 9u)) {
            tx_generator_enabled = 0u;
            control_count++;
        }
    }
    pbuf_free(p);
    if (test_mode == V31_UDP_TEST_RX_SINK) v40_sink_completed++;
}

void v31_udp_test_select(uint32_t mode)
{
    test_mode = mode <= V40_TCP_TEST_TX_SOURCE ? mode : V31_UDP_TEST_ECHO;
}

uint32_t v31_udp_test_mode(void)
{
    return test_mode;
}

err_t v25_udp_echo_start(void)
{
    err_t result;

    if (v40_tx_pool_init() != 0)
        return ERR_MEM;
    echo_pcb = udp_new_ip_type(IPADDR_TYPE_V4);
    if (echo_pcb == NULL)
        return ERR_MEM;
    result = udp_bind(echo_pcb, IP_ANY_TYPE, 1234u);
    if (result != ERR_OK) {
        udp_remove(echo_pcb);
        echo_pcb = NULL;
        return result;
    }
    udp_recv(echo_pcb, echo_receive, NULL);

    return ERR_OK;
}

void v31_udp_tx_generator_service(uint32_t link_up)
{
    struct pbuf *frames[V40_TX_PRODUCE_BUDGET];
    uint32_t i;
    uint32_t prepared = 0u;
    uint32_t attempted = 0u;
    uint32_t remaining_start = 0u;

    if (test_mode != V31_UDP_TEST_TX_SOURCE ||
        tx_generator_enabled == 0u || link_up == 0u ||
        echo_pcb == NULL)
        return;

    /* Producer phase: generate a real, distinct payload in every FREE slot.
       No packet data is prefilled before V40TXGO. */
    for (prepared = 0u; prepared < V40_TX_PRODUCE_BUDGET; prepared++) {
        frames[prepared] = v40_tx_pool_prepare_udp(
            tx_sequence + prepared, V31_UDP_TX_PAYLOAD_BYTES);
        if (frames[prepared] == (struct pbuf *)0)
            break;
    }
    v40_tx_pool_note_producer_call(prepared);
    remaining_start = prepared;

    /* Submitter phase: enqueue every READY slot without waiting for DMA. */
    for (i = 0u; i < prepared; i++) {
        uint32_t sequence = tx_sequence;
        err_t result;

        if (v40_tx_pool_mark_udp_inflight(frames[i]) != 0) {
            error_count++;
            pbuf_free(frames[i]);
            remaining_start = i + 1u;
            break;
        }
        result = udp_sendto(echo_pcb, frames[i], &tx_destination,
                            tx_destination_port);
        v40_tx_pool_set_udp_result(frames[i], result == ERR_OK);
        attempted++;
        v40_tx_pool_note_submit_result(result);
        if (result == ERR_OK) {
            tx_sequence = sequence + 1u;
            tx_generated_count++;
            tx_byte_count += V31_UDP_TX_PAYLOAD_BYTES;
        } else if (result == ERR_MEM) {
            tx_retry_count++;
        } else {
            error_count++;
        }
        /* SGDMA linkoutput owns another reference after ERR_OK. Its LAST
           completion releases that reference and invokes udp_custom_free. */
        pbuf_free(frames[i]);
        if (result != ERR_OK) {
            remaining_start = i + 1u;
            break;
        }
    }
    /* Any READY slots after a failed submission were never handed to lwIP. */
    for (i = remaining_start; i < prepared; i++)
        pbuf_free(frames[i]);
    v40_tx_pool_note_submit_batch(attempted);
}

uint32_t v25_udp_echo_requests(void)
{
    return echo_count;
}

uint32_t v25_udp_echo_errors(void)
{
    return error_count;
}

uint32_t v25_udp_echo_rx_bytes(void)
{
    return rx_byte_count;
}

uint32_t v25_udp_echo_tx_bytes(void)
{
    return tx_byte_count;
}

uint32_t v31_udp_rx_packets(void)
{
    return rx_packet_count;
}

uint32_t v31_udp_sink_packets(void)
{
    return sink_count;
}

uint32_t v31_udp_tx_generated_packets(void)
{
    return tx_generated_count;
}

uint32_t v31_udp_tx_retry_count(void)
{
    return tx_retry_count;
}

uint32_t v31_udp_control_packets(void)
{
    return control_count;
}

const v40_tx_pool_stats_t *v40_udp_tx_pool_stats(void)
{
    return v40_tx_pool_stats();
}
