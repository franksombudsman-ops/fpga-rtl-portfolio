#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"

/* -------------------------------------------------------------
 * Custom AXI-Lite peripheral memory map
 * ------------------------------------------------------------- */

#define AXI_BASE            0xA4000000U

#define REG_CONTROL         (AXI_BASE + 0x00U)
#define REG_STATUS          (AXI_BASE + 0x04U)
#define REG_THRESHOLD_HIGH  (AXI_BASE + 0x08U)
#define REG_THRESHOLD_LOW   (AXI_BASE + 0x0CU)
#define REG_PWM_DUTY        (AXI_BASE + 0x10U)
#define REG_SENSOR_RAW      (AXI_BASE + 0x14U)
#define REG_SENSOR_FILTERED (AXI_BASE + 0x18U)
#define REG_VERSION         (AXI_BASE + 0x1CU)


static int check_register(
    const char *name,
    UINTPTR address,
    u32 expected
)
{
    u32 value = Xil_In32(address);

    xil_printf("%s = 0x%08x", name, value);

    if (value == expected) {
        xil_printf("  PASS\r\n");
        return 0;
    }

    xil_printf(
        "  FAIL (expected 0x%08x)\r\n",
        expected
    );

    return 1;
}


int main(void)
{
    int failures = 0;

    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf(" ZCU104 AXI-LITE PS <-> PL HARDWARE TEST\r\n");
    xil_printf("============================================\r\n");

    /* ---------------------------------------------------------
     * PL -> PS READ TEST
     * --------------------------------------------------------- */

    xil_printf("\r\n[1] Initial FPGA register reads\r\n");

    failures += check_register(
        "CONTROL         ",
        REG_CONTROL,
        0x00000000U
    );

    failures += check_register(
        "STATUS          ",
        REG_STATUS,
        0x0000001BU
    );

    failures += check_register(
        "THRESHOLD_HIGH  ",
        REG_THRESHOLD_HIGH,
        0x00000C00U
    );

    failures += check_register(
        "THRESHOLD_LOW   ",
        REG_THRESHOLD_LOW,
        0x00000B80U
    );

    failures += check_register(
        "PWM_DUTY        ",
        REG_PWM_DUTY,
        0x00000099U
    );

    failures += check_register(
        "SENSOR_RAW      ",
        REG_SENSOR_RAW,
        0x00000A35U
    );

    failures += check_register(
        "SENSOR_FILTERED ",
        REG_SENSOR_FILTERED,
        0x00000A10U
    );

    failures += check_register(
        "VERSION         ",
        REG_VERSION,
        0x00010000U
    );


    /* ---------------------------------------------------------
     * PS -> PL WRITE TEST
     * --------------------------------------------------------- */

    xil_printf("\r\n[2] ARM writing FPGA configuration registers\r\n");

    Xil_Out32(REG_CONTROL,        0x00000001U);
    Xil_Out32(REG_THRESHOLD_HIGH, 0x00000777U);
    Xil_Out32(REG_THRESHOLD_LOW,  0x00000666U);
    Xil_Out32(REG_PWM_DUTY,       0x00000055U);


    /* ---------------------------------------------------------
     * PS -> PL -> PS READBACK TEST
     * --------------------------------------------------------- */

    xil_printf("\r\n[3] AXI register readback\r\n");

    failures += check_register(
        "CONTROL         ",
        REG_CONTROL,
        0x00000001U
    );

    failures += check_register(
        "THRESHOLD_HIGH  ",
        REG_THRESHOLD_HIGH,
        0x00000777U
    );

    failures += check_register(
        "THRESHOLD_LOW   ",
        REG_THRESHOLD_LOW,
        0x00000666U
    );

    failures += check_register(
        "PWM_DUTY        ",
        REG_PWM_DUTY,
        0x00000055U
    );


    xil_printf("\r\n");

    if (failures == 0) {
        xil_printf("============================================\r\n");
        xil_printf(" ALL PS <-> PL AXI TESTS PASSED\r\n");
        xil_printf("============================================\r\n");
    }
    else {
        xil_printf("============================================\r\n");
        xil_printf(" AXI TEST FAILED: %d mismatches\r\n", failures);
        xil_printf("============================================\r\n");
    }

    while (1) {
        /* Hold application after test */
    }

    return 0;
}