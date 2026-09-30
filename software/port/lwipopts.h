#ifndef LWIPOPTS_H
#define LWIPOPTS_H

/* Bare-metal, single-threaded port. */
#define NO_SYS                         1
#define SYS_LIGHTWEIGHT_PROT           0
#define LWIP_NETCONN                   0
#define LWIP_SOCKET                    0
#define LWIP_NETIF_API                 0

/* V26 keeps the v25 UDP build available for inherited regressions and enables
 * the raw TCP API only for the new firmware image. */
#define LWIP_IPV4                      1
#define LWIP_IPV6                      0
#define LWIP_ETHERNET                  1
#define LWIP_ARP                       1
#define LWIP_ICMP                      1
#define LWIP_UDP                       1
#ifdef V26_TCP_ECHO
#define LWIP_TCP                       1
#else
#define LWIP_TCP                       0
#endif
#define LWIP_RAW                       0
#define LWIP_DHCP                      0
#define LWIP_AUTOIP                    0
#define LWIP_ACD                       0
#define LWIP_DNS                       0
#define LWIP_IGMP                      0

/* The custom RV32I core traps misaligned halfword/word accesses. */
#define MEM_ALIGNMENT                  4
#define ETH_PAD_SIZE                   2

/* Keep the static footprint inside the 128 KiB DMEM. */
#define MEM_SIZE                       (24 * 1024)
#define MEMP_NUM_PBUF                  16
#define MEMP_NUM_UDP_PCB               4
#define MEMP_NUM_SYS_TIMEOUT           8
#ifdef V26_TCP_ECHO
#define MEMP_NUM_TCP_PCB               2
#define MEMP_NUM_TCP_PCB_LISTEN        1
#define MEMP_NUM_TCP_SEG               32
#endif
#define PBUF_POOL_SIZE                 24
/* One pool payload must hold the largest Ethernet frame plus ETH_PAD_SIZE.
 * Twenty-four entries cover eight preposted RX frames, frames retained by
 * TCP/lwIP, and control-traffic headroom without changing the TCP windows. */
#define PBUF_POOL_BUFSIZE              1536
#if PBUF_POOL_BUFSIZE < (1514 + ETH_PAD_SIZE)
#error "V40 requires one pbuf to hold a maximum RX frame plus ETH_PAD_SIZE"
#endif
#define LWIP_SUPPORT_CUSTOM_PBUF       1

#ifdef V26_TCP_ECHO
/* One active echo connection. Two MSS-sized windows keep the static memory
 * cost controlled while still allowing normal TCP segmentation. */
#define TCP_MSS                         1460
#define TCP_WND                         (8 * TCP_MSS)
#define TCP_SND_BUF                     (8 * TCP_MSS)
#define TCP_SND_QUEUELEN                32
#define TCP_OVERSIZE                    0
#endif

#define LWIP_TIMERS                    1
#define LWIP_SINGLE_NETIF              1
#define LWIP_NETIF_STATUS_CALLBACK     1
#define LWIP_NETIF_LINK_CALLBACK       1
#define LWIP_STATS                     0
#define LWIP_DEBUG                     0
#define LWIP_NOASSERT                  0
#define LWIP_PROVIDE_ERRNO             1

/* Retain the software algorithm in the same image for per-netif A/B mode. */
#include "port/v40_checksum_profile.h"
#define LWIP_CHECKSUM_CTRL_PER_NETIF   1
#define LWIP_CHKSUM_ALGORITHM          2
#define LWIP_CHKSUM                    v40_checksum_scan
#define CHECKSUM_GEN_IP                1
#define CHECKSUM_GEN_UDP               1
#define CHECKSUM_GEN_TCP               1
#define CHECKSUM_GEN_ICMP              1
#define CHECKSUM_CHECK_IP              1
#define CHECKSUM_CHECK_UDP             1
#define CHECKSUM_CHECK_TCP             1
#define CHECKSUM_CHECK_ICMP            1

#define IP_FORWARD                     0
#define IP_REASSEMBLY                  0
#define IP_FRAG                        0
#define IP_OPTIONS_ALLOWED             0
#define ARP_QUEUEING                   0
#define LWIP_BROADCAST_PING            0
#define LWIP_MULTICAST_PING            0

#endif
