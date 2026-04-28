// control_tb: self-checking testbench for the control decoder.
// Drives every row of the decode table plus unknown opcodes and compares
// all ten control outputs against the expected values from architecture.md.

`timescale 1ns / 1ps

module control_tb;

  import rv32_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic       funct7_b5;
  logic       reg_write;
  logic       alu_a_src;
  logic       alu_b_src;
  alu_op_e    alu_op;
  wb_sel_e    wb_sel;
  logic       mem_read;
  logic       mem_write;
  logic       branch;
  logic       jump;
  logic       jalr;

  control dut (
    .opcode    (opcode),
    .funct3    (funct3),
    .funct7_b5 (funct7_b5),
    .reg_write (reg_write),
    .alu_a_src (alu_a_src),
    .alu_b_src (alu_b_src),
    .alu_op    (alu_op),
    .wb_sel    (wb_sel),
    .mem_read  (mem_read),
    .mem_write (mem_write),
    .branch    (branch),
    .jump      (jump),
    .jalr      (jalr)
  );

  // iverilog does not implement enum .name(), so decode to text by hand
  function automatic string alu_op_str(input alu_op_e op);
    case (op)
      ALU_ADD:    alu_op_str = "ALU_ADD";
      ALU_SUB:    alu_op_str = "ALU_SUB";
      ALU_AND:    alu_op_str = "ALU_AND";
      ALU_OR:     alu_op_str = "ALU_OR";
      ALU_XOR:    alu_op_str = "ALU_XOR";
      ALU_SLL:    alu_op_str = "ALU_SLL";
      ALU_SRL:    alu_op_str = "ALU_SRL";
      ALU_SRA:    alu_op_str = "ALU_SRA";
      ALU_SLT:    alu_op_str = "ALU_SLT";
      ALU_SLTU:   alu_op_str = "ALU_SLTU";
      ALU_PASS_B: alu_op_str = "ALU_PASS_B";
      default:    alu_op_str = "ALU_???";
    endcase
  endfunction

  function automatic string wb_sel_str(input wb_sel_e sel);
    case (sel)
      WB_ALU:  wb_sel_str = "WB_ALU";
      WB_MEM:  wb_sel_str = "WB_MEM";
      WB_PC4:  wb_sel_str = "WB_PC4";
      default: wb_sel_str = "WB_???";
    endcase
  endfunction

  task automatic check_bit(input string instr_name, input string sig_name,
                           input logic got, input logic expected);
    if (got !== expected) begin
      $display("FAIL: %s signal %s got %0b expected %0b", instr_name, sig_name, got, expected);
      $fatal(1);
    end
  endtask

  task automatic check(input string          instr_name,
                       input logic     [6:0] i_opcode,
                       input logic     [2:0] i_funct3,
                       input logic           i_funct7_b5,
                       input logic           e_reg_write,
                       input logic           e_alu_a_src,
                       input logic           e_alu_b_src,
                       input alu_op_e        e_alu_op,
                       input wb_sel_e        e_wb_sel,
                       input logic           e_mem_read,
                       input logic           e_mem_write,
                       input logic           e_branch,
                       input logic           e_jump,
                       input logic           e_jalr);
    opcode    = i_opcode;
    funct3    = i_funct3;
    funct7_b5 = i_funct7_b5;
    #1;

    check_bit(instr_name, "reg_write", reg_write, e_reg_write);
    check_bit(instr_name, "alu_a_src", alu_a_src, e_alu_a_src);
    check_bit(instr_name, "alu_b_src", alu_b_src, e_alu_b_src);
    check_bit(instr_name, "mem_read",  mem_read,  e_mem_read);
    check_bit(instr_name, "mem_write", mem_write, e_mem_write);
    check_bit(instr_name, "branch",    branch,    e_branch);
    check_bit(instr_name, "jump",      jump,      e_jump);
    check_bit(instr_name, "jalr",      jalr,      e_jalr);

    if (alu_op !== e_alu_op) begin
      $display("FAIL: %s signal alu_op got %s expected %s",
               instr_name, alu_op_str(alu_op), alu_op_str(e_alu_op));
      $fatal(1);
    end
    if (wb_sel !== e_wb_sel) begin
      $display("FAIL: %s signal wb_sel got %s expected %s",
               instr_name, wb_sel_str(wb_sel), wb_sel_str(e_wb_sel));
      $fatal(1);
    end
  endtask

  initial begin
    $dumpfile("sim/build/control_tb.vcd");
    $dumpvars(0, control_tb);

    //                            opcode     funct3      b30  rw a_src b_src alu_op      wb_sel  mr mw br jmp jalr
    // R-type, alu_op from funct3 and instr[30]
    check("add",   OP_REG,    F3_ADD_SUB, 1'b0, 1'b1, 1'b0, 1'b0, ALU_ADD,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("sub",   OP_REG,    F3_ADD_SUB, 1'b1, 1'b1, 1'b0, 1'b0, ALU_SUB,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("sll",   OP_REG,    F3_SLL,     1'b0, 1'b1, 1'b0, 1'b0, ALU_SLL,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("slt",   OP_REG,    F3_SLT,     1'b0, 1'b1, 1'b0, 1'b0, ALU_SLT,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("sltu",  OP_REG,    F3_SLTU,    1'b0, 1'b1, 1'b0, 1'b0, ALU_SLTU,   WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("xor",   OP_REG,    F3_XOR,     1'b0, 1'b1, 1'b0, 1'b0, ALU_XOR,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("srl",   OP_REG,    F3_SRL_SRA, 1'b0, 1'b1, 1'b0, 1'b0, ALU_SRL,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("sra",   OP_REG,    F3_SRL_SRA, 1'b1, 1'b1, 1'b0, 1'b0, ALU_SRA,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("or",    OP_REG,    F3_OR,      1'b0, 1'b1, 1'b0, 1'b0, ALU_OR,     WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("and",   OP_REG,    F3_AND,     1'b0, 1'b1, 1'b0, 1'b0, ALU_AND,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

    // I-arith, instr[30] only matters for shifts
    check("addi",  OP_IMM,    F3_ADD_SUB, 1'b0, 1'b1, 1'b0, 1'b1, ALU_ADD,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    // addi with a negative immediate sets instr[30], which must not decode as sub
    check("addi_neg_imm", OP_IMM, F3_ADD_SUB, 1'b1, 1'b1, 1'b0, 1'b1, ALU_ADD, WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("slti",  OP_IMM,    F3_SLT,     1'b0, 1'b1, 1'b0, 1'b1, ALU_SLT,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("sltiu", OP_IMM,    F3_SLTU,    1'b0, 1'b1, 1'b0, 1'b1, ALU_SLTU,   WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("xori",  OP_IMM,    F3_XOR,     1'b0, 1'b1, 1'b0, 1'b1, ALU_XOR,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("ori",   OP_IMM,    F3_OR,      1'b0, 1'b1, 1'b0, 1'b1, ALU_OR,     WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("andi",  OP_IMM,    F3_AND,     1'b0, 1'b1, 1'b0, 1'b1, ALU_AND,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("slli",  OP_IMM,    F3_SLL,     1'b0, 1'b1, 1'b0, 1'b1, ALU_SLL,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("srli",  OP_IMM,    F3_SRL_SRA, 1'b0, 1'b1, 1'b0, 1'b1, ALU_SRL,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("srai",  OP_IMM,    F3_SRL_SRA, 1'b1, 1'b1, 1'b0, 1'b1, ALU_SRA,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

    // loads and stores, address is rs1 + imm
    check("lw",    OP_LOAD,   F3_LW,      1'b0, 1'b1, 1'b0, 1'b1, ALU_ADD,    WB_MEM, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    check("lb",    OP_LOAD,   F3_LB,      1'b0, 1'b1, 1'b0, 1'b1, ALU_ADD,    WB_MEM, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    check("sw",    OP_STORE,  F3_LW,      1'b0, 1'b0, 1'b0, 1'b1, ALU_ADD,    WB_ALU, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
    check("sb",    OP_STORE,  F3_LB,      1'b0, 1'b0, 1'b0, 1'b1, ALU_ADD,    WB_ALU, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);

    // branches, resolved by branch_cmp so the ALU inputs are don't care defaults
    check("beq",   OP_BRANCH, F3_BEQ,     1'b0, 1'b0, 1'b0, 1'b0, ALU_ADD,    WB_ALU, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
    check("bne",   OP_BRANCH, F3_BNE,     1'b0, 1'b0, 1'b0, 1'b0, ALU_ADD,    WB_ALU, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
    check("bltu",  OP_BRANCH, F3_BLTU,    1'b0, 1'b0, 1'b0, 1'b0, ALU_ADD,    WB_ALU, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

    // jumps, link value comes from PC+4
    check("jal",   OP_JAL,    3'b000,     1'b0, 1'b1, 1'b0, 1'b0, ALU_ADD,    WB_PC4, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    check("jalr",  OP_JALR,   3'b000,     1'b0, 1'b1, 1'b0, 1'b1, ALU_ADD,    WB_PC4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);

    // upper immediates
    check("lui",   OP_LUI,    3'b000,     1'b0, 1'b1, 1'b0, 1'b1, ALU_PASS_B, WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("auipc", OP_AUIPC,  3'b000,     1'b0, 1'b1, 1'b1, 1'b1, ALU_ADD,    WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

    // unknown opcodes decode to a nop that writes nothing
    check("unknown_0000000", 7'b0000000, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, ALU_ADD, WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("unknown_1111111", 7'b1111111, 3'b111, 1'b1, 1'b0, 1'b0, 1'b0, ALU_ADD, WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    check("unknown_0001011", 7'b0001011, 3'b101, 1'b1, 1'b0, 1'b0, 1'b0, ALU_ADD, WB_ALU, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

    $display("PASS: control");
    $finish;
  end

endmodule
