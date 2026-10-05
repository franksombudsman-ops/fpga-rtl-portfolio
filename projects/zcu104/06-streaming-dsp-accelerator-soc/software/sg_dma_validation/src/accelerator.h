#ifndef PROJECT06_ACCELERATOR_H
#define PROJECT06_ACCELERATOR_H

#include <stdint.h>

#include "xparameters.h"
#include "xil_io.h"

#define ACCEL_BASE XPAR_ACCELERATOR_0_BASEADDR

#define ACCEL_REG_CONTROL            0x00U
#define ACCEL_REG_STATUS             0x04U
#define ACCEL_REG_THRESHOLD_LO       0x08U
#define ACCEL_REG_THRESHOLD_HI       0x0CU
#define ACCEL_REG_SAMPLE_COUNT       0x10U
#define ACCEL_REG_RESULT_COUNT       0x14U
#define ACCEL_REG_EVENT_COUNT        0x18U
#define ACCEL_REG_INPUT_STALL_COUNT  0x1CU
#define ACCEL_REG_OUTPUT_STALL_COUNT 0x20U

#define ACCEL_CONTROL_ENABLE         (1U << 0)
#define ACCEL_CONTROL_STATE_CLEAR    (1U << 1)
#define ACCEL_CONTROL_COUNTER_CLEAR  (1U << 2)

#define ACCEL_STATUS_ENABLED         (1U << 0)
#define ACCEL_STATUS_IDLE            (1U << 1)
#define ACCEL_STATUS_INPUT_ACTIVE    (1U << 2)
#define ACCEL_STATUS_OUTPUT_ACTIVE   (1U << 3)

#define ACCEL_TEST_THRESHOLD UINT64_C(0x0000000040000000)

static inline void accel_write(uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(ACCEL_BASE + offset), value);
}

static inline uint32_t accel_read(uint32_t offset)
{
    return Xil_In32((UINTPTR)(ACCEL_BASE + offset));
}

static inline void accel_disable(void)
{
    accel_write(ACCEL_REG_CONTROL, 0U);
}

static inline void accel_enable(void)
{
    accel_write(ACCEL_REG_CONTROL, ACCEL_CONTROL_ENABLE);
}

static inline void accel_set_threshold(uint64_t threshold)
{
    accel_write(
        ACCEL_REG_THRESHOLD_LO,
        (uint32_t)(threshold & UINT64_C(0xFFFFFFFF))
    );

    accel_write(
        ACCEL_REG_THRESHOLD_HI,
        (uint32_t)((threshold >> 32) & UINT64_C(0x1F))
    );
}

#endif
