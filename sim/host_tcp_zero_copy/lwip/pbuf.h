#ifndef V40_HOST_TCP_ZC_LWIP_PBUF_H
#define V40_HOST_TCP_ZC_LWIP_PBUF_H

#include <stdint.h>

typedef uint16_t u16_t;

struct pbuf {
    struct pbuf *next;
    void *payload;
    u16_t tot_len;
    u16_t len;
    u16_t ref;
};

#endif
