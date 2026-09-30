#include "lwip/pbuf.h"

struct pbuf *pbuf_alloced_custom(int layer, u16_t length, int type,
                                 struct pbuf_custom *custom,
                                 void *payload_mem, u16_t payload_mem_len)
{
    (void)layer;
    (void)type;
    if (custom == 0 || payload_mem == 0 || length > payload_mem_len)
        return 0;
    custom->pbuf.next = 0;
    custom->pbuf.payload = payload_mem;
    custom->pbuf.len = length;
    custom->pbuf.tot_len = length;
    custom->pbuf.ref = 1;
    return &custom->pbuf;
}

void pbuf_ref(struct pbuf *p)
{
    p->ref++;
}

u16_t pbuf_free(struct pbuf *p)
{
    struct pbuf_custom *custom;
    if (p == 0 || p->ref == 0)
        return 0;
    p->ref--;
    if (p->ref != 0)
        return 0;
    custom = (struct pbuf_custom *)p;
    custom->custom_free_function(p);
    return 1;
}
