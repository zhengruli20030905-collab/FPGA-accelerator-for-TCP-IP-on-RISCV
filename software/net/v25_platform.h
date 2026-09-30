#ifndef V25_PLATFORM_H
#define V25_PLATFORM_H

#include <stdint.h>

typedef struct {
    uint32_t ff_tx_frames;
    uint32_t ff_rx_frames;
    uint32_t ff_rx_drops;
    uint32_t ff_rx_errors;
    uint32_t mii_tx_frames;
    uint32_t mii_tx_active_nibbles;
    uint32_t mii_tx_errors;
    uint32_t mii_rx_frames;
    uint32_t mii_rx_active_nibbles;
    uint32_t mii_rx_errors;
    uint32_t mii_counters_valid;
} v25_platform_hw_counters_t;

uint32_t v25_platform_timer_cycles(void);
uint32_t v25_platform_read_board_switches(void);
void v25_platform_uart_puts(const char *text);
void v25_platform_uart_hex32(uint32_t value);
int v25_platform_read_link(uint32_t *link_up);
void v25_platform_set_link_led(uint32_t link_up);
void v25_platform_mark_ready(void);
uint32_t v25_platform_stack_used_bytes(void);
void v25_platform_read_hw_counters(v25_platform_hw_counters_t *counters);
void v25_platform_assert(const char *message, const char *file, int line);

#endif
