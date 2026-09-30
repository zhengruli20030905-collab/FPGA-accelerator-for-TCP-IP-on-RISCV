#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "lwip/pbuf.h"
#include "net/tx_buffer_pool.h"

static uint32_t fake_cycles;

uint32_t v25_platform_timer_cycles(void)
{
    fake_cycles += 17u;
    return fake_cycles;
}

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static uint8_t expected_byte(uint32_t sequence, uint32_t offset, uint8_t tag)
{
    if (offset == 0u) return (uint8_t)'V';
    if (offset == 1u) return (uint8_t)'4';
    if (offset == 2u) return (uint8_t)'0';
    if (offset == 3u) return tag;
    if (offset >= 4u && offset <= 11u)
        return (uint8_t)(sequence >> (((offset - 4u) & 3u) * 8u));
    return (uint8_t)((sequence + offset * 31u + 7u) & 0xffu);
}

static void check_payload(const uint8_t *payload, uint32_t sequence,
                          uint32_t length, uint8_t tag)
{
    uint32_t i;
    for (i = 0u; i < length; i++)
        require(payload[i] == expected_byte(sequence, i, tag),
                "realtime payload mismatch");
}

int main(void)
{
    struct pbuf *udp[V40_TX_POOL_SIZE];
    void *tcp[V40_TX_POOL_SIZE];
    const v40_tx_pool_stats_t *stats;
    uint32_t batch;
    uint32_t i;
    uint32_t sequence = 0u;

    require(v40_tx_pool_init() == 0, "pool init");

    /* 126 complete wraps x eight slots = 1008 real payload generations. */
    for (batch = 0u; batch < 126u; batch++) {
        for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
            udp[i] = v40_tx_pool_prepare_udp(sequence, 1472u);
            require(udp[i] != 0, "prepare UDP slot");
            check_payload((const uint8_t *)udp[i]->payload, sequence,
                          1472u, (uint8_t)'T');
            sequence++;
        }
        require(v40_tx_pool_prepare_udp(sequence, 1472u) == 0,
                "ninth slot must see pool full");
        for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
            pbuf_ref(udp[i]);
            require(v40_tx_pool_mark_udp_inflight(udp[i]) == 0,
                    "mark UDP inflight");
            v40_tx_pool_set_udp_result(udp[i], 1);
            require(pbuf_free(udp[i]) == 0,
                    "application release must retain DMA reference");
        }
        stats = v40_tx_pool_stats();
        require(stats->free_current == 0u && stats->inflight_current == 8u,
                "all eight UDP slots concurrently inflight");
        for (i = 0u; i < V40_TX_POOL_SIZE; i++)
            require(pbuf_free(udp[i]) == 1,
                    "DMA completion releases final UDP reference");
    }

    /* A failed enqueue is classified as an error and still returns its slot. */
    udp[0] = v40_tx_pool_prepare_udp(sequence++, 513u);
    require(udp[0] != 0, "prepare non-word UDP length");
    require(v40_tx_pool_mark_udp_inflight(udp[0]) == 0,
            "mark failing UDP inflight");
    v40_tx_pool_set_udp_result(udp[0], 0);
    require(pbuf_free(udp[0]) == 1, "failed UDP submit recovery");

    /* A descriptor/DMA error arrives after the application has released its
       reference.  The DMA-owned reference must keep the same slot alive until
       completion, classify the result as an error, and then return it. */
    udp[0] = v40_tx_pool_prepare_udp(sequence++, 1472u);
    require(udp[0] != 0, "prepare UDP DMA-error slot");
    pbuf_ref(udp[0]);
    require(v40_tx_pool_mark_udp_inflight(udp[0]) == 0,
            "mark UDP DMA-error inflight");
    v40_tx_pool_set_udp_result(udp[0], 1);
    require(pbuf_free(udp[0]) == 0,
            "application release retains DMA-error slot");
    v40_tx_pool_note_udp_dma_result(udp[0], 0);
    require(pbuf_free(udp[0]) == 1,
            "DMA error completion returns UDP slot");

    /* tcp_write(ERR_MEM) must not discard or regenerate the READY payload.
       Retry the exact same pointer and only release it after ACK. */
    tcp[0] = v40_tx_pool_prepare_tcp(0x12345678u, 1460u);
    require(tcp[0] != 0, "prepare TCP ERR_MEM slot");
    check_payload((const uint8_t *)tcp[0], 0x12345678u, 1460u,
                  (uint8_t)'C');
    v40_tx_pool_note_tcp_retry(ERR_MEM);
    stats = v40_tx_pool_stats();
    require(stats->ready_current == 1u && stats->inflight_current == 0u,
            "ERR_MEM retains same READY slot");
    check_payload((const uint8_t *)tcp[0], 0x12345678u, 1460u,
                  (uint8_t)'C');
    require(v40_tx_pool_mark_tcp_unacked(tcp[0]) == 0,
            "retry accepts same TCP slot");
    v40_tx_pool_tcp_ack(1460u);
    require(v40_tx_pool_stats()->free_current == V40_TX_POOL_SIZE,
            "ACK releases retried TCP slot");

    /* TCP pointers remain allocated after queue/DMA time. Only ACK frees them. */
    for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
        tcp[i] = v40_tx_pool_prepare_tcp(i, 1460u);
        require(tcp[i] != 0, "prepare TCP slot");
        check_payload((const uint8_t *)tcp[i], i, 1460u, (uint8_t)'C');
        require(v40_tx_pool_mark_tcp_unacked(tcp[i]) == 0,
                "mark TCP unacked");
    }
    stats = v40_tx_pool_stats();
    require(stats->free_current == 0u && stats->tcp_unacked_bytes == 11680u,
            "TCP buffers retained before ACK");

    v40_tx_pool_tcp_ack(100u);
    stats = v40_tx_pool_stats();
    require(stats->free_current == 0u && stats->tcp_unacked_bytes == 11580u,
            "partial ACK must not free a slot");
    v40_tx_pool_tcp_ack((1460u - 100u) + 2u * 1460u);
    stats = v40_tx_pool_stats();
    require(stats->free_current == 3u && stats->tcp_unacked_bytes == 7300u,
            "one ACK releases multiple complete slots");
    v40_tx_pool_tcp_abort_all();

    stats = v40_tx_pool_stats();
    require(stats->free_current == V40_TX_POOL_SIZE, "abort returns all slots");
    require(stats->inflight_current == 0u, "no slot remains inflight");
    require(stats->max_inflight == V40_TX_POOL_SIZE,
            "maximum inflight reaches pool depth");
    require(stats->reuse_count >= 1000u, "more than 1000 slot reuses");
    require(stats->udp_complete == 1008u, "all UDP completions counted");
    require(stats->udp_error == 2u, "UDP submit and DMA failures counted");
    require(stats->tcp_ack_callbacks == 3u,
            "retry, partial and multi-slot ACKs counted");
    require(stats->tcp_abort_recovery == 5u, "abort reclaimed five TCP slots");
    require(stats->tcp_err_mem == 1u && stats->tcp_retry == 1u,
            "ERR_MEM retry accounting");
    require(stats->state_errors == 0u && stats->generation_errors == 0u,
            "no ownership errors");

    printf("V40 TX BUFFER POOL HOST TEST PASSED reuse=%u max_inflight=%u "
           "udp_done=%u tcp_ack_callbacks=%u abort_recovery=%u\n",
           stats->reuse_count, stats->max_inflight, stats->udp_complete,
           stats->tcp_ack_callbacks, stats->tcp_abort_recovery);
    return 0;
}
