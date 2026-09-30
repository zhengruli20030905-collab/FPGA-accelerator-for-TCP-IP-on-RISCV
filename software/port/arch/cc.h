#ifndef LWIP_ARCH_CC_H
#define LWIP_ARCH_CC_H

#include <stdint.h>
#include "net/v25_platform.h"

#define BYTE_ORDER LITTLE_ENDIAN

#define PACK_STRUCT_BEGIN
#define PACK_STRUCT_END
#define PACK_STRUCT_STRUCT __attribute__((packed))
#define PACK_STRUCT_FIELD(x) x
#define PACK_STRUCT_FLD_8(x) x
#define PACK_STRUCT_FLD_S(x) x

#define LWIP_PLATFORM_DIAG(x) do { } while (0)
#define LWIP_PLATFORM_ASSERT(x) \
    v25_platform_assert((x), __FILE__, __LINE__)

#endif
