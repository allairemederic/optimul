/*
 * MicroBlaze controller for transformer_top
 *
 * The host application:
 *   1. writes the input matrix into the shared BRAM through QDMA;
 *   2. writes CMD_START;
 *   3. waits for STATUS_DONE;
 *   4. reads the output and latency through QDMA.
 */


#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_types.h"
#include "xtransformer_top.h"
#include "xparameters.h"
#include "xaxipmon.h"

/* Number of 32-bit input and output values. */
#define IO_DEPTH 512

/*
 * Shared BRAM memory map
 *
 * 0x0000 - 0x07FF  : 512 int32 input values
 * 0x0800 - 0x0FFF  : 512 float output values
 * 0x1000           : command
 * 0x1004           : status
 * 0x1008           : cycle count, low 32 bits
 * 0x100C           : cycle count, high 32 bits
 *
 * The BRAM must therefore contain at least 0x1010 bytes.
 * An 8 KiB BRAM is sufficient.
 */
#define BRAM_BASE          XPAR_BRAM_0_BASEADDR

#define INPUT_OFFSET       0x0000U
#define OUTPUT_OFFSET      0x0800U
#define COMMAND_OFFSET     0x1000U
#define STATUS_OFFSET      0x1004U
#define CYCLES_LOW_OFFSET  0x1008U
#define CYCLES_HIGH_OFFSET 0x100CU

/* Host commands. */
#define CMD_NONE  0U
#define CMD_START 1U

/* MicroBlaze status values. */
#define STATUS_IDLE  0U
#define STATUS_BUSY  1U
#define STATUS_DONE  2U
#define STATUS_ERROR 3U

XTransformer_top transformer;
XAxiPmon performanceMonitor;

/*
 * The input and output buffers are located directly in the shared BRAM.
 * No copy is required inside the MicroBlaze.
 */

volatile int *input_flat = (volatile int *)(BRAM_BASE + INPUT_OFFSET);
volatile float *output_flat = (volatile float *)(BRAM_BASE + OUTPUT_OFFSET);

static void write_status(u32 status)
{
    Xil_Out32(BRAM_BASE + STATUS_OFFSET, status);
}


static void run_transformer(void)
{
    u32 cyclesLow;
    u32 cyclesHigh;
    u64 cycles;

    write_status(STATUS_BUSY);

    /*
     * Give transformer_top the addresses of the buffers located in the shared BRAM.
     */
    XTransformer_top_Set_input_flat(&transformer,(UINTPTR)input_flat);
    XTransformer_top_Set_output_flat(&transformer,(UINTPTR)output_flat);

    print("Starting Transformer\n\r");

    XAxiPmon_ResetGlobalClkCounter(&performanceMonitor);
    XAxiPmon_EnableGlobalClkCounter(&performanceMonitor);

    XTransformer_top_Start(&transformer);

    /* Wait for the accelerator. */
    while(!XTransformer_top_IsDone(&transformer));

    XAxiPmon_DisableGlobalClkCounter(&performanceMonitor);

    print("Transformer finished \n\r");

    XAxiPmon_GetGlobalClkCounter(&performanceMonitor, &cyclesHigh, &cyclesLow);

    cycles = ((u64)cyclesHigh << 32) | cyclesLow;

    /*
     * Make the latency available to the host application.
     */
    Xil_Out32(BRAM_BASE + CYCLES_LOW_OFFSET, cyclesLow);
    Xil_Out32(BRAM_BASE + CYCLES_HIGH_OFFSET, cyclesHigh);

    /*
     * Clear the command before indicating that the output is ready.
     * The host must not read the output before STATUS_DONE.
     */
    Xil_Out32(BRAM_BASE + COMMAND_OFFSET, CMD_NONE);
    write_status(STATUS_DONE);

    print("Printing Results\n\r");

    printf("Latency: %llu cycles | %f ms", cycles, (float)cycles / 100000.0 );
}



int main()
{

    print("Entering Main\n\r");
    print("Starting Initialization\n\r");

    XAxiPmon_Config *CfgPtr;
    int status;

    init_platform();

    /*
    * Initialize the performance monitor.
    */
    CfgPtr = XAxiPmon_LookupConfig(XPAR_AXIPMON_0_DEVICE_ID);

    if (CfgPtr == NULL) {
        xil_printf("ERROR: AXI Performance Monitor not found\r\n");
        return XST_FAILURE;
    }

    status = XAxiPmon_CfgInitialize(&performanceMonitor, CfgPtr, CfgPtr->BaseAddress);

    if (status != XST_SUCCESS) {
        xil_printf("ERROR: AXI Performance Monitor initialization failed\r\n");
        return XST_FAILURE;
    }

    /*
    * Initialize transformer_top.
    */
    Xil_Out32(BRAM_BASE + COMMAND_OFFSET, CMD_NONE);
    Xil_Out32(BRAM_BASE + CYCLES_LOW_OFFSET, 0U);
    Xil_Out32(BRAM_BASE + CYCLES_HIGH_OFFSET, 0U);
    write_status(STATUS_IDLE);

    xil_printf("MicroBlaze ready. Waiting for QDMA input.\r\n");

    /*
    * Persistent service loop.
    */

    while (1) {
        u32 command = Xil_In32(BRAM_BASE + COMMAND_OFFSET);

        if (command == CMD_START) {
            xil_printf("START command received\r\n");
            run_transformer();
        }
    }

    return XST_SUCCESS;
}
