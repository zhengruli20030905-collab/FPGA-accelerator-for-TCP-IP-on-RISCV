#include "port/v40_checksum_profile.h"
#include "port/v28_profile.h"
#include "net/v25_platform.h"
/* The unchanged lwIP algorithm 2 measures actual scans, including every pbuf.
 * LWIP_CHKSUM has no RX/TX or protocol context. Report aggregate scope. */
extern uint16_t lwip_standard_chksum(const void *, int);
uint32_t v40_checksum_hardware;
uint32_t v40_header_parse_calls, v40_header_parse_bytes;
volatile uint32_t v40_checksum_scan_calls;
volatile uint64_t v40_checksum_scan_bytes, v40_checksum_scan_ticks;
uint16_t v40_checksum_scan(const void *data, int length)
{
    uint32_t start = v28_profile_begin();
    uint16_t result = lwip_standard_chksum(data, length);
    uint32_t elapsed = v28_profile_elapsed(start);
    v40_checksum_scan_calls++;
    v40_checksum_scan_bytes += (uint32_t)length;
    v40_checksum_scan_ticks += elapsed;
    return result;
}
static void value(const char *label, uint32_t v)
{ v25_platform_uart_puts(label); v25_platform_uart_hex32(v); }
void v40_checksum_report(void)
{
    value("CSUM SW_SCAN_CALLS=",v40_checksum_scan_calls);
    value(" BYTES_HI=",(uint32_t)(v40_checksum_scan_bytes>>32));
    value(" BYTES_LO=",(uint32_t)v40_checksum_scan_bytes);
    value(" TICKS_HI=",(uint32_t)(v40_checksum_scan_ticks>>32));
    value(" TICKS_LO=",(uint32_t)v40_checksum_scan_ticks);
    value(" HEADER_CALLS=",v40_header_parse_calls);
    value(" HEADER_BYTES=",v40_header_parse_bytes);
    v25_platform_uart_puts(" SCOPE=ALL_LWIP_SCANS\n");
}
