#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/tcp.h"
#include "net/tcp_echo.h"
#include "net/tcp_zero_copy_lifetime.h"
#include "net/tx_buffer_pool.h"

#define V26_TCP_ECHO_PORT 5001u
#define V26_TCP_POLL_INTERVAL 2u
#define V40_TCP_TX_CHUNK_BYTES 1460u

typedef enum {
    V26_TCP_IDLE = 0,
    V26_TCP_ACTIVE,
    V26_TCP_CLOSING
} v26_tcp_state_t;

typedef struct {
    struct tcp_pcb *pcb;
    v26_tcp_state_t state;
} v26_tcp_connection_t;

static struct tcp_pcb *listen_pcb;
static v26_tcp_connection_t connection;
static v26_tcp_echo_stats_t stats;
static v40_tcp_zc_manager_t echo_zero_copy;
static uint32_t source_test_mode;
static uint32_t sink_test_mode;
static uint32_t source_enabled;
static uint32_t source_sequence;
static void *source_ready[V40_TX_POOL_SIZE];
static uint32_t source_ready_read;
static uint32_t source_ready_write;
static uint32_t source_ready_count;

static err_t tcp_echo_recv(void *arg, struct tcp_pcb *pcb,
                           struct pbuf *p, err_t error);
static err_t tcp_echo_sent(void *arg, struct tcp_pcb *pcb, u16_t length);
static err_t tcp_echo_poll(void *arg, struct tcp_pcb *pcb);
static void tcp_echo_error(void *arg, err_t error);

static uint32_t pbuf_node_count(const struct pbuf *p)
{
    uint32_t count = 0u;
    while (p != NULL) {
        count++;
        p = p->next;
    }
    return count;
}

static void note_echo_pbuf_shape(const struct pbuf *p)
{
    uint32_t nodes = pbuf_node_count(p);
    stats.echo_pbuf_nodes += nodes;
    if (nodes == 1u)
        stats.echo_single_pbuf_callbacks++;
    else
        stats.echo_multi_pbuf_callbacks++;
    if (nodes > stats.echo_max_pbuf_nodes)
        stats.echo_max_pbuf_nodes = nodes;
}

static void release_echo_pbuf(struct pbuf *p, void *arg)
{
    LWIP_UNUSED_ARG(arg);
    if (p != NULL)
        pbuf_free(p);
}

static void release_source_ready(void)
{
    while (source_ready_count != 0u) {
        void *payload = source_ready[source_ready_read];
        source_ready[source_ready_read] = NULL;
        source_ready_read = (source_ready_read + 1u) % V40_TX_POOL_SIZE;
        source_ready_count--;
        v40_tx_pool_cancel_ready(payload);
    }
    source_ready_read = 0u;
    source_ready_write = 0u;
}

static int tcp_payload_is_command(const struct pbuf *p, const char *command,
                                  uint32_t length)
{
    uint8_t bytes[10];
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

static void reset_connection(void)
{
    (void)v40_tcp_zc_abort(&echo_zero_copy);
    release_source_ready();
    v40_tx_pool_tcp_abort_all();
    source_enabled = 0u;
    connection.pcb = NULL;
    connection.state = V26_TCP_IDLE;
}

static err_t abort_connection(struct tcp_pcb *pcb)
{
    source_enabled = 0u;
    stats.abort_count++;
    /* tcp_abort first releases lwIP's PBUF_ROM wrappers.  Its error callback
       then releases the application-owned RX pbufs retained below them. */
    tcp_abort(pcb);
    return ERR_ABRT;
}

static void install_callbacks(struct tcp_pcb *pcb)
{
    tcp_arg(pcb, &connection);
    tcp_recv(pcb, tcp_echo_recv);
    tcp_sent(pcb, tcp_echo_sent);
    tcp_err(pcb, tcp_echo_error);
    tcp_poll(pcb, tcp_echo_poll, V26_TCP_POLL_INTERVAL);
}

static err_t close_connection(struct tcp_pcb *pcb)
{
    err_t result;

    if (v40_tcp_zc_owner_count(&echo_zero_copy) != 0u ||
        v40_tcp_zc_ack_count(&echo_zero_copy) != 0u ||
        source_ready_count != 0u || v40_tx_pool_tcp_unacked() != 0u) {
        v40_tcp_zc_note_close_wait(&echo_zero_copy);
        return ERR_INPROGRESS;
    }

    tcp_arg(pcb, NULL);
    tcp_recv(pcb, NULL);
    tcp_sent(pcb, NULL);
    tcp_err(pcb, NULL);
    tcp_poll(pcb, NULL, 0u);
    result = tcp_close(pcb);
    if (result == ERR_OK) {
        connection.pcb = NULL;
        connection.state = V26_TCP_IDLE;
        stats.close_count++;
    } else {
        install_callbacks(pcb);
        if (result == ERR_MEM)
            stats.write_err_mem_count++;
        else
            stats.error_count++;
    }
    return result;
}

static err_t send_pending(struct tcp_pcb *pcb)
{
    int queued_data = 0;
    v40_tcp_zc_span_t span;
    int available;

    while ((available = v40_tcp_zc_peek_submit(&echo_zero_copy, &span)) > 0 &&
           span.length <= tcp_sndbuf(pcb)) {
        err_t result = tcp_write(pcb, span.payload, span.length, 0u);

        if (result == ERR_MEM) {
            stats.write_err_mem_count++;
            v40_tcp_zc_note_retry(&echo_zero_copy);
            break;
        }
        if (result != ERR_OK) {
            stats.error_count++;
            return abort_connection(pcb);
        }

        if (v40_tcp_zc_commit_submit(&echo_zero_copy, &span) != 0) {
            stats.error_count++;
            return abort_connection(pcb);
        }
        stats.tx_bytes += span.length;
        stats.echo_write_count++;
        queued_data = 1;
    }
    if (available < 0) {
        stats.error_count++;
        return abort_connection(pcb);
    }

    if (queued_data != 0) {
        err_t result = tcp_output(pcb);
        stats.echo_output_calls++;
        if (result == ERR_MEM)
            stats.write_err_mem_count++;
        else if (result != ERR_OK)
            stats.error_count++;
    }

    if ((connection.state == V26_TCP_CLOSING) &&
        v40_tcp_zc_owner_count(&echo_zero_copy) == 0u) {
        err_t result = close_connection(pcb);
        if ((result != ERR_OK) && (result != ERR_MEM) &&
            (result != ERR_INPROGRESS))
            return abort_connection(pcb);
    }
    return ERR_OK;
}

static err_t tcp_echo_recv(void *arg, struct tcp_pcb *pcb,
                           struct pbuf *p, err_t error)
{
    v26_tcp_connection_t *state = (v26_tcp_connection_t *)arg;

    if ((state != &connection) || (connection.pcb != pcb)) {
        if (p != NULL) {
            tcp_recved(pcb, p->tot_len);
            pbuf_free(p);
        }
        stats.error_count++;
        return abort_connection(pcb);
    }

    if (p == NULL) {
        source_enabled = 0u;
        release_source_ready();
        connection.state = V26_TCP_CLOSING;
        if (v40_tcp_zc_owner_count(&echo_zero_copy) == 0u &&
            v40_tx_pool_tcp_unacked() == 0u) {
            err_t result = close_connection(pcb);
            if ((result != ERR_OK) && (result != ERR_MEM))
                return abort_connection(pcb);
            return ERR_OK;
        }
        return send_pending(pcb);
    }

    if (error != ERR_OK) {
        pbuf_free(p);
        stats.error_count++;
        return error;
    }

    if (source_test_mode != 0u) {
        uint16_t received = p->tot_len;
        if (tcp_payload_is_command(p, "V40TCPGO", 8u)) {
            source_sequence = 0u;
            source_enabled = 1u;
            stats.source_control_count++;
        } else if (tcp_payload_is_command(p, "V40TCPSTOP", 10u)) {
            source_enabled = 0u;
            stats.source_control_count++;
        } else {
            stats.error_count++;
        }
        tcp_recved(pcb, received);
        pbuf_free(p);
        return ERR_OK;
    }

    if (sink_test_mode != 0u) {
        uint16_t received = p->tot_len;
        stats.recv_callback_count++;
        stats.rx_bytes += received;
        tcp_recved(pcb, received);
        pbuf_free(p);
        return ERR_OK;
    }

    stats.recv_callback_count++;
    if (v40_tcp_zc_enqueue(&echo_zero_copy, p) != 0) {
        if (v40_tcp_zc_owner_count(&echo_zero_copy) >=
            V40_TCP_ZC_OWNER_CAPACITY) {
            v40_tcp_zc_note_retry(&echo_zero_copy);
            return ERR_MEM;
        }
        pbuf_free(p);
        stats.error_count++;
        return abort_connection(pcb);
    }
    stats.rx_bytes += p->tot_len;
    note_echo_pbuf_shape(p);
    return send_pending(pcb);
}

static err_t tcp_echo_sent(void *arg, struct tcp_pcb *pcb, u16_t length)
{
    if ((arg != &connection) || (connection.pcb != pcb)) {
        stats.error_count++;
        return abort_connection(pcb);
    }
    if (source_test_mode != 0u) {
        v40_tx_pool_tcp_ack(length);
        stats.source_acked_bytes += length;
        if (connection.state == V26_TCP_CLOSING &&
            v40_tx_pool_tcp_unacked() == 0u)
            return close_connection(pcb);
        return ERR_OK;
    }
    {
        uint32_t accepted = v40_tcp_zc_ack(&echo_zero_copy, length);
        if (accepted != length) {
            if (accepted != 0u)
                tcp_recved(pcb, (u16_t)accepted);
            stats.error_count++;
            return abort_connection(pcb);
        }
        tcp_recved(pcb, length);
    }
    return send_pending(pcb);
}

static err_t tcp_echo_poll(void *arg, struct tcp_pcb *pcb)
{
    if ((arg != &connection) || (connection.pcb != pcb)) {
        stats.error_count++;
        return abort_connection(pcb);
    }
    if (source_test_mode != 0u)
        return ERR_OK;
    return send_pending(pcb);
}

static void tcp_echo_error(void *arg, err_t error)
{
    LWIP_UNUSED_ARG(error);
    if (arg == &connection) {
        stats.error_count++;
        reset_connection();
    }
}

static err_t tcp_echo_accept(void *arg, struct tcp_pcb *new_pcb, err_t error)
{
    LWIP_UNUSED_ARG(arg);

    if ((error != ERR_OK) || (new_pcb == NULL)) {
        stats.error_count++;
        return ERR_VAL;
    }
    if (connection.pcb != NULL) {
        stats.abort_count++;
        tcp_abort(new_pcb);
        return ERR_ABRT;
    }

    connection.pcb = new_pcb;
    connection.state = V26_TCP_ACTIVE;
    stats.accept_count++;
    install_callbacks(new_pcb);
    return ERR_OK;
}

err_t v26_tcp_echo_start(void)
{
    struct tcp_pcb *pcb;
    err_t result;

    if (listen_pcb != NULL)
        return ERR_OK;

    v40_tcp_zc_init(&echo_zero_copy, release_echo_pbuf, NULL);

    pcb = tcp_new_ip_type(IPADDR_TYPE_V4);
    if (pcb == NULL)
        return ERR_MEM;

    result = tcp_bind(pcb, IP_ANY_TYPE, V26_TCP_ECHO_PORT);
    if (result != ERR_OK) {
        (void)tcp_close(pcb);
        return result;
    }

    listen_pcb = tcp_listen_with_backlog_and_err(pcb, 1u, &result);
    if (listen_pcb == NULL) {
        (void)tcp_close(pcb);
        return result;
    }
    tcp_accept(listen_pcb, tcp_echo_accept);
    return ERR_OK;
}

void v40_tcp_test_select(uint32_t source_mode, uint32_t sink_mode)
{
    source_test_mode = source_mode != 0u;
    sink_test_mode = (source_test_mode == 0u) && (sink_mode != 0u);
    source_enabled = 0u;
}

void v40_tcp_tx_generator_service(uint32_t link_up)
{
    uint32_t prepared = 0u;
    uint32_t submitted = 0u;
    int queued = 0;

    if (source_test_mode == 0u || link_up == 0u ||
        connection.state != V26_TCP_ACTIVE || connection.pcb == NULL)
        return;

    /* Producer owns a persistent READY FIFO. It may run ahead of tcp_write,
       but uses a finite budget so RX/timers keep receiving service. */
    while (source_enabled != 0u && prepared < V40_TX_PRODUCE_BUDGET &&
           source_ready_count < V40_TX_POOL_SIZE) {
        void *payload = v40_tx_pool_prepare_tcp(
            source_sequence, V40_TCP_TX_CHUNK_BYTES);
        if (payload == (void *)0)
            break;
        source_ready[source_ready_write] = payload;
        source_ready_write = (source_ready_write + 1u) % V40_TX_POOL_SIZE;
        source_ready_count++;
        source_sequence++;
        stats.source_generated_chunks++;
        stats.source_generated_bytes += V40_TCP_TX_CHUNK_BYTES;
        prepared++;
    }
    v40_tx_pool_note_producer_call(prepared);

    /* Submitter always drains existing READY work, even after V40TCPSTOP.
       ERR_MEM leaves the same slot READY for a later service call. */
    while (submitted < V40_TX_PRODUCE_BUDGET &&
           source_ready_count != 0u &&
           tcp_sndbuf(connection.pcb) >= V40_TCP_TX_CHUNK_BYTES) {
        void *payload = source_ready[source_ready_read];
        err_t result = tcp_write(connection.pcb, payload,
                                 V40_TCP_TX_CHUNK_BYTES,
                                 TCP_WRITE_FLAG_MORE);
        v40_tx_pool_note_submit_result(result);
        if (result != ERR_OK) {
            if (result == ERR_MEM) {
                stats.write_err_mem_count++;
                stats.source_retry_count++;
                v40_tx_pool_note_tcp_retry(result);
            } else {
                stats.error_count++;
                (void)abort_connection(connection.pcb);
                return;
            }
            break;
        }
        if (v40_tx_pool_mark_tcp_unacked(payload) != 0) {
            stats.error_count++;
            (void)abort_connection(connection.pcb);
            return;
        }
        source_ready[source_ready_read] = NULL;
        source_ready_read = (source_ready_read + 1u) % V40_TX_POOL_SIZE;
        source_ready_count--;
        submitted++;
        stats.tx_bytes += V40_TCP_TX_CHUNK_BYTES;
        queued = 1;
    }
    v40_tx_pool_note_submit_batch(submitted);
    if (queued != 0) {
        err_t result = tcp_output(connection.pcb);
        stats.source_output_calls++;
        if (result == ERR_MEM) {
            stats.write_err_mem_count++;
            stats.source_retry_count++;
            v40_tx_pool_note_tcp_retry(result);
        } else if (result != ERR_OK) {
            stats.error_count++;
        }
    }
}

void v40_tcp_link_down(void)
{
    /* A down PHY cannot make forward progress on queued no-copy segments.
       Abort the PCB first so lwIP drops its PBUF_ROM references; the error
       callback then releases every application-owned RX pbuf exactly once. */
    if (connection.pcb != NULL)
        (void)abort_connection(connection.pcb);
}

const v26_tcp_echo_stats_t *v26_tcp_echo_stats(void)
{
    return &stats;
}

const v40_tcp_zc_stats_t *v40_tcp_echo_zero_copy_stats(void)
{
    return v40_tcp_zc_stats(&echo_zero_copy);
}
