#include <stdint.h>
#include "net/packet_sgdma.h"
#include "net/v25_platform.h"

typedef enum {
    V34_DESC_FREE = 0,
    V34_DESC_PREPARED,
    V34_DESC_PUBLISHED
} v34_desc_state_t;

typedef struct {
    uint32_t ticket;
    uint32_t requested_length;
    void *cookie;
    uint8_t first;
    uint8_t last;
    uint8_t state;
    uint8_t reserved;
} v34_desc_meta_t;

typedef struct {
    v34_sgdma_desc_t *descriptors;
    v34_desc_meta_t *metadata;
    uint32_t prepared_tail;
    uint32_t published_tail;
    uint32_t reclaim_head;
    uint32_t direction;
    v34_sgdma_ring_stats_t *stats;
    uint32_t reclaim_frame_active;
    uint32_t reclaim_ticket;
    uint32_t reclaim_requested;
    uint32_t reclaim_actual;
    uint32_t reclaim_status;
    uint32_t reclaim_segments;
    void *reclaim_cookie;
} v34_ring_context_t;

static v34_sgdma_desc_t tx_descriptor_ring[V34_SGDMA_RING_ENTRIES]
    __attribute__((aligned(16)));
static v34_sgdma_desc_t rx_descriptor_ring[V34_SGDMA_RING_ENTRIES]
    __attribute__((aligned(16)));
static v34_desc_meta_t tx_descriptor_meta[V34_SGDMA_RING_ENTRIES];
static v34_desc_meta_t rx_descriptor_meta[V34_SGDMA_RING_ENTRIES];

typedef char v34_descriptor_must_be_16_bytes
    [(sizeof(v34_sgdma_desc_t) == 16u) ? 1 : -1];
typedef char v34_ring_must_be_power_of_two
    [((V34_SGDMA_RING_ENTRIES & (V34_SGDMA_RING_ENTRIES - 1u)) == 0u) ? 1 : -1];

static v34_sgdma_stats_t driver_stats;
static v34_ring_context_t tx_ring;
static v34_ring_context_t rx_ring;
static uint32_t last_error;
static uint32_t last_status;

static void fence_rw(void)
{
    __asm__ volatile ("fence rw, rw" ::: "memory");
}

static uint32_t ring_hardware_head(const v34_ring_context_t *ring)
{
    return ring->direction == V34_SGDMA_TX ? SG_REG_TX_HEAD : SG_REG_RX_HEAD;
}

static void ring_write_tail(const v34_ring_context_t *ring, uint32_t value)
{
    if (ring->direction == V34_SGDMA_TX)
        SG_REG_TX_TAIL = value;
    else
        SG_REG_RX_TAIL = value;
}

static void update_high_watermarks(v34_ring_context_t *ring)
{
    uint32_t prepared_pending = ring->prepared_tail - ring->reclaim_head;
    uint32_t published_pending = ring->published_tail - ring->reclaim_head;
    if (prepared_pending > ring->stats->max_prepared_pending)
        ring->stats->max_prepared_pending = prepared_pending;
    if (published_pending > ring->stats->max_published_pending)
        ring->stats->max_published_pending = published_pending;
}

static void reset_software_ring(v34_ring_context_t *ring)
{
    uint32_t i;

    ring->prepared_tail = 0u;
    ring->published_tail = 0u;
    ring->reclaim_head = 0u;
    ring->reclaim_frame_active = 0u;
    ring->reclaim_ticket = 0u;
    ring->reclaim_requested = 0u;
    ring->reclaim_actual = 0u;
    ring->reclaim_status = 0u;
    ring->reclaim_segments = 0u;
    ring->reclaim_cookie = (void *)0;

    ring->stats->descriptors_prepared = 0u;
    ring->stats->descriptors_reclaimed = 0u;
    ring->stats->frames_prepared = 0u;
    ring->stats->frames_reclaimed = 0u;
    ring->stats->completion_errors = 0u;
    ring->stats->ring_full = 0u;
    ring->stats->doorbell_writes = 0u;
    ring->stats->reclaim_empty_polls = 0u;
    ring->stats->max_prepared_pending = 0u;
    ring->stats->max_published_pending = 0u;
    ring->stats->max_segments_per_frame = 0u;
    ring->stats->consistency_errors = 0u;

    for (i = 0u; i < V34_SGDMA_RING_ENTRIES; i++) {
        ring->descriptors[i].buffer_addr = 0u;
        ring->descriptors[i].length_or_capacity = 0u;
        ring->descriptors[i].status = 0u;
        ring->descriptors[i].control = 0u;
        ring->metadata[i].ticket = 0u;
        ring->metadata[i].requested_length = 0u;
        ring->metadata[i].cookie = (void *)0;
        ring->metadata[i].first = 0u;
        ring->metadata[i].last = 0u;
        ring->metadata[i].state = V34_DESC_FREE;
    }
}

int v34_sgdma_init(void)
{
    if (SG_REG_ID != SG_V34_ID ||
        (SG_REG_CAPABILITY & SG_V34_CAPABILITIES) != SG_V34_CAPABILITIES)
        return -1;

    tx_ring.descriptors = tx_descriptor_ring;
    tx_ring.metadata = tx_descriptor_meta;
    tx_ring.direction = V34_SGDMA_TX;
    tx_ring.stats = &driver_stats.tx;
    rx_ring.descriptors = rx_descriptor_ring;
    rx_ring.metadata = rx_descriptor_meta;
    rx_ring.direction = V34_SGDMA_RX;
    rx_ring.stats = &driver_stats.rx;

    SG_REG_CTRL = 0u;
    SG_REG_TX_DESC_BASE = (uint32_t)(uintptr_t)tx_descriptor_ring;
    SG_REG_TX_RING_SIZE = V34_SGDMA_RING_ENTRIES;
    SG_REG_RX_DESC_BASE = (uint32_t)(uintptr_t)rx_descriptor_ring;
    SG_REG_RX_RING_SIZE = V34_SGDMA_RING_ENTRIES;
    SG_REG_CTRL = SG_CTRL_RESET_RING;

    reset_software_ring(&tx_ring);
    reset_software_ring(&rx_ring);
    driver_stats.async_recoveries = 0u;
    driver_stats.blocking_wait_loops = 0u;
    last_error = 0u;
    last_status = 0u;

    fence_rw();
    SG_REG_CTRL = SG_CTRL_ENABLE;
    return (SG_REG_STATUS & 0x80u) ? 0 : -1;
}

static uint32_t ring_free_slots(const v34_ring_context_t *ring)
{
    uint32_t occupied = ring->prepared_tail - ring->reclaim_head;
    return occupied >= V34_SGDMA_RING_ENTRIES ?
           0u : V34_SGDMA_RING_ENTRIES - occupied;
}

uint32_t v34_sgdma_tx_free_slots(void) { return ring_free_slots(&tx_ring); }
uint32_t v34_sgdma_rx_free_slots(void) { return ring_free_slots(&rx_ring); }
uint32_t v34_sgdma_tx_prepared_count(void)
{ return tx_ring.prepared_tail - tx_ring.published_tail; }
uint32_t v34_sgdma_rx_prepared_count(void)
{ return rx_ring.prepared_tail - rx_ring.published_tail; }
uint32_t v34_sgdma_tx_published_pending(void)
{ return tx_ring.published_tail - tx_ring.reclaim_head; }
uint32_t v34_sgdma_rx_published_pending(void)
{ return rx_ring.published_tail - rx_ring.reclaim_head; }

static int ring_prepare_frame(v34_ring_context_t *ring,
                              const v34_sgdma_segment_t *segments,
                              uint32_t segment_count, void *cookie,
                              uint32_t *ticket, uint32_t checksum_control)
{
    uint32_t i;
    uint32_t total = 0u;
    uint32_t base_ticket;

    if (segments == (const v34_sgdma_segment_t *)0 || cookie == (void *)0 ||
        segment_count == 0u || segment_count > V34_SGDMA_MAX_FRAME_SEGMENTS)
        return -1;
    if (ring_free_slots(ring) < segment_count) {
        ring->stats->ring_full++;
        return -2;
    }
    for (i = 0u; i < segment_count; i++) {
        uint32_t index = (ring->prepared_tail + i) &
                         (V34_SGDMA_RING_ENTRIES - 1u);
        if (segments[i].address == (void *)0 || segments[i].length == 0u ||
            segments[i].length > 2048u)
            return -1;
        if (ring->metadata[index].state != V34_DESC_FREE) {
            ring->stats->consistency_errors++;
            return -3;
        }
        total += segments[i].length;
        if (total > 2048u)
            return -1;
    }

    base_ticket = ring->prepared_tail;
    for (i = 0u; i < segment_count; i++) {
        uint32_t index = (base_ticket + i) & (V34_SGDMA_RING_ENTRIES - 1u);
        v34_sgdma_desc_t *desc = &ring->descriptors[index];
        v34_desc_meta_t *meta = &ring->metadata[index];

        desc->buffer_addr = (uint32_t)(uintptr_t)segments[i].address;
        desc->length_or_capacity = segments[i].length;
        desc->status = 0u;
        desc->control = 0u;
        meta->ticket = base_ticket;
        meta->requested_length = segments[i].length;
        meta->cookie = cookie;
        meta->first = i == 0u;
        meta->last = i == segment_count - 1u;
        meta->state = V34_DESC_PREPARED;
    }

    /* OWN is the final descriptor field written. The frame is still invisible
       to hardware until one later TAIL write publishes the complete chain. */
    for (i = 0u; i < segment_count; i++) {
        uint32_t index = (base_ticket + i) & (V34_SGDMA_RING_ENTRIES - 1u);
        uint32_t control = SG_DESC_OWN |
            (ring->direction == V34_SGDMA_TX ? SG_DESC_TX : SG_DESC_RX);
        if (i == 0u)
            control |= SG_DESC_FIRST | (checksum_control & 0x3ffe0u);
        if (i == segment_count - 1u)
            control |= SG_DESC_LAST;
        ring->descriptors[index].control = control;
    }
    fence_rw();
    ring->prepared_tail += segment_count;
    ring->stats->descriptors_prepared += segment_count;
    ring->stats->frames_prepared++;
    if (segment_count > ring->stats->max_segments_per_frame)
        ring->stats->max_segments_per_frame = segment_count;
    if (ticket != (uint32_t *)0)
        *ticket = base_ticket;
    update_high_watermarks(ring);
    return 0;
}

int v34_sgdma_prepare_tx_frame(const v34_sgdma_segment_t *segments,
                               uint32_t segment_count, void *cookie,
                               uint32_t *ticket, uint32_t checksum_control)
{
    return ring_prepare_frame(&tx_ring, segments, segment_count, cookie, ticket, checksum_control);
}

int v34_sgdma_prepare_rx_frame(const v34_sgdma_segment_t *segments,
                               uint32_t segment_count, void *cookie,
                               uint32_t *ticket, uint32_t checksum_control)
{
    return ring_prepare_frame(&rx_ring, segments, segment_count, cookie, ticket, checksum_control);
}

static int ring_kick(v34_ring_context_t *ring)
{
    uint32_t cursor;

    if (ring->prepared_tail == ring->published_tail)
        return 0;
    cursor = ring->published_tail;
    while (cursor != ring->prepared_tail) {
        uint32_t index = cursor & (V34_SGDMA_RING_ENTRIES - 1u);
        if (ring->metadata[index].state != V34_DESC_PREPARED) {
            ring->stats->consistency_errors++;
            return -1;
        }
        ring->metadata[index].state = V34_DESC_PUBLISHED;
        cursor++;
    }

    fence_rw();
    ring_write_tail(ring, ring->prepared_tail);
    ring->published_tail = ring->prepared_tail;
    ring->stats->doorbell_writes++;
    update_high_watermarks(ring);
    return 0;
}

int v34_sgdma_kick_tx(void) { return ring_kick(&tx_ring); }
int v34_sgdma_kick_rx(void) { return ring_kick(&rx_ring); }

static int ring_try_reclaim(v34_ring_context_t *ring,
                            v34_sgdma_completion_t *completion)
{
    uint32_t hardware_head;

    if (completion == (v34_sgdma_completion_t *)0)
        return -1;
    hardware_head = ring_hardware_head(ring);
    if ((hardware_head - ring->reclaim_head) == 0u) {
        ring->stats->reclaim_empty_polls++;
        return 0;
    }
    if ((hardware_head - ring->reclaim_head) >
        (ring->published_tail - ring->reclaim_head) ||
        (hardware_head - ring->reclaim_head) > V34_SGDMA_RING_ENTRIES) {
        ring->stats->consistency_errors++;
        return -2;
    }

    while (ring->reclaim_head != hardware_head) {
        uint32_t index = ring->reclaim_head & (V34_SGDMA_RING_ENTRIES - 1u);
        v34_sgdma_desc_t *desc = &ring->descriptors[index];
        v34_desc_meta_t *meta = &ring->metadata[index];
        uint32_t status;
        uint32_t is_last;

        fence_rw();
        if (meta->state != V34_DESC_PUBLISHED ||
            (desc->control & SG_DESC_OWN) != 0u) {
            ring->stats->consistency_errors++;
            return -3;
        }
        if (!ring->reclaim_frame_active) {
            if (!meta->first) {
                ring->stats->consistency_errors++;
                return -4;
            }
            ring->reclaim_frame_active = 1u;
            ring->reclaim_ticket = meta->ticket;
            ring->reclaim_requested = 0u;
            ring->reclaim_actual = 0u;
            ring->reclaim_status = SG_DESC_DONE;
            ring->reclaim_segments = 0u;
            ring->reclaim_cookie = meta->cookie;
        } else if (meta->first || meta->ticket != ring->reclaim_ticket ||
                   meta->cookie != ring->reclaim_cookie) {
            ring->stats->consistency_errors++;
            return -5;
        }

        status = desc->status;
        is_last = meta->last;
        if (is_last && (status & SG_CSUM_DONE) && !(ring->reclaim_status & SG_DESC_ERROR))
            ring->reclaim_status = status & 0xffffu;
        ring->reclaim_requested += meta->requested_length;
        ring->reclaim_actual += status >> 16;
        ring->reclaim_segments++;
        if ((status & (SG_DESC_DONE | SG_DESC_ERROR)) != SG_DESC_DONE &&
            (ring->reclaim_status & SG_DESC_ERROR) == 0u)
            ring->reclaim_status = status & 0xffffu;
        last_status = status;

        meta->state = V34_DESC_FREE;
        meta->cookie = (void *)0;
        meta->first = 0u;
        meta->last = 0u;
        desc->buffer_addr = 0u;
        desc->length_or_capacity = 0u;
        desc->status = 0u;
        desc->control = 0u;
        ring->reclaim_head++;
        ring->stats->descriptors_reclaimed++;

        if (is_last) {
            completion->ticket = ring->reclaim_ticket;
            completion->direction = ring->direction;
            completion->requested_length = ring->reclaim_requested;
            completion->actual_length = ring->reclaim_actual;
            completion->status = (ring->reclaim_actual << 16) |
                                 (ring->reclaim_status & 0xffffu);
            completion->segment_count = ring->reclaim_segments;
            completion->cookie = ring->reclaim_cookie;
            if ((completion->status & (SG_DESC_DONE | SG_DESC_ERROR)) !=
                SG_DESC_DONE) {
                ring->stats->completion_errors++;
                last_error = SG_REG_ERROR;
            }
            ring->stats->frames_reclaimed++;
            ring->reclaim_frame_active = 0u;
            ring->reclaim_cookie = (void *)0;
            return 1;
        }
    }
    return 0;
}

int v34_sgdma_try_reclaim_tx(v34_sgdma_completion_t *completion)
{ return ring_try_reclaim(&tx_ring, completion); }
int v34_sgdma_try_reclaim_rx(v34_sgdma_completion_t *completion)
{ return ring_try_reclaim(&rx_ring, completion); }

void v34_sgdma_recover(void)
{
    last_error = SG_REG_ERROR;
    SG_REG_CTRL = SG_CTRL_ENABLE | SG_CTRL_CLEAR;
    driver_stats.async_recoveries++;
}

const v34_sgdma_stats_t *v34_sgdma_stats(void) { return &driver_stats; }

static void value(const char *name, uint32_t value_to_print)
{
    v25_platform_uart_puts(name);
    v25_platform_uart_hex32(value_to_print);
}

static void report_ring(const char *prefix, const v34_sgdma_ring_stats_t *stats,
                        uint32_t hw_done, uint32_t hw_bytes,
                        uint32_t hw_errors, uint32_t tail_writes,
                        uint32_t head, uint32_t tail)
{
    v25_platform_uart_puts(prefix);
    value(" FRAME_PREP=", stats->frames_prepared);
    value(" FRAME_DONE=", stats->frames_reclaimed);
    value(" SEG_PREP=", stats->descriptors_prepared);
    value(" SEG_DONE=", stats->descriptors_reclaimed);
    value(" MAX_SEG=", stats->max_segments_per_frame);
    v25_platform_uart_puts("\n");
    v25_platform_uart_puts(prefix);
    value(" DOORBELL=", stats->doorbell_writes);
    value(" FULL=", stats->ring_full);
    value(" MAX_PREP=", stats->max_prepared_pending);
    value(" MAX_PUB=", stats->max_published_pending);
    value(" EMPTY=", stats->reclaim_empty_polls);
    value(" CONSISTENCY=", stats->consistency_errors);
    v25_platform_uart_puts("\n");
    v25_platform_uart_puts(prefix);
    value(" HW_SEG=", hw_done);
    value(" BYTES=", hw_bytes);
    value(" ERR=", hw_errors);
    value(" TAIL_WRITES=", tail_writes);
    value(" HEAD=", head);
    value(" TAIL=", tail);
    v25_platform_uart_puts("\n");
}

void v34_sgdma_report(void)
{
    report_ring("SG TX", &driver_stats.tx, SG_REG_TX_DESC_DONE,
                SG_REG_TX_BYTES, SG_REG_TX_ERRORS, SG_REG_TX_TAIL_WRITES,
                SG_REG_TX_HEAD, SG_REG_TX_TAIL);
    report_ring("SG RX", &driver_stats.rx, SG_REG_RX_DESC_DONE,
                SG_REG_RX_BYTES, SG_REG_RX_ERRORS, SG_REG_RX_TAIL_WRITES,
                SG_REG_RX_HEAD, SG_REG_RX_TAIL);
    value("SG HW TX_FRAME=", SG_REG_TX_FRAME_COUNT);
    value(" RX_FRAME=", SG_REG_RX_FRAME_COUNT);
    value(" TX_SEG=", SG_REG_TX_SEGMENT_COUNT);
    value(" RX_SEG=", SG_REG_RX_SEGMENT_COUNT);
    value(" CHAIN_ERR=", SG_REG_CHAIN_ERROR_COUNT);
    v25_platform_uart_puts("\n");
    value("SG HW TX_CANCEL=", SG_REG_TX_CANCEL_COUNT);
    value(" RX_DROP=", SG_REG_RX_DROP_COUNT);
    value(" MAX_TX_SEG=", SG_REG_MAX_TX_SEGMENTS);
    value(" MAX_RX_SEG=", SG_REG_MAX_RX_SEGMENTS);
    v25_platform_uart_puts("\n");
    value("SG LAST_ERR=", last_error);
    value(" LAST_RING=", SG_REG_LAST_ERROR_RING);
    value(" LAST_DESC=", SG_REG_LAST_ERROR_DESC);
    value(" LAST_STATUS=", last_status);
    value(" RECOVER=", driver_stats.async_recoveries);
    v25_platform_uart_puts("\n");
    value("SG CYC BUSY=", SG_REG_BUSY_CYCLES);
    value(" IDLE=", SG_REG_IDLE_CYCLES);
    value(" WAIT_TX=", SG_REG_WAIT_TX_CYCLES);
    value(" WAIT_RX=", SG_REG_WAIT_RX_CYCLES);
    v25_platform_uart_puts("\n");
    value("SG DESC_CYC FETCH=", SG_REG_FETCH_CYCLES);
    value(" WB=", SG_REG_WB_CYCLES);
    value(" TX_GRANTS=", SG_REG_TX_GRANTS);
    value(" RX_GRANTS=", SG_REG_RX_GRANTS);
    value(" BOTH_READY=", SG_REG_BOTH_READY_CYCLES);
    v25_platform_uart_puts("\n");
}
