/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 *
 * Dual-source hardware validation:
 *
 * Pmod AD1 ----------------------\
 *                                 -> AXI4-Stream packet arbiter
 * Synthetic telemetry source ----/
 * -> asynchronous AXI4-Stream FIFO
 * -> AXI DMA S2MM
 * -> DDR
 * -> Cortex-A53
 *
 * Verifies packet integrity and independent sequence continuity
 * for both AXI4-Stream sources.
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"

#define DMA_BASEADDR              XPAR_XAXIDMA_0_BASEADDR

#define RX_WORDS                  4U
#define RX_BYTES                  (RX_WORDS * sizeof(u32))

#define TARGET_PER_SOURCE         8U
#define MAX_PACKET_ATTEMPTS       4096U

#define AD1_HEADER                0xAD100001U
#define TELEMETRY_HEADER          0xA5000001U

#define PACKET_TRAILER_TAG        0x5A000000U
#define PACKET_TRAILER_MASK       0xFF000000U
#define PACKET_SEQUENCE_MASK      0x00FFFFFFU

#define DMA_TIMEOUT               100000000U

static XAxiDma AxiDma;

static u32 RxBuffer[RX_WORDS] __attribute__((aligned(64)));

int main(void)
{
    XAxiDma_Config *DmaCfg;

    u32 Timeout;
    u32 Header;
    u32 Word1;
    u32 Word2;
    u32 Trailer;

    u32 SampleA;
    u32 SampleB;
    u32 Sequence;
    u32 Timestamp;

    u32 PreviousAd1Sequence = 0U;
    u32 PreviousTelemetrySequence = 0U;

    u32 Ad1Count = 0U;
    u32 TelemetryCount = 0U;

    u32 Ad1Errors = 0U;
    u32 TelemetryErrors = 0U;
    u32 FramingErrors = 0U;
    u32 UnknownPackets = 0U;

    u32 Attempt;

    int Ad1SequenceValid = 0;
    int TelemetrySequenceValid = 0;
    int Status;

    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf("Project 05 - Dual-Source AXI Arbitration Test\r\n");
    xil_printf("============================================\r\n");

    /*
     * --------------------------------------------------------
     * AXI DMA initialization
     * --------------------------------------------------------
     */
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

    xil_printf(
        "DMA base = 0x%08x\r\n",
        (unsigned int)DMA_BASEADDR
    );

    xil_printf(
        "RX buffer = 0x%08x\r\n\r\n",
        (unsigned int)(UINTPTR)RxBuffer
    );

    xil_printf("Waiting for both AXI sources...\r\n\r\n");

    /*
     * --------------------------------------------------------
     * Repeated DMA packet capture
     * --------------------------------------------------------
     */
    for (Attempt = 0U;
         Attempt < MAX_PACKET_ATTEMPTS;
         ++Attempt) {

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
                "FAIL: DMA start failed at attempt %u\r\n",
                (unsigned int)Attempt
            );

            return XST_FAILURE;
        }

        Timeout = DMA_TIMEOUT;

        while (XAxiDma_Busy(
                   &AxiDma,
                   XAXIDMA_DEVICE_TO_DMA)) {

            if (--Timeout == 0U) {
                xil_printf(
                    "FAIL: DMA timeout at attempt %u\r\n",
                    (unsigned int)Attempt
                );

                return XST_FAILURE;
            }
        }

        Xil_DCacheInvalidateRange(
            (INTPTR)RxBuffer,
            RX_BYTES
        );

        Header  = RxBuffer[0];
        Word1   = RxBuffer[1];
        Word2   = RxBuffer[2];
        Trailer = RxBuffer[3];

        /*
         * ====================================================
         * Source S0 - Real Pmod AD1
         *
         * word0 = 0xAD100001
         * word1 = {8'h00, sample_a, sample_b}
         * word2 = sequence
         * word3 = 0x5A000000 | sequence[23:0]
         * ====================================================
         */
        if (Header == AD1_HEADER) {

            SampleA = (Word1 >> 12) & 0x00000FFFU;
            SampleB = Word1 & 0x00000FFFU;
            Sequence = Word2;

            if ((Word1 & 0xFF000000U) != 0U) {
                ++Ad1Errors;
                ++FramingErrors;
            }

            if ((Trailer & PACKET_TRAILER_MASK)
                != PACKET_TRAILER_TAG) {

                ++Ad1Errors;
                ++FramingErrors;
            }

            if ((Trailer & PACKET_SEQUENCE_MASK)
                != (Sequence & PACKET_SEQUENCE_MASK)) {

                ++Ad1Errors;
                ++FramingErrors;
            }

            if (Ad1SequenceValid != 0) {

                if (Sequence !=
                    (PreviousAd1Sequence + 1U)) {

                    ++Ad1Errors;
                }
            }

            PreviousAd1Sequence = Sequence;
            Ad1SequenceValid = 1;

            ++Ad1Count;

            if (Ad1Count <= TARGET_PER_SOURCE) {

                xil_printf(
                    "AD1 [%02u] A=%03x B=%03x "
                    "SEQ=%08x T=%08x\r\n",
                    (unsigned int)Ad1Count,
                    (unsigned int)SampleA,
                    (unsigned int)SampleB,
                    (unsigned int)Sequence,
                    (unsigned int)Trailer
                );
            }
        }

        /*
         * ====================================================
         * Source S1 - Synthetic telemetry
         *
         * word0 = 0xA5000001
         * word1 = sequence
         * word2 = packet timestamp
         * word3 = 0x5A000000 | sequence[23:0]
         * ====================================================
         */
        else if (Header == TELEMETRY_HEADER) {

            Sequence = Word1;
            Timestamp = Word2;

            if ((Trailer & PACKET_TRAILER_MASK)
                != PACKET_TRAILER_TAG) {

                ++TelemetryErrors;
                ++FramingErrors;
            }

            if ((Trailer & PACKET_SEQUENCE_MASK)
                != (Sequence & PACKET_SEQUENCE_MASK)) {

                ++TelemetryErrors;
                ++FramingErrors;
            }

            if (TelemetrySequenceValid != 0) {

                if (Sequence !=
                    (PreviousTelemetrySequence + 1U)) {

                    ++TelemetryErrors;
                }
            }

            PreviousTelemetrySequence = Sequence;
            TelemetrySequenceValid = 1;

            ++TelemetryCount;

            if (TelemetryCount <= TARGET_PER_SOURCE) {

                xil_printf(
                    "TEL [%02u] SEQ=%08x "
                    "TS=%08x T=%08x\r\n",
                    (unsigned int)TelemetryCount,
                    (unsigned int)Sequence,
                    (unsigned int)Timestamp,
                    (unsigned int)Trailer
                );
            }
        }

        /*
         * Unknown packet/header.
         *
         * If packet locking/arbitration were corrupted,
         * malformed headers could appear here.
         */
        else {

            ++UnknownPackets;
            ++FramingErrors;

            xil_printf(
                "UNKNOWN H=%08x W1=%08x "
                "W2=%08x W3=%08x\r\n",
                (unsigned int)Header,
                (unsigned int)Word1,
                (unsigned int)Word2,
                (unsigned int)Trailer
            );
        }

        /*
         * Both independent sources have now been observed
         * and validated sufficiently.
         */
        if ((Ad1Count >= TARGET_PER_SOURCE) &&
            (TelemetryCount >= TARGET_PER_SOURCE)) {

            break;
        }
    }

    /*
     * --------------------------------------------------------
     * Results
     * --------------------------------------------------------
     */
    xil_printf("\r\n");
    xil_printf("--------------------------------------------\r\n");
    xil_printf("Dual-Source Hardware Validation Summary\r\n");
    xil_printf("--------------------------------------------\r\n");

    xil_printf(
        "DMA packet attempts        : %u\r\n",
        (unsigned int)(Attempt + 1U)
    );

    xil_printf(
        "AD1 packets verified       : %u\r\n",
        (unsigned int)Ad1Count
    );

    xil_printf(
        "Telemetry packets verified : %u\r\n",
        (unsigned int)TelemetryCount
    );

    xil_printf(
        "Unknown packets            : %u\r\n",
        (unsigned int)UnknownPackets
    );

    xil_printf("\r\n");

    xil_printf(
        "AD1 integrity              : %s\r\n",
        ((Ad1Count >= TARGET_PER_SOURCE) &&
         (Ad1Errors == 0U))
            ? "PASS" : "FAIL"
    );

    xil_printf(
        "Telemetry integrity        : %s\r\n",
        ((TelemetryCount >= TARGET_PER_SOURCE) &&
         (TelemetryErrors == 0U))
            ? "PASS" : "FAIL"
    );

    xil_printf(
        "Packet boundary integrity  : %s\r\n",
        (FramingErrors == 0U)
            ? "PASS" : "FAIL"
    );

    xil_printf(
        "AD1 sequence integrity     : %s\r\n",
        ((Ad1Count >= TARGET_PER_SOURCE) &&
         (Ad1Errors == 0U))
            ? "PASS" : "FAIL"
    );

    xil_printf(
        "Telemetry sequence         : %s\r\n",
        ((TelemetryCount >= TARGET_PER_SOURCE) &&
         (TelemetryErrors == 0U))
            ? "PASS" : "FAIL"
    );

    if ((Ad1Count >= TARGET_PER_SOURCE) &&
        (TelemetryCount >= TARGET_PER_SOURCE) &&
        (Ad1Errors == 0U) &&
        (TelemetryErrors == 0U) &&
        (FramingErrors == 0U) &&
        (UnknownPackets == 0U)) {

        xil_printf(
            "Dual-source arbitration    : PASS\r\n"
        );

        xil_printf("\r\n");

        xil_printf(
            "AD1 + Telemetry -> AXI Arbiter -> "
            "CDC FIFO -> DMA -> DDR -> A53: PASS\r\n"
        );

        return XST_SUCCESS;
    }

    xil_printf(
        "Dual-source arbitration    : FAIL\r\n"
    );

    xil_printf("\r\n");

    xil_printf(
        "AD1 + Telemetry -> AXI Arbiter -> "
        "CDC FIFO -> DMA -> DDR -> A53: FAIL\r\n"
    );

    return XST_FAILURE;
}