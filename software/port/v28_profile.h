#ifndef V28_PROFILE_H
#define V28_PROFILE_H
#include <stdint.h>
enum v28_phase {PROF_RX_PIO, PROF_RX_DMA, PROF_PBUF_ALLOC, PROF_RX_COPY,
    PROF_STACK_EXCL, PROF_TX_COPY, PROF_TX_PIO, PROF_TX_DMA, PROF_TX_WAIT, PROF_COUNT};
#ifdef V31_SGDMA
extern uint32_t v28_profile_enabled;
extern uint64_t v28_tx_inclusive_ticks;
void v28_profile_init(uint32_t enable);
uint32_t v28_profile_begin(void);
uint32_t v28_profile_elapsed(uint32_t start);
void v28_profile_add(enum v28_phase phase, uint32_t ticks);
void v28_profile_report(void);
#endif
#endif
