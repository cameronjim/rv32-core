// imm_gen: pure combinational immediate generator for the RV32I core.
// Picks the I, S, B, U, or J immediate field based on the opcode and sign
// extends it to the full datapath width. Unknown opcodes produce zero.

module imm_gen
  import rv32_pkg::*;
#(
  parameter int DATA_WIDTH = 32
) (
  input  logic [DATA_WIDTH-1:0] instr,
  output logic [DATA_WIDTH-1:0] imm
);

  logic [6:0]            opcode;
  logic [DATA_WIDTH-1:0] imm_i;
  logic [DATA_WIDTH-1:0] imm_s;
  logic [DATA_WIDTH-1:0] imm_b;
  logic [DATA_WIDTH-1:0] imm_u;
  logic [DATA_WIDTH-1:0] imm_j;

  assign opcode = instr[6:0];

  // field layouts follow the unprivileged ISA spec, instr[31] is always the
  // sign bit so every format sign extends from the same wire

  assign imm_i = {{20{instr[31]}}, instr[31:20]};

  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};

  // B is a 13 bit signed offset with bit 0 hardwired low, so only 12 bits are
  // encoded and imm[11] sits in instr[7] while imm[12] sits in instr[31]
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

  assign imm_u = {instr[31:12], 12'b0};

  // J is a 21 bit signed offset with bit 0 hardwired low; the fields are
  // shuffled so that imm[10:1] and imm[19:12] land in the same instruction
  // bit positions they occupy in the B and U formats
  assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  always_comb begin
    case (opcode)
      OP_LOAD, OP_IMM, OP_JALR: imm = imm_i;
      OP_STORE:                 imm = imm_s;
      OP_BRANCH:                imm = imm_b;
      OP_LUI, OP_AUIPC:         imm = imm_u;
      OP_JAL:                   imm = imm_j;
      default:                  imm = '0;
    endcase
  end

endmodule
