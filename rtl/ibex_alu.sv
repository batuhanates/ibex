// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Arithmetic logic unit
 */
module ibex_alu (
    input  ibex_pkg::alu_op_e operator_i,
    input  logic [31:0]       operand_a_i,
    input  logic [31:0]       operand_b_i,

    input  logic [32:0]       multdiv_operand_a_i,
    input  logic [32:0]       multdiv_operand_b_i,

    input  logic              multdiv_en_i,

    output logic [31:0]       adder_result_o,
    output logic [33:0]       adder_result_ext_o,

    output logic [31:0]       result_o,
    output logic              comparison_result_o,
    output logic              is_equal_result_o
);
  import ibex_pkg::*;

  logic [31:0] operand_a_rev;
  logic [32:0] operand_b_neg;

  // bit reverse operand_a for left shifts and bit counting
  for (genvar k = 0; k < 32; k++) begin : gen_rev_operand_a
    assign operand_a_rev[k] = operand_a_i[31-k];
  end

  ///////////
  // Adder //
  ///////////

  logic        adder_op_b_negate;
  logic [32:0] adder_in_a, adder_in_b;
  logic [31:0] adder_result;

  always_comb begin
    adder_op_b_negate = 1'b0;

    unique case (operator_i)
      // Adder OPs
      ALU_SUB,

      // Custom OPs
      ALU_CUST1, ALU_CUST2,

      // Comparator OPs
      ALU_EQ,   ALU_NE,
      ALU_GE,   ALU_GEU,
      ALU_LT,   ALU_LTU,
      ALU_SLT,  ALU_SLTU: adder_op_b_negate = 1'b1;

      default:;
    endcase
  end

  // prepare operand a
  assign adder_in_a    = multdiv_en_i ? multdiv_operand_a_i : {operand_a_i,1'b1};

  // prepare operand b
  assign operand_b_neg = {operand_b_i,1'b0} ^ {33{adder_op_b_negate}};
  assign adder_in_b    = multdiv_en_i ? multdiv_operand_b_i : operand_b_neg ;

  // actual adder
  assign adder_result_ext_o = $unsigned(adder_in_a) + $unsigned(adder_in_b);

  assign adder_result       = adder_result_ext_o[32:1];

  assign adder_result_o     = adder_result;

  ///////////
  // Shift //
  ///////////

  logic        shift_left;         // should we shift left
  logic        shift_arithmetic;

  logic  [4:0] shift_amt;          // amount of shift, to the right
  logic [31:0] shift_op_a;         // input of the shifter
  logic [31:0] shift_result;
  logic [31:0] shift_right_result;
  logic [31:0] shift_left_result;

  assign shift_amt = operand_b_i[4:0];

  assign shift_left = (operator_i == ALU_SLL);

  assign shift_arithmetic = (operator_i == ALU_SRA);

  // choose the bit reversed or the normal input for shift operand a
  assign shift_op_a    = shift_left ? operand_a_rev : operand_a_i;

  // right shifts, we let the synthesizer optimize this
  logic [32:0] shift_op_a_32;
  assign shift_op_a_32 = {shift_arithmetic & shift_op_a[31], shift_op_a};

  // The MSB of shift_right_result_ext can safely be ignored. We just extend the input to always
  // do arithmetic shifts.
  logic signed [32:0] shift_right_result_signed;
  logic        [32:0] shift_right_result_ext;
  assign shift_right_result_signed = $signed(shift_op_a_32) >>> shift_amt[4:0];
  assign shift_right_result_ext    = $unsigned(shift_right_result_signed);
  assign shift_right_result        = shift_right_result_ext[31:0];

  // bit reverse the shift_right_result for left shifts
  for (genvar j = 0; j < 32; j++) begin : gen_rev_shift_right_result
    assign shift_left_result[j] = shift_right_result[31-j];
  end

  assign shift_result = shift_left ? shift_left_result : shift_right_result;

  ////////////////
  // Comparison //
  ////////////////

  logic is_equal;
  logic is_greater_equal;  // handles both signed and unsigned forms
  logic cmp_signed;

  always_comb begin
    cmp_signed = 1'b0;

    unique case (operator_i)
      ALU_GE,
      ALU_LT,
      ALU_SLT: begin
        cmp_signed = 1'b1;
      end

      default:;
    endcase
  end

  assign is_equal = (adder_result == 32'b0);
  assign is_equal_result_o = is_equal;

  // Is greater equal
  always_comb begin
    if ((operand_a_i[31] ^ operand_b_i[31]) == 1'b0) begin
      is_greater_equal = (adder_result[31] == 1'b0);
    end else begin
      is_greater_equal = operand_a_i[31] ^ (cmp_signed);
    end
  end

  // GTE unsigned:
  // (a[31] == 1 && b[31] == 1) => adder_result[31] == 0
  // (a[31] == 0 && b[31] == 0) => adder_result[31] == 0
  // (a[31] == 1 && b[31] == 0) => 1
  // (a[31] == 0 && b[31] == 1) => 0

  // GTE signed:
  // (a[31] == 1 && b[31] == 1) => adder_result[31] == 0
  // (a[31] == 0 && b[31] == 0) => adder_result[31] == 0
  // (a[31] == 1 && b[31] == 0) => 0
  // (a[31] == 0 && b[31] == 1) => 1

  // generate comparison result
  logic cmp_result;

  always_comb begin
    cmp_result = is_equal;

    unique case (operator_i)
      ALU_EQ:            cmp_result =  is_equal;
      ALU_NE:            cmp_result = ~is_equal;
      ALU_GE,  ALU_GEU:  cmp_result = is_greater_equal;
      ALU_LT,  ALU_LTU,
      ALU_SLT, ALU_SLTU: cmp_result = ~is_greater_equal;

      default:;
    endcase
  end

  assign comparison_result_o = cmp_result;

  //////////////
  // Custom 0 //
  //////////////

  logic [31:0] cust0_result;
  logic [32:0] cust0_result_ext;
  logic [5:0] cust0_count_a;
  logic [5:0] cust0_count_b;
  logic [32:0] cust0_count_a_ext;
  logic [32:0] cust0_count_b_ext;

  logic [7:0][2:0] cust0_lut_counts_a;
  logic [7:0][2:0] cust0_lut_counts_b;
  logic [3:0][3:0] cust0_lut_add1_a;
  logic [3:0][3:0] cust0_lut_add1_b;
  logic [1:0][4:0] cust0_lut_add2_a;
  logic [1:0][4:0] cust0_lut_add2_b;

  generate
    for (genvar i = 0; i < 8; i = i + 1) begin : hw_luts
      hw_lut (
        .data (operand_a_i[4*i+3:4*i]),
        .count (cust0_lut_counts_a[i])
      );

      hw_lut (
        .data (operand_b_i[4*i+3:4*i]),
        .count (cust0_lut_counts_b[i])
      );
    end

    for (genvar i = 0; i < 8; i = i + 2) begin : hw_luts_add1
      assign cust0_lut_add1_a[i/2] = {1'b0, cust0_lut_counts_a[i]} + {1'b0, cust0_lut_counts_a[i+1]};
      assign cust0_lut_add1_b[i/2] = {1'b0, cust0_lut_counts_b[i]} + {1'b0, cust0_lut_counts_b[i+1]};
    end

    for (genvar i = 0; i < 4; i = i + 2) begin : hw_luts_add2
      assign cust0_lut_add2_a[i/2] = {1'b0, cust0_lut_add1_a[i]} + {1'b0, cust0_lut_add1_a[i+1]};
      assign cust0_lut_add2_b[i/2] = {1'b0, cust0_lut_add1_b[i]} + {1'b0, cust0_lut_add1_b[i+1]};
    end
  endgenerate

  assign cust0_count_a = {1'b0, cust0_lut_add2_a[0]} + {1'b0, cust0_lut_add2_a[1]};
  assign cust0_count_b = {1'b0, cust0_lut_add2_b[0]} + {1'b0, cust0_lut_add2_b[1]};

  assign cust0_count_a_ext[32:0] = {26'b0, cust0_count_a, 1'b1};
  assign cust0_count_b_ext[32:0] = ~{26'b0, cust0_count_b, 1'b0};
  assign cust0_result_ext = $unsigned(cust0_count_a_ext) + $unsigned(cust0_count_b_ext);
  assign cust0_result = cust0_result_ext[32:1];

  //////////////
  // Custom 1 //
  //////////////

  logic [31:0] cust1_m;
  logic [31:0] cust1_c;
  logic [31:0] cust1_result;

  assign cust1_m = adder_result;
  assign cust1_c = {32{cust1_m[31]}};
  assign cust1_result = cust1_m ^ ((operand_a_i ^ cust1_m) & cust1_c);

  //////////////
  // Custom 2 //
  //////////////

  logic [31:0] cust2_result;
  logic [31:0] cust2_r;
  logic [31:0] cust2_m;

  assign cust2_r = adder_result;
  assign cust2_m = {32{cust2_r[31]}};
  assign cust2_result = (cust2_r + cust2_m) ^ cust2_m;

  ////////////////
  // Result mux //
  ////////////////

  always_comb begin
    result_o   = '0;

    unique case (operator_i)
      // Standard Operations
      ALU_AND:  result_o = operand_a_i & operand_b_i;
      ALU_OR:   result_o = operand_a_i | operand_b_i;
      ALU_XOR:  result_o = operand_a_i ^ operand_b_i;

      // Adder Operations
      ALU_ADD, ALU_SUB: result_o = adder_result;

      // Shift Operations
      ALU_SLL,
      ALU_SRL, ALU_SRA: result_o = shift_result;

      // Comparison Operations
      ALU_EQ,   ALU_NE,
      ALU_GE,   ALU_GEU,
      ALU_LT,   ALU_LTU,
      ALU_SLT,  ALU_SLTU: result_o = {31'h0,cmp_result};

      // Custom Operations
      ALU_CUST0: result_o = cust0_result;
      ALU_CUST1: result_o = cust1_result;
      ALU_CUST2: result_o = cust2_result;

      default:;
    endcase
  end

endmodule
