// reg_file: 32 x 32 bit RISC-V register file with two combinational read
// ports and one synchronous write port. x0 is hardwired to zero. No
// write-through: a read in the same cycle as a write returns the old value.

module reg_file #(
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 32,
    parameter int ADDR_WIDTH = $clog2(NUM_REGS)
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [ADDR_WIDTH-1:0] rs1_addr,
    output logic [DATA_WIDTH-1:0] rs1_data,
    input  logic [ADDR_WIDTH-1:0] rs2_addr,
    output logic [DATA_WIDTH-1:0] rs2_data,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    input  logic [DATA_WIDTH-1:0] rd_data,
    input  logic                  rd_we
);

  // writes to x0 are gated off below; the read muxes also force zero so x0
  // reads clean even before the first reset
  logic [DATA_WIDTH-1:0] regs[NUM_REGS];

  assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_REGS; i++) begin
        regs[i] <= '0;
      end
    end else if (rd_we && (rd_addr != '0)) begin
      regs[rd_addr] <= rd_data;
    end
  end

endmodule
