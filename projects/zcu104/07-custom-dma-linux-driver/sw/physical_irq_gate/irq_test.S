.section .text.start,"ax"
.global _start
.type _start,%function

/* -------------------------------------------------------------
 * Project 07 physical A53 IRQ service test
 * PL IRQ: pl_ps_irq0[0] -> GIC SPI ID 121
 * ------------------------------------------------------------- */

.equ P07_IRQ_STATUS,    0xA0000010
.equ P07_IRQ_ENABLE,    0xA0000014
.equ P07_SCRATCH,       0xA00003FC

.equ GICD_CTLR,         0xF9010000
.equ GICD_IGROUPR3,     0xF901008C
.equ GICD_ISENABLER3,   0xF901010C
.equ GICD_ICPENDR3,     0xF901028C
.equ GICD_IPRIORITY121, 0xF9010479
.equ GICD_ITARGET121,   0xF9010879
.equ GICD_ICFGR7,       0xF9010C1C

.equ GICC_CTLR,         0xF9020000
.equ GICC_PMR,          0xF9020004
.equ GICC_IAR,          0xF902000C
.equ GICC_EOIR,         0xF9020010

/* OCM evidence area */
.equ RESULT_BASE,       0xFFFCF000
.equ STACK_TOP,         0xFFFDF000

.equ IRQ121_MASK,       0x02000000
.equ IRQ121_EDGE_BIT,   0x00080000

/* ASCII-ish evidence marker: "ISR1" */
.equ ISR_MAGIC,         0x49535231
.equ BAD_MAGIC,         0xBAD10000

_start:
    /* No interrupt is allowed while vector/GIC setup is incomplete. */
    msr     daifset, #0xf
    msr     spsel, #1

    ldr     x0, =STACK_TOP
    mov     sp, x0

    adr     x0, vectors
    msr     vbar_el3, x0
    isb

    /*
     * Physical IRQ routing to EL3.
     * GICC_CTLR.FIQEn=0 means Group0 is presented as IRQ.
     * SCR_EL3.IRQ must therefore be set while executing at EL3.
     */
    mrs     x2, scr_el3
    orr     x2, x2, #0x2
    msr     scr_el3, x2
    isb

    /* Clear evidence area and capture execution EL. */
    ldr     x0, =RESULT_BASE
    str     wzr, [x0, #0]     /* ISR magic */
    str     wzr, [x0, #4]     /* raw GICC_IAR */
    str     wzr, [x0, #8]     /* decoded IRQ ID */

    mrs     x1, CurrentEL
    str     w1, [x0, #12]

    /*
     * Remove any stale level-sensitive PL source before enabling
     * the GIC path.
     */
    ldr     x0, =P07_IRQ_STATUS
    mov     w1, #1
    str     w1, [x0]
    dsb     sy

    bl      setup_gic

    /* Enable P07 TX-completion interrupt source.
     * setup_gic clobbers w1, so explicitly reload bit0.
     */
    ldr     x0, =P07_IRQ_ENABLE
    mov     w1, #1
    str     w1, [x0]
    dsb     sy

    /* Unmask IRQ exceptions at the Cortex-A53. */
    msr     daifclr, #2
    isb

    /* Scratch write creates synthetic P07 completion event. */
    ldr     x0, =P07_SCRATCH
    ldr     w1, =0x49535254
    str     w1, [x0]
    dsb     sy

wait_forever:
    wfe
    b       wait_forever


/* -------------------------------------------------------------
 * Configure GIC-400 for SPI 121 -> CPU0
 * ------------------------------------------------------------- */
.type setup_gic,%function
setup_gic:
    /* Disable CPU interface and distributor during setup. */
    ldr     x0, =GICC_CTLR
    str     wzr, [x0]

    ldr     x0, =GICD_CTLR
    str     wzr, [x0]
    dsb     sy

    /* Clear stale pending IRQ121. */
    ldr     x0, =GICD_ICPENDR3
    ldr     w1, =IRQ121_MASK
    str     w1, [x0]

    /* IRQ121 -> Group 0. */
    ldr     x0, =GICD_IGROUPR3
    ldr     w2, [x0]
    bic     w2, w2, w1
    str     w2, [x0]

    /* Level-sensitive, matching our asserted-until-W1C RTL irq. */
    ldr     x0, =GICD_ICFGR7
    ldr     w2, [x0]
    ldr     w3, =IRQ121_EDGE_BIT
    bic     w2, w2, w3
    str     w2, [x0]

    /* Priority = 0x80. */
    ldr     x0, =GICD_IPRIORITY121
    mov     w2, #0x80
    strb    w2, [x0]

    /* Route IRQ121 to Cortex-A53 CPU0. */
    ldr     x0, =GICD_ITARGET121
    mov     w2, #1
    strb    w2, [x0]

    /* Allow priority 0x80 through CPU interface. */
    ldr     x0, =GICC_PMR
    mov     w2, #0xff
    str     w2, [x0]

    /* Enable IRQ121. */
    ldr     x0, =GICD_ISENABLER3
    str     w1, [x0]

    /* Enable Group0 distribution. */
    ldr     x0, =GICD_CTLR
    mov     w2, #1
    str     w2, [x0]

    /* Enable Group0 at CPU interface. */
    ldr     x0, =GICC_CTLR
    str     w2, [x0]

    dsb     sy
    isb
    ret


/* -------------------------------------------------------------
 * AArch64 exception vector table
 *
 * Current EL using SPx IRQ vector = VBAR + 0x280.
 * ------------------------------------------------------------- */
.balign 2048
vectors:
    b default_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler

    .balign 128
    b default_handler
    .balign 128
    b irq_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler

    .balign 128
    b default_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler

    .balign 128
    b default_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler
    .balign 128
    b default_handler


/* -------------------------------------------------------------
 * Actual Cortex-A53 IRQ handler
 * ------------------------------------------------------------- */
irq_handler:
    sub     sp, sp, #64

    stp     x0, x1, [sp, #0]
    stp     x2, x3, [sp, #16]
    stp     x4, x5, [sp, #32]
    stp     x6, x7, [sp, #48]

    /* Interrupt acknowledge. */
    ldr     x0, =GICC_IAR
    ldr     w1, [x0]

    /* Save raw IAR evidence. */
    ldr     x0, =RESULT_BASE
    str     w1, [x0, #4]

    /* Decode interrupt ID. */
    and     w2, w1, #0x3ff
    str     w2, [x0, #8]

    cmp     w2, #121
    b.ne    unexpected_irq

    /*
     * Level interrupt: remove physical PL source BEFORE EOI.
     * P07 IRQ_STATUS uses W1C.
     */
    ldr     x3, =P07_IRQ_STATUS
    mov     w4, #1
    str     w4, [x3]
    dsb     sy

    /* End interrupt at GIC CPU interface. */
    ldr     x3, =GICC_EOIR
    str     w1, [x3]
    dsb     sy

    /* Commit PASS signature only after source-clear + EOI. */
    ldr     w4, =ISR_MAGIC
    str     w4, [x0, #0]
    dsb     sy

    ldp     x0, x1, [sp, #0]
    ldp     x2, x3, [sp, #16]
    ldp     x4, x5, [sp, #32]
    ldp     x6, x7, [sp, #48]

    add     sp, sp, #64
    eret


unexpected_irq:
    ldr     w3, =BAD_MAGIC
    orr     w3, w3, w2
    str     w3, [x0, #0]
    dsb     sy

    msr     daifset, #2

unexpected_loop:
    wfe
    b       unexpected_loop


default_handler:
    ldr     x0, =RESULT_BASE
    ldr     w1, =0xBAD00001
    str     w1, [x0]
    dsb     sy

    msr     daifset, #0xf

default_loop:
    wfe
    b       default_loop
