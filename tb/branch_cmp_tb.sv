// branch_cmp_tb: self-checking testbench for the branch comparator.
// Runs directed cases for all six branch types plus undefined funct3, then a
// randomized loop cross-checked against $signed / unsigned reference compares.

`timescale 1ns / 1ps

module branch_cmp_tb
  import rv32_pkg::*;
;

  localparam int DATA_WIDTH = 32;
  localparam int RANDOM_CASES = 2000;

  logic [DATA_WIDTH-1:0] rs1_data;
  logic [DATA_WIDTH-1:0] rs2_data;
  logic [2:0]            funct3;
  logic                  taken;

  branch_cmp #(
    .DATA_WIDTH (DATA_WIDTH)
  ) dut (
    .rs1_data (rs1_data),
    .rs2_data (rs2_data),
    .funct3   (funct3),
    .taken    (taken)
  );

  // drive one case, settle combinationally, compare against expected
  task automatic check(input logic [2:0]            f3,
                       input logic [DATA_WIDTH-1:0] a,
                       input logic [DATA_WIDTH-1:0] b,
                       input logic                  expected);
    begin
      funct3   = f3;
      rs1_data = a;
      rs2_data = b;
      #1;
      if (taken !== expected) begin
        $display("FAIL: funct3=%03b rs1=0x%08h rs2=0x%08h got=%b expected=%b",
                 f3, a, b, taken, expected);
        $fatal(1);
      end
    end
  endtask

  // reference model, independent of the DUT case statement
  function automatic logic expect_taken(input logic [2:0]            f3,
                                        input logic [DATA_WIDTH-1:0] a,
                                        input logic [DATA_WIDTH-1:0] b);
    case (f3)
      F3_BEQ:  expect_taken = (a == b);
      F3_BNE:  expect_taken = (a != b);
      F3_BLT:  expect_taken = ($signed(a) <  $signed(b));
      F3_BGE:  expect_taken = ($signed(a) >= $signed(b));
      F3_BLTU: expect_taken = (a <  b);
      F3_BGEU: expect_taken = (a >= b);
      default: expect_taken = 1'b0;
    endcase
  endfunction

  logic [DATA_WIDTH-1:0] rand_a;
  logic [DATA_WIDTH-1:0] rand_b;
  logic [2:0]            rand_f3;

  initial begin
    $dumpfile("sim/build/branch_cmp_tb.vcd");
    $dumpvars(0, branch_cmp_tb);

    // beq: taken and not taken
    check(F3_BEQ, 32'd7, 32'd7, 1'b1);
    check(F3_BEQ, 32'd7, 32'd8, 1'b0);

    // bne: taken and not taken
    check(F3_BNE, 32'd7, 32'd8, 1'b1);
    check(F3_BNE, 32'd7, 32'd7, 1'b0);

    // blt signed: taken and not taken
    check(F3_BLT, 32'hFFFF_FFFB, 32'd3, 1'b1);
    check(F3_BLT, 32'd3, 32'hFFFF_FFFB, 1'b0);

    // bge signed: taken and not taken
    check(F3_BGE, 32'd3, 32'hFFFF_FFFB, 1'b1);
    check(F3_BGE, 32'hFFFF_FFFB, 32'd3, 1'b0);

    // bltu: taken and not taken
    check(F3_BLTU, 32'd3, 32'hFFFF_FFFB, 1'b1);
    check(F3_BLTU, 32'hFFFF_FFFB, 32'd3, 1'b0);

    // bgeu: taken and not taken
    check(F3_BGEU, 32'hFFFF_FFFB, 32'd3, 1'b1);
    check(F3_BGEU, 32'd3, 32'hFFFF_FFFB, 1'b0);

    // equal operands across all six encodings
    check(F3_BEQ,  32'h1234_5678, 32'h1234_5678, 1'b1);
    check(F3_BNE,  32'h1234_5678, 32'h1234_5678, 1'b0);
    check(F3_BLT,  32'h1234_5678, 32'h1234_5678, 1'b0);
    check(F3_BGE,  32'h1234_5678, 32'h1234_5678, 1'b1);
    check(F3_BLTU, 32'h1234_5678, 32'h1234_5678, 1'b0);
    check(F3_BGEU, 32'h1234_5678, 32'h1234_5678, 1'b1);

    // zero versus zero
    check(F3_BEQ,  32'd0, 32'd0, 1'b1);
    check(F3_BNE,  32'd0, 32'd0, 1'b0);
    check(F3_BLT,  32'd0, 32'd0, 1'b0);
    check(F3_BGE,  32'd0, 32'd0, 1'b1);
    check(F3_BLTU, 32'd0, 32'd0, 1'b0);
    check(F3_BGEU, 32'd0, 32'd0, 1'b1);

    // signed and unsigned disagree: -1 is below 1 signed, above it unsigned
    check(F3_BLT,  32'hFFFF_FFFF, 32'd1, 1'b1);
    check(F3_BGE,  32'hFFFF_FFFF, 32'd1, 1'b0);
    check(F3_BLTU, 32'hFFFF_FFFF, 32'd1, 1'b0);
    check(F3_BGEU, 32'hFFFF_FFFF, 32'd1, 1'b1);

    // the signed/unsigned boundary at 0x80000000, both operand orders
    check(F3_BLT,  32'h8000_0000, 32'h7FFF_FFFF, 1'b1);
    check(F3_BGE,  32'h8000_0000, 32'h7FFF_FFFF, 1'b0);
    check(F3_BLTU, 32'h8000_0000, 32'h7FFF_FFFF, 1'b0);
    check(F3_BGEU, 32'h8000_0000, 32'h7FFF_FFFF, 1'b1);
    check(F3_BLT,  32'h7FFF_FFFF, 32'h8000_0000, 1'b0);
    check(F3_BGE,  32'h7FFF_FFFF, 32'h8000_0000, 1'b1);
    check(F3_BLTU, 32'h7FFF_FFFF, 32'h8000_0000, 1'b1);
    check(F3_BGEU, 32'h7FFF_FFFF, 32'h8000_0000, 1'b0);

    // zero against the most negative value
    check(F3_BLT,  32'h8000_0000, 32'd0, 1'b1);
    check(F3_BGE,  32'd0, 32'h8000_0000, 1'b1);
    check(F3_BLTU, 32'd0, 32'h8000_0000, 1'b1);
    check(F3_BGEU, 32'h8000_0000, 32'd0, 1'b1);

    // undefined funct3 encodings never take the branch
    check(3'b010, 32'd0, 32'd0, 1'b0);
    check(3'b010, 32'hFFFF_FFFF, 32'd1, 1'b0);
    check(3'b011, 32'd5, 32'd5, 1'b0);
    check(3'b011, 32'h8000_0000, 32'h7FFF_FFFF, 1'b0);

    for (int i = 0; i < RANDOM_CASES; i++) begin
      rand_a  = $urandom();
      rand_b  = $urandom();
      rand_f3 = $urandom_range(0, 7);
      // bias toward equal and boundary operands so those paths get hit often
      if (i % 8 == 0) rand_b = rand_a;
      if (i % 8 == 1) rand_a = 32'h8000_0000;
      if (i % 8 == 2) rand_b = 32'hFFFF_FFFF;
      check(rand_f3, rand_a, rand_b, expect_taken(rand_f3, rand_a, rand_b));
    end

    $display("PASS: branch_cmp");
    $finish;
  end

endmodule
