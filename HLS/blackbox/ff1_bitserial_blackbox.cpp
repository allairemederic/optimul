// Functional C++ model of the M_ff1 RTL blackbox
// This function is used during C simulation
// During HLS synthesis, it is replaced by the RTL implementation

#include <ap_int.h>
#include "ff1.h"

void ff1_bitserial_blackbox(int layer, ap_int<4> activations[4][128], ap_int<16> results[4][32]) {
    
    // Compute: (4 x 128) x (128 x 32) -> (4 x 32)
    for (int sample = 0; sample < 4; ++sample) {

        for (int output_index = 0; output_index < 32; ++output_index) {
            
            ap_int<16> accumulator = 0;

            for (int input_index = 0; input_index < 128; ++input_index) {
                accumulator += ap_int<16>(activations[sample][input_index])* ap_int<16>( ff1_W[layer][output_index][input_index]);
            }

            results[sample][output_index] = accumulator;
        }
    }
}