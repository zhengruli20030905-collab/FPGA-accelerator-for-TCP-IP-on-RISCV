#include "lwip/arch.h"
#include "net/v25_platform.h"
#include "port/v25_time.h"
#include "port/v40_clock_config.h"

static v25_time_state_t system_time;

void v25_time_reset(v25_time_state_t *state, uint32_t cycles)
{
    state->previous_cycles = cycles;
    state->remainder_cycles = 0u;
    state->milliseconds = 0u;
    state->initialized = 1u;
}

uint32_t v25_time_update(v25_time_state_t *state, uint32_t cycles)
{
    uint32_t delta;

    if (state->initialized == 0u) {
        v25_time_reset(state, cycles);
        return 0u;
    }

    /* Unsigned subtraction is intentionally wrap-safe for one 32-bit wrap. */
    delta = cycles - state->previous_cycles;
    state->previous_cycles = cycles;
    state->remainder_cycles += delta;

    /* sys_now() is called continuously by the main loop, so this loop is
       normally zero or one iteration and avoids RV32M division instructions. */
    while (state->remainder_cycles >= V40_CYCLES_PER_MS) {
        state->remainder_cycles -= V40_CYCLES_PER_MS;
        state->milliseconds++;
    }

    return state->milliseconds;
}

u32_t sys_now(void)
{
    return (u32_t)v25_time_update(&system_time,
                                  v25_platform_timer_cycles());
}

int v25_time_wrap_self_test(void)
{
    v25_time_state_t test = {0u, 0u, 0u, 0u};
    uint32_t before;
    uint32_t after;

    /* Directed v40 25 MHz conversion checks: 25,000 cycles is exactly 1 ms. */
    v25_time_reset(&test, 0u);
    if (v25_time_update(&test, V40_CYCLES_PER_MS - 1u) != 0u)
        return 0;
    if (v25_time_update(&test, V40_CYCLES_PER_MS) != 1u)
        return 0;
    if (v25_time_update(&test, V40_CYCLES_PER_MS * 2u) != 2u)
        return 0;

    test.initialized = 0u;
    v25_time_reset(&test, 0xfffff000u);
    before = v25_time_update(&test, 0xfffffff0u);
    /* Cross the 32-bit cycle-counter wrap by enough cycles to exceed one
       25 MHz millisecond.  The old 0x4000 endpoint only accumulated 20,480
       cycles and therefore correctly remained at 0 ms after the v40 change. */
    after = v25_time_update(&test, 0x00008000u);

    return (after >= before) && (after != 0u);
}
