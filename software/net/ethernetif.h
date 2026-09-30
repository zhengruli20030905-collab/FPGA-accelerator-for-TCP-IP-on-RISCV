#ifndef V25_ETHERNETIF_H
#define V25_ETHERNETIF_H

#include <stdint.h>
#include "lwip/err.h"
#include "lwip/netif.h"

typedef struct {
    uint32_t linkoutput_calls;
    uint32_t linkoutput_busy;
    uint32_t tx_frames;
    uint32_t tx_bytes;
    uint32_t tx_errors;
    uint32_t tx_timeouts;
    uint32_t rx_frames;
    uint32_t rx_bytes;
    uint32_t rx_dequeues;
    uint32_t pbuf_alloc_failures;
    uint32_t rx_drops;
    uint32_t rx_errors;
    uint32_t input_ok;
    uint32_t input_errors;
    uint32_t tx_enqueued;
    uint32_t tx_completed;
    uint32_t tx_completion_errors;
    uint32_t tx_pool_full;
    uint32_t rx_submitted;
    uint32_t rx_completed;
    uint32_t rx_completion_errors;
    uint32_t rx_buffer_full;
    uint32_t rx_budget_exhausted;
    uint32_t max_tx_inflight;
    uint32_t max_rx_inflight;
    uint32_t service_calls;
    uint32_t rx_posted_current;
    uint32_t rx_posted_min;
    uint32_t rx_posted_max;
    uint32_t rx_refill_attempts;
    uint32_t rx_refill_success;
    uint32_t rx_refill_fail;
    uint32_t rx_reclaim_batches;
    uint32_t rx_max_reclaim_batch;
    uint32_t rx_buffer_starvation;
    uint32_t rx_slot_state_errors;
    uint32_t rx_pbuf_alloc_frames;
    uint32_t rx_pbuf_nodes;
    uint32_t rx_single_pbuf_frames;
    uint32_t rx_multi_pbuf_frames;
    uint32_t rx_max_pbuf_nodes;
} v25_ethernetif_stats_t;

err_t v25_ethernetif_init(struct netif *netif);
void v25_ethernetif_poll(struct netif *netif);
void v34_ethernetif_service(struct netif *netif);
const v25_ethernetif_stats_t *v25_ethernetif_stats(void);

#endif
