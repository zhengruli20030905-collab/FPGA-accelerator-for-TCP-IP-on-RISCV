#ifndef V25_UDP_ECHO_H
#define V25_UDP_ECHO_H

#include <stdint.h>
#include "lwip/err.h"
#include "net/tx_buffer_pool.h"

#define V31_UDP_TEST_ECHO       0u
#define V31_UDP_TEST_RX_SINK    1u
#define V31_UDP_TEST_TX_SOURCE  2u
#define V40_TCP_TEST_TX_SOURCE  3u
#define V31_UDP_TX_PAYLOAD_BYTES 1472u

void v31_udp_test_select(uint32_t mode);
uint32_t v31_udp_test_mode(void);
err_t v25_udp_echo_start(void);
void v31_udp_tx_generator_service(uint32_t link_up);
uint32_t v25_udp_echo_requests(void);
uint32_t v25_udp_echo_errors(void);
uint32_t v25_udp_echo_rx_bytes(void);
uint32_t v25_udp_echo_tx_bytes(void);
uint32_t v31_udp_rx_packets(void);
uint32_t v31_udp_sink_packets(void);
uint32_t v31_udp_tx_generated_packets(void);
uint32_t v31_udp_tx_retry_count(void);
uint32_t v31_udp_control_packets(void);
const v40_tx_pool_stats_t *v40_udp_tx_pool_stats(void);

#endif
