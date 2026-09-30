#ifndef V40_TX_BUFFER_POOL_H
#define V40_TX_BUFFER_POOL_H

#include <stdint.h>
#include "lwip/err.h"
#include "lwip/pbuf.h"

#define V40_TX_POOL_SIZE 8u
#define V40_TX_PRODUCE_BUDGET 4u
#define V40_TX_SLOT_STORAGE_BYTES 1600u

typedef enum {
    V40_TX_SLOT_FREE = 0,
    V40_TX_SLOT_FILLING,
    V40_TX_SLOT_READY,
    V40_TX_SLOT_UDP_INFLIGHT,
    V40_TX_SLOT_TCP_UNACKED,
    V40_TX_SLOT_ERROR
} v40_tx_slot_state_t;

typedef struct {
    uint32_t init_ok;
    uint32_t init_fail;
    uint32_t free_current;
    uint32_t ready_current;
    uint32_t inflight_current;
    uint32_t min_free;
    uint32_t max_ready;
    uint32_t max_inflight;
    uint32_t reuse_count;
    uint32_t no_free_events;
    uint32_t state_errors;
    uint32_t generation_errors;
    uint32_t producer_calls;
    uint32_t producer_frames;
    uint32_t producer_bytes;
    uint32_t producer_ticks_lo;
    uint32_t producer_ticks_hi;
    uint32_t producer_max_batch;
    uint32_t submit_calls;
    uint32_t submit_frames;
    uint32_t submit_retry;
    uint32_t submit_err_mem;
    uint32_t submit_other_error;
    uint32_t submit_max_batch;
    uint32_t partial_flush;
    uint32_t udp_complete;
    uint32_t udp_error;
    uint32_t udp_stale_complete;
    uint32_t tcp_submitted_bytes;
    uint32_t tcp_acked_bytes;
    uint32_t tcp_unacked_bytes;
    uint32_t tcp_max_unacked;
    uint32_t tcp_ack_callbacks;
    uint32_t tcp_err_mem;
    uint32_t tcp_retry;
    uint32_t tcp_abort_recovery;
} v40_tx_pool_stats_t;

int v40_tx_pool_init(void);
struct pbuf *v40_tx_pool_prepare_udp(uint32_t sequence, uint16_t length);
int v40_tx_pool_mark_udp_inflight(struct pbuf *p);
void v40_tx_pool_set_udp_result(struct pbuf *p, int success);
void v40_tx_pool_note_producer_call(uint32_t frames);
void v40_tx_pool_note_submit_batch(uint32_t frames);
void v40_tx_pool_note_submit_result(err_t result);
void v40_tx_pool_note_partial_flush(void);
void v40_tx_pool_note_udp_dma_result(struct pbuf *p, int success);
void *v40_tx_pool_prepare_tcp(uint32_t sequence, uint16_t length);
int v40_tx_pool_mark_tcp_unacked(void *payload);
void v40_tx_pool_cancel_ready(void *payload);
void v40_tx_pool_tcp_ack(uint32_t bytes);
void v40_tx_pool_tcp_abort_all(void);
uint32_t v40_tx_pool_tcp_unacked(void);
void v40_tx_pool_note_tcp_retry(err_t result);
const v40_tx_pool_stats_t *v40_tx_pool_stats(void);

#endif
