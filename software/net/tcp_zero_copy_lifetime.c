#include <stddef.h>
#include <stdint.h>
#include "net/tcp_zero_copy_lifetime.h"

static uint32_t next_index(uint32_t index, uint32_t capacity)
{
    index++;
    return index == capacity ? 0u : index;
}

static void clear_owner(v40_tcp_zc_owner_t *owner)
{
    owner->head = (struct pbuf *)0;
    owner->submit_node = (struct pbuf *)0;
    owner->total_bytes = 0u;
    owner->submitted_bytes = 0u;
    owner->acked_bytes = 0u;
    owner->outstanding_records = 0u;
    owner->state = V40_TCP_ZC_OWNER_FREE;
}

static uint32_t pbuf_chain_bytes(const struct pbuf *p, uint32_t *nodes)
{
    uint32_t bytes = 0u;
    uint32_t count = 0u;

    while (p != (const struct pbuf *)0) {
        bytes += p->len;
        count++;
        p = p->next;
    }
    *nodes = count;
    return bytes;
}

static void release_head_owners(v40_tcp_zc_manager_t *manager)
{
    while (manager->owner_count != 0u) {
        v40_tcp_zc_owner_t *owner = &manager->owners[manager->owner_head];
        struct pbuf *head;

        if (owner->acked_bytes != owner->total_bytes)
            break;
        if (owner->submitted_bytes != owner->total_bytes ||
            owner->outstanding_records != 0u ||
            owner->state != V40_TCP_ZC_OWNER_UNACKED) {
            manager->stats.free_before_ack_violations++;
            manager->stats.consistency_errors++;
            break;
        }

        head = owner->head;
        clear_owner(owner);
        manager->owner_head = next_index(manager->owner_head,
                                         V40_TCP_ZC_OWNER_CAPACITY);
        manager->owner_count--;
        manager->stats.owner_current = manager->owner_count;
        manager->stats.owner_released++;
        if (manager->release_fn != (v40_tcp_zc_release_fn)0)
            manager->release_fn(head, manager->release_arg);
    }
}

void v40_tcp_zc_init(v40_tcp_zc_manager_t *manager,
                     v40_tcp_zc_release_fn release_fn, void *release_arg)
{
    uint32_t i;

    if (manager == (v40_tcp_zc_manager_t *)0)
        return;
    for (i = 0u; i < V40_TCP_ZC_OWNER_CAPACITY; i++) {
        manager->owners[i].generation = 0u;
        clear_owner(&manager->owners[i]);
    }
    for (i = 0u; i < V40_TCP_ZC_ACK_CAPACITY; i++) {
        manager->ack_records[i].owner_index = 0u;
        manager->ack_records[i].owner_generation = 0u;
        manager->ack_records[i].remaining_bytes = 0u;
    }
    manager->owner_head = 0u;
    manager->owner_tail = 0u;
    manager->owner_count = 0u;
    manager->ack_head = 0u;
    manager->ack_tail = 0u;
    manager->ack_count = 0u;
    manager->next_generation = 0u;
    manager->release_fn = release_fn;
    manager->release_arg = release_arg;
    {
        uint32_t *word = (uint32_t *)(void *)&manager->stats;
        uint32_t words = (uint32_t)(sizeof(manager->stats) / sizeof(uint32_t));
        for (i = 0u; i < words; i++)
            word[i] = 0u;
    }
}

int v40_tcp_zc_enqueue(v40_tcp_zc_manager_t *manager, struct pbuf *p)
{
    v40_tcp_zc_owner_t *owner;
    uint32_t nodes;
    uint32_t bytes;

    if (manager == (v40_tcp_zc_manager_t *)0 || p == (struct pbuf *)0)
        return -1;
    if (manager->owner_count >= V40_TCP_ZC_OWNER_CAPACITY) {
        manager->stats.owner_exhausted++;
        return -2;
    }

    bytes = pbuf_chain_bytes(p, &nodes);
    if (bytes == 0u || nodes == 0u || bytes != p->tot_len) {
        manager->stats.consistency_errors++;
        return -1;
    }
    owner = &manager->owners[manager->owner_tail];
    if (owner->state != V40_TCP_ZC_OWNER_FREE ||
        owner->head != (struct pbuf *)0) {
        manager->stats.consistency_errors++;
        return -1;
    }

    manager->next_generation++;
    if (manager->next_generation == 0u)
        manager->next_generation = 1u;
    owner->head = p;
    owner->submit_node = p;
    owner->total_bytes = bytes;
    owner->submitted_bytes = 0u;
    owner->acked_bytes = 0u;
    owner->generation = manager->next_generation;
    owner->outstanding_records = 0u;
    owner->state = V40_TCP_ZC_OWNER_QUEUED;

    manager->owner_tail = next_index(manager->owner_tail,
                                     V40_TCP_ZC_OWNER_CAPACITY);
    manager->owner_count++;
    manager->stats.zero_copy_callbacks++;
    manager->stats.zero_copy_bytes += bytes;
    manager->stats.zero_copy_nodes += nodes;
    manager->stats.owner_current = manager->owner_count;
    if (manager->owner_count > manager->stats.owner_max)
        manager->stats.owner_max = manager->owner_count;
    return 0;
}

int v40_tcp_zc_peek_submit(v40_tcp_zc_manager_t *manager,
                           v40_tcp_zc_span_t *span)
{
    uint32_t offset;
    uint32_t index;

    if (manager == (v40_tcp_zc_manager_t *)0 ||
        span == (v40_tcp_zc_span_t *)0)
        return -1;
    if (manager->ack_count >= V40_TCP_ZC_ACK_CAPACITY)
        return 0;

    index = manager->owner_head;
    for (offset = 0u; offset < manager->owner_count; offset++) {
        v40_tcp_zc_owner_t *owner = &manager->owners[index];
        while (owner->submit_node != (struct pbuf *)0 &&
               owner->submit_node->len == 0u)
            owner->submit_node = owner->submit_node->next;
        if (owner->submit_node != (struct pbuf *)0) {
            span->payload = owner->submit_node->payload;
            span->length = owner->submit_node->len;
            span->reserved = 0u;
            span->owner_index = index;
            span->owner_generation = owner->generation;
            return 1;
        }
        index = next_index(index, V40_TCP_ZC_OWNER_CAPACITY);
    }
    return 0;
}

int v40_tcp_zc_commit_submit(v40_tcp_zc_manager_t *manager,
                             const v40_tcp_zc_span_t *span)
{
    v40_tcp_zc_owner_t *owner;
    v40_tcp_zc_ack_record_t *record;

    if (manager == (v40_tcp_zc_manager_t *)0 ||
        span == (const v40_tcp_zc_span_t *)0 ||
        span->owner_index >= V40_TCP_ZC_OWNER_CAPACITY ||
        span->length == 0u || manager->ack_count >= V40_TCP_ZC_ACK_CAPACITY) {
        if (manager != (v40_tcp_zc_manager_t *)0)
            manager->stats.consistency_errors++;
        return -1;
    }
    owner = &manager->owners[span->owner_index];
    if (owner->generation != span->owner_generation ||
        owner->state == V40_TCP_ZC_OWNER_FREE ||
        owner->submit_node == (struct pbuf *)0 ||
        owner->submit_node->payload != span->payload ||
        owner->submit_node->len != span->length ||
        owner->submitted_bytes + span->length > owner->total_bytes) {
        manager->stats.payload_stability_violations++;
        manager->stats.consistency_errors++;
        return -1;
    }

    record = &manager->ack_records[manager->ack_tail];
    record->owner_index = span->owner_index;
    record->owner_generation = span->owner_generation;
    record->remaining_bytes = span->length;
    manager->ack_tail = next_index(manager->ack_tail,
                                   V40_TCP_ZC_ACK_CAPACITY);
    manager->ack_count++;
    manager->stats.ack_queue_current = manager->ack_count;
    if (manager->ack_count > manager->stats.ack_queue_max)
        manager->stats.ack_queue_max = manager->ack_count;

    owner->submitted_bytes += span->length;
    owner->outstanding_records++;
    owner->submit_node = owner->submit_node->next;
    if (owner->submit_node == (struct pbuf *)0) {
        if (owner->submitted_bytes != owner->total_bytes) {
            manager->stats.consistency_errors++;
            return -1;
        }
        owner->state = V40_TCP_ZC_OWNER_UNACKED;
    } else {
        owner->state = V40_TCP_ZC_OWNER_PARTIAL;
    }
    return 0;
}

uint32_t v40_tcp_zc_ack(v40_tcp_zc_manager_t *manager, uint32_t bytes)
{
    uint32_t requested = bytes;
    uint32_t records_completed = 0u;

    if (manager == (v40_tcp_zc_manager_t *)0)
        return 0u;
    manager->stats.ack_callbacks++;

    while (bytes != 0u && manager->ack_count != 0u) {
        v40_tcp_zc_ack_record_t *record =
            &manager->ack_records[manager->ack_head];
        v40_tcp_zc_owner_t *owner;
        uint32_t accepted;

        if (record->owner_index >= V40_TCP_ZC_OWNER_CAPACITY) {
            manager->stats.consistency_errors++;
            break;
        }
        owner = &manager->owners[record->owner_index];
        if (owner->state == V40_TCP_ZC_OWNER_FREE ||
            owner->generation != record->owner_generation ||
            record->remaining_bytes == 0u ||
            owner->acked_bytes >= owner->total_bytes) {
            manager->stats.consistency_errors++;
            break;
        }

        accepted = bytes < record->remaining_bytes ?
                   bytes : record->remaining_bytes;
        if (accepted < record->remaining_bytes)
            manager->stats.partial_ack_events++;
        record->remaining_bytes -= accepted;
        owner->acked_bytes += accepted;
        manager->stats.acked_bytes += accepted;
        bytes -= accepted;

        if (record->remaining_bytes == 0u) {
            record->owner_index = 0u;
            record->owner_generation = 0u;
            manager->ack_head = next_index(manager->ack_head,
                                           V40_TCP_ZC_ACK_CAPACITY);
            manager->ack_count--;
            manager->stats.ack_queue_current = manager->ack_count;
            records_completed++;
            if (owner->outstanding_records != 0u)
                owner->outstanding_records--;
            else
                manager->stats.consistency_errors++;
            release_head_owners(manager);
        }
    }

    if (records_completed > 1u)
        manager->stats.cumulative_ack_events++;
    if (bytes != 0u)
        manager->stats.consistency_errors++;
    return requested - bytes;
}

uint32_t v40_tcp_zc_abort(v40_tcp_zc_manager_t *manager)
{
    uint32_t released = 0u;

    if (manager == (v40_tcp_zc_manager_t *)0)
        return 0u;
    if (manager->owner_count != 0u)
        manager->stats.abort_recovery_count++;
    while (manager->owner_count != 0u) {
        v40_tcp_zc_owner_t *owner = &manager->owners[manager->owner_head];
        struct pbuf *head = owner->head;

        clear_owner(owner);
        manager->owner_head = next_index(manager->owner_head,
                                         V40_TCP_ZC_OWNER_CAPACITY);
        manager->owner_count--;
        released++;
        if (manager->release_fn != (v40_tcp_zc_release_fn)0)
            manager->release_fn(head, manager->release_arg);
    }
    manager->owner_tail = manager->owner_head;
    manager->ack_head = 0u;
    manager->ack_tail = 0u;
    manager->ack_count = 0u;
    manager->stats.owner_current = 0u;
    manager->stats.ack_queue_current = 0u;
    return released;
}

void v40_tcp_zc_note_retry(v40_tcp_zc_manager_t *manager)
{
    if (manager != (v40_tcp_zc_manager_t *)0)
        manager->stats.retry_count++;
}

void v40_tcp_zc_note_close_wait(v40_tcp_zc_manager_t *manager)
{
    if (manager != (v40_tcp_zc_manager_t *)0)
        manager->stats.close_wait_count++;
}

uint32_t v40_tcp_zc_owner_count(const v40_tcp_zc_manager_t *manager)
{
    return manager == (const v40_tcp_zc_manager_t *)0 ?
           0u : manager->owner_count;
}

uint32_t v40_tcp_zc_ack_count(const v40_tcp_zc_manager_t *manager)
{
    return manager == (const v40_tcp_zc_manager_t *)0 ?
           0u : manager->ack_count;
}

const v40_tcp_zc_stats_t *v40_tcp_zc_stats(
    const v40_tcp_zc_manager_t *manager)
{
    return manager == (const v40_tcp_zc_manager_t *)0 ?
           (const v40_tcp_zc_stats_t *)0 : &manager->stats;
}

typedef struct {
    uint32_t releases;
} v40_tcp_zc_self_test_context_t;

static void self_test_release(struct pbuf *p, void *arg)
{
    v40_tcp_zc_self_test_context_t *context =
        (v40_tcp_zc_self_test_context_t *)arg;
    if (p != (struct pbuf *)0)
        context->releases++;
}

int v40_tcp_zc_self_test(void)
{
    v40_tcp_zc_manager_t manager;
    v40_tcp_zc_self_test_context_t context;
    struct pbuf pbufs[V40_TCP_ZC_OWNER_CAPACITY + 2u];
    uint32_t payload[V40_TCP_ZC_OWNER_CAPACITY + 2u];
    v40_tcp_zc_span_t span;
    uint32_t i;

    context.releases = 0u;
    v40_tcp_zc_init(&manager, self_test_release, &context);
    for (i = 0u; i < V40_TCP_ZC_OWNER_CAPACITY + 2u; i++) {
        pbufs[i].next = (struct pbuf *)0;
        pbufs[i].payload = &payload[i];
        pbufs[i].len = 4u;
        pbufs[i].tot_len = 4u;
    }

    pbufs[0].len = 54u;
    pbufs[0].tot_len = 1460u;
    pbufs[0].next = &pbufs[1];
    pbufs[1].len = 1406u;
    pbufs[1].tot_len = 1406u;
    if (v40_tcp_zc_enqueue(&manager, &pbufs[0]) != 0)
        return 0;
    if (v40_tcp_zc_peek_submit(&manager, &span) != 1 ||
        span.length != 54u)
        return 0;
    v40_tcp_zc_note_retry(&manager);
    if (v40_tcp_zc_peek_submit(&manager, &span) != 1 ||
        span.length != 54u || v40_tcp_zc_commit_submit(&manager, &span) != 0)
        return 0;
    if (v40_tcp_zc_peek_submit(&manager, &span) != 1 ||
        span.length != 1406u || v40_tcp_zc_commit_submit(&manager, &span) != 0)
        return 0;
    if (v40_tcp_zc_ack(&manager, 27u) != 27u || context.releases != 0u)
        return 0;
    if (v40_tcp_zc_ack(&manager, 1433u) != 1433u ||
        context.releases != 1u || manager.owner_count != 0u ||
        manager.ack_count != 0u || manager.stats.partial_ack_events == 0u ||
        manager.stats.cumulative_ack_events == 0u)
        return 0;

    for (i = 0u; i < V40_TCP_ZC_OWNER_CAPACITY; i++) {
        pbufs[i].next = (struct pbuf *)0;
        pbufs[i].len = 4u;
        pbufs[i].tot_len = 4u;
        if (v40_tcp_zc_enqueue(&manager, &pbufs[i]) != 0)
            return 0;
    }
    if (v40_tcp_zc_enqueue(&manager,
                           &pbufs[V40_TCP_ZC_OWNER_CAPACITY]) != -2 ||
        manager.stats.owner_exhausted == 0u)
        return 0;
    if (v40_tcp_zc_abort(&manager) != V40_TCP_ZC_OWNER_CAPACITY ||
        manager.owner_count != 0u || manager.ack_count != 0u)
        return 0;
    return 1;
}
