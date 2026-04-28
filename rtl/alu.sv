// alu: pure combinational arithmetic and logic unit for the RV32I core.
// Selects one of eleven operations with op; shifts use the low 5 bits of b.
// No flags and no zero output, branches are resolved by branch_cmp instead.

module alu
  import rv32_pkg::*;
#(
  parameter int DATA_WIDTH = 32
) (
  input  logic [DATA_WIDTH-1:0] a,
  input  logic [DATA_WIDTH-1:0] b,
  input  alu_op_e               op,
  output logic [DATA_WIDTH-1:0] result
);

  // shift amount field width: 5 bits for a 32 bit datapath
  localparam int SHAMT_WIDTH = $clog2(DATA_WIDTH);

  logic [SHAMT_WIDTH-1:0] shamt;

  assign shamt = b[SHAMT_WIDTH-1:0];

  always_comb begin
    case (op)
      ALU_ADD:    result = a + b;
      ALU_SUB:    result = a - b;
      ALU_AND:    result = a & b;
      ALU_OR:     result = a | b;
      ALU_XOR:    result = a ^ b;
      ALU_SLL:    result = a << shamt;
      ALU_SRL:    result = a >> shamt;
      // arithmetic shift needs both operand and operator signed to replicate the sign bit
      ALU_SRA:    result = $signed(a) >>> shamt;
      ALU_SLT:    result = {{DATA_WIDTH-1{1'b0}}, ($signed(a) < $signed(b))};
      ALU_SLTU:   result = {{DATA_WIDTH-1{1'b0}}, (a < b)};
      ALU_PASS_B: result = b;
      default:    result = '0;
    endcase
  end

endmodule
