#ifndef V40_CLOCK_CONFIG_H
#define V40_CLOCK_CONFIG_H

/* Formal v40 CPU/MMIO/system clock.  Keep all wall-clock conversions here. */
#define V40_CPU_HZ        25000000u
#define V40_CYCLES_PER_MS (V40_CPU_HZ / 1000u)
#define V40_CYCLES_PER_US (V40_CPU_HZ / 1000000u)
#define V40_MS_TO_CYCLES(ms) ((unsigned int)(ms) * V40_CYCLES_PER_MS)

#endif
