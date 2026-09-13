/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 * First hardware validation:
 * PL telemetry source -> async AXI4-Stream FIFO
 * -> AXI DMA S2MM -> DDR -> Cortex-A53 verification
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"

#define DMA_BASEADDR        XPAR_XAXIDMA_0_BASEADDR

#define RX_WORDS            4U
#define RX_BYTES            (RX_WORDS * sizeof(u32))

#define PACKET_HEADER       0xA5000001U
#define PACKET_TRAILER_MASK 0xFF000000U
#define PACKET_TRAILER_TAG  0x5A000000U

#define DMA_TIMEOUT         100000000U

static XAxiDma AxiDma;

/*
 * Global aligned buffer.
 * The linker should place this in DDR; we will verify its final
 * address from the ELF/map before running on hardware.
 */
static u32 RxBuffer[RX_WORDS] __attribute__((aligned(64)));

int main(void)
{
    XAxiDma_Config *DmaCfg;
    u32 Timeout;
    u32 Sequence;
    u32 ExpectedTrailer;
    int Status;
    int i;

    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf("Project 05 - AXI DMA DDR Hardware Test\r\n");
    xil_printf("============================================\r\n");

    /*
     * Vitis 2023.2 / SDT-generated platform:
     * initialize AXI DMA from its verified base address.
     */
    DmaCfg = XAxiDma_LookupConfig(DMA_BASEADDR);

    if (DmaCfg == NULL) {
        xil_printf("ERROR: AXI DMA configuration not found\r\n");
        return XST_FAILURE;
    }

    Status = XAxiDma_CfgInitialize(&AxiDma, DmaCfg);

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: XAxiDma_CfgInitialize failed\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("ERROR: DMA unexpectedly configured for SG mode\r\n");
        return XST_FAILURE;
    }

    xil_printf("DMA initialized at 0x%08x\r\n",
               (unsigned int)DMA_BASEADDR);

    /*
     * First test uses polling only.
     * IRQ 121 will be enabled in the next validation stage.
     */
    XAxiDma_IntrDisable(&AxiDma,
                        XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DEVICE_TO_DMA);

    /*
     * Protect against dirty cache lines being written over
     * DMA-received data.
     */
    Xil_DCacheFlushRange((INTPTR)RxBuffer, RX_BYTES);

    xil_printf("RX buffer address = 0x%08x\r\n",
               (unsigned int)(UINTPTR)RxBuffer);

    xil_printf("Starting 16-byte S2MM transfer...\r\n");

    Status = XAxiDma_SimpleTransfer(
        &AxiDma,
        (UINTPTR)RxBuffer,
        RX_BYTES,
        XAXIDMA_DEVICE_TO_DMA
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: XAxiDma_SimpleTransfer failed\r\n");
        return XST_FAILURE;
    }

    Timeout = DMA_TIMEOUT;

    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA)) {
        if (--Timeout == 0U) {
            xil_printf("ERROR: DMA transfer timeout\r\n");
            return XST_FAILURE;
        }
    }

    /*
     * DMA has written DDR. Discard stale A53 cache contents
     * before inspecting the buffer.
     */
    Xil_DCacheInvalidateRange((INTPTR)RxBuffer, RX_BYTES);

    xil_printf("\r\nDMA transfer complete\r\n");

    for (i = 0; i < RX_WORDS; ++i) {
        xil_printf("RX[%d] = 0x%08x\r\n",
                   i,
                   (unsigned int)RxBuffer[i]);
    }

    /*
     * Validate packet structure without assuming which sequence
     * number is currently at the head of the async FIFO.
     */
    if (RxBuffer[0] != PACKET_HEADER) {
        xil_printf("FAIL: invalid packet header\r\n");
        return XST_FAILURE;
    }

    Sequence = RxBuffer[1];

    ExpectedTrailer =
        PACKET_TRAILER_TAG | (Sequence & 0x00FFFFFFU);

    if ((RxBuffer[3] & PACKET_TRAILER_MASK) !=
        PACKET_TRAILER_TAG) {
        xil_printf("FAIL: invalid trailer tag\r\n");
        return XST_FAILURE;
    }

    if (RxBuffer[3] != ExpectedTrailer) {
        xil_printf("FAIL: trailer/sequence mismatch\r\n");
        return XST_FAILURE;
    }

    xil_printf("\r\n");
    xil_printf("PACKET VALIDATION: PASS\r\n");
    xil_printf("Sequence  = 0x%08x\r\n",
               (unsigned int)Sequence);
    xil_printf("Timestamp = 0x%08x\r\n",
               (unsigned int)RxBuffer[2]);

    xil_printf("\r\n");
    xil_printf("PL -> CDC -> DMA -> DDR -> A53 : PASS\r\n");

    return XST_SUCCESS;
}
