#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "net/tcp_zero_copy_lifetime.h"

typedef struct {
    uint32_t releases;
    struct pbuf *last;
} release_log_t;

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void release_pbuf(struct pbuf *p, void *arg)
{
    release_log_t *log = (release_log_t *)arg;
    require(p != NULL, "released pbuf must be non-null");
    log->releases++;
    log->last = p;
}

static void init_node(struct pbuf *p, void *payload, uint16_t length)
{
    p->next = NULL;
    p->payload = payload;
    p->len = length;
    p->tot_len = length;
    p->ref = 1u;
}

static void submit_all(v40_tcp_zc_manager_t *manager)
{
    v40_tcp_zc_span_t span;
    while (v40_tcp_zc_peek_submit(manager, &span) == 1)
        require(v40_tcp_zc_commit_submit(manager, &span) == 0,
                "commit submit span");
}

static void test_single_partial_ack(void)
{
    v40_tcp_zc_manager_t manager;
    release_log_t log = {0u, NULL};
    struct pbuf p;
    uint8_t payload[1460];
    v40_tcp_zc_span_t span;

    init_node(&p, payload, sizeof(payload));
    v40_tcp_zc_init(&manager, release_pbuf, &log);
    require(v40_tcp_zc_enqueue(&manager, &p) == 0, "enqueue single pbuf");
    require(v40_tcp_zc_peek_submit(&manager, &span) == 1,
            "peek single pbuf");
    v40_tcp_zc_note_retry(&manager);
    {
        v40_tcp_zc_span_t retry;
        require(v40_tcp_zc_peek_submit(&manager, &retry) == 1,
                "retry peek");
        require(retry.payload == span.payload && retry.length == span.length &&
                retry.owner_generation == span.owner_generation,
                "ERR_MEM retry keeps exact payload and owner");
    }
    require(v40_tcp_zc_commit_submit(&manager, &span) == 0,
            "commit single pbuf");
    require(v40_tcp_zc_ack(&manager, 100u) == 100u, "partial ack accepted");
    require(log.releases == 0u, "partial ACK must retain pbuf");
    require(v40_tcp_zc_ack(&manager, 1360u) == 1360u,
            "final ack accepted");
    require(log.releases == 1u && log.last == &p,
            "final ACK releases exact pbuf");
    require(manager.stats.partial_ack_events == 1u &&
            manager.stats.free_before_ack_violations == 0u &&
            manager.stats.retry_count == 1u,
            "single ACK counters");
}

static void test_multi_node_cumulative_ack(void)
{
    v40_tcp_zc_manager_t manager;
    release_log_t log = {0u, NULL};
    struct pbuf nodes[3];
    uint8_t a[54], b[700], c[706];

    init_node(&nodes[0], a, sizeof(a));
    init_node(&nodes[1], b, sizeof(b));
    init_node(&nodes[2], c, sizeof(c));
    nodes[0].next = &nodes[1];
    nodes[1].next = &nodes[2];
    nodes[0].tot_len = 1460u;
    nodes[1].tot_len = 1406u;
    v40_tcp_zc_init(&manager, release_pbuf, &log);
    require(v40_tcp_zc_enqueue(&manager, &nodes[0]) == 0,
            "enqueue multi-node pbuf");
    submit_all(&manager);
    require(manager.ack_count == 3u, "three ACK records created");
    require(v40_tcp_zc_ack(&manager, 1460u) == 1460u,
            "cumulative ACK accepted");
    require(log.releases == 1u && log.last == &nodes[0],
            "cumulative ACK releases chain head once");
    require(manager.stats.cumulative_ack_events == 1u &&
            manager.stats.zero_copy_nodes == 3u,
            "multi-node cumulative counters");
}

static void test_multi_owner_ack_and_stability(void)
{
    v40_tcp_zc_manager_t manager;
    release_log_t log = {0u, NULL};
    struct pbuf p[3];
    uint8_t payload[3][128];
    v40_tcp_zc_span_t span;
    uint32_t i;

    v40_tcp_zc_init(&manager, release_pbuf, &log);
    for (i = 0u; i < 3u; i++) {
        init_node(&p[i], payload[i], sizeof(payload[i]));
        require(v40_tcp_zc_enqueue(&manager, &p[i]) == 0,
                "enqueue multiple owners");
    }
    submit_all(&manager);
    require(v40_tcp_zc_ack(&manager, 300u) == 300u,
            "ACK spans owners");
    require(log.releases == 2u && manager.owner_count == 1u,
            "ACK releases only fully acknowledged owners");
    require(v40_tcp_zc_ack(&manager, 84u) == 84u && log.releases == 3u,
            "remaining owner release");

    init_node(&p[0], payload[0], sizeof(payload[0]));
    require(v40_tcp_zc_enqueue(&manager, &p[0]) == 0,
            "enqueue stability owner");
    require(v40_tcp_zc_peek_submit(&manager, &span) == 1,
            "peek stability owner");
    p[0].payload = payload[1];
    require(v40_tcp_zc_commit_submit(&manager, &span) != 0,
            "changed payload pointer rejected");
    require(manager.stats.payload_stability_violations == 1u,
            "stability violation counted");
    require(v40_tcp_zc_abort(&manager) == 1u,
            "stability failure abort recovery");
}

static void test_exhaustion_abort(void)
{
    v40_tcp_zc_manager_t manager;
    release_log_t log = {0u, NULL};
    struct pbuf p[V40_TCP_ZC_OWNER_CAPACITY + 1u];
    uint8_t payload[V40_TCP_ZC_OWNER_CAPACITY + 1u][4];
    uint32_t i;

    v40_tcp_zc_init(&manager, release_pbuf, &log);
    for (i = 0u; i < V40_TCP_ZC_OWNER_CAPACITY + 1u; i++)
        init_node(&p[i], payload[i], 4u);
    for (i = 0u; i < V40_TCP_ZC_OWNER_CAPACITY; i++)
        require(v40_tcp_zc_enqueue(&manager, &p[i]) == 0,
                "fill owner queue");
    require(v40_tcp_zc_enqueue(&manager,
                               &p[V40_TCP_ZC_OWNER_CAPACITY]) == -2,
            "owner exhaustion reported");
    v40_tcp_zc_note_close_wait(&manager);
    require(log.releases == 0u, "queued owners retained before abort");
    require(v40_tcp_zc_abort(&manager) == V40_TCP_ZC_OWNER_CAPACITY,
            "abort releases every retained owner");
    require(log.releases == V40_TCP_ZC_OWNER_CAPACITY &&
            manager.owner_count == 0u && manager.ack_count == 0u &&
            manager.stats.owner_exhausted == 1u &&
            manager.stats.abort_recovery_count == 1u &&
            manager.stats.close_wait_count == 1u,
            "exhaustion and abort counters");
}

static void test_long_wrap(void)
{
    v40_tcp_zc_manager_t manager;
    release_log_t log = {0u, NULL};
    struct pbuf p;
    uint8_t payload[64];
    uint32_t i;

    v40_tcp_zc_init(&manager, release_pbuf, &log);
    for (i = 0u; i < 12000u; i++) {
        init_node(&p, payload, sizeof(payload));
        require(v40_tcp_zc_enqueue(&manager, &p) == 0,
                "long-run enqueue");
        submit_all(&manager);
        require(v40_tcp_zc_ack(&manager, 17u) == 17u,
                "long-run partial ACK");
        require(log.releases == i, "long-run retain before final ACK");
        require(v40_tcp_zc_ack(&manager, 47u) == 47u,
                "long-run final ACK");
    }
    require(log.releases == 12000u && manager.owner_count == 0u &&
            manager.ack_count == 0u &&
            manager.stats.consistency_errors == 0u &&
            manager.stats.free_before_ack_violations == 0u,
            "long-run wrap remains consistent");
}

int main(void)
{
    require(v40_tcp_zc_self_test() == 1, "firmware self-test model");
    test_single_partial_ack();
    test_multi_node_cumulative_ack();
    test_multi_owner_ack_and_stability();
    test_exhaustion_abort();
    test_long_wrap();
    puts("V40 TCP ZERO-COPY ACK LIFETIME HOST TEST PASSED");
    return 0;
}
