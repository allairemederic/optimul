#include "bitSerialMatMult.h"

#include <ap_int.h>

namespace BSMM{

void bitSerialMatrixMult_top(   ap_int<4> matrixL [2][2], 
                                ap_int<4> matrixR [2][2], 
                                ap_int<8> matrixP[2][2]){

    #pragma HLS INTERFACE m_axi port=matrixL offset=slave bundle=gmem0 depth=4
    #pragma HLS INTERFACE m_axi port=matrixR offset=slave bundle=gmem1 depth=4
    #pragma HLS INTERFACE m_axi port=matrixP offset=slave bundle=gmem2 depth=4

    #pragma HLS INTERFACE s_axilite port=matrixL bundle=control
    #pragma HLS INTERFACE s_axilite port=matrixR bundle=control
    #pragma HLS INTERFACE s_axilite port=matrixP bundle=control
    #pragma HLS INTERFACE s_axilite port=return bundle=control

    bitSerialMatrixMult<2,2,2,4,4>(matrixL, matrixR, matrixP);

}

}