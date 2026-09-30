#ifndef V34_PACKET_SGDMA_H
#define V34_PACKET_SGDMA_H

#include <stdint.h>

#define SG_MMIO(off) (*(volatile uint32_t *)(0x10004000u + (off)))
#define SG_REG_ID                  SG_MMIO(0x00u)
#define SG_REG_CTRL                SG_MMIO(0x04u)
#define SG_REG_STATUS              SG_MMIO(0x08u)
#define SG_REG_ERROR               SG_MMIO(0x0cu)
#define SG_REG_ARB_STATE           SG_MMIO(0x10u)
#define SG_REG_LAST_ERROR_RING     SG_MMIO(0x14u)
#define SG_REG_LAST_ERROR_DESC     SG_MMIO(0x18u)
#define SG_REG_TX_DESC_BASE        SG_MMIO(0x20u)
#define SG_REG_TX_RING_SIZE        SG_MMIO(0x24u)
#define SG_REG_TX_HEAD             SG_MMIO(0x28u)
#define SG_REG_TX_TAIL             SG_MMIO(0x2cu)
#define SG_REG_TX_DESC_DONE        SG_MMIO(0x30u)
#define SG_REG_TX_BYTES            SG_MMIO(0x34u)
#define SG_REG_TX_ERRORS           SG_MMIO(0x38u)
#define SG_REG_TX_TAIL_WRITES      SG_MMIO(0x3cu)
#define SG_REG_RX_DESC_BASE        SG_MMIO(0x40u)
#define SG_REG_RX_RING_SIZE        SG_MMIO(0x44u)
#define SG_REG_RX_HEAD             SG_MMIO(0x48u)
#define SG_REG_RX_TAIL             SG_MMIO(0x4cu)
#define SG_REG_RX_DESC_DONE        SG_MMIO(0x50u)
#define SG_REG_RX_BYTES            SG_MMIO(0x54u)
#define SG_REG_RX_ERRORS           SG_MMIO(0x58u)
#define SG_REG_RX_TAIL_WRITES      SG_MMIO(0x5cu)
#define SG_REG_BUSY_CYCLES         SG_MMIO(0x60u)
#define SG_REG_IDLE_CYCLES         SG_MMIO(0x64u)
#define SG_REG_WAIT_TX_CYCLES      SG_MMIO(0x68u)
#define SG_REG_WAIT_RX_CYCLES      SG_MMIO(0x6cu)
#define SG_REG_FETCH_CYCLES        SG_MMIO(0x70u)
#define SG_REG_WB_CYCLES           SG_MMIO(0x74u)
#define SG_REG_TX_GRANTS           SG_MMIO(0x78u)
#define SG_REG_RX_GRANTS           SG_MMIO(0x7cu)
#define SG_REG_BOTH_READY_CYCLES   SG_MMIO(0x80u)
#define SG_REG_STATE               SG_MMIO(0x84u)
#define SG_REG_CAPABILITY          SG_MMIO(0x88u)
#define SG_REG_TX_FRAME_COUNT      SG_MMIO(0x8cu)
#define SG_REG_RX_FRAME_COUNT      SG_MMIO(0x90u)
#define SG_REG_TX_SEGMENT_COUNT    SG_MMIO(0x94u)
#define SG_REG_RX_SEGMENT_COUNT    SG_MMIO(0x98u)
#define SG_REG_CHAIN_ERROR_COUNT   SG_MMIO(0x9cu)
#define SG_REG_TX_CANCEL_COUNT     SG_MMIO(0xa0u)
#define SG_REG_RX_DROP_COUNT       SG_MMIO(0xa4u)
#define SG_REG_MAX_TX_SEGMENTS     SG_MMIO(0xa8u)
#define SG_REG_MAX_RX_SEGMENTS     SG_MMIO(0xacu)

#define SG_V34_ID             0x53473335u /* Compatibility API name; V35 ABI. */
#define SG_CAP_MULTI_SEGMENT  0x01u
#define SG_CAP_UNALIGNED      0x02u
#define SG_CAP_TX_GATHER      0x04u
#define SG_CAP_RX_SCATTER     0x08u
#define SG_CAP_ZERO_COPY      0x10u
#define SG_CAP_TX_IP_CSUM     0x20u
#define SG_CAP_TX_L4_CSUM     0x40u
#define SG_CAP_RX_IP_CSUM     0x80u
#define SG_CAP_RX_L4_CSUM     0x100u
#define SG_CAP_CSUM_CROSS_SEGMENT 0x200u
#define SG_V34_CAPABILITIES   0x3ffu
#define SG_CSUM_IP            0x20u
#define SG_CSUM_L4            0x40u
#define SG_CSUM_AUTO          0x80u
#define SG_CSUM_DONE          0x80u
#define SG_CSUM_IP_OK         0x100u
#define SG_CSUM_L4_OK         0x200u
#define SG_CSUM_BAD           0x400u
#define SG_CSUM_UNSUPPORTED   0x800u
#define SG_CSUM_UDP_ZERO      0x1000u
#define SG_CSUM_PATCHED       0x2000u
#define SG_CSUM_PARSE         0x4000u
#define SG_REG_CSUM(index)    SG_MMIO(0x100u+4u*(index))

#define SG_CTRL_ENABLE       0x1u
#define SG_CTRL_ABORT        0x2u
#define SG_CTRL_CLEAR        0x4u
#define SG_CTRL_RESET_RING   0x8u
#define SG_STATUS_ERROR      0x20u
#define SG_DESC_OWN          0x1u
#define SG_DESC_RX           0x0u
#define SG_DESC_TX           0x2u
#define SG_DESC_FIRST        0x4u
#define SG_DESC_LAST         0x8u
#define SG_DESC_DONE         0x1u
#define SG_DESC_ERROR        0x2u
#define SG_DESC_ABORTED      0x4u
#define SG_DESC_TIMEOUT      0x8u
#define SG_DESC_CONFLICT     0x10u
#define SG_DESC_BAD          0x20u
#define SG_DESC_SMALL        0x40u

#define SG_ERR_NONE               0u
#define SG_ERR_BAD_BASE           1u
#define SG_ERR_BAD_RING_SIZE      2u
#define SG_ERR_BAD_TAIL           3u
#define SG_ERR_OWN                4u
#define SG_ERR_SEGMENTATION       5u
#define SG_ERR_BAD_BUFFER         6u
#define SG_ERR_BAD_LENGTH         7u
#define SG_ERR_BUFFER_SMALL       8u
#define SG_ERR_DESC_TIMEOUT       9u
#define SG_ERR_PAYLOAD_TIMEOUT   10u
#define SG_ERR_DESC_CONFLICT     11u
#define SG_ERR_PAYLOAD_CONFLICT  12u
#define SG_ERR_PACKET_CONFLICT   13u
#define SG_ERR_ABORTED           14u
#define SG_ERR_OVERLAP           15u
#define SG_ERR_INTERNAL          16u
#define SG_ERR_DIRECTION         17u
#define SG_ERR_MISSING_FIRST     18u
#define SG_ERR_UNEXPECTED_FIRST  19u
#define SG_ERR_MISSING_LAST      20u
#define SG_ERR_CHAIN_TOO_LONG    21u
#define SG_ERR_CHAIN_ABORTED     22u
#define SG_ERR_FRAME_TOO_LARGE   23u
#define SG_ERR_CSUM_CONFIG       24u
#define SG_ERR_CSUM_PARSE        25u
#define SG_ERR_CSUM_PATCH        26u
#define SG_ERR_IP_CSUM           27u
#define SG_ERR_L4_CSUM           28u
#define SG_ERR_CSUM_UNSUPPORTED  29u

#define V34_SGDMA_RING_ENTRIES       32u
#define V34_SGDMA_MAX_FRAME_SEGMENTS 16u
#define V34_SGDMA_RX 0u
#define V34_SGDMA_TX 1u

typedef struct __attribute__((aligned(16))) {
    volatile uint32_t buffer_addr;
    volatile uint32_t length_or_capacity;
    volatile uint32_t control;
    volatile uint32_t status;
} v34_sgdma_desc_t;

typedef struct {
    void *address;
    uint32_t length;
} v34_sgdma_segment_t;

typedef struct {
    uint32_t ticket;
    uint32_t direction;
    uint32_t requested_length;
    uint32_t actual_length;
    uint32_t status;
    uint32_t segment_count;
    void *cookie;
} v34_sgdma_completion_t;

typedef struct {
    uint32_t descriptors_prepared;
    uint32_t descriptors_reclaimed;
    uint32_t frames_prepared;
    uint32_t frames_reclaimed;
    uint32_t completion_errors;
    uint32_t ring_full;
    uint32_t doorbell_writes;
    uint32_t reclaim_empty_polls;
    uint32_t max_prepared_pending;
    uint32_t max_published_pending;
    uint32_t max_segments_per_frame;
    uint32_t consistency_errors;
} v34_sgdma_ring_stats_t;

typedef struct {
    v34_sgdma_ring_stats_t tx;
    v34_sgdma_ring_stats_t rx;
    uint32_t async_recoveries;
    uint32_t blocking_wait_loops;
} v34_sgdma_stats_t;

int v34_sgdma_init(void);
uint32_t v34_sgdma_tx_free_slots(void);
uint32_t v34_sgdma_rx_free_slots(void);
uint32_t v34_sgdma_tx_prepared_count(void);
uint32_t v34_sgdma_rx_prepared_count(void);
uint32_t v34_sgdma_tx_published_pending(void);
uint32_t v34_sgdma_rx_published_pending(void);
int v34_sgdma_prepare_tx_frame(const v34_sgdma_segment_t *segments,
                               uint32_t segment_count, void *cookie,
                               uint32_t *ticket, uint32_t checksum_control);
int v34_sgdma_prepare_rx_frame(const v34_sgdma_segment_t *segments,
                               uint32_t segment_count, void *cookie,
                               uint32_t *ticket, uint32_t checksum_control);
int v34_sgdma_kick_tx(void);
int v34_sgdma_kick_rx(void);
int v34_sgdma_try_reclaim_tx(v34_sgdma_completion_t *completion);
int v34_sgdma_try_reclaim_rx(v34_sgdma_completion_t *completion);
void v34_sgdma_recover(void);
const v34_sgdma_stats_t *v34_sgdma_stats(void);
void v34_sgdma_report(void);

#endif
