/*
 * main.c: simple test application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable only in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xtransformer_top.h"
#include "xparameters.h"
#include "test_vector.h"
#include "xaxipmon.h"

#define IO_DEPTH 128
#define SCALE (1 << 22)

XTransformer_top transformer;
XAxiPmon performanceMonitor;
XAxiPmon_Config *CfgPtr;
u64 cycles;
u32 cyclesLow;
u32 cyclesHigh;

// input and output of the transformer mapped to the shared BRAM between the cpu and hls ip
volatile int *input_flat  = (int *) XPAR_BRAM_0_BASEADDR;
volatile float *output_flat = (float *) (XPAR_BRAM_0_BASEADDR + IO_DEPTH*sizeof(int));

void init_input(){
    for(int i = 0; i < IO_DEPTH; i++){
        input_flat[i] = (int)(test_input_flat[i] * SCALE);
    }
}

int main()
{

    print("Entering Main\n\r");
    print("Starting Initialization\n\r");

    init_platform();

    CfgPtr = XAxiPmon_LookupConfig(XPAR_AXIPMON_0_DEVICE_ID);
    XAxiPmon_CfgInitialize(&performanceMonitor, CfgPtr, CfgPtr->BaseAddress);

    XTransformer_top_Initialize(&transformer, XPAR_TRANSFORMER_TOP_0_DEVICE_ID);

    init_input();

    XTransformer_top_Set_input_flat(&transformer, (UINTPTR)input_flat);
    XTransformer_top_Set_output_flat(&transformer, (UINTPTR)output_flat);

    print("Starting Transformer\n\r");

    XAxiPmon_ResetGlobalClkCounter(&performanceMonitor);
    XAxiPmon_EnableGlobalClkCounter(&performanceMonitor);

    XTransformer_top_Start(&transformer);

    while(!XTransformer_top_IsDone(&transformer));

    XAxiPmon_DisableGlobalClkCounter(&performanceMonitor);

    print("Transformer finished \n\r");

    XAxiPmon_GetGlobalClkCounter(&performanceMonitor, &cyclesHigh, &cyclesLow);

    cycles = ((u64)cyclesHigh << 32) | cyclesLow;

    print("Printing Results\n\r");

    printf("Latency: %llu cycles | %f ms", cycles, (float)cycles / 100000.0 );

    //for(int i = 0; i < IO_DEPTH; i++){
    //    printf("%d = %f\n", i, output_flat[i]);
    //}

    print("Exiting Main\n\r");

    cleanup_platform();
    return 0;
}
