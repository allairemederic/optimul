// FFN PARTAGÉ | S=4 D=32 H=128 | U0=8 U1=4 | index L
#include "bitSerialMatMult.h"
#include "ff0.h"
#include "ff1.h"
#include "layer_tables.h"
#include "transformer_top.h"
#include "ap_int.h"

namespace {

constexpr int kNumSamples = 4;
constexpr int kInputSize = 32;
constexpr int kHiddenSize = 128;
constexpr int kOutputSize = 32;

static ap_int<7> quantize_input_value(const act_t value, const int threshold) {
    const ap_int<20> shifted_value = (value + 4) >> 3;

    if (shifted_value > threshold) {
        return static_cast<ap_int<7>>(threshold);
    }
    if (shifted_value < -threshold) {
        return static_cast<ap_int<7>>(-threshold);
    }

    return static_cast<ap_int<7>>(shifted_value);
}

static void quantize_input_block(const act_t input[kInputSize], ap_int<7> quantized_input[kInputSize], const int threshold) {
    for (int index = 0; index < kInputSize; ++index) {
#pragma HLS UNROLL
        quantized_input[index] = quantize_input_value(input[index], threshold);
    }
}

template <int OutputCount, int InputCount, typename WeightType>
static void bit_serial_vector_matrix_multiply(
    const ap_int<7> input[InputCount],
    const WeightType weights[OutputCount][InputCount],
    ap_int<20> result[OutputCount]) {
    for (int output_index = 0; output_index < OutputCount; ++output_index) {
#pragma HLS PIPELINE II=1
        ap_int<7> left_matrix[1][InputCount];
        ap_int<7> right_matrix[InputCount][1];
        ap_int<20> partial_output[1][1] = {{0}};

        for (int feature_index = 0; feature_index < InputCount; ++feature_index) {
#pragma HLS UNROLL
            left_matrix[0][feature_index] = input[feature_index];
            right_matrix[feature_index][0] = weights[output_index][feature_index];
        }

        BSMM::bitSerialMatrixMult<1, InputCount, 1, 7, 7, 20>(left_matrix, right_matrix, partial_output);
        result[output_index] = partial_output[0][0];
    }
}

static ap_int<20> requantize_ff0_output(
    const ap_int<20> raw_output,
    const int scale_factor,
    const int shift_value,
    const int bias,
    const int positive_threshold) {
    ap_int<36> scaled_output = static_cast<ap_int<36>>(raw_output) * static_cast<ap_uint<17>>(scale_factor);

    ap_int<20> y = (shift_value > 0)
        ? static_cast<ap_int<20>>((scaled_output + ((ap_int<36>)1 << (shift_value - 1))) >> shift_value)
        : static_cast<ap_int<20>>(scaled_output);

    y += bias;
    y = (y > positive_threshold) ? static_cast<ap_int<20>>(positive_threshold)
      : (y < -positive_threshold ? static_cast<ap_int<20>>(-positive_threshold) : y);

    return (y < 0) ? ap_int<20>(0) : y;
}

static ap_int<19> requantize_ff1_output(
    const ap_int<19> raw_output,
    const int scale_factor,
    const int shift_value,
    const int bias) {
    ap_int<35> scaled_output = static_cast<ap_int<35>>(raw_output) * static_cast<ap_uint<17>>(scale_factor);

    ap_int<19> y = (shift_value > 0)
        ? static_cast<ap_int<19>>((scaled_output + ((ap_int<35>)1 << (shift_value - 1))) >> shift_value)
        : static_cast<ap_int<19>>(scaled_output);

    y += bias;
    return y;
}

}  // namespace

void ffn_shared(int L, act_t input[kNumSamples][kInputSize], act_t output[kNumSamples][kOutputSize]) {
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

    ap_int<7> hidden_activation[kNumSamples][kHiddenSize];
#pragma HLS ARRAY_PARTITION variable=hidden_activation cyclic factor=128 dim=2

    for (int sample_index = 0; sample_index < kNumSamples; ++sample_index) {
#pragma HLS PIPELINE II=1
        ap_int<7> quantized_input[kInputSize];
        ap_int<20> hidden_pre_activation[kHiddenSize];

        quantize_input_block(input[sample_index], quantized_input, F0_THDIN[L]);
        bit_serial_vector_matrix_multiply<kHiddenSize, kInputSize>(quantized_input, ff0_W[L], hidden_pre_activation);

        for (int hidden_index = 0; hidden_index < kHiddenSize; ++hidden_index) {
#pragma HLS UNROLL
            hidden_activation[sample_index][hidden_index] = static_cast<ap_int<7>>(
                requantize_ff0_output(
                    hidden_pre_activation[hidden_index],
                    ff0_M0[L][hidden_index],
                    ff0_SH[L][hidden_index],
                    ff0_B[L][hidden_index],
                    F0_THDPOS[L]));
        }

        ap_int<20> output_pre_activation[kOutputSize];
        bit_serial_vector_matrix_multiply<kOutputSize, kHiddenSize>(hidden_activation[sample_index], ff1_W[L], output_pre_activation);

        for (int output_index = 0; output_index < kOutputSize; ++output_index) {
#pragma HLS UNROLL
            output[sample_index][output_index] = static_cast<act_t>(
                requantize_ff1_output(
                    static_cast<ap_int<19>>(output_pre_activation[output_index]),
                    ff1_M0[L][output_index],
                    ff1_SH[L][output_index],
                    ff1_B[L][output_index]));
        }
    }
}
