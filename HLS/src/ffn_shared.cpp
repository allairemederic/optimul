#include "ff0.h"
#include "ff1.h"
#include "layer_tables.h"
#include "transformer_top.h"
#include <ap_int.h>

// For the RTL implementation of BISMO
void ff1_bitserial_blackbox(int layer, ap_int<4> activations[4][128], ap_int<16> results[4][32]);

// Shared FFN
// S = 4, D = 32, H = 128, U0 = 8, U1 = 4
void ffn_shared(int L, act_t input[4][32], act_t output[4][32]) {

#pragma HLS ARRAY_RESHAPE variable=ff0_W cyclic factor=32 dim=3
#pragma HLS ARRAY_PARTITION variable=ff0_W cyclic factor=8 dim=2
#pragma HLS BIND_STORAGE variable=ff0_W type=rom_2p impl=bram
#pragma HLS BIND_STORAGE variable=ff0_M0 type=rom_1p impl=lutram
#pragma HLS BIND_STORAGE variable=ff0_SH type=rom_1p impl=lutram
#pragma HLS ARRAY_RESHAPE variable=ff1_W cyclic factor=128 dim=3
#pragma HLS ARRAY_PARTITION variable=ff1_W cyclic factor=4 dim=2
#pragma HLS BIND_STORAGE variable=ff1_W type=rom_2p impl=bram
#pragma HLS BIND_STORAGE variable=ff1_M0 type=rom_1p impl=lutram
#pragma HLS BIND_STORAGE variable=ff1_SH type=rom_1p impl=lutram
    ap_int<4> mid[4][128];
#pragma HLS ARRAY_PARTITION variable=mid cyclic factor=128 dim=2

    M_ff0: for (int s = 0; s < 4; s++)
      for (int ii = 0; ii < 128; ii += 8) {
#pragma HLS PIPELINE II=1
        for (int u = 0; u < 8; u++) {
#pragma HLS UNROLL
          ap_int<14> acc = 0;
          for (int j0 = 0; j0 < 1; j0++)
            for (int jp = 0; jp < 32; jp++) {
#pragma HLS UNROLL
              int j = j0*32 + jp;
              if (j < 32) {
              ap_int<14> xw_ = input[s][j];
              ap_int<14> xm_ = (xw_ + 4) >> 3;
              int th_ = F0_THDIN[L];
              ap_int<4> xv = xm_ >  th_ ? (ap_int<4>)th_
                        : (xm_ < -th_ ? (ap_int<4>)(-th_) : (ap_int<4>)xm_);
              acc += (ap_int<14>)ff0_W[L][ii+u][j] * xv;
              }
            }
          ap_int<30> tmp = (ap_int<30>)acc * (ap_uint<17>)ff0_M0[L][ii+u];
          int shv = ff0_SH[L][ii+u];
          ap_int<14> y = (shv > 0)
              ? (ap_int<14>)((tmp + ((ap_int<30>)1 << (shv-1))) >> shv)
              : (ap_int<14>)tmp;
          y += ff0_B[L][ii+u];
          int cp_ = F0_THDPOS[L];
          y = y > cp_ ? (ap_int<14>)cp_ : (y < -cp_ ? (ap_int<14>)(-cp_) : y);
          if (y < 0) y = 0;
          mid[s][ii+u] = y;
        }
      }

    M_ff1: for (int s = 0; s < 4; s++)
      for (int ii = 0; ii < 32; ii += 4) {
#pragma HLS PIPELINE II=1
        for (int u = 0; u < 4; u++) {
#pragma HLS UNROLL
          ap_int<15> acc = 0;
          for (int j0 = 0; j0 < 1; j0++)
            for (int jp = 0; jp < 128; jp++) {
#pragma HLS UNROLL
              int j = j0*128 + jp;
              if (j < 128) {
              ap_int<4> xv = mid[s][j];
              acc += (ap_int<15>)ff1_W[L][ii+u][j] * xv;
              }
            }
          ap_int<31> tmp = (ap_int<31>)acc * (ap_uint<17>)ff1_M0[L][ii+u];
          int shv = ff1_SH[L][ii+u];
          ap_int<15> y = (shv > 0)
              ? (ap_int<15>)((tmp + ((ap_int<31>)1 << (shv-1))) >> shv)
              : (ap_int<15>)tmp;
          y += ff1_B[L][ii+u];
          output[s][ii+u] = y;
        }
      }
}
