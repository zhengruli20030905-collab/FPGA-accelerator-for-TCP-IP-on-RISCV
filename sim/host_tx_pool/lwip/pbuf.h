#ifndef V40_HOST_LWIP_PBUF_H
#define V40_HOST_LWIP_PBUF_H
#include <stdint.h>
typedef uint16_t u16_t;

struct pbuf {
    struct pbuf *next;
    void *payload;
    u16_t tot_len;
    u16_t len;
    u16_t ref;
};

struct pbuf_custom {
    struct pbuf pbuf;
    void (*custom_free_function)(struct pbuf *p);
};

#define PBUF_TRANSPORT 0
#define PBUF_REF 0

struct pbuf *pbuf_alloced_custom(int layer, u16_t length, int type,
                                 struct pbuf_custom *custom,
                                 void *payload_mem, u16_t payload_mem_len);
void pbuf_ref(struct pbuf *p);
u16_t pbuf_free(struct pbuf *p);
#endif
