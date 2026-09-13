/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 *
 * Repeated hardware validation:
 * PL telemetry source -> asynchronous AXI4-Stream FIFO
 * -> AXI DMA S2MM -> DDR -> Cortex-A53
 *
 * Verifies eight consecutive telemetry packets.
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"

#define DMA_BASEADDR        XPAR_XAXIDMA_0_BASEADDR

#define RX_WORDS            4U
#define RX_BYTES            (RX_WORDS * sizeof(u32))
#define PACKET_COUNT        8U

#define PACKET_HEADER       0xA5000001U
#define PACKET_TRAILER_TAG  0x5A000000U

#define DMA_TIMEOUT         100000000U

static XAxiDma AxiDma;

static u32 RxBuffer[RX_WORDS] __attribute__((aligned(64)));

int main(void)
{
    XAxiDma_Config *DmaCfg;
    u32 Timeout;
    u32 Sequence;
    u32 PreviousSequence = 0U;
    u32 Timestamp;
    u32 PreviousTimestamp = 0U;
    u32 ExpectedTrailer;
    u32 Packet;
    int Status;

    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf("Project 05 - 8 Packet DMA Continuity Test\r\n");
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
        xil_printf("ERROR: unexpected SG configuration\r\n");
        return XST_FAILURE;
    }

    XAxiDma_IntrDisable(
        &AxiDma,
        XAXIDMA_IRQ_ALL_MASK,
        XAXIDMA_DEVICE_TO_DMA
    );

    xil_printf("DMA base = 0x%08x\r\n",
               (unsigned int)DMA_BASEADDR);

    xil_printf("RX buffer = 0x%08x\r\n\r\n",
               (unsigned int)(UINTPTR)RxBuffer);

    for (Packet = 0U; Packet < PACKET_COUNT; ++Packet) {

        RxBuffer[0] = 0U;
        RxBuffer[1] = 0U;
        RxBuffer[2] = 0U;
        RxBuffer[3] = 0U;

        Xil_DCacheFlushRange(
            (INTPTR)RxBuffer,
            RX_BYTES
        );

        Status = XAxiDma_SimpleTransfer(
            &AxiDma,
            (UINTPTR)RxBuffer,
            RX_BYTES,
            XAXIDMA_DEVICE_TO_DMA
        );

        if (Status != XST_SUCCESS) {
            xil_printf(
                "FAIL: packet %u DMA start failed\r\n",
                (unsigned int)Packet
            );
            return XST_FAILURE;
        }

        Timeout = DMA_TIMEOUT;

        while (XAxiDma_Busy(
                   &AxiDma,
                   XAXIDMA_DEVICE_TO_DMA)) {

            if (--Timeout == 0U) {
                xil_printf(
                    "FAIL: packet %u DMA timeout\r\n",
                    (unsigned int)Packet
                );
                return XST_FAILURE;
            }
        }

        Xil_DCacheInvalidateRange(
            (INTPTR)RxBuffer,
            RX_BYTES
        );

        Sequence  = RxBuffer[1];
        Timestamp = RxBuffer[2];

        ExpectedTrailer =
            PACKET_TRAILER_TAG |
            (Sequence & 0x00FFFFFFU);

        xil_printf(
            "PKT[%u] H=%08x SEQ=%08x TS=%08x T=%08x\r\n",
            (unsigned int)Packet,
            (unsigned int)RxBuffer[0],
            (unsigned int)Sequence,
            (unsigned int)Timestamp,
            (unsigned int)RxBuffer[3]
        );

        if (RxBuffer[0] != PACKET_HEADER) {
            xil_printf(
                "FAIL: packet %u invalid header\r\n",
                (unsigned int)Packet
            );
            return XST_FAILURE;
        }

        if (RxBuffer[3] != ExpectedTrailer) {
            xil_printf(
                "FAIL: packet %u trailer mismatch\r\n",
                (unsigned int)Packet
            );
            return XST_FAILURE;
        }

        if (Packet > 0U) {

            if (Sequence != (PreviousSequence + 1U)) {
                xil_printf(
                    "FAIL: sequence discontinuity "
                    "previous=%08x current=%08x\r\n",
                    (unsigned int)PreviousSequence,
                    (unsigned int)Sequence
                );
                return XST_FAILURE;
            }

            if (Timestamp <= PreviousTimestamp) {
                xil_printf(
                    "FAIL: timestamp did not progress "
                    "previous=%08x current=%08x\r\n",
                    (unsigned int)PreviousTimestamp,
                    (unsigned int)Timestamp
                );
                return XST_FAILURE;
            }
        }

        PreviousSequence  = Sequence;
        PreviousTimestamp = Timestamp;
    }

    xil_printf("\r\n");
    xil_printf("8 PACKET CONTINUITY TEST: PASS\r\n");
    xil_printf("Packets verified : %u\r\n",
               (unsigned int)PACKET_COUNT);

    xil_printf("First-to-last sequence continuity: PASS\r\n");
    xil_printf("Timestamp progression: PASS\r\n");
    xil_printf("Header/trailer integrity: PASS\r\n");

    xil_printf("\r\n");
    xil_printf(
        "PL -> CDC -> DMA -> DDR -> A53 MULTI-PACKET: PASS\r\n"
    );

    return XST_SUCCESS;
}