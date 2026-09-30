#ifndef V25_TIME_H
#define V25_TIME_H

#include <stdint.h>

typedef struct {
    uint32_t previous_cycles;
    uint32_t remainder_cycles;
    uint32_t milliseconds;
    uint32_t initialized;
} v25_time_state_t;

void v25_time_reset(v25_time_state_t *state, uint32_t cycles);
uint32_t v25_time_update(v25_time_state_t *state, uint32_t cycles);
int v25_time_wrap_self_test(void);

#endif
