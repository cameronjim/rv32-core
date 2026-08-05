// imm_gen_tb: self-checking testbench for the RV32I immediate generator.
// Every vector is a real instruction encoding cross-checked against
// riscv-none-elf-as, covering all five formats plus unknown opcodes.

`timescale 1ns / 1ps

module imm_gen_tb;

  import rv32_pkg::*;

  localparam int DATA_WIDTH = 32;

  logic [DATA_WIDTH-1:0] instr;
  logic [DATA_WIDTH-1:0] imm;

  int unsigned checks;

  imm_gen #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .instr (instr),
    .imm   (imm)
  );

  task automatic check(
    input logic [DATA_WIDTH-1:0] instr_in,
    input logic [DATA_WIDTH-1:0] expected,
    input string                 name
  );
    instr = instr_in;
    #1;
    checks = checks + 1;
    if (imm !== expected) begin
      $display("FAIL: %s instr=0x%08h got=0x%08h expected=0x%08h",
               name, instr_in, imm, expected);
      $fatal(1);
    end
  endtask

  // B and J offsets encode a halfword-aligned target, bit 0 must never be set
  task automatic check_even(
    input logic [DATA_WIDTH-1:0] instr_in,
    input string                 name
  );
    instr = instr_in;
    #1;
    checks = checks + 1;
    if (imm[0] !== 1'b0) begin
      $display("FAIL: %s instr=0x%08h got=0x%08h expected bit 0 clear",
               name, instr_in, imm);
      $fatal(1);
    end
  endtask

  initial begin
    $dumpfile("sim/build/imm_gen_tb.vcd");
    $dumpvars(0, imm_gen_tb);

    checks = 0;

    // I format, OP_IMM: full signed range plus a shift where the funct7 bits
    // are part of the immediate rather than a separate field
    check(32'hFFF0_0093, 32'hFFFF_FFFF, "addi x1,x0,-1");
    check(32'h7FF0_0093, 32'h0000_07FF, "addi x1,x0,2047");
    check(32'h8000_0093, 32'hFFFF_F800, "addi x1,x0,-2048");
    check(32'hF002_7193, 32'hFFFF_FF00, "andi x3,x4,-256");
    check(32'h0013_3293, 32'h0000_0001, "sltiu x5,x6,1");
    check(32'h4051_5093, 32'h0000_0405, "srai x1,x2,5");
    check(32'h01F1_1093, 32'h0000_001F, "slli x1,x2,31");

    // I format, OP_LOAD: funct3 must not change the format selection
    check(32'h0080_A103, 32'h0000_0008, "lw x2,8(x1)");
    check(32'hFF80_A103, 32'hFFFF_FFF8, "lw x2,-8(x1)");
    check(32'hFFF4_0383, 32'hFFFF_FFFF, "lb x7,-1(x8)");
    check(32'h7FF5_5483, 32'h0000_07FF, "lhu x9,2047(x10)");

    // I format, OP_JALR
    check(32'hFEC1_00E7, 32'hFFFF_FFEC, "jalr x1,-20(x2)");
    check(32'h7FF1_00E7, 32'h0000_07FF, "jalr x1,2047(x2)");

    // S format: the immediate is split across instr[31:25] and instr[11:7]
    check(32'hFE20_AE23, 32'hFFFF_FFFC, "sw x2,-4(x1)");
    check(32'h0020_A823, 32'h0000_0010, "sw x2,16(x1)");
    check(32'h8020_A023, 32'hFFFF_F800, "sw x2,-2048(x1)");
    check(32'hFEB6_0FA3, 32'hFFFF_FFFF, "sb x11,-1(x12)");
    check(32'h00D7_10A3, 32'h0000_0001, "sh x13,1(x14)");

    // B format: 13 bit offset, imm[11] in instr[7] and imm[12] in instr[31]
    check(32'h0020_8463, 32'h0000_0008, "beq x1,x2,+8");
    check(32'hFE20_8CE3, 32'hFFFF_FFF8, "beq x1,x2,-8");
    check(32'hFE41_9FE3, 32'hFFFF_FFFE, "bne x3,x4,-2");
    // +2048 sets imm[11] only, the bit that lives outside its natural position
    check(32'h0062_C0E3, 32'h0000_0800, "blt x5,x6,+2048");
    check(32'h7E00_0FE3, 32'h0000_0FFE, "beq x0,x0,+4094");
    check(32'h8000_0063, 32'hFFFF_F000, "beq x0,x0,-4096");

    // U format: upper 20 bits pass through, low 12 bits are zero
    check(32'hFFFF_F0B7, 32'hFFFF_F000, "lui x1,0xFFFFF");
    check(32'h1234_50B7, 32'h1234_5000, "lui x1,0x12345");
    check(32'h0000_1297, 32'h0000_1000, "auipc x5,0x1");
    check(32'h8000_0097, 32'h8000_0000, "auipc x1,0x80000");

    // J format: 21 bit offset, imm[11] in instr[20] and imm[19:12] in place
    check(32'h0100_00EF, 32'h0000_0010, "jal x1,+16");
    check(32'hFF1F_F0EF, 32'hFFFF_FFF0, "jal x1,-16");
    check(32'h0010_006F, 32'h0000_0800, "jal x0,+2048");
    check(32'h0000_106F, 32'h0000_1000, "jal x0,+4096");
    check(32'h7FFF_F06F, 32'h000F_FFFE, "jal x0,+1048574");
    check(32'h8000_006F, 32'hFFF0_0000, "jal x0,-1048576");

    // opcodes with no immediate field
    check(32'h0031_00B3, 32'h0000_0000, "add x1,x2,x3 (R type)");
    check(32'h4062_86B3, 32'h0000_0000, "sub x13,x5,x6 (R type)");
    check(32'hFFFF_FFFF, 32'h0000_0000, "opcode 7'b1111111");
    check(32'h0000_007F, 32'h0000_0000, "opcode 7'b1111111, zero fields");
    check(32'h0000_0073, 32'h0000_0000, "ecall (OP_SYSTEM)");
    check(32'h0000_0000, 32'h0000_0000, "all zeros");

    // bit 0 of a branch or jump offset is never encoded, always reads back low
    check_even(32'h0020_8463, "beq +8 alignment");
    check_even(32'hFE20_8CE3, "beq -8 alignment");
    check_even(32'h7E00_0FE3, "beq +4094 alignment");
    check_even(32'h8000_0063, "beq -4096 alignment");
    check_even(32'hFFFF_FFE3, "branch, all encoded bits set");
    check_even(32'h0100_00EF, "jal +16 alignment");
    check_even(32'hFF1F_F0EF, "jal -16 alignment");
    check_even(32'h7FFF_F06F, "jal +1048574 alignment");
    check_even(32'h8000_006F, "jal -1048576 alignment");
    check_even(32'hFFFF_FFEF, "jal, all encoded bits set");

    // all-ones instruction fields: the widest negative offset each format can
    // encode, confirms sign extension fills every upper bit
    check(32'hFFFF_FFE3, 32'hFFFF_FFFE, "branch with every offset bit set");
    check(32'hFFFF_FFEF, 32'hFFFF_FFFE, "jal with every offset bit set");
    check(32'hFFFF_FFA3, 32'hFFFF_FFFF, "store with every offset bit set");

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: imm_gen");
    $finish;
  end

endmodule
