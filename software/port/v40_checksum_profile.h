#ifndef V40_CHECKSUM_PROFILE_H
#define V40_CHECKSUM_PROFILE_H
#include <stdint.h>
uint16_t v40_checksum_scan(const void *data, int length);
void v40_checksum_report(void);
extern uint32_t v40_checksum_hardware;
extern uint32_t v40_header_parse_calls, v40_header_parse_bytes;
#endif
