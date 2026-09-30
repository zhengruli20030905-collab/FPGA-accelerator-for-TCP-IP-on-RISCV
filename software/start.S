    .section .text.start
    .globl _start

_start:
    lui  sp, %hi(__stack_top)
    addi sp, sp, %lo(__stack_top)

#if defined(V25_LWIP_NOSYS) || defined(V26_TCP_ECHO)
    /* Fill the unused stack before C code starts so firmware can report a
       real high-water mark without touching an active stack frame. */
    lui  t0, %hi(__stack_limit)
    addi t0, t0, %lo(__stack_limit)
    lui  t1, %hi(__stack_top)
    addi t1, t1, %lo(__stack_top)
    lui  t2, 0xa5a5a
    addi t2, t2, 0x5a5

fill_stack_canary:
    beq  t0, t1, stack_canary_done
    sw   t2, 0(t0)
    addi t0, t0, 4
    jal  zero, fill_stack_canary

stack_canary_done:
#endif

    lui  t0, %hi(__bss_start)
    addi t0, t0, %lo(__bss_start)
    lui  t1, %hi(__bss_end)
    addi t1, t1, %lo(__bss_end)

clear_bss:
    beq  t0, t1, call_main
    sw   zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, clear_bss

call_main:
    jal  ra, main

halt:
    ebreak
    jal  zero, halt
