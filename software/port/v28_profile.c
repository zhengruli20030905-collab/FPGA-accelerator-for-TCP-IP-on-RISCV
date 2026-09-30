#include "port/v28_profile.h"
#include "net/v25_platform.h"
#include "port/v40_clock_config.h"
uint32_t v28_profile_enabled;
uint64_t v28_tx_inclusive_ticks;
static struct { uint64_t ticks; uint32_t samples; } counters[PROF_COUNT];
static uint32_t saturated, timer_pair_min, disabled_loop, enabled_loop;
static const char *names[PROF_COUNT] = {"RX_PIO", "RX_SGDMA_WAIT", "PBUF_ALLOC", "RX_COPY",
    "STACK_EXCL", "TX_COPY", "TX_PIO", "TX_SGDMA_WAIT", "TX_WAIT"};
uint32_t v28_profile_begin(void)
{
    return v28_profile_enabled ? v25_platform_timer_cycles() : 0u;
}
uint32_t v28_profile_elapsed(uint32_t start)
{
    return v28_profile_enabled ? (uint32_t)(v25_platform_timer_cycles() - start) : 0u;
}
void v28_profile_add(enum v28_phase phase, uint32_t ticks)
{
    if (!v28_profile_enabled) return;
    if (UINT64_MAX - counters[phase].ticks < ticks) {
        counters[phase].ticks = UINT64_MAX; saturated = 1u;
    } else counters[phase].ticks += ticks;
    if (counters[phase].samples != UINT32_MAX) counters[phase].samples++;
    else saturated = 1u;
}
void v28_profile_init(uint32_t enable)
{
    uint32_t i, a, b;
    volatile uint32_t sink = 0u;
    timer_pair_min = UINT32_MAX;
    for (i = 0u; i < 64u; i++) {
        a = v25_platform_timer_cycles(); b = v25_platform_timer_cycles();
        if ((uint32_t)(b-a) < timer_pair_min) timer_pair_min = b-a;
    }
    v28_profile_enabled = 0u; a = v25_platform_timer_cycles();
    for (i=0u;i<64u;i++) { b=v28_profile_begin(); sink += v28_profile_elapsed(b); }
    disabled_loop = v25_platform_timer_cycles()-a;
    v28_profile_enabled = 1u; a = v25_platform_timer_cycles();
    for (i=0u;i<64u;i++) { b=v28_profile_begin(); sink += v28_profile_elapsed(b); }
    enabled_loop = v25_platform_timer_cycles()-a;
    v28_profile_enabled = enable != 0u;
    (void)sink;
}
static void value(const char *name, uint32_t v)
{
    v25_platform_uart_puts(name); v25_platform_uart_hex32(v);
}
void v28_profile_report(void)
{
    uint32_t i;
    value("PROFILE ENABLE=",v28_profile_enabled);
    value(" TIMER_PAIR_MIN=",timer_pair_min); value(" OFF_LOOP64=",disabled_loop);
    value(" ON_LOOP64=",enabled_loop); value(" SAT=",saturated);
    v25_platform_uart_puts(" TICK_HZ=25000000 VALUES=HEX\n");
    if (!v28_profile_enabled) return;
    /* NO_SYS single thread: no interrupt/DMA writes these statistics. Each
       64-bit snapshot is stable while printed. UART time is not profiled. */
    for(i=0u;i<PROF_COUNT;i++) {
        v25_platform_uart_puts("PROFILE ");v25_platform_uart_puts(names[i]);
        value(" TICKS_HI=",(uint32_t)(counters[i].ticks>>32));
        value(" LO=",(uint32_t)counters[i].ticks);
        value(" N=",counters[i].samples);v25_platform_uart_puts("\n");
    }
}
