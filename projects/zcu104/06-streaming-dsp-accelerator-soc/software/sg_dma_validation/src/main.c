#include <stdint.h>
#include <string.h>

#include "xparameters.h"
#include "xstatus.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xaxidma.h"
#include "xscugic.h"
#include "xinterrupt_wrap.h"

#ifdef __aarch64__
#include "xil_mmu.h"
#endif

#include "accelerator.h"
#include "impulse128_vectors.h"

/* ------------------------------------------------------------------------- */
/* Hardware definitions                                                       */
/* ------------------------------------------------------------------------- */

#define DMA_BASE_ADDR XPAR_XAXIDMA_0_BASEADDR

#define TX_INTR_ID \
    XPAR_AXI_DMA_0_INTERRUPTS

#define RX_INTR_ID \
    XPAR_AXI_DMA_0_INTERRUPTS_1

#define INTC_PARENT \
    XPAR_AXI_DMA_0_INTERRUPT_PARENT

#define DDR_BASE_ADDR XPAR_PSU_DDR_0_BASEADDRESS

/*
 * Follow the AXI DMA SG example memory organization.
 *
 * Keep descriptors away from the application image and place all DMA-visible
 * addresses below 4 GiB because Project06 DMA address width is 32 bits.
 */
#define MEM_BASE_ADDR       ((UINTPTR)DDR_BASE_ADDR + 0x01000000U)

#define RX_BD_SPACE_BASE    (MEM_BASE_ADDR + 0x00000000U)
#define RX_BD_SPACE_HIGH    (MEM_BASE_ADDR + 0x0000FFFFU)

#define TX_BD_SPACE_BASE    (MEM_BASE_ADDR + 0x00010000U)
#define TX_BD_SPACE_HIGH    (MEM_BASE_ADDR + 0x0001FFFFU)

#define TX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00100000U)
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00300000U)

#define SOURCE_BYTES \
    (IMPULSE_SAMPLE_COUNT * sizeof(int16_t))

#define RESULT_BYTES \
    (IMPULSE_SAMPLE_COUNT * sizeof(uint64_t))

#define MARK_UNCACHEABLE    0x701U

#define DMA_TIMEOUT         100000000U
#define ACCEL_TIMEOUT       10000000U
#define RESET_TIMEOUT       100000U

#define ENERGY_MASK         ((UINT64_C(1) << 37) - 1U)

/* ------------------------------------------------------------------------- */
/* Driver state                                                               */
/* ------------------------------------------------------------------------- */

static XAxiDma AxiDma;

static volatile uint32_t TxDone;
static volatile uint32_t RxDone;
static volatile uint32_t DmaError;
static volatile uint32_t RxActualBytes;

/* ------------------------------------------------------------------------- */
/* Accelerator                                                                */
/* ------------------------------------------------------------------------- */

static int AccelWaitIdle(void)
{
    uint32_t timeout;

    for (timeout = 0; timeout < ACCEL_TIMEOUT; ++timeout) {
        if (accel_read(ACCEL_REG_STATUS) & ACCEL_STATUS_IDLE) {
            return XST_SUCCESS;
        }
    }

    return XST_FAILURE;
}

static int AccelPrepare(void)
{
    accel_disable();

    if (AccelWaitIdle() != XST_SUCCESS) {
        xil_printf("FAIL: accelerator did not become idle\r\n");
        return XST_FAILURE;
    }

    accel_set_threshold(ACCEL_TEST_THRESHOLD);

    /*
     * ENABLE remains zero. Bits 1 and 2 are write-one pulses.
     */
    accel_write(
        ACCEL_REG_CONTROL,
        ACCEL_CONTROL_STATE_CLEAR |
        ACCEL_CONTROL_COUNTER_CLEAR
    );

    if (accel_read(ACCEL_REG_SAMPLE_COUNT) != 0U ||
        accel_read(ACCEL_REG_RESULT_COUNT) != 0U ||
        accel_read(ACCEL_REG_EVENT_COUNT) != 0U) {

        xil_printf("FAIL: accelerator counters did not clear\r\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

/* ------------------------------------------------------------------------- */
/* DMA completion processing                                                  */
/* ------------------------------------------------------------------------- */

static void TxComplete(XAxiDma_BdRing *Ring)
{
    XAxiDma_Bd *BdPtr;
    XAxiDma_Bd *Cur;
    int count;
    int i;

    count = XAxiDma_BdRingFromHw(
        Ring,
        XAXIDMA_ALL_BDS,
        &BdPtr
    );

    if (count <= 0) {
        return;
    }

    Cur = BdPtr;

    for (i = 0; i < count; ++i) {
        uint32_t status = XAxiDma_BdGetSts(Cur);

        if ((status & XAXIDMA_BD_STS_ALL_ERR_MASK) ||
            !(status & XAXIDMA_BD_STS_COMPLETE_MASK)) {

            DmaError = 1U;
            break;
        }

        Cur = (XAxiDma_Bd *)
            XAxiDma_BdRingNext(Ring, Cur);
    }

    if (XAxiDma_BdRingFree(Ring, count, BdPtr) != XST_SUCCESS) {
        DmaError = 1U;
        return;
    }

    if (!DmaError) {
        TxDone += (uint32_t)count;
    }
}

static void RxComplete(XAxiDma_BdRing *Ring)
{
    XAxiDma_Bd *BdPtr;
    XAxiDma_Bd *Cur;
    int count;
    int i;

    count = XAxiDma_BdRingFromHw(
        Ring,
        XAXIDMA_ALL_BDS,
        &BdPtr
    );

    if (count <= 0) {
        return;
    }

    Cur = BdPtr;

    for (i = 0; i < count; ++i) {
        uint32_t status = XAxiDma_BdGetSts(Cur);

        if ((status & XAXIDMA_BD_STS_ALL_ERR_MASK) ||
            !(status & XAXIDMA_BD_STS_COMPLETE_MASK)) {

            DmaError = 1U;
            break;
        }

        RxActualBytes =
            XAxiDma_BdGetActualLength(
                Cur,
                Ring->MaxTransferLen
            );

        Cur = (XAxiDma_Bd *)
            XAxiDma_BdRingNext(Ring, Cur);

        ++RxDone;
    }

    if (XAxiDma_BdRingFree(Ring, count, BdPtr) != XST_SUCCESS) {
        DmaError = 1U;
    }
}

/* ------------------------------------------------------------------------- */
/* DMA interrupt handlers                                                     */
/* ------------------------------------------------------------------------- */

static void ResetDmaAfterError(void)
{
    uint32_t timeout = RESET_TIMEOUT;

    XAxiDma_Reset(&AxiDma);

    while (timeout != 0U) {
        if (XAxiDma_ResetIsDone(&AxiDma)) {
            return;
        }
        --timeout;
    }
}

static void TxIntrHandler(void *Callback)
{
    XAxiDma_BdRing *Ring =
        (XAxiDma_BdRing *)Callback;

    uint32_t irq =
        XAxiDma_BdRingGetIrq(Ring);

    XAxiDma_BdRingAckIrq(Ring, irq);

    if (!(irq & XAXIDMA_IRQ_ALL_MASK)) {
        return;
    }

    if (irq & XAXIDMA_IRQ_ERROR_MASK) {
        DmaError = 1U;
        ResetDmaAfterError();
        return;
    }

    if (irq & (XAXIDMA_IRQ_IOC_MASK |
               XAXIDMA_IRQ_DELAY_MASK)) {
        TxComplete(Ring);
    }
}

static void RxIntrHandler(void *Callback)
{
    XAxiDma_BdRing *Ring =
        (XAxiDma_BdRing *)Callback;

    uint32_t irq =
        XAxiDma_BdRingGetIrq(Ring);

    XAxiDma_BdRingAckIrq(Ring, irq);

    if (!(irq & XAXIDMA_IRQ_ALL_MASK)) {
        return;
    }

    if (irq & XAXIDMA_IRQ_ERROR_MASK) {
        DmaError = 1U;
        ResetDmaAfterError();
        return;
    }

    if (irq & (XAXIDMA_IRQ_IOC_MASK |
               XAXIDMA_IRQ_DELAY_MASK)) {
        RxComplete(Ring);
    }
}

/* ------------------------------------------------------------------------- */
/* GIC                                                                        */
/* ------------------------------------------------------------------------- */

static int SetupInterrupts(void)
{
    XAxiDma_BdRing *tx_ring =
        XAxiDma_GetTxRing(&AxiDma);

    XAxiDma_BdRing *rx_ring =
        XAxiDma_GetRxRing(&AxiDma);

    int status;

    /*
     * Unified Vitis / SDT interrupt flow.
     *
     * XPAR_AXI_DMA_0_INTERRUPTS and _1 are encoded interrupt
     * descriptions. XSetupInterruptSystem decodes them and connects
     * them to the GIC correctly.
     */

    status = XSetupInterruptSystem(
        tx_ring,
        (void *)TxIntrHandler,
        TX_INTR_ID,
        INTC_PARENT,
        0xA0U
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: MM2S interrupt setup
");
        return status;
    }

    status = XSetupInterruptSystem(
        rx_ring,
        (void *)RxIntrHandler,
        RX_INTR_ID,
        INTC_PARENT,
        0xA0U
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: S2MM interrupt setup
");
        return status;
    }

    return XST_SUCCESS;
}

/* ------------------------------------------------------------------------- */
/* SG ring setup                                                              */
/* ------------------------------------------------------------------------- */

static int SetupTxRing(void)
{
    XAxiDma_BdRing *ring =
        XAxiDma_GetTxRing(&AxiDma);

    XAxiDma_Bd template_bd;
    uint32_t count;
    int status;

    XAxiDma_BdRingIntDisable(
        ring,
        XAXIDMA_IRQ_ALL_MASK
    );

    count = XAxiDma_BdRingCntCalc(
        XAXIDMA_BD_MINIMUM_ALIGNMENT,
        TX_BD_SPACE_HIGH -
        TX_BD_SPACE_BASE + 1U
    );

    status = XAxiDma_BdRingCreate(
        ring,
        TX_BD_SPACE_BASE,
        TX_BD_SPACE_BASE,
        XAXIDMA_BD_MINIMUM_ALIGNMENT,
        count
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX BD ring create %d\r\n", status);
        return status;
    }

    XAxiDma_BdClear(&template_bd);

    status = XAxiDma_BdRingClone(
        ring,
        &template_bd
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX BD ring clone %d\r\n", status);
        return status;
    }

    status = XAxiDma_BdRingSetCoalesce(
        ring,
        1U,
        100U
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX coalesce %d\r\n", status);
        return status;
    }

    XAxiDma_BdRingIntEnable(
        ring,
        XAXIDMA_IRQ_ALL_MASK
    );

    status = XAxiDma_BdRingStart(ring);

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX ring start %d\r\n", status);
        return status;
    }

    return XST_SUCCESS;
}

static int SetupRxRing(void)
{
    XAxiDma_BdRing *ring =
        XAxiDma_GetRxRing(&AxiDma);

    XAxiDma_Bd template_bd;
    XAxiDma_Bd *bd;
    uint32_t count;
    int status;

    XAxiDma_BdRingIntDisable(
        ring,
        XAXIDMA_IRQ_ALL_MASK
    );

    count = XAxiDma_BdRingCntCalc(
        XAXIDMA_BD_MINIMUM_ALIGNMENT,
        RX_BD_SPACE_HIGH -
        RX_BD_SPACE_BASE + 1U
    );

    status = XAxiDma_BdRingCreate(
        ring,
        RX_BD_SPACE_BASE,
        RX_BD_SPACE_BASE,
        XAXIDMA_BD_MINIMUM_ALIGNMENT,
        count
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX BD ring create %d\r\n", status);
        return status;
    }

    XAxiDma_BdClear(&template_bd);

    status = XAxiDma_BdRingClone(
        ring,
        &template_bd
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX BD ring clone %d\r\n", status);
        return status;
    }

    status = XAxiDma_BdRingSetCoalesce(
        ring,
        1U,
        100U
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX coalesce %d\r\n", status);
        return status;
    }

    /*
     * Exactly one receive descriptor for the first physical campaign.
     */
    status = XAxiDma_BdRingAlloc(
        ring,
        1,
        &bd
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX BD allocation %d\r\n", status);
        return status;
    }

    status = XAxiDma_BdSetBufAddr(
        bd,
        RX_BUFFER_BASE
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX buffer address %d\r\n", status);
        return status;
    }

    status = XAxiDma_BdSetLength(
        bd,
        RESULT_BYTES,
        ring->MaxTransferLen
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX BD length %d\r\n", status);
        return status;
    }

    XAxiDma_BdSetCtrl(bd, 0U);
    XAxiDma_BdSetId(bd, RX_BUFFER_BASE);

    status = XAxiDma_BdRingToHw(
        ring,
        1,
        bd
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX BD ToHw %d\r\n", status);
        return status;
    }

    XAxiDma_BdRingIntEnable(
        ring,
        XAXIDMA_IRQ_ALL_MASK
    );

    status = XAxiDma_BdRingStart(ring);

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: RX ring start %d\r\n", status);
        return status;
    }

    return XST_SUCCESS;
}

/* ------------------------------------------------------------------------- */
/* TX packet                                                                  */
/* ------------------------------------------------------------------------- */

static int SubmitImpulse(void)
{
    XAxiDma_BdRing *ring =
        XAxiDma_GetTxRing(&AxiDma);

    XAxiDma_Bd *bd;
    volatile int16_t *src =
        (volatile int16_t *)TX_BUFFER_BASE;

    uint32_t i;
    int status;

    for (i = 0; i < IMPULSE_SAMPLE_COUNT; ++i) {
        src[i] = impulse_input[i];
    }

    Xil_DCacheFlushRange(
        TX_BUFFER_BASE,
        SOURCE_BYTES
    );

    status = XAxiDma_BdRingAlloc(
        ring,
        1,
        &bd
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX BD allocation %d\r\n", status);
        return status;
    }

    status = XAxiDma_BdSetBufAddr(
        bd,
        TX_BUFFER_BASE
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX buffer address %d\r\n", status);
        return status;
    }

    status = XAxiDma_BdSetLength(
        bd,
        SOURCE_BYTES,
        ring->MaxTransferLen
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX BD length %d\r\n", status);
        return status;
    }

    XAxiDma_BdSetCtrl(
        bd,
        XAXIDMA_BD_CTRL_TXSOF_MASK |
        XAXIDMA_BD_CTRL_TXEOF_MASK
    );

    XAxiDma_BdSetId(
        bd,
        TX_BUFFER_BASE
    );

    status = XAxiDma_BdRingToHw(
        ring,
        1,
        bd
    );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: TX BD ToHw %d\r\n", status);
        return status;
    }

    return XST_SUCCESS;
}

/* ------------------------------------------------------------------------- */
/* Numerical validation                                                       */
/* ------------------------------------------------------------------------- */

static int ValidateResults(void)
{
    volatile uint64_t *result =
        (volatile uint64_t *)RX_BUFFER_BASE;

    uint32_t failures = 0U;
    uint32_t events = 0U;
    uint32_t i;

    Xil_DCacheInvalidateRange(
        RX_BUFFER_BASE,
        RESULT_BYTES
    );

    if (RxActualBytes != RESULT_BYTES) {
        xil_printf(
            "FAIL: RX actual bytes %lu expected %lu\r\n",
            (unsigned long)RxActualBytes,
            (unsigned long)RESULT_BYTES
        );
        ++failures;
    }

    for (i = 0; i < IMPULSE_SAMPLE_COUNT; ++i) {
        uint64_t raw = result[i];

        int16_t fir =
            (int16_t)(raw & UINT64_C(0xFFFF));

        uint64_t energy =
            (raw >> 16) & ENERGY_MASK;

        uint8_t event =
            (uint8_t)((raw >> 53) & UINT64_C(1));

        uint16_t reserved =
            (uint16_t)((raw >> 54) & UINT64_C(0x3FF));

        events += event;

        if (fir != impulse_fir_expected[i] ||
            energy != impulse_energy_expected[i] ||
            event != impulse_event_expected[i] ||
            reserved != 0U) {

            if (failures < 8U) {
                xil_printf(
                    "MISMATCH[%lu] FIR=%d/%d "
                    "ENERGY=0x%08lx%08lx "
                    "EVENT=%u/%u RESERVED=0x%x\r\n",
                    (unsigned long)i,
                    (int)fir,
                    (int)impulse_fir_expected[i],
                    (unsigned long)(energy >> 32),
                    (unsigned long)(energy & UINT64_C(0xFFFFFFFF)),
                    (unsigned)event,
                    (unsigned)impulse_event_expected[i],
                    (unsigned)reserved
                );
            }

            ++failures;
        }
    }

    if (events != IMPULSE_EXPECTED_EVENT_COUNT) {
        xil_printf(
            "FAIL: event total %lu expected %lu\r\n",
            (unsigned long)events,
            (unsigned long)IMPULSE_EXPECTED_EVENT_COUNT
        );
        ++failures;
    }

    return failures == 0U ?
        XST_SUCCESS :
        XST_FAILURE;
}

/* ------------------------------------------------------------------------- */
/* Main                                                                       */
/* ------------------------------------------------------------------------- */

int main(void)
{
    XAxiDma_Config *dma_cfg;
    volatile uint8_t *rx =
        (volatile uint8_t *)RX_BUFFER_BASE;

    uint32_t timeout;
    uint32_t sample_count;
    uint32_t result_count;
    uint32_t event_count;
    uint32_t input_stalls;
    uint32_t output_stalls;
    int status;

    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf("PROJECT06 SG-DMA PHYSICAL VALIDATION\r\n");
    xil_printf("============================================\r\n");

    xil_printf(
        "Accelerator : 0x%08lx\r\n",
        (unsigned long)ACCEL_BASE
    );

    xil_printf(
        "AXI DMA     : 0x%08lx\r\n",
        (unsigned long)XPAR_AXI_DMA_0_BASEADDR
    );

    xil_printf(
        "MM2S IRQ    : %u\r\n",
        (unsigned)TX_INTR_ID
    );

    xil_printf(
        "S2MM IRQ    : %u\r\n",
        (unsigned)RX_INTR_ID
    );

    /*
     * Project06 DMA has a 32-bit address space.
     */
    if (((uint64_t)RX_BD_SPACE_BASE >> 32) != 0U ||
        ((uint64_t)TX_BD_SPACE_BASE >> 32) != 0U ||
        ((uint64_t)TX_BUFFER_BASE >> 32) != 0U ||
        ((uint64_t)RX_BUFFER_BASE >> 32) != 0U) {

        xil_printf("FAIL: DMA memory is above 4 GiB\r\n");
        return XST_FAILURE;
    }

#ifdef __aarch64__
    /*
     * AXI DMA BDs must not live in ordinary cached memory here.
     */
    Xil_SetTlbAttributes(
        RX_BD_SPACE_BASE,
        MARK_UNCACHEABLE
    );

    Xil_SetTlbAttributes(
        TX_BD_SPACE_BASE,
        MARK_UNCACHEABLE
    );
#endif

    /*
     * Initialize RX memory and push any dirty cache lines out before
     * S2MM owns the destination.
     */
    memset((void *)rx, 0xA5, RESULT_BYTES);

    Xil_DCacheFlushRange(
        RX_BUFFER_BASE,
        RESULT_BYTES
    );

    dma_cfg =
        XAxiDma_LookupConfigBaseAddr(DMA_BASE_ADDR);

    if (dma_cfg == NULL) {
        xil_printf("FAIL: AXI DMA configuration not found\r\n");
        return XST_FAILURE;
    }

    status =
        XAxiDma_CfgInitialize(
            &AxiDma,
            dma_cfg
        );

    if (status != XST_SUCCESS) {
        xil_printf("FAIL: AXI DMA initialization %d\r\n", status);
        return status;
    }

    if (!XAxiDma_HasSg(&AxiDma)) {
        xil_printf("FAIL: AXI DMA is not in SG mode\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA SG mode : PASS\r\n");

    status = AccelPrepare();

    if (status != XST_SUCCESS) {
        return status;
    }

    xil_printf("Accelerator : configured and cleared\r\n");

    status = SetupTxRing();

    if (status != XST_SUCCESS) {
        return status;
    }

    /*
     * RX/S2MM is deliberately prepared before transmission.
     */
    status = SetupRxRing();

    if (status != XST_SUCCESS) {
        return status;
    }

    xil_printf("S2MM         : armed\r\n");

    status = SetupInterrupts();

    if (status != XST_SUCCESS) {
        return status;
    }

    TxDone = 0U;
    RxDone = 0U;
    DmaError = 0U;
    RxActualBytes = 0U;

    /*
     * Submit MM2S while accelerator is disabled.
     * The stream may assert TVALID, but the accelerator gates acceptance
     * until ENABLE is set.
     */
    status = SubmitImpulse();

    if (status != XST_SUCCESS) {
        return status;
    }

    xil_printf("MM2S         : descriptor submitted\r\n");

    /*
     * S2MM already owns a destination descriptor. Now permit input samples.
     */
    accel_enable();

    xil_printf("Accelerator  : ENABLE\r\n");

    for (timeout = 0U;
         timeout < DMA_TIMEOUT;
         ++timeout) {

        if (DmaError) {
            break;
        }

        if (TxDone >= 1U &&
            RxDone >= 1U) {
            break;
        }
    }

    if (DmaError) {
        xil_printf("FAIL: AXI DMA error interrupt\r\n");
        return XST_FAILURE;
    }

    if (TxDone < 1U || RxDone < 1U) {
        xil_printf(
            "FAIL: DMA timeout TX=%lu RX=%lu\r\n",
            (unsigned long)TxDone,
            (unsigned long)RxDone
        );
        return XST_FAILURE;
    }

    xil_printf(
        "DMA complete : TX=%lu RX=%lu bytes=%lu\r\n",
        (unsigned long)TxDone,
        (unsigned long)RxDone,
        (unsigned long)RxActualBytes
    );

    accel_disable();

    if (AccelWaitIdle() != XST_SUCCESS) {
        xil_printf("FAIL: accelerator failed to drain\r\n");
        return XST_FAILURE;
    }

    sample_count =
        accel_read(ACCEL_REG_SAMPLE_COUNT);

    result_count =
        accel_read(ACCEL_REG_RESULT_COUNT);

    event_count =
        accel_read(ACCEL_REG_EVENT_COUNT);

    input_stalls =
        accel_read(ACCEL_REG_INPUT_STALL_COUNT);

    output_stalls =
        accel_read(ACCEL_REG_OUTPUT_STALL_COUNT);

    xil_printf("\r\n=== ACCELERATOR TELEMETRY ===\r\n");

    xil_printf(
        "SAMPLE_COUNT       : %lu\r\n",
        (unsigned long)sample_count
    );

    xil_printf(
        "RESULT_COUNT       : %lu\r\n",
        (unsigned long)result_count
    );

    xil_printf(
        "EVENT_COUNT        : %lu\r\n",
        (unsigned long)event_count
    );

    xil_printf(
        "INPUT_STALL_COUNT  : %lu\r\n",
        (unsigned long)input_stalls
    );

    xil_printf(
        "OUTPUT_STALL_COUNT : %lu\r\n",
        (unsigned long)output_stalls
    );

    if (sample_count != IMPULSE_SAMPLE_COUNT ||
        result_count != IMPULSE_SAMPLE_COUNT ||
        event_count != IMPULSE_EXPECTED_EVENT_COUNT) {

        xil_printf("FAIL: accelerator telemetry mismatch\r\n");
        return XST_FAILURE;
    }

    xil_printf("\r\n=== NUMERICAL VALIDATION ===\r\n");

    status = ValidateResults();

    if (status != XST_SUCCESS) {
        xil_printf("PROJECT06 PHYSICAL VALIDATION: FAIL\r\n");
        return XST_FAILURE;
    }

    xil_printf("128/128 result words match golden model\r\n");
    xil_printf("FIR              : PASS\r\n");
    xil_printf("MOVING ENERGY    : PASS\r\n");
    xil_printf("THRESHOLD EVENT  : PASS\r\n");
    xil_printf("RESERVED BITS    : PASS\r\n");
    xil_printf("DMA INTERRUPTS   : PASS\r\n");
    xil_printf("ACCEL COUNTERS   : PASS\r\n");

    xil_printf("\r\n");
    xil_printf("PROJECT06 PHYSICAL VALIDATION: PASS\r\n");
    xil_printf("============================================\r\n");

    return XST_SUCCESS;
}
