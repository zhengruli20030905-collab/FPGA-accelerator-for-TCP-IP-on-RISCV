#include <stddef.h>
#include <stdint.h>
#include "lwip/pbuf.h"
#include "net/tx_buffer_pool.h"
#include "net/v25_platform.h"

typedef struct {
    struct pbuf_custom custom;
    uint32_t state;
    uint32_t protocol;
    uint32_t generation;
    uint32_t completed_generation;
    uint32_t sequence;
    uint32_t length;
    uint32_t acked;
    uint32_t udp_success;
    uint32_t use_count;
    uint32_t storage[V40_TX_SLOT_STORAGE_BYTES / sizeof(uint32_t)];
} v40_tx_slot_t;

#define V40_TX_PROTOCOL_NONE 0u
#define V40_TX_PROTOCOL_UDP  1u
#define V40_TX_PROTOCOL_TCP  2u

static v40_tx_slot_t tx_slots[V40_TX_POOL_SIZE] __attribute__((aligned(4)));
static v40_tx_pool_stats_t tx_stats;
static uint32_t initialized;
static uint64_t producer_ticks;
static uint32_t tcp_order[V40_TX_POOL_SIZE];
static uint32_t tcp_order_read;
static uint32_t tcp_order_write;
static uint32_t tcp_order_count;

static v40_tx_slot_t *slot_from_pbuf(struct pbuf *p)
{
    uint32_t i;

    for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
        if (p == &tx_slots[i].custom.pbuf)
            return &tx_slots[i];
    }
    return (v40_tx_slot_t *)0;
}

static v40_tx_slot_t *slot_from_payload(void *payload, uint32_t *index)
{
    uintptr_t address = (uintptr_t)payload;
    uint32_t i;

    for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
        uintptr_t base = (uintptr_t)&tx_slots[i].storage[0];
        uintptr_t end = base + sizeof(tx_slots[i].storage);
        if (address >= base && address < end) {
            if (index != (uint32_t *)0)
                *index = i;
            return &tx_slots[i];
        }
    }
    return (v40_tx_slot_t *)0;
}

static void update_extrema(void)
{
    if (tx_stats.free_current < tx_stats.min_free)
        tx_stats.min_free = tx_stats.free_current;
    if (tx_stats.ready_current > tx_stats.max_ready)
        tx_stats.max_ready = tx_stats.ready_current;
    if (tx_stats.inflight_current > tx_stats.max_inflight)
        tx_stats.max_inflight = tx_stats.inflight_current;
}

static void release_slot(v40_tx_slot_t *slot, uint32_t success)
{
    if (slot->state != V40_TX_SLOT_UDP_INFLIGHT) {
        tx_stats.state_errors++;
        tx_stats.udp_stale_complete++;
        slot->state = V40_TX_SLOT_ERROR;
        return;
    }
    if (slot->completed_generation == slot->generation) {
        tx_stats.generation_errors++;
        tx_stats.udp_stale_complete++;
        slot->state = V40_TX_SLOT_ERROR;
        return;
    }

    slot->completed_generation = slot->generation;
    slot->state = V40_TX_SLOT_FREE;
    slot->protocol = V40_TX_PROTOCOL_NONE;
    slot->length = 0u;
    if (tx_stats.inflight_current != 0u)
        tx_stats.inflight_current--;
    else
        tx_stats.state_errors++;
    tx_stats.free_current++;
    if (success != 0u)
        tx_stats.udp_complete++;
    else
        tx_stats.udp_error++;
    update_extrema();
}

static void udp_custom_free(struct pbuf *p)
{
    v40_tx_slot_t *slot = slot_from_pbuf(p);

    if (slot == (v40_tx_slot_t *)0) {
        tx_stats.state_errors++;
        tx_stats.udp_stale_complete++;
        return;
    }
    if (slot->state == V40_TX_SLOT_READY) {
        slot->state = V40_TX_SLOT_FREE;
        slot->protocol = V40_TX_PROTOCOL_NONE;
        slot->length = 0u;
        if (tx_stats.ready_current != 0u)
            tx_stats.ready_current--;
        else
            tx_stats.state_errors++;
        tx_stats.free_current++;
        update_extrema();
        return;
    }
    release_slot(slot, slot->udp_success);
}

static v40_tx_slot_t *find_free_slot(void)
{
    uint32_t i;

    for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
        if (tx_slots[i].state == V40_TX_SLOT_FREE)
            return &tx_slots[i];
    }
    return (v40_tx_slot_t *)0;
}

static void fill_realtime_payload(uint8_t *payload, uint32_t sequence,
                                  uint16_t length, uint8_t protocol_tag)
{
    uint32_t offset = 0u;
    uint32_t value;

    /* Every byte is regenerated for every packet. Bytes 12 onward depend on
       both sequence and byte offset, so this is not a static replay path. */
    while (offset < length && (offset < 12u ||
           (((uintptr_t)(payload + offset) & 3u) != 0u))) {
        payload[offset] = (uint8_t)((sequence + offset * 31u + 7u) & 0xffu);
        offset++;
    }
    while (offset + 4u <= length) {
        uint32_t b0 = (sequence + offset * 31u + 7u) & 0xffu;
        uint32_t b1 = (b0 + 31u) & 0xffu;
        uint32_t b2 = (b1 + 31u) & 0xffu;
        uint32_t b3 = (b2 + 31u) & 0xffu;
        value = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
        *(uint32_t *)(void *)(payload + offset) = value;
        offset += 4u;
    }
    while (offset < length) {
        payload[offset] = (uint8_t)((sequence + offset * 31u + 7u) & 0xffu);
        offset++;
    }

    if (length > 0u) payload[0] = (uint8_t)'V';
    if (length > 1u) payload[1] = (uint8_t)'4';
    if (length > 2u) payload[2] = (uint8_t)'0';
    if (length > 3u) payload[3] = protocol_tag;
    if (length > 4u) payload[4] = (uint8_t)sequence;
    if (length > 5u) payload[5] = (uint8_t)(sequence >> 8);
    if (length > 6u) payload[6] = (uint8_t)(sequence >> 16);
    if (length > 7u) payload[7] = (uint8_t)(sequence >> 24);
    if (length > 8u) payload[8] = (uint8_t)sequence;
    if (length > 9u) payload[9] = (uint8_t)(sequence >> 8);
    if (length > 10u) payload[10] = (uint8_t)(sequence >> 16);
    if (length > 11u) payload[11] = (uint8_t)(sequence >> 24);

}

int v40_tx_pool_init(void)
{
    uint32_t i;

    if (initialized != 0u)
        return 0;

    tx_stats.free_current = V40_TX_POOL_SIZE;
    tx_stats.min_free = V40_TX_POOL_SIZE;
    for (i = 0u; i < V40_TX_POOL_SIZE; i++) {
        tx_slots[i].state = V40_TX_SLOT_FREE;
        tx_slots[i].protocol = V40_TX_PROTOCOL_NONE;
        tx_slots[i].generation = 0u;
        tx_slots[i].completed_generation = 0u;
        tx_slots[i].sequence = 0u;
        tx_slots[i].length = 0u;
        tx_slots[i].udp_success = 0u;
        tx_slots[i].use_count = 0u;
        tx_slots[i].custom.custom_free_function = udp_custom_free;
    }
    initialized = 1u;
    tx_stats.init_ok = 1u;
    return 0;
}

struct pbuf *v40_tx_pool_prepare_udp(uint32_t sequence, uint16_t length)
{
    v40_tx_slot_t *slot;
    struct pbuf *p;
    uint32_t start;

    if (initialized == 0u && v40_tx_pool_init() != 0) {
        tx_stats.init_fail++;
        return (struct pbuf *)0;
    }
    slot = find_free_slot();
    if (slot == (v40_tx_slot_t *)0) {
        tx_stats.no_free_events++;
        return (struct pbuf *)0;
    }

    slot->state = V40_TX_SLOT_FILLING;
    slot->protocol = V40_TX_PROTOCOL_UDP;
    slot->generation++;
    if (slot->generation == 0u)
        slot->generation = 1u;
    slot->sequence = sequence;
    slot->length = length;
    slot->custom.custom_free_function = udp_custom_free;
    p = pbuf_alloced_custom(PBUF_TRANSPORT, length, PBUF_REF,
                            &slot->custom, slot->storage,
                            (u16_t)sizeof(slot->storage));
    if (p == (struct pbuf *)0) {
        slot->state = V40_TX_SLOT_FREE;
        slot->protocol = V40_TX_PROTOCOL_NONE;
        slot->length = 0u;
        tx_stats.init_fail++;
        return (struct pbuf *)0;
    }

    start = v25_platform_timer_cycles();
    fill_realtime_payload((uint8_t *)p->payload, sequence, length,
                          (uint8_t)'T');
    producer_ticks += (uint32_t)(v25_platform_timer_cycles() - start);
    tx_stats.producer_ticks_lo = (uint32_t)producer_ticks;
    tx_stats.producer_ticks_hi = (uint32_t)(producer_ticks >> 32);
    tx_stats.producer_frames++;
    tx_stats.producer_bytes += length;

    slot->state = V40_TX_SLOT_READY;
    slot->use_count++;
    if (slot->use_count > 1u)
        tx_stats.reuse_count++;
    tx_stats.free_current--;
    tx_stats.ready_current++;
    update_extrema();
    return p;
}

void *v40_tx_pool_prepare_tcp(uint32_t sequence, uint16_t length)
{
    v40_tx_slot_t *slot;
    uint8_t *payload;
    uint32_t start;

    if (initialized == 0u && v40_tx_pool_init() != 0) {
        tx_stats.init_fail++;
        return (void *)0;
    }
    if (length > V40_TX_SLOT_STORAGE_BYTES) {
        tx_stats.state_errors++;
        return (void *)0;
    }
    slot = find_free_slot();
    if (slot == (v40_tx_slot_t *)0) {
        tx_stats.no_free_events++;
        return (void *)0;
    }

    slot->state = V40_TX_SLOT_FILLING;
    slot->protocol = V40_TX_PROTOCOL_TCP;
    slot->generation++;
    if (slot->generation == 0u)
        slot->generation = 1u;
    slot->sequence = sequence;
    slot->length = length;
    slot->acked = 0u;
    payload = (uint8_t *)&slot->storage[0];
    start = v25_platform_timer_cycles();
    fill_realtime_payload(payload, sequence, length, (uint8_t)'C');
    producer_ticks += (uint32_t)(v25_platform_timer_cycles() - start);
    tx_stats.producer_ticks_lo = (uint32_t)producer_ticks;
    tx_stats.producer_ticks_hi = (uint32_t)(producer_ticks >> 32);
    tx_stats.producer_frames++;
    tx_stats.producer_bytes += length;

    slot->state = V40_TX_SLOT_READY;
    slot->use_count++;
    if (slot->use_count > 1u)
        tx_stats.reuse_count++;
    tx_stats.free_current--;
    tx_stats.ready_current++;
    update_extrema();
    return payload;
}

int v40_tx_pool_mark_tcp_unacked(void *payload)
{
    uint32_t index;
    v40_tx_slot_t *slot = slot_from_payload(payload, &index);

    if (slot == (v40_tx_slot_t *)0 ||
        slot->state != V40_TX_SLOT_READY ||
        slot->protocol != V40_TX_PROTOCOL_TCP ||
        tcp_order_count >= V40_TX_POOL_SIZE) {
        tx_stats.state_errors++;
        return -1;
    }
    slot->state = V40_TX_SLOT_TCP_UNACKED;
    tcp_order[tcp_order_write] = index;
    tcp_order_write = (tcp_order_write + 1u) % V40_TX_POOL_SIZE;
    tcp_order_count++;
    if (tx_stats.ready_current != 0u)
        tx_stats.ready_current--;
    else
        tx_stats.state_errors++;
    tx_stats.inflight_current++;
    tx_stats.tcp_submitted_bytes += slot->length;
    tx_stats.tcp_unacked_bytes += slot->length;
    if (tx_stats.tcp_unacked_bytes > tx_stats.tcp_max_unacked)
        tx_stats.tcp_max_unacked = tx_stats.tcp_unacked_bytes;
    update_extrema();
    return 0;
}

void v40_tx_pool_cancel_ready(void *payload)
{
    v40_tx_slot_t *slot = slot_from_payload(payload, (uint32_t *)0);

    if (slot == (v40_tx_slot_t *)0 || slot->state != V40_TX_SLOT_READY) {
        tx_stats.state_errors++;
        return;
    }
    slot->state = V40_TX_SLOT_FREE;
    slot->protocol = V40_TX_PROTOCOL_NONE;
    slot->length = 0u;
    slot->acked = 0u;
    if (tx_stats.ready_current != 0u)
        tx_stats.ready_current--;
    else
        tx_stats.state_errors++;
    tx_stats.free_current++;
    update_extrema();
}

void v40_tx_pool_tcp_ack(uint32_t bytes)
{
    tx_stats.tcp_ack_callbacks++;
    while (bytes != 0u && tcp_order_count != 0u) {
        uint32_t index = tcp_order[tcp_order_read];
        v40_tx_slot_t *slot = &tx_slots[index];
        uint32_t remaining;
        uint32_t accepted;

        if (slot->state != V40_TX_SLOT_TCP_UNACKED ||
            slot->protocol != V40_TX_PROTOCOL_TCP ||
            slot->acked > slot->length) {
            tx_stats.state_errors++;
            return;
        }
        remaining = slot->length - slot->acked;
        accepted = bytes < remaining ? bytes : remaining;
        slot->acked += accepted;
        bytes -= accepted;
        tx_stats.tcp_acked_bytes += accepted;
        if (tx_stats.tcp_unacked_bytes >= accepted)
            tx_stats.tcp_unacked_bytes -= accepted;
        else {
            tx_stats.tcp_unacked_bytes = 0u;
            tx_stats.state_errors++;
        }
        if (slot->acked == slot->length) {
            slot->completed_generation = slot->generation;
            slot->state = V40_TX_SLOT_FREE;
            slot->protocol = V40_TX_PROTOCOL_NONE;
            slot->length = 0u;
            slot->acked = 0u;
            tcp_order_read = (tcp_order_read + 1u) % V40_TX_POOL_SIZE;
            tcp_order_count--;
            if (tx_stats.inflight_current != 0u)
                tx_stats.inflight_current--;
            else
                tx_stats.state_errors++;
            tx_stats.free_current++;
        }
    }
    if (bytes != 0u)
        tx_stats.generation_errors++;
    update_extrema();
}

void v40_tx_pool_tcp_abort_all(void)
{
    while (tcp_order_count != 0u) {
        uint32_t index = tcp_order[tcp_order_read];
        v40_tx_slot_t *slot = &tx_slots[index];

        if (slot->state != V40_TX_SLOT_TCP_UNACKED ||
            slot->protocol != V40_TX_PROTOCOL_TCP)
            tx_stats.state_errors++;
        else {
            uint32_t remaining = slot->length - slot->acked;
            if (tx_stats.tcp_unacked_bytes >= remaining)
                tx_stats.tcp_unacked_bytes -= remaining;
            else
                tx_stats.tcp_unacked_bytes = 0u;
            slot->state = V40_TX_SLOT_FREE;
            slot->protocol = V40_TX_PROTOCOL_NONE;
            slot->length = 0u;
            slot->acked = 0u;
            if (tx_stats.inflight_current != 0u)
                tx_stats.inflight_current--;
            tx_stats.free_current++;
        }
        tcp_order_read = (tcp_order_read + 1u) % V40_TX_POOL_SIZE;
        tcp_order_count--;
        tx_stats.tcp_abort_recovery++;
    }
    tcp_order_read = 0u;
    tcp_order_write = 0u;
    update_extrema();
}

uint32_t v40_tx_pool_tcp_unacked(void)
{
    return tx_stats.tcp_unacked_bytes;
}

void v40_tx_pool_note_tcp_retry(err_t result)
{
    tx_stats.tcp_retry++;
    if (result == ERR_MEM)
        tx_stats.tcp_err_mem++;
}

int v40_tx_pool_mark_udp_inflight(struct pbuf *p)
{
    v40_tx_slot_t *slot = slot_from_pbuf(p);

    if (slot == (v40_tx_slot_t *)0 ||
        slot->state != V40_TX_SLOT_READY ||
        slot->protocol != V40_TX_PROTOCOL_UDP) {
        tx_stats.state_errors++;
        return -1;
    }
    slot->state = V40_TX_SLOT_UDP_INFLIGHT;
    slot->udp_success = 0u;
    if (tx_stats.ready_current != 0u)
        tx_stats.ready_current--;
    else
        tx_stats.state_errors++;
    tx_stats.inflight_current++;
    update_extrema();
    return 0;
}

void v40_tx_pool_set_udp_result(struct pbuf *p, int success)
{
    v40_tx_slot_t *slot = slot_from_pbuf(p);

    if (slot == (v40_tx_slot_t *)0 ||
        slot->state != V40_TX_SLOT_UDP_INFLIGHT) {
        tx_stats.state_errors++;
        return;
    }
    slot->udp_success = success != 0;
}

void v40_tx_pool_note_udp_dma_result(struct pbuf *p, int success)
{
    v40_tx_slot_t *slot = slot_from_pbuf(p);

    /* Most Ethernet output pbufs are not V40 UDP pool objects. */
    if (slot == (v40_tx_slot_t *)0)
        return;
    if (slot->state != V40_TX_SLOT_UDP_INFLIGHT ||
        slot->protocol != V40_TX_PROTOCOL_UDP) {
        tx_stats.state_errors++;
        return;
    }
    if (success == 0)
        slot->udp_success = 0u;
}

void v40_tx_pool_note_producer_call(uint32_t frames)
{
    tx_stats.producer_calls++;
    if (frames > tx_stats.producer_max_batch)
        tx_stats.producer_max_batch = frames;
}

void v40_tx_pool_note_submit_batch(uint32_t frames)
{
    tx_stats.submit_calls++;
    if (frames > tx_stats.submit_max_batch)
        tx_stats.submit_max_batch = frames;
}

void v40_tx_pool_note_submit_result(err_t result)
{
    if (result == ERR_OK)
        tx_stats.submit_frames++;
    else if (result == ERR_MEM) {
        tx_stats.submit_retry++;
        tx_stats.submit_err_mem++;
    } else {
        tx_stats.submit_retry++;
        tx_stats.submit_other_error++;
    }
}

void v40_tx_pool_note_partial_flush(void)
{
    tx_stats.partial_flush++;
}

const v40_tx_pool_stats_t *v40_tx_pool_stats(void)
{
    return &tx_stats;
}
