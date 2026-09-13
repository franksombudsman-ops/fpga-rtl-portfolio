/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 * Interrupt-driven AXI DMA S2MM validation.
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xinterrupt_wrap.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"

#define DMA_BASEADDR       XPAR_XAXIDMA_0_BASEADDR
#define DMA_RX_INTR_ID     XPAR_XAXIDMA_0_INTERRUPTS
#define DMA_INTR_PARENT    XPAR_XAXIDMA_0_INTERRUPT_PARENT

#define RX_WORDS           4U
#define RX_BYTES           (RX_WORDS * sizeof(u32))

#define PACKET_HEADER      0xA5000001U
#define TRAILER_TAG        0x5A000000U

#define WAIT_TIMEOUT       100000000U

static XAxiDma AxiDma;

static volatile int RxDone = 0;
static volatile int Error  = 0;

static u32 RxBuffer[RX_WORDS] __attribute__((aligned(64)));

static void RxIntrHandler(void *Callback)
{
    XAxiDma *DmaPtr = (XAxiDma *)Callback;
    u32 IrqStatus;

    IrqStatus =
        XAxiDma_IntrGetIrq(DmaPtr, XAXIDMA_DEVICE_TO_DMA);

    XAxiDma_IntrAckIrq(
        DmaPtr,
        IrqStatus,
        XAXIDMA_DEVICE_TO_DMA
    );

    if (!(IrqStatus & XAXIDMA_IRQ_ALL_MASK)) {
        return;
    }

    if (IrqStatus & XAXIDMA_IRQ_ERROR_MASK) {
        Error = 1;
        XAxiDma_Reset(DmaPtr);
        return;
    }

    if (IrqStatus & XAXIDMA_IRQ_IOC_MASK) {
        RxDone = 1;
    }
}

int main(void)
{
    XAxiDma_Config *DmaCfg;
    u32 Timeout;
    u32 Sequence;
    u32 ExpectedTrailer;
    int Status;

    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf("Project 05 - DMA INTERRUPT TEST\r\n");
    xil_printf("============================================\r\n");

    DmaCfg = XAxiDma_LookupConfig(DMA_BASEADDR);

    if (DmaCfg == NULL) {
        xil_printf("ERROR: DMA configuration not found\r\n");
        return XST_FAILURE;
    }

    Status = XAxiDma_CfgInitialize(&AxiDma, DmaCfg);

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: DMA initialization failed\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("ERROR: unexpected SG mode\r\n");
        return XST_FAILURE;
    }

    /*
     * Disable DMA's internal RX interrupt while configuring
     * the CPU interrupt path.
     */
    XAxiDma_IntrDisable(
        &AxiDma,
        XAXIDMA_IRQ_ALL_MASK,
        XAXIDMA_DEVICE_TO_DMA
    );

    Status = XSetupInterruptSystem(
        &AxiDma,
        &RxIntrHandler,
        DMA_RX_INTR_ID,
        DMA_INTR_PARENT,
        XINTERRUPT_DEFAULT_PRIORITY
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: interrupt setup failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA initialized\r\n");
    xil_printf("DMA encoded interrupt = 0x%08x\r\n",
               (unsigned int)DMA_RX_INTR_ID);
    xil_printf("Expected physical GIC IRQ = 121\r\n");

    RxDone = 0;
    Error  = 0;

    Xil_DCacheFlushRange(
        (INTPTR)RxBuffer,
        RX_BYTES
    );

    /*
     * Enable DMA completion/error interrupts.
     */
    XAxiDma_IntrEnable(
        &AxiDma,
        XAXIDMA_IRQ_ALL_MASK,
        XAXIDMA_DEVICE_TO_DMA
    );

    xil_printf("Starting 16-byte DMA receive...\r\n");
    xil_printf("Waiting for DMA interrupt...\r\n");

    Status = XAxiDma_SimpleTransfer(
        &AxiDma,
        (UINTPTR)RxBuffer,
        RX_BYTES,
        XAXIDMA_DEVICE_TO_DMA
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: DMA transfer start failed\r\n");
        return XST_FAILURE;
    }

    Timeout = WAIT_TIMEOUT;

    /*
     * We are NOT polling the DMA hardware here.
     * The ISR changes RxDone when the interrupt arrives.
     */
    while ((!RxDone) && (!Error)) {

        if (--Timeout == 0U) {
            xil_printf("FAIL: interrupt timeout\r\n");
            return XST_FAILURE;
        }
    }

    if (Error) {
        xil_printf("FAIL: DMA error interrupt\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA INTERRUPT RECEIVED\r\n");

    Xil_DCacheInvalidateRange(
        (INTPTR)RxBuffer,
        RX_BYTES
    );

    xil_printf("RX[0] = 0x%08x\r\n", RxBuffer[0]);
    xil_printf("RX[1] = 0x%08x\r\n", RxBuffer[1]);
    xil_printf("RX[2] = 0x%08x\r\n", RxBuffer[2]);
    xil_printf("RX[3] = 0x%08x\r\n", RxBuffer[3]);

    Sequence = RxBuffer[1];

    ExpectedTrailer =
        TRAILER_TAG |
        (Sequence & 0x00FFFFFFU);

    if (RxBuffer[0] != PACKET_HEADER) {
        xil_printf("FAIL: header mismatch\r\n");
        return XST_FAILURE;
    }

    if (RxBuffer[3] != ExpectedTrailer) {
        xil_printf("FAIL: trailer mismatch\r\n");
        return XST_FAILURE;
    }

    xil_printf("\r\nPACKET VALIDATION: PASS\r\n");
    xil_printf("DMA IRQ 121 -> A53 ISR: PASS\r\n");
    xil_printf("PL -> CDC -> DMA -> DDR -> INTERRUPT -> A53: PASS\r\n");

    XDisconnectInterruptCntrl(
        DMA_RX_INTR_ID,
        DMA_INTR_PARENT
    );

    return XST_SUCCESS;
}
