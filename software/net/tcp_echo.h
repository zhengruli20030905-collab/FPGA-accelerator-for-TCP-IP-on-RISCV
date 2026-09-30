#ifndef V26_TCP_ECHO_H
#define V26_TCP_ECHO_H

#include <stdint.h>
#include "lwip/err.h"
#include "net/tcp_zero_copy_lifetime.h"

typedef struct {
    uint32_t accept_count;
    uint32_t recv_callback_count;
    uint32_t rx_bytes;
    uint32_t tx_bytes;
    uint32_t echo_write_count;
    uint32_t write_err_mem_count;
    uint32_t close_count;
    uint32_t abort_count;
    uint32_t error_count;
    uint32_t source_generated_chunks;
    uint32_t source_generated_bytes;
    uint32_t source_acked_bytes;
    uint32_t source_control_count;
    uint32_t source_output_calls;
    uint32_t source_retry_count;
    uint32_t echo_pbuf_nodes;
    uint32_t echo_single_pbuf_callbacks;
    uint32_t echo_multi_pbuf_callbacks;
    uint32_t echo_max_pbuf_nodes;
    uint32_t echo_copy_bytes;
    uint32_t echo_copy_fallback_calls;
    uint32_t echo_output_calls;
} v26_tcp_echo_stats_t;

err_t v26_tcp_echo_start(void);
void v40_tcp_test_select(uint32_t source_mode, uint32_t sink_mode);
void v40_tcp_tx_generator_service(uint32_t link_up);
void v40_tcp_link_down(void);
const v26_tcp_echo_stats_t *v26_tcp_echo_stats(void);
const v40_tcp_zc_stats_t *v40_tcp_echo_zero_copy_stats(void);

#endif
