#include <stdint.h>
#include <string.h>
#include "lwip/etharp.h"
#include "lwip/pbuf.h"
#include "net/ethernetif.h"
#include "port/v40_clock_config.h"
#include "net/packet_sgdma.h"
#include "net/tx_buffer_pool.h"
#include "net/v25_platform.h"
#include "port/v28_profile.h"

#define MMIO(a) (*(volatile uint32_t *)(a))
#define TX_DATA MMIO(0x10003050u)
#define TX_LEN MMIO(0x10003054u)
#define TX_CMD MMIO(0x10003058u)
#define TX_STATUS MMIO(0x1000305cu)
#define RX_DATA MMIO(0x10003070u)
#define RX_LEN MMIO(0x10003074u)
#define RX_CMD MMIO(0x10003078u)
#define RX_STATUS MMIO(0x1000307cu)
#define BOARD_SW MMIO(0x10002008u)

#define TIMEOUT_TICKS V40_MS_TO_CYCLES(100u)
#define V34_FRAME_BUFFER_BYTES 2048u
#define V34_FRAME_BUFFER_WORDS (V34_FRAME_BUFFER_BYTES / 4u)
#define V34_RX_FRAME_COUNT 8u
#define V34_RX_PREPOST_TARGET V34_RX_FRAME_COUNT
#define V34_TX_PUBLISH_BATCH 4u
#define V34_RX_POLL_BUDGET 8u

typedef enum {
    V34_RX_FREE = 0,
    V34_RX_ALLOCATED,
    V34_RX_PREPARING,
    V34_RX_POSTED,
    V34_RX_DMA_COMPLETE,
    V34_RX_DELIVERING,
    V34_RX_OWNED_BY_LWIP,
    V34_RX_ERROR_RELEASE
} v34_rx_state_t;

typedef struct {
    struct pbuf *p;
    uint32_t state;
    uint32_t length;
    uint32_t descriptor_status;
    uint32_t ticket;
    uint32_t segment_count;
    uint32_t context_index;
} v34_rx_frame_t;

/* PIO still needs one contiguous software frame. SGDMA never accesses these. */
static uint32_t pio_tx_words[V34_FRAME_BUFFER_WORDS] __attribute__((aligned(4)));
static uint32_t pio_rx_words[V34_FRAME_BUFFER_WORDS] __attribute__((aligned(4)));
static const uint8_t tx_zero_padding[60] __attribute__((aligned(4))) = {0};
static v34_rx_frame_t rx_frames[V34_RX_FRAME_COUNT];
static v34_rx_frame_t *rx_completed[V34_RX_FRAME_COUNT];
static uint32_t rx_completed_read;
static uint32_t rx_completed_write;
static uint32_t rx_completed_count;
static uint32_t rx_dma_inflight;
static uint32_t tx_dma_inflight;
static uint32_t tx_prepared_batch;
static uint32_t rx_posted_initialized;
static v25_ethernetif_stats_t driver_stats;
static uint32_t sgdma_mode;
static uint32_t pio_rx;
static uint32_t pio_tx;
static uint32_t sgdma_rx;
static uint32_t sgdma_tx;
static uint32_t tx_gather_segments;
static uint32_t rx_scatter_segments;
static uint32_t tx_full_frame_copy_calls;
static uint32_t rx_full_frame_copy_calls;

static uint32_t pbuf_node_count(const struct pbuf *p)
{
    uint32_t count = 0u;
    while (p != (const struct pbuf *)0) {
        count++;
        p = p->next;
    }
    return count;
}

static void note_rx_pbuf_allocation(const struct pbuf *p)
{
    uint32_t nodes = pbuf_node_count(p);
    driver_stats.rx_pbuf_alloc_frames++;
    driver_stats.rx_pbuf_nodes += nodes;
    if (nodes == 1u)
        driver_stats.rx_single_pbuf_frames++;
    else
        driver_stats.rx_multi_pbuf_frames++;
    if (nodes > driver_stats.rx_max_pbuf_nodes)
        driver_stats.rx_max_pbuf_nodes = nodes;
}

static int wait_bits(volatile uint32_t *reg, uint32_t mask, uint32_t value)
{
    uint32_t start = v25_platform_timer_cycles();
    while ((*reg & mask) != value) {
        if ((uint32_t)(v25_platform_timer_cycles() - start) >= TIMEOUT_TICKS)
            return -1;
    }
    return 0;
}

static int descriptor_succeeded(uint32_t status)
{
    return (status & (SG_DESC_DONE | SG_DESC_ERROR)) == SG_DESC_DONE;
}

static v34_rx_frame_t *find_free_rx_frame(void)
{
    uint32_t i;
    for (i = 0u; i < V34_RX_FRAME_COUNT; i++) {
        if (rx_frames[i].state == V34_RX_FREE)
            return &rx_frames[i];
    }
    return (v34_rx_frame_t *)0;
}

static int rx_frame_cookie_valid(v34_rx_frame_t *frame)
{
    uintptr_t address = (uintptr_t)frame;
    uintptr_t base = (uintptr_t)&rx_frames[0];
    uintptr_t end = (uintptr_t)&rx_frames[V34_RX_FRAME_COUNT];
    uint32_t index;

    if (address < base || address >= end ||
        ((address - base) % sizeof(v34_rx_frame_t)) != 0u)
        return 0;
    index = (uint32_t)((address - base) / sizeof(v34_rx_frame_t));
    return frame->context_index == index;
}

static void update_rx_posted_extrema(void)
{
    if (!rx_posted_initialized) {
        driver_stats.rx_posted_min = driver_stats.rx_posted_current;
        driver_stats.rx_posted_max = driver_stats.rx_posted_current;
        rx_posted_initialized = 1u;
        return;
    }
    if (driver_stats.rx_posted_current < driver_stats.rx_posted_min)
        driver_stats.rx_posted_min = driver_stats.rx_posted_current;
    if (driver_stats.rx_posted_current > driver_stats.rx_posted_max)
        driver_stats.rx_posted_max = driver_stats.rx_posted_current;
}

static void update_inflight_high_watermarks(void)
{
    if (tx_dma_inflight > driver_stats.max_tx_inflight)
        driver_stats.max_tx_inflight = tx_dma_inflight;
    if (rx_dma_inflight > driver_stats.max_rx_inflight)
        driver_stats.max_rx_inflight = rx_dma_inflight;
}

static void release_rx_frame(v34_rx_frame_t *frame)
{
    if (frame->p != (struct pbuf *)0)
        pbuf_free(frame->p);
    frame->p = (struct pbuf *)0;
    frame->state = V34_RX_FREE;
    frame->length = 0u;
    frame->descriptor_status = 0u;
    frame->ticket = 0u;
    frame->segment_count = 0u;
}

static void queue_completed_rx(v34_rx_frame_t *frame)
{
    if (rx_completed_count >= V34_RX_FRAME_COUNT) {
        frame->state = V34_RX_ERROR_RELEASE;
        driver_stats.rx_buffer_full++;
        driver_stats.rx_buffer_starvation++;
        driver_stats.rx_drops++;
        driver_stats.rx_errors++;
        release_rx_frame(frame);
        return;
    }
    rx_completed[rx_completed_write] = frame;
    rx_completed_write = (rx_completed_write + 1u) % V34_RX_FRAME_COUNT;
    rx_completed_count++;
}

static void reclaim_sgdma_completions(void)
{
    v34_sgdma_completion_t completion;
    int result;
    uint32_t rx_reclaimed = 0u;

    /* Completion is frame-level: the ring driver consumes all segment
       completions but returns to this layer only after the LAST descriptor. */
    for (;;) {
        result = v34_sgdma_try_reclaim_tx(&completion);
        if (result <= 0)
            break;
        if (tx_dma_inflight != 0u)
            tx_dma_inflight--;
        else
            driver_stats.tx_completion_errors++;
        if (completion.direction != V34_SGDMA_TX ||
            completion.cookie == (void *)0) {
            driver_stats.tx_completion_errors++;
            driver_stats.tx_errors++;
        } else if (descriptor_succeeded(completion.status)) {
            driver_stats.tx_completed++;
            driver_stats.tx_frames++;
            driver_stats.tx_bytes += completion.actual_length;
        } else {
            driver_stats.tx_completion_errors++;
            driver_stats.tx_errors++;
        }
        /* linkoutput took exactly one reference for the whole descriptor
           chain. It is released once, and only once, at frame completion. */
        if (completion.cookie != (void *)0) {
            v40_tx_pool_note_udp_dma_result(
                (struct pbuf *)completion.cookie,
                descriptor_succeeded(completion.status));
            pbuf_free((struct pbuf *)completion.cookie);
        }
    }
    if (result < 0)
        driver_stats.tx_completion_errors++;

    for (;;) {
        result = v34_sgdma_try_reclaim_rx(&completion);
        if (result <= 0)
            break;
        {
            v34_rx_frame_t *frame = (v34_rx_frame_t *)completion.cookie;
            int valid_frame = rx_frame_cookie_valid(frame);
            rx_reclaimed++;
            if (rx_dma_inflight != 0u) {
                rx_dma_inflight--;
            } else {
                driver_stats.rx_slot_state_errors++;
            }
            if (driver_stats.rx_posted_current != 0u) {
                driver_stats.rx_posted_current--;
                update_rx_posted_extrema();
            } else {
                driver_stats.rx_slot_state_errors++;
            }
            driver_stats.rx_completed++;
            driver_stats.rx_dequeues++;
            if (completion.direction != V34_SGDMA_RX ||
                !valid_frame ||
                frame->state != V34_RX_POSTED ||
                frame->ticket != completion.ticket ||
                frame->segment_count != completion.segment_count) {
                driver_stats.rx_completion_errors++;
                driver_stats.rx_errors++;
                driver_stats.rx_slot_state_errors++;
                if (valid_frame)
                    release_rx_frame(frame);
            } else {
                frame->length = completion.actual_length;
                frame->descriptor_status = completion.status;
                frame->state = V34_RX_DMA_COMPLETE;
                if (!descriptor_succeeded(completion.status)) {
                    driver_stats.rx_completion_errors++;
                    driver_stats.rx_errors++;
                    driver_stats.rx_drops++;
                    frame->state = V34_RX_ERROR_RELEASE;
                    release_rx_frame(frame);
                } else {
                    queue_completed_rx(frame);
                }
            }
        }
    }
    if (result < 0)
        driver_stats.rx_completion_errors++;
    if (rx_reclaimed != 0u) {
        driver_stats.rx_reclaim_batches++;
        if (rx_reclaimed > driver_stats.rx_max_reclaim_batch)
            driver_stats.rx_max_reclaim_batch = rx_reclaimed;
    }
    if ((SG_REG_STATUS & SG_STATUS_ERROR) != 0u)
        v34_sgdma_recover();
}

static uint32_t prepare_free_rx_slots(void)
{
    uint32_t prepared = 0u;
    v34_rx_frame_t *frame;

    while (rx_dma_inflight < V34_RX_PREPOST_TARGET) {
        v34_sgdma_segment_t segments[V34_SGDMA_MAX_FRAME_SEGMENTS];
        struct pbuf *q;
        uint32_t segment_count = 0u;

        frame = find_free_rx_frame();
        if (frame == (v34_rx_frame_t *)0) {
            driver_stats.rx_buffer_starvation++;
            break;
        }

        driver_stats.rx_refill_attempts++;
        frame->state = V34_RX_ALLOCATED;
        frame->p = pbuf_alloc(PBUF_RAW,
                              (u16_t)(1514u + ETH_PAD_SIZE), PBUF_POOL);
        if (frame->p == (struct pbuf *)0) {
            frame->state = V34_RX_FREE;
            driver_stats.pbuf_alloc_failures++;
            driver_stats.rx_refill_fail++;
            break;
        }
        note_rx_pbuf_allocation(frame->p);
        if (pbuf_remove_header(frame->p, ETH_PAD_SIZE) != 0u) {
            release_rx_frame(frame);
            driver_stats.rx_refill_fail++;
            break;
        }
        for (q = frame->p; q != (struct pbuf *)0; q = q->next) {
            if (q->len == 0u)
                continue;
            if (segment_count >= V34_SGDMA_MAX_FRAME_SEGMENTS) {
                release_rx_frame(frame);
                driver_stats.rx_refill_fail++;
                return prepared;
            }
            segments[segment_count].address = q->payload;
            segments[segment_count].length = q->len;
            segment_count++;
        }
        frame->state = V34_RX_PREPARING;
        frame->length = 0u;
        frame->descriptor_status = 0u;
        frame->segment_count = segment_count;
        if (v34_sgdma_prepare_rx_frame(segments, segment_count,
                                      frame, &frame->ticket,
                                      v40_checksum_hardware ? 0xe0u : 0u) != 0) {
            release_rx_frame(frame);
            driver_stats.rx_refill_fail++;
            break;
        }

        rx_dma_inflight++;
        prepared++;
        driver_stats.rx_refill_success++;
        driver_stats.rx_submitted++;
        sgdma_rx++;
        rx_scatter_segments += segment_count;
        update_inflight_high_watermarks();
    }
    return prepared;
}

static int publish_prepared_rx(void)
{
    uint32_t i;
    uint32_t posted = 0u;

    if (v34_sgdma_rx_prepared_count() == 0u)
        return 0;
    if (v34_sgdma_kick_rx() != 0)
        return -1;
    for (i = 0u; i < V34_RX_FRAME_COUNT; i++) {
        if (rx_frames[i].state == V34_RX_PREPARING) {
            rx_frames[i].state = V34_RX_POSTED;
            posted++;
        }
    }
    if (posted == 0u) {
        driver_stats.rx_slot_state_errors++;
        return -1;
    }
    driver_stats.rx_posted_current += posted;
    if (driver_stats.rx_posted_current > V34_RX_FRAME_COUNT) {
        driver_stats.rx_slot_state_errors++;
        driver_stats.rx_posted_current = V34_RX_FRAME_COUNT;
        return -1;
    }
    update_rx_posted_extrema();
    return 0;
}

static int kick_prepared(void)
{
    uint32_t partial_tx = tx_prepared_batch != 0u &&
                          tx_prepared_batch < V34_TX_PUBLISH_BATCH;
    int rx_result = publish_prepared_rx();
    int tx_result = v34_sgdma_kick_tx();
    if (tx_result == 0) {
        if (partial_tx != 0u)
            v40_tx_pool_note_partial_flush();
        tx_prepared_batch = 0u;
    }
    return (rx_result == 0 && tx_result == 0) ? 0 : -1;
}

void v34_ethernetif_service(struct netif *netif)
{
    (void)netif;
    if (!sgdma_mode)
        return;

    driver_stats.service_calls++;
    reclaim_sgdma_completions();
    (void)prepare_free_rx_slots();
    if (kick_prepared() != 0) {
        driver_stats.tx_errors++;
        driver_stats.rx_errors++;
    }
}

static err_t output_frame(struct netif *netif, struct pbuf *p)
{
    uint32_t len;
    uint32_t wire_len;
    uint32_t start;
    uint32_t i;
    err_t result = ERR_IF;

    (void)netif;
    driver_stats.linkoutput_calls++;
    if (TX_STATUS & 1u)
        driver_stats.linkoutput_busy++;
    if (pbuf_remove_header(p, ETH_PAD_SIZE) != 0u)
        return ERR_BUF;

    len = p->tot_len;
    if (len < 14u || len > 1514u)
        goto finish;
    wire_len = len < 60u ? 60u : len;

    if (sgdma_mode) {
        v34_sgdma_segment_t segments[V34_SGDMA_MAX_FRAME_SEGMENTS];
        struct pbuf *q;
        uint32_t segment_count = 0u;
        uint32_t ticket;
        uint32_t checksum_control = 0u;

        if (v40_checksum_hardware) {
            uint8_t header[34];
            uint32_t copied = len < sizeof(header) ? len : sizeof(header);
            if (pbuf_copy_partial(p, header, (u16_t)copied, 0) != copied)
                goto finish;
            v40_header_parse_calls++;
            v40_header_parse_bytes += copied;
            if (header[12] == 8u && header[13] == 0u) {
                if (copied < 34u || (header[14] >> 4) != 4u ||
                    (header[14] & 15u) < 5u ||
                    (header[20] & 0x3fu) != 0u || header[21] != 0u)
                    goto finish;
                checksum_control = SG_CSUM_IP | (14u << 10);
                if (header[23] == 17u)
                    checksum_control |= SG_CSUM_L4 | (1u << 8);
                else if (header[23] == 6u)
                    checksum_control |= SG_CSUM_L4 | (2u << 8);
                else if (header[23] != 1u)
                    goto finish; /* fail closed: unknown L4, no unchecked send */
            } else if (!(header[12] == 8u && header[13] == 6u))
                goto finish;
        }

        reclaim_sgdma_completions();
        for (q = p; q != (struct pbuf *)0; q = q->next) {
            if (q->len == 0u)
                continue;
            if (segment_count >= V34_SGDMA_MAX_FRAME_SEGMENTS) {
                result = ERR_MEM;
                goto finish;
            }
            segments[segment_count].address = q->payload;
            segments[segment_count].length = q->len;
            segment_count++;
        }
        if (len < 60u) {
            if (segment_count >= V34_SGDMA_MAX_FRAME_SEGMENTS) {
                result = ERR_MEM;
                goto finish;
            }
            segments[segment_count].address = (void *)tx_zero_padding;
            segments[segment_count].length = 60u - len;
            segment_count++;
        }
        if (v34_sgdma_tx_free_slots() < segment_count) {
            driver_stats.tx_pool_full++;
            result = ERR_MEM;
            goto finish;
        }

        /* The caller may release p immediately after ERR_OK. Hold one frame
           reference until LAST completion; no per-segment references exist. */
        pbuf_ref(p);
        start = v28_profile_begin();
        if (v34_sgdma_prepare_tx_frame(segments, segment_count,
                                      p, &ticket, checksum_control) != 0) {
            pbuf_free(p);
            result = ERR_MEM;
            goto finish;
        }
        (void)ticket;
        tx_dma_inflight++;
        tx_prepared_batch++;
        driver_stats.tx_enqueued++;
        sgdma_tx++;
        tx_gather_segments += segment_count;
        update_inflight_high_watermarks();
        v28_profile_add(PROF_TX_DMA, v28_profile_elapsed(start));

        if (tx_prepared_batch >= V34_TX_PUBLISH_BATCH) {
            (void)prepare_free_rx_slots();
            if (kick_prepared() != 0) {
                driver_stats.tx_errors++;
                result = ERR_IF;
                goto finish;
            }
        }
        result = ERR_OK;
    } else {
        start = v28_profile_begin();
        if (wait_bits(&TX_STATUS, 1u, 0u) != 0) {
            v28_profile_add(PROF_TX_WAIT, v28_profile_elapsed(start));
            driver_stats.tx_timeouts++;
            result = ERR_TIMEOUT;
            goto finish;
        }
        v28_profile_add(PROF_TX_WAIT, v28_profile_elapsed(start));
        TX_CMD = 2u;

        start = v28_profile_begin();
        if (pbuf_copy_partial(p, pio_tx_words,
                              (u16_t)len, 0u) != len) {
            result = ERR_BUF;
            goto finish;
        }
        memset((uint8_t *)pio_tx_words + len, 0,
               ((wire_len + 3u) & ~3u) - len);
        v28_profile_add(PROF_TX_COPY, v28_profile_elapsed(start));
        tx_full_frame_copy_calls++;
        for (i = 0u; i < (wire_len + 3u) / 4u; i++)
            TX_DATA = pio_tx_words[i];
        pio_tx++;

        TX_LEN = wire_len;
        TX_CMD = 1u;
        start = v28_profile_begin();
        if (wait_bits(&TX_STATUS, 6u, 2u) != 0) {
            v28_profile_add(PROF_TX_WAIT, v28_profile_elapsed(start));
            driver_stats.tx_timeouts++;
            result = ERR_TIMEOUT;
            goto finish;
        }
        v28_profile_add(PROF_TX_WAIT, v28_profile_elapsed(start));
        driver_stats.tx_frames++;
        driver_stats.tx_bytes += wire_len;
        result = ERR_OK;
    }

finish:
    if (result != ERR_OK) {
        driver_stats.tx_errors++;
    }
    if (pbuf_add_header(p, ETH_PAD_SIZE) != 0u)
        return ERR_BUF;
    return result;
}

static err_t low_level_output(struct netif *netif, struct pbuf *p)
{
    uint32_t start = v28_profile_begin();
    err_t result = output_frame(netif, p);
    v28_tx_inclusive_ticks += v28_profile_elapsed(start);
    return result;
}

static struct pbuf *complete_rx_pbuf(struct netif *netif,
                                     v34_rx_frame_t *frame)
{
    uint32_t i;
    uint32_t len;
    int local = 1;
    int broadcast = 1;
    struct pbuf *p;
    uint8_t *bytes;

    if (!rx_frame_cookie_valid(frame) ||
        frame->state != V34_RX_DMA_COMPLETE ||
        frame->p == (struct pbuf *)0) {
        driver_stats.rx_slot_state_errors++;
        driver_stats.rx_errors++;
        return (struct pbuf *)0;
    }
    frame->state = V34_RX_DELIVERING;
    len = frame->length;
    p = frame->p;
    if (!descriptor_succeeded(frame->descriptor_status) ||
        len < 14u || len > 1514u) {
        driver_stats.rx_errors++;
        goto drop;
    }

    /* DMA wrote directly into the allocated pbuf chain. Trimming changes only
       metadata and frees unused tail pbufs; it does not copy frame bytes. */
    pbuf_realloc(p, (u16_t)len);
    if (pbuf_add_header(p, ETH_PAD_SIZE) != 0u) {
        driver_stats.rx_errors++;
        goto drop;
    }
    bytes = (uint8_t *)p->payload + ETH_PAD_SIZE;
    for (i = 0u; i < 6u; i++) {
        if (bytes[i] != netif->hwaddr[i])
            local = 0;
        if (bytes[i] != 0xffu)
            broadcast = 0;
    }
    if (!local && !broadcast) {
        (void)pbuf_remove_header(p, ETH_PAD_SIZE);
        goto drop;
    }

    driver_stats.rx_frames++;
    driver_stats.rx_bytes += len;
    frame->p = (struct pbuf *)0;
    frame->state = V34_RX_OWNED_BY_LWIP;
    /* The context is reusable immediately; lwIP exclusively owns p now. */
    frame->state = V34_RX_FREE;
    frame->length = 0u;
    frame->descriptor_status = 0u;
    frame->ticket = 0u;
    frame->segment_count = 0u;
    return p;

drop:
    driver_stats.rx_drops++;
    frame->state = V34_RX_ERROR_RELEASE;
    release_rx_frame(frame);
    return (struct pbuf *)0;
}

#ifdef V34_ZERO_COPY
/* Exhaust the pool before rings are enabled, then free every reference and
   prove a full-size chain can be allocated again. This tests recovery without
   publishing half a descriptor chain or leaking an RX ownership context. */
static int rx_pbuf_pool_recovery_self_test(void)
{
    struct pbuf *held[PBUF_POOL_SIZE];
    struct pbuf *probe;
    struct pbuf *unexpected;
    uint32_t held_count = 0u;

    while (held_count < PBUF_POOL_SIZE) {
        held[held_count] = pbuf_alloc(PBUF_RAW, 1u, PBUF_POOL);
        if (held[held_count] == (struct pbuf *)0)
            break;
        held_count++;
    }
    unexpected = pbuf_alloc(PBUF_RAW, 1u, PBUF_POOL);
    if (held_count != PBUF_POOL_SIZE || unexpected != (struct pbuf *)0) {
        if (unexpected != (struct pbuf *)0)
            pbuf_free(unexpected);
        while (held_count != 0u) {
            held_count--;
            pbuf_free(held[held_count]);
        }
        return 0;
    }
    while (held_count != 0u) {
        held_count--;
        pbuf_free(held[held_count]);
    }
    probe = pbuf_alloc(PBUF_RAW, (u16_t)(1514u + ETH_PAD_SIZE), PBUF_POOL);
    if (probe == (struct pbuf *)0)
        return 0;
    if (pbuf_node_count(probe) != 1u) {
        pbuf_free(probe);
        return 0;
    }
    pbuf_free(probe);
    return 1;
}
#endif

static struct pbuf *low_level_input_sgdma(struct netif *netif)
{
    v34_rx_frame_t *frame;
    if (rx_completed_count == 0u)
        return (struct pbuf *)0;
    frame = rx_completed[rx_completed_read];
    rx_completed_read = (rx_completed_read + 1u) % V34_RX_FRAME_COUNT;
    rx_completed_count--;
    return complete_rx_pbuf(netif, frame);
}

static struct pbuf *low_level_input_pio(struct netif *netif)
{
    uint32_t len;
    uint32_t start;
    uint32_t i;
    int local = 1;
    int broadcast = 1;
    struct pbuf *p = (struct pbuf *)0;
    uint8_t *bytes = (uint8_t *)pio_rx_words;

    if (!(RX_STATUS & 1u))
        return (struct pbuf *)0;
    driver_stats.rx_dequeues++;
    len = RX_LEN & 0xffffu;
    if (len < 14u || len > 1514u || (RX_STATUS & 0x184u)) {
        driver_stats.rx_errors++;
        goto drop;
    }

    start = v28_profile_begin();
    RX_CMD = 2u;
    for (i = 0u; i < (len + 3u) / 4u; i++) {
        RX_CMD = 4u;
        if (wait_bits(&RX_STATUS, 0x200u, 0x200u) != 0) {
            v28_profile_add(PROF_RX_PIO, v28_profile_elapsed(start));
            driver_stats.rx_errors++;
            goto drop;
        }
        pio_rx_words[i] = RX_DATA;
    }
    pio_rx++;
    v28_profile_add(PROF_RX_PIO, v28_profile_elapsed(start));

    for (i = 0u; i < 6u; i++) {
        if (bytes[i] != netif->hwaddr[i])
            local = 0;
        if (bytes[i] != 0xffu)
            broadcast = 0;
    }
    if (!local && !broadcast)
        goto drop;

    start = v28_profile_begin();
    p = pbuf_alloc(PBUF_RAW, (u16_t)(len + ETH_PAD_SIZE), PBUF_POOL);
    v28_profile_add(PROF_PBUF_ALLOC, v28_profile_elapsed(start));
    if (p == (struct pbuf *)0) {
        driver_stats.pbuf_alloc_failures++;
        goto drop;
    }
    note_rx_pbuf_allocation(p);
    start = v28_profile_begin();
    if (pbuf_remove_header(p, ETH_PAD_SIZE) != 0u ||
        pbuf_take(p, pio_rx_words, (u16_t)len) != ERR_OK ||
        pbuf_add_header(p, ETH_PAD_SIZE) != 0u) {
        pbuf_free(p);
        p = (struct pbuf *)0;
        driver_stats.rx_errors++;
        goto drop;
    }
    v28_profile_add(PROF_RX_COPY, v28_profile_elapsed(start));
    rx_full_frame_copy_calls++;
    RX_CMD = 1u;
    driver_stats.rx_frames++;
    driver_stats.rx_bytes += len;
    return p;

drop:
    driver_stats.rx_drops++;
    RX_CMD = 1u;
    return (struct pbuf *)0;
}

static void deliver_input(struct netif *netif, struct pbuf *p)
{
    uint64_t tx_before = v28_tx_inclusive_ticks;
    uint32_t start = v28_profile_begin();
    uint32_t elapsed;
    uint32_t nested;

    if (netif->input(p, netif) != ERR_OK) {
        pbuf_free(p);
        driver_stats.input_errors++;
    } else {
        driver_stats.input_ok++;
    }
    elapsed = v28_profile_elapsed(start);
    nested = (uint32_t)(v28_tx_inclusive_ticks - tx_before);
    v28_profile_add(PROF_STACK_EXCL, elapsed >= nested ? elapsed - nested : 0u);
}

void v25_ethernetif_poll(struct netif *netif)
{
    struct pbuf *p;

    if (!sgdma_mode) {
        p = low_level_input_pio(netif);
        if (p != (struct pbuf *)0)
            deliver_input(netif, p);
        return;
    }

    v34_ethernetif_service(netif);
    {
        uint32_t budget = V34_RX_POLL_BUDGET;
        while (budget != 0u && rx_completed_count != 0u) {
            p = low_level_input_sgdma(netif);
            if (p != (struct pbuf *)0)
                deliver_input(netif, p);
            budget--;
        }
        if (rx_completed_count != 0u)
            driver_stats.rx_budget_exhausted++;
    }
    v34_ethernetif_service(netif);
}

err_t v25_ethernetif_init(struct netif *netif)
{
    static const uint8_t mac[6] = {2u, 0x12u, 0x34u, 0x56u, 0x78u, 0x9au};
    uint32_t switches = BOARD_SW;
    uint32_t i;

    if (SG_REG_ID != SG_V34_ID ||
        (SG_REG_CAPABILITY & SG_V34_CAPABILITIES) != SG_V34_CAPABILITIES)
        return ERR_IF;
    sgdma_mode = switches & 1u;
    v40_checksum_hardware = sgdma_mode && ((switches >> 5) & 1u);
    NETIF_SET_CHECKSUM_CTRL(netif, v40_checksum_hardware ?
        (NETIF_CHECKSUM_GEN_ICMP | NETIF_CHECKSUM_CHECK_ICMP) : NETIF_CHECKSUM_ENABLE_ALL);

    for (i = 0u; i < V34_RX_FRAME_COUNT; i++) {
        rx_frames[i].p = (struct pbuf *)0;
        rx_frames[i].state = V34_RX_FREE;
        rx_frames[i].context_index = i;
    }
    for (i = 0u; i < 6u; i++)
        netif->hwaddr[i] = mac[i];
#ifdef V34_ZERO_COPY
    if (!rx_pbuf_pool_recovery_self_test()) {
        v25_platform_uart_puts("V40 RX PBUF POOL RECOVERY SELF-TEST FAIL\n");
        return ERR_IF;
    }
    v25_platform_uart_puts(
        "V40 RX PBUF POOL EXHAUST/RECOVERY SELF-TEST PASS\n");
#endif
    v28_profile_init((switches >> 1) & 1u);
    rx_completed_read = 0u;
    rx_completed_write = 0u;
    rx_completed_count = 0u;
    rx_dma_inflight = 0u;
    tx_dma_inflight = 0u;
    tx_prepared_batch = 0u;
    rx_posted_initialized = 0u;

    if (sgdma_mode && v34_sgdma_init() != 0)
        return ERR_IF;
    if (sgdma_mode) {
        if (prepare_free_rx_slots() != V34_RX_PREPOST_TARGET ||
            publish_prepared_rx() != 0 ||
            rx_dma_inflight != V34_RX_PREPOST_TARGET ||
            driver_stats.rx_posted_current != V34_RX_PREPOST_TARGET) {
            driver_stats.rx_slot_state_errors++;
            return ERR_IF;
        }
    }
    v25_platform_uart_puts(sgdma_mode ?
        "V40 IO_MODE=SGDMA SINGLE-PBUF RX PREPOST=8 TX_POOL=8\n" :
        "V40 IO_MODE=PIO STAGING TX_POOL=8\n");
    v25_platform_uart_puts(
        "V40 IO/PROFILE/TEST LATCHED AT RESET SW0/SW1/SW6/SW5/SW4:SW3\n");
    if (sgdma_mode)
        v25_platform_uart_puts(
            "V40 RX PREPOST READY FRAME_TARGET=8\n");
    v25_platform_uart_puts(
        "V40 TCP_ECHO_MODE=ZERO_COPY ACK_OWNERSHIP OWNER=16 ACK_RECORD=32\n");
    v25_platform_uart_puts("V40 PBUF_POOL SIZE=24 BUFSIZE=1536\n");
    v28_profile_report();

    v25_platform_uart_puts(v40_checksum_hardware ?
        "V40 CHECKSUM_MODE=HARDWARE IP/UDP/TCP; ICMP=SOFTWARE\n" :
        "V40 CHECKSUM_MODE=SOFTWARE\n");
    v25_platform_uart_puts("V40 CHECKSUM CAPABILITY=TX_IP,TX_L4,RX_IP,RX_L4,CROSS_SEGMENT SW5=RESET_LATCHED\n");

    netif->name[0] = 'r';
    netif->name[1] = 'v';
    netif->output = etharp_output;
    netif->linkoutput = low_level_output;
    netif->hwaddr_len = 6u;
    netif->mtu = 1500u;
    netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP |
                   NETIF_FLAG_ETHERNET;
    return ERR_OK;
}

const v25_ethernetif_stats_t *v25_ethernetif_stats(void)
{
    return &driver_stats;
}

static void value(const char *name, uint32_t value_to_print)
{
    v25_platform_uart_puts(name);
    v25_platform_uart_hex32(value_to_print);
}

void v28_io_report(void)
{
    v25_platform_uart_puts("IO PIO_RX=");
    v25_platform_uart_hex32(pio_rx);
    value(" PIO_TX=", pio_tx);
    value(" SG_RX=", sgdma_rx);
    value(" SG_TX=", sgdma_tx);
    v25_platform_uart_puts("\n");
    value("ASYNC TX_ENQ=", driver_stats.tx_enqueued);
    value(" TX_DONE=", driver_stats.tx_completed);
    value(" TX_ERR=", driver_stats.tx_completion_errors);
    value(" TX_POOL_FULL=", driver_stats.tx_pool_full);
    value(" MAX_TX_INFLIGHT=", driver_stats.max_tx_inflight);
    v25_platform_uart_puts("\n");
    value("ASYNC RX_SUB=", driver_stats.rx_submitted);
    value(" RX_DONE=", driver_stats.rx_completed);
    value(" RX_ERR=", driver_stats.rx_completion_errors);
    value(" RX_POOL_FULL=", driver_stats.rx_buffer_full);
    value(" MAX_RX_INFLIGHT=", driver_stats.max_rx_inflight);
    value(" RX_BUDGET=", driver_stats.rx_budget_exhausted);
    v25_platform_uart_puts("\n");
    value("RX PREPOST_TARGET=", V34_RX_PREPOST_TARGET);
    value(" POSTED_CURRENT=", driver_stats.rx_posted_current);
    value(" POSTED_MIN=", driver_stats.rx_posted_min);
    value(" POSTED_MAX=", driver_stats.rx_posted_max);
    value(" INFLIGHT_CURRENT=", rx_dma_inflight);
    v25_platform_uart_puts("\n");
    value("RX REFILL_ATTEMPTS=", driver_stats.rx_refill_attempts);
    value(" SUCCESS=", driver_stats.rx_refill_success);
    value(" FAIL=", driver_stats.rx_refill_fail);
    value(" RECLAIM_BATCHES=", driver_stats.rx_reclaim_batches);
    value(" MAX_RECLAIM_BATCH=", driver_stats.rx_max_reclaim_batch);
    v25_platform_uart_puts("\n");
    value("RX BUFFER_STARVATION=", driver_stats.rx_buffer_starvation);
    value(" SLOT_STATE_ERROR=", driver_stats.rx_slot_state_errors);
    value(" PBUF_ALLOC_FAIL=", driver_stats.pbuf_alloc_failures);
    value(" DROP=", driver_stats.rx_drops);
    value(" DESC_DONE=", driver_stats.rx_completed);
    value(" DESC_ERROR=", driver_stats.rx_completion_errors);
    v25_platform_uart_puts("\n");
    value("V40 PBUF RX_FRAME=", driver_stats.rx_pbuf_alloc_frames);
    value(" RX_NODE=", driver_stats.rx_pbuf_nodes);
    value(" SINGLE=", driver_stats.rx_single_pbuf_frames);
    value(" MULTI=", driver_stats.rx_multi_pbuf_frames);
    value(" MAX_NODE=", driver_stats.rx_max_pbuf_nodes);
    value(" ALLOC_FAIL=", driver_stats.pbuf_alloc_failures);
    v25_platform_uart_puts("\n");
    value("ZERO_COPY TX_GATHER_SEG=", tx_gather_segments);
    value(" RX_SCATTER_SEG=", rx_scatter_segments);
    value(" TX_FULL_COPY_CALLS=", tx_full_frame_copy_calls);
    value(" RX_FULL_COPY_CALLS=", rx_full_frame_copy_calls);
    v25_platform_uart_puts("\n");
    v34_sgdma_report();
    v40_checksum_report();
    for (uint32_t counter = 0u; counter < 17u; counter++) {
        value("CSUM HW_INDEX=",counter);
        value(" VALUE=",SG_REG_CSUM(counter));
        v25_platform_uart_puts("\n");
    }
    v28_profile_report();
}
