// hazard_unit: pure combinational stall and flush control for the pipeline.
// Detects the load-use hazard between ID/EX and IF/ID and turns an EX stage
// control flow redirect into pipeline flushes. Redirect wins over stall.

module hazard_unit #(
  parameter int REG_ADDR_WIDTH = 5
) (
  input  logic                      id_ex_mem_read,
  input  logic [REG_ADDR_WIDTH-1:0] id_ex_rd,
  input  logic [REG_ADDR_WIDTH-1:0] if_id_rs1,
  input  logic [REG_ADDR_WIDTH-1:0] if_id_rs2,
  // decoder flags: whether the IF/ID instruction actually reads that register
  input  logic                      if_id_uses_rs1,
  input  logic                      if_id_uses_rs2,
  // EX is taking a branch, jal or jalr this cycle
  input  logic                      ex_redirect,
  output logic                      stall_pc,
  output logic                      stall_if_id,
  output logic                      flush_if_id,
  output logic                      bubble_id_ex
);

  // a load in EX can only hazard when it writes a register other than x0
  logic load_in_ex;
  logic rs1_match;
  logic rs2_match;
  logic load_use;

  assign load_in_ex = id_ex_mem_read && (id_ex_rd != '0);
  assign rs1_match  = if_id_uses_rs1 && (id_ex_rd == if_id_rs1);
  assign rs2_match  = if_id_uses_rs2 && (id_ex_rd == if_id_rs2);
  assign load_use   = load_in_ex && (rs1_match || rs2_match);

  // the stalled instruction is wrong-path on a redirect, so drop the stall
  assign stall_pc     = load_use && !ex_redirect;
  assign stall_if_id  = load_use && !ex_redirect;
  assign flush_if_id  = ex_redirect;
  assign bubble_id_ex = load_use || ex_redirect;

endmodule
