/*
 * Frank Ouma
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 *
 * FINAL REAL DUAL-SOURCE HARDWARE VALIDATION
 *
 * Real Pmod AD1 ----\
 *                    -> packet-safe AXIS arbiter
 * Real MPU6050 -----/
 * -> async AXIS CDC FIFO
 * -> AXI DMA S2MM
 * -> DDR
 * -> Cortex-A53
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"

#define DMA_BASEADDR              XPAR_XAXIDMA_0_BASEADDR

#define RX_WORDS                  7U
#define RX_BYTES                  (RX_WORDS * sizeof(u32))

#define TARGET_PER_SOURCE         8U
#define MAX_PACKET_ATTEMPTS       4096U
#define DMA_TIMEOUT               100000000U

#define SENTINEL                  0xCCCCCCCCU

#define AD1_HEADER                0xAD100001U
#define MPU_HEADER                0x60500001U

#define AD1_BYTES                 16U
#define MPU_BYTES                 28U

#define AD1_TRAILER_TAG           0x5A000000U
#define MPU_TRAILER_TAG           0x5B000000U

#define TRAILER_MASK              0xFF000000U
#define SEQUENCE_MASK             0x00FFFFFFU

static XAxiDma AxiDma;

static u32 RxBuffer[RX_WORDS]
    __attribute__((aligned(64)));

int main(void)
{
    XAxiDma_Config *DmaCfg;

    u32 Timeout;
    u32 DmaStatus;
    u32 RxBytes;

    u32 Header;
    u32 Sequence;
    u32 Trailer;

    u32 PreviousAd1Sequence = 0U;
    u32 PreviousMpuSequence = 0U;

    u32 Ad1Count = 0U;
    u32 MpuCount = 0U;

    u32 Ad1FormatErrors = 0U;
    u32 MpuFormatErrors = 0U;

    u32 Ad1SequenceErrors = 0U;
    u32 MpuSequenceErrors = 0U;

    u32 FramingErrors = 0U;
    u32 UnknownPackets = 0U;

    u32 FirstAd1Word = 0U;

    u32 FirstMpuW1 = 0U;
    u32 FirstMpuW2 = 0U;
    u32 FirstMpuW3 = 0U;
    u32 FirstMpuW4 = 0U;

    int Ad1SequenceValid = 0;
    int MpuSequenceValid = 0;

    int Ad1VariationSeen = 0;
    int MpuVariationSeen = 0;

    u32 Attempt;
    u32 i;

    int Status;

    xil_printf("\r\n");
    xil_printf("====================================================\r\n");
    xil_printf("Project 05 - REAL Dual-Source End-to-End Validation\r\n");
    xil_printf("====================================================\r\n");
    xil_printf("AD1 + MPU6050 -> Arbiter -> CDC -> DMA -> DDR -> A53\r\n\r\n");

    /*
     * DMA initialization.
     */
    DmaCfg = XAxiDma_LookupConfig(DMA_BASEADDR);

    if (DmaCfg == NULL) {
        xil_printf("FAIL: DMA configuration not found\r\n");
        return XST_FAILURE;
    }

    Status = XAxiDma_CfgInitialize(&AxiDma, DmaCfg);

    if (Status != XST_SUCCESS) {
        xil_printf("FAIL: DMA initialization\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("FAIL: unexpected scatter-gather configuration\r\n");
        return XST_FAILURE;
    }

    XAxiDma_IntrDisable(
        &AxiDma,
        XAXIDMA_IRQ_ALL_MASK,
        XAXIDMA_DEVICE_TO_DMA
    );

    xil_printf(
        "DMA base : 0x%08x\r\n",
        (unsigned int)DMA_BASEADDR
    );

    xil_printf(
        "RX buffer: 0x%08x\r\n\r\n",
        (unsigned int)(UINTPTR)RxBuffer
    );

    xil_printf(
        "ACTION: move/tilt MPU6050 and vary AD1 input during test.\r\n\r\n"
    );

    for (Attempt = 0U;
         Attempt < MAX_PACKET_ATTEMPTS;
         ++Attempt) {

        /*
         * Fill unused buffer area with sentinel.
         * This helps prove the shorter 4-word AD1 packet
         * terminated at its TLAST.
         */
        for (i = 0U; i < RX_WORDS; ++i) {
            RxBuffer[i] = SENTINEL;
        }

        Xil_DCacheFlushRange(
            (INTPTR)RxBuffer,
            RX_BYTES
        );

        /*
         * RX_BYTES is 28 bytes: enough for the largest packet.
         *
         * AD1 packet = 16 bytes.
         * MPU packet = 28 bytes.
         *
         * S2MM terminates the received packet at AXIS TLAST.
         */
        Status = XAxiDma_SimpleTransfer(
            &AxiDma,
            (UINTPTR)RxBuffer,
            RX_BYTES,
            XAXIDMA_DEVICE_TO_DMA
        );

        if (Status != XST_SUCCESS) {
            xil_printf(
                "FAIL: DMA start at attempt %u\r\n",
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

        DmaStatus = XAxiDma_ReadReg(
            DMA_BASEADDR,
            XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET
        );

        if ((DmaStatus & XAXIDMA_ERR_ALL_MASK) != 0U) {

            xil_printf(
                "FAIL: DMA status error 0x%08x\r\n",
                (unsigned int)DmaStatus
            );

            return XST_FAILURE;
        }

        Xil_DCacheInvalidateRange(
            (INTPTR)RxBuffer,
            RX_BYTES
        );

        /*
         * In Direct Register / Simple S2MM mode,
         * the length register reports received bytes
         * after packet completion.
         */
        RxBytes = XAxiDma_ReadReg(
            DMA_BASEADDR,
            XAXIDMA_RX_OFFSET +
            XAXIDMA_BUFFLEN_OFFSET
        );

        RxBytes &= 0x03FFFFFFU;

        Header = RxBuffer[0];

        /*
         * ==================================================
         * S0: REAL PMOD AD1
         *
         * W0 = 0xAD100001
         * W1 = {00, sample_a[11:0], sample_b[11:0]}
         * W2 = sequence
         * W3 = 0x5A000000 | sequence[23:0]   TLAST
         * ==================================================
         */
        if (Header == AD1_HEADER) {

            u32 Word1 = RxBuffer[1];

            Sequence = RxBuffer[2];
            Trailer  = RxBuffer[3];

            ++Ad1Count;

            if (RxBytes != AD1_BYTES) {
                ++Ad1FormatErrors;
                ++FramingErrors;
            }

            if ((Word1 & 0xFF000000U) != 0U) {
                ++Ad1FormatErrors;
            }

            if ((Trailer & TRAILER_MASK)
                != AD1_TRAILER_TAG) {

                ++Ad1FormatErrors;
                ++FramingErrors;
            }

            if ((Trailer & SEQUENCE_MASK)
                != (Sequence & SEQUENCE_MASK)) {

                ++Ad1FormatErrors;
                ++FramingErrors;
            }

            /*
             * A 4-word AD1 packet must not overwrite
             * words 4..6 of our 7-word receive buffer.
             */
            if ((RxBuffer[4] != SENTINEL) ||
                (RxBuffer[5] != SENTINEL) ||
                (RxBuffer[6] != SENTINEL)) {

                ++Ad1FormatErrors;
                ++FramingErrors;
            }

            if (Ad1SequenceValid != 0) {

                if (Sequence !=
                    (PreviousAd1Sequence + 1U)) {

                    ++Ad1SequenceErrors;
                }
            }

            PreviousAd1Sequence = Sequence;
            Ad1SequenceValid = 1;

            if (Ad1Count == 1U) {
                FirstAd1Word = Word1;
            }
            else if (Word1 != FirstAd1Word) {
                Ad1VariationSeen = 1;
            }

            if (Ad1Count <= TARGET_PER_SOURCE) {

                xil_printf(
                    "AD1 [%02u] LEN=%02u "
                    "A=%03x B=%03x "
                    "SEQ=%08x T=%08x\r\n",
                    (unsigned int)Ad1Count,
                    (unsigned int)RxBytes,
                    (unsigned int)((Word1 >> 12)
                                   & 0x00000FFFU),
                    (unsigned int)(Word1
                                   & 0x00000FFFU),
                    (unsigned int)Sequence,
                    (unsigned int)Trailer
                );
            }
        }

        /*
         * ==================================================
         * S1: REAL MPU6050
         *
         * W0 = 0x60500001
         * W1 = {Accel X, Accel Y}
         * W2 = {Accel Z, Temperature}
         * W3 = {Gyro X, Gyro Y}
         * W4 = {Gyro Z, 16'h0000}
         * W5 = sequence
         * W6 = 0x5B000000 | sequence[23:0]   TLAST
         * ==================================================
         */
        else if (Header == MPU_HEADER) {

            u32 W1 = RxBuffer[1];
            u32 W2 = RxBuffer[2];
            u32 W3 = RxBuffer[3];
            u32 W4 = RxBuffer[4];

            Sequence = RxBuffer[5];
            Trailer  = RxBuffer[6];

            ++MpuCount;

            if (RxBytes != MPU_BYTES) {
                ++MpuFormatErrors;
                ++FramingErrors;
            }

            if ((W4 & 0x0000FFFFU) != 0U) {
                ++MpuFormatErrors;
            }

            if ((Trailer & TRAILER_MASK)
                != MPU_TRAILER_TAG) {

                ++MpuFormatErrors;
                ++FramingErrors;
            }

            if ((Trailer & SEQUENCE_MASK)
                != (Sequence & SEQUENCE_MASK)) {

                ++MpuFormatErrors;
                ++FramingErrors;
            }

            if (MpuSequenceValid != 0) {

                if (Sequence !=
                    (PreviousMpuSequence + 1U)) {

                    ++MpuSequenceErrors;
                }
            }

            PreviousMpuSequence = Sequence;
            MpuSequenceValid = 1;

            if (MpuCount == 1U) {

                FirstMpuW1 = W1;
                FirstMpuW2 = W2;
                FirstMpuW3 = W3;
                FirstMpuW4 = W4;
            }
            else if ((W1 != FirstMpuW1) ||
                     (W2 != FirstMpuW2) ||
                     (W3 != FirstMpuW3) ||
                     (W4 != FirstMpuW4)) {

                MpuVariationSeen = 1;
            }

            if (MpuCount <= TARGET_PER_SOURCE) {

                xil_printf(
                    "MPU [%02u] LEN=%02u "
                    "AX=%04x AY=%04x "
                    "AZ=%04x TMP=%04x "
                    "GX=%04x GY=%04x "
                    "GZ=%04x SEQ=%08x\r\n",

                    (unsigned int)MpuCount,
                    (unsigned int)RxBytes,

                    (unsigned int)((W1 >> 16) & 0xFFFFU),
                    (unsigned int)(W1 & 0xFFFFU),

                    (unsigned int)((W2 >> 16) & 0xFFFFU),
                    (unsigned int)(W2 & 0xFFFFU),

                    (unsigned int)((W3 >> 16) & 0xFFFFU),
                    (unsigned int)(W3 & 0xFFFFU),

                    (unsigned int)((W4 >> 16) & 0xFFFFU),

                    (unsigned int)Sequence
                );
            }
        }

        /*
         * Any other header means the stream arriving
         * in DDR was not a valid AD1 or MPU packet.
         */
        else {

            ++UnknownPackets;
            ++FramingErrors;

            xil_printf(
                "UNKNOWN LEN=%u "
                "W0=%08x W1=%08x W2=%08x "
                "W3=%08x W4=%08x W5=%08x W6=%08x\r\n",

                (unsigned int)RxBytes,
                (unsigned int)RxBuffer[0],
                (unsigned int)RxBuffer[1],
                (unsigned int)RxBuffer[2],
                (unsigned int)RxBuffer[3],
                (unsigned int)RxBuffer[4],
                (unsigned int)RxBuffer[5],
                (unsigned int)RxBuffer[6]
            );
        }

        /*
         * Finish only after BOTH real sources have
         * sufficient packets AND actual changing data.
         */
        if ((Ad1Count >= TARGET_PER_SOURCE) &&
            (MpuCount >= TARGET_PER_SOURCE) &&
            (Ad1VariationSeen != 0) &&
            (MpuVariationSeen != 0)) {

            break;
        }
    }

    xil_printf("\r\n");
    xil_printf("====================================================\r\n");
    xil_printf("REAL DUAL-SOURCE HARDWARE VALIDATION SUMMARY\r\n");
    xil_printf("====================================================\r\n");

    xil_printf(
        "DMA packet attempts       : %u\r\n",
        (unsigned int)(Attempt + 1U)
    );

    xil_printf(
        "AD1 packets verified      : %u\r\n",
        (unsigned int)Ad1Count
    );

    xil_printf(
        "MPU packets verified      : %u\r\n",
        (unsigned int)MpuCount
    );

    xil_printf(
        "Unknown packets           : %u\r\n",
        (unsigned int)UnknownPackets
    );

    xil_printf(
        "Framing errors            : %u\r\n",
        (unsigned int)FramingErrors
    );

    xil_printf(
        "AD1 format errors         : %u\r\n",
        (unsigned int)Ad1FormatErrors
    );

    xil_printf(
        "MPU format errors         : %u\r\n",
        (unsigned int)MpuFormatErrors
    );

    xil_printf(
        "AD1 sequence errors       : %u\r\n",
        (unsigned int)Ad1SequenceErrors
    );

    xil_printf(
        "MPU sequence errors       : %u\r\n\r\n",
        (unsigned int)MpuSequenceErrors
    );

    xil_printf(
        "AD1 live data variation   : %s\r\n",
        Ad1VariationSeen ? "PASS" : "FAIL"
    );

    xil_printf(
        "MPU live data variation   : %s\r\n",
        MpuVariationSeen ? "PASS" : "FAIL"
    );

    xil_printf(
        "Packet boundary integrity : %s\r\n",
        (FramingErrors == 0U) ? "PASS" : "FAIL"
    );

    xil_printf(
        "AD1 sequence integrity    : %s\r\n",
        ((Ad1Count >= TARGET_PER_SOURCE) &&
         (Ad1SequenceErrors == 0U))
            ? "PASS" : "FAIL"
    );

    xil_printf(
        "MPU sequence integrity    : %s\r\n",
        ((MpuCount >= TARGET_PER_SOURCE) &&
         (MpuSequenceErrors == 0U))
            ? "PASS" : "FAIL"
    );

    if ((Ad1Count >= TARGET_PER_SOURCE) &&
        (MpuCount >= TARGET_PER_SOURCE) &&
        (UnknownPackets == 0U) &&
        (FramingErrors == 0U) &&
        (Ad1FormatErrors == 0U) &&
        (MpuFormatErrors == 0U) &&
        (Ad1SequenceErrors == 0U) &&
        (MpuSequenceErrors == 0U) &&
        (Ad1VariationSeen != 0) &&
        (MpuVariationSeen != 0)) {

        xil_printf("\r\n");

        xil_printf(
            "Dual-real-source arbitration : PASS\r\n"
        );

        xil_printf(
            "AD1 + MPU -> Arbiter -> CDC -> "
            "DMA -> DDR -> A53: PASS\r\n"
        );

        return XST_SUCCESS;
    }

    xil_printf("\r\n");

    xil_printf(
        "Dual-real-source arbitration : FAIL\r\n"
    );

    xil_printf(
        "AD1 + MPU -> Arbiter -> CDC -> "
        "DMA -> DDR -> A53: FAIL\r\n"
    );

    return XST_FAILURE;
}