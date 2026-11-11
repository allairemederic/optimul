#pragma once

#include <ap_int.h>

namespace BSMM {

void bitSerialMatrixMult_top(ap_int<4> matrixL[2][2],
                             ap_int<4> matrixR[2][2],
                             ap_int<8> matrixP[2][2]);

template <int M, int K, int N, int L_BITS, int R_BITS,
          int P_BITS = L_BITS + R_BITS>
void bitSerialMatrixMult(ap_int<L_BITS> matrixL[M][K],
                         ap_int<R_BITS> matrixR[K][N],
                         ap_int<P_BITS> matrixP[M][N]) {
    for (int m = 0; m < M; ++m) {
        for (int n = 0; n < N; ++n) {
            matrixP[m][n] = 0;
        }
    }

    for (int i = 0; i < L_BITS; ++i) {
        const int leftWeight = (i == L_BITS - 1) ? -(1 << i) : (1 << i);
        for (int j = 0; j < R_BITS; ++j) {
            const int rightWeight = (j == R_BITS - 1) ? -(1 << j) : (1 << j);
            const int bitWeight = leftWeight * rightWeight;

            for (int m = 0; m < M; ++m) {
                for (int n = 0; n < N; ++n) {
                    for (int k = 0; k < K; ++k) {
                        matrixP[m][n] += bitWeight
                            * (matrixL[m][k][i] ? 1 : 0)
                            * (matrixR[k][n][j] ? 1 : 0);
                    }
                }
            }
        }
    }
}

template <int OutputCount, int InputCount, int L_BITS, int R_BITS,
          int P_BITS>
void bitSerialVectorMatrixMult(
    const ap_int<L_BITS> input[InputCount],
    const ap_int<R_BITS> weights[OutputCount][InputCount],
    ap_int<P_BITS> result[OutputCount]) {
    for (int outputIndex = 0; outputIndex < OutputCount; ++outputIndex) {
#pragma HLS PIPELINE II=1
        ap_int<L_BITS> leftMatrix[1][InputCount];
        ap_int<R_BITS> rightMatrix[InputCount][1];
        ap_int<P_BITS> partialResult[1][1];

        for (int inputIndex = 0; inputIndex < InputCount; ++inputIndex) {
#pragma HLS UNROLL
            leftMatrix[0][inputIndex] = input[inputIndex];
            rightMatrix[inputIndex][0] = weights[outputIndex][inputIndex];
        }

        bitSerialMatrixMult<1, InputCount, 1, L_BITS, R_BITS, P_BITS>(
            leftMatrix, rightMatrix, partialResult);
        result[outputIndex] = partialResult[0][0];
    }
}

}