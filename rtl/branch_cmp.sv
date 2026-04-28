// branch_cmp: pure combinational branch condition comparator.
// Compares rs1_data against rs2_data under the branch funct3 encoding and
// asserts taken. Undefined funct3 values (010, 011) leave taken deasserted.

module branch_cmp
  import rv32_pkg::*;
#(
  parameter int DATA_WIDTH = 32
) (
  input  logic [DATA_WIDTH-1:0] rs1_data,
  input  logic [DATA_WIDTH-1:0] rs2_data,
  input  logic [2:0]            funct3,
  output logic                  taken
);

  logic eq;
  logic lt_signed;
  logic lt_unsigned;

  assign eq          = (rs1_data == rs2_data);
  assign lt_signed   = ($signed(rs1_data) < $signed(rs2_data));
  assign lt_unsigned = (rs1_data < rs2_data);

  always_comb begin
    case (funct3)
      F3_BEQ:  taken = eq;
      F3_BNE:  taken = !eq;
      F3_BLT:  taken = lt_signed;
      F3_BGE:  taken = !lt_signed;
      F3_BLTU: taken = lt_unsigned;
      F3_BGEU: taken = !lt_unsigned;
      default: taken = 1'b0;
    endcase
  end

endmodule
