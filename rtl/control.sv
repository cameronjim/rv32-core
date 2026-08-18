// control: pure combinational instruction decoder for the RV32I core.
// Maps opcode, funct3 and instr[30] to datapath control signals.
// Unknown opcodes decode to all zeros, a nop that writes nothing.

module control
  import rv32_pkg::*;
(
  input  logic [6:0] opcode,
  input  logic [2:0] funct3,
  input  logic       funct7_b5,
  output logic       reg_write,
  output logic       alu_a_src,
  output logic       alu_b_src,
  output alu_op_e    alu_op,
  output wb_sel_e    wb_sel,
  output logic       mem_read,
  output logic       mem_write,
  output logic       branch,
  output logic       jump,
  output logic       jalr,
  // which register fields this instruction actually reads. The pipeline's
  // hazard unit qualifies its load-use match with these, so an instruction
  // that never reads rs1 or rs2 cannot stall on a stale field.
  output logic       uses_rs1,
  output logic       uses_rs2
);

  // ALU op decoded from funct3 for R-type and I-arith. is_reg gates sub, since
  // funct7_b5 is part of the immediate for addi and must be ignored there.
  function automatic alu_op_e funct3_alu_op(logic [2:0] f3, logic b30, logic is_reg);
    case (f3)
      F3_ADD_SUB: begin
        if (is_reg && b30) funct3_alu_op = ALU_SUB;
        else               funct3_alu_op = ALU_ADD;
      end
      F3_SLL:     funct3_alu_op = ALU_SLL;
      F3_SLT:     funct3_alu_op = ALU_SLT;
      F3_SLTU:    funct3_alu_op = ALU_SLTU;
      F3_XOR:     funct3_alu_op = ALU_XOR;
      // b30 selects srai for both R-type and I-arith shifts
      F3_SRL_SRA: begin
        if (b30) funct3_alu_op = ALU_SRA;
        else     funct3_alu_op = ALU_SRL;
      end
      F3_OR:      funct3_alu_op = ALU_OR;
      F3_AND:     funct3_alu_op = ALU_AND;
      default:    funct3_alu_op = ALU_ADD;
    endcase
  endfunction

  always_comb begin
    // benign defaults, also the decode for unknown opcodes
    reg_write = 1'b0;
    alu_a_src = 1'b0;
    alu_b_src = 1'b0;
    alu_op    = ALU_ADD;
    wb_sel    = WB_ALU;
    mem_read  = 1'b0;
    mem_write = 1'b0;
    branch    = 1'b0;
    jump      = 1'b0;
    jalr      = 1'b0;
    uses_rs1  = 1'b0;
    uses_rs2  = 1'b0;

    case (opcode)
      OP_REG: begin
        reg_write = 1'b1;
        alu_op    = funct3_alu_op(funct3, funct7_b5, 1'b1);
        uses_rs1  = 1'b1;
        uses_rs2  = 1'b1;
      end

      OP_IMM: begin
        reg_write = 1'b1;
        alu_b_src = 1'b1;
        alu_op    = funct3_alu_op(funct3, funct7_b5, 1'b0);
        uses_rs1  = 1'b1;
      end

      OP_LOAD: begin
        reg_write = 1'b1;
        alu_b_src = 1'b1;
        wb_sel    = WB_MEM;
        mem_read  = 1'b1;
        uses_rs1  = 1'b1;
      end

      // the store address is rs1 + imm and the stored word is rs2, so a store
      // reads both fields even though its alu_b is the immediate
      OP_STORE: begin
        alu_b_src = 1'b1;
        mem_write = 1'b1;
        uses_rs1  = 1'b1;
        uses_rs2  = 1'b1;
      end

      OP_BRANCH: begin
        branch   = 1'b1;
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
      end

      // jal links pc+4 and targets pc+imm, so it reads no register
      OP_JAL: begin
        reg_write = 1'b1;
        wb_sel    = WB_PC4;
        jump      = 1'b1;
      end

      OP_JALR: begin
        reg_write = 1'b1;
        alu_b_src = 1'b1;
        wb_sel    = WB_PC4;
        jalr      = 1'b1;
        uses_rs1  = 1'b1;
      end

      OP_LUI: begin
        reg_write = 1'b1;
        alu_b_src = 1'b1;
        alu_op    = ALU_PASS_B;
      end

      OP_AUIPC: begin
        reg_write = 1'b1;
        alu_a_src = 1'b1;
        alu_b_src = 1'b1;
      end

      default: ;
    endcase
  end

endmodule
