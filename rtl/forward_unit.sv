// forward_unit: pure combinational data hazard bypass selects for the EX stage.
// Compares the ID/EX source registers against the EX/MEM and MEM/WB destinations
// and picks the newest writer, EX/MEM ahead of MEM/WB, x0 never forwards.

module forward_unit #(
  parameter int REG_ADDR_WIDTH = 5,
  parameter int FWD_WIDTH      = 2
) (
  input  logic [REG_ADDR_WIDTH-1:0] id_ex_rs1,
  input  logic [REG_ADDR_WIDTH-1:0] id_ex_rs2,
  input  logic [REG_ADDR_WIDTH-1:0] ex_mem_rd,
  input  logic                      ex_mem_reg_write,
  input  logic [REG_ADDR_WIDTH-1:0] mem_wb_rd,
  input  logic                      mem_wb_reg_write,
  output logic [FWD_WIDTH-1:0]      fwd_a,
  output logic [FWD_WIDTH-1:0]      fwd_b
);

  // select encoding, mirrored by cpu_top's operand muxes
  localparam logic [FWD_WIDTH-1:0] FWD_REG    = 2'b00;
  localparam logic [FWD_WIDTH-1:0] FWD_EX_MEM = 2'b01;
  localparam logic [FWD_WIDTH-1:0] FWD_MEM_WB = 2'b10;

  // a stage can only bypass when it actually writes a register other than x0
  logic ex_mem_valid;
  logic mem_wb_valid;

  assign ex_mem_valid = ex_mem_reg_write && (ex_mem_rd != '0);
  assign mem_wb_valid = mem_wb_reg_write && (mem_wb_rd != '0);

  always_comb begin
    // newest writer wins, so EX/MEM is tested before MEM/WB
    if (ex_mem_valid && (ex_mem_rd == id_ex_rs1)) begin
      fwd_a = FWD_EX_MEM;
    end else if (mem_wb_valid && (mem_wb_rd == id_ex_rs1)) begin
      fwd_a = FWD_MEM_WB;
    end else begin
      fwd_a = FWD_REG;
    end

    if (ex_mem_valid && (ex_mem_rd == id_ex_rs2)) begin
      fwd_b = FWD_EX_MEM;
    end else if (mem_wb_valid && (mem_wb_rd == id_ex_rs2)) begin
      fwd_b = FWD_MEM_WB;
    end else begin
      fwd_b = FWD_REG;
    end
  end

endmodule
