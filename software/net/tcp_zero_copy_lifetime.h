#ifndef V40_TCP_ZERO_COPY_LIFETIME_H
#define V40_TCP_ZERO_COPY_LIFETIME_H

#include <stdint.h>
#include "lwip/pbuf.h"

#define V40_TCP_ZC_OWNER_CAPACITY 16u
#define V40_TCP_ZC_ACK_CAPACITY   32u

typedef enum {
    V40_TCP_ZC_OWNER_FREE = 0,
    V40_TCP_ZC_OWNER_QUEUED,
    V40_TCP_ZC_OWNER_PARTIAL,
    V40_TCP_ZC_OWNER_UNACKED
} v40_tcp_zc_owner_state_t;

typedef struct {
    uint32_t zero_copy_callbacks;
    uint32_t zero_copy_bytes;
    uint32_t zero_copy_nodes;
    uint32_t ack_callbacks;
    uint32_t partial_ack_events;
    uint32_t cumulative_ack_events;
    uint32_t acked_bytes;
    uint32_t owner_current;
    uint32_t owner_max;
    uint32_t owner_exhausted;
    uint32_t owner_released;
    uint32_t free_before_ack_violations;
    uint32_t ack_queue_current;
    uint32_t ack_queue_max;
    uint32_t retry_count;
    uint32_t abort_recovery_count;
    uint32_t close_wait_count;
    uint32_t payload_stability_violations;
    uint32_t consistency_errors;
} v40_tcp_zc_stats_t;

typedef struct {
    struct pbuf *head;
    struct pbuf *submit_node;
    uint32_t total_bytes;
    uint32_t submitted_bytes;
    uint32_t acked_bytes;
    uint32_t generation;
    uint32_t outstanding_records;
    uint32_t state;
} v40_tcp_zc_owner_t;

typedef struct {
    uint32_t owner_index;
    uint32_t owner_generation;
    uint32_t remaining_bytes;
} v40_tcp_zc_ack_record_t;

typedef void (*v40_tcp_zc_release_fn)(struct pbuf *p, void *arg);

typedef struct {
    v40_tcp_zc_owner_t owners[V40_TCP_ZC_OWNER_CAPACITY];
    v40_tcp_zc_ack_record_t ack_records[V40_TCP_ZC_ACK_CAPACITY];
    uint32_t owner_head;
    uint32_t owner_tail;
    uint32_t owner_count;
    uint32_t ack_head;
    uint32_t ack_tail;
    uint32_t ack_count;
    uint32_t next_generation;
    v40_tcp_zc_release_fn release_fn;
    void *release_arg;
    v40_tcp_zc_stats_t stats;
} v40_tcp_zc_manager_t;

typedef struct {
    const void *payload;
    uint16_t length;
    uint16_t reserved;
    uint32_t owner_index;
    uint32_t owner_generation;
} v40_tcp_zc_span_t;

void v40_tcp_zc_init(v40_tcp_zc_manager_t *manager,
                     v40_tcp_zc_release_fn release_fn, void *release_arg);
int v40_tcp_zc_enqueue(v40_tcp_zc_manager_t *manager, struct pbuf *p);
int v40_tcp_zc_peek_submit(v40_tcp_zc_manager_t *manager,
                           v40_tcp_zc_span_t *span);
int v40_tcp_zc_commit_submit(v40_tcp_zc_manager_t *manager,
                             const v40_tcp_zc_span_t *span);
uint32_t v40_tcp_zc_ack(v40_tcp_zc_manager_t *manager, uint32_t bytes);
uint32_t v40_tcp_zc_abort(v40_tcp_zc_manager_t *manager);
void v40_tcp_zc_note_retry(v40_tcp_zc_manager_t *manager);
void v40_tcp_zc_note_close_wait(v40_tcp_zc_manager_t *manager);
uint32_t v40_tcp_zc_owner_count(const v40_tcp_zc_manager_t *manager);
uint32_t v40_tcp_zc_ack_count(const v40_tcp_zc_manager_t *manager);
const v40_tcp_zc_stats_t *v40_tcp_zc_stats(
    const v40_tcp_zc_manager_t *manager);
int v40_tcp_zc_self_test(void);

#endif
