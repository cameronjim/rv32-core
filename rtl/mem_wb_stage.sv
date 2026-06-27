// mem_wb_stage: the pipeline's back end, the EX/MEM and MEM/WB registers with
// the memory access and writeback logic between them. Owns the external data
// bus protocol and the load extension, and taps out the values the forwarding
// unit and the register file write port need. Split out of cpu_top to keep
// both files inside the size rule.

module mem_wb_stage
  import rv32_pkg::*;
#(
  parameter int DATA_WIDTH     = 32,
  parameter int REG_ADDR_WIDTH = 5
) (
  input  logic                      clk,
  input  logic                      rst_n,
  // EX stage results entering the EX/MEM register
  input  logic [DATA_WIDTH-1:0]     ex_alu_result,
  input  logic [DATA_WIDTH-1:0]     ex_store_data,
  input  logic [DATA_WIDTH-1:0]     ex_pc_plus4,
  input  logic [REG_ADDR_WIDTH-1:0] ex_rd,
  input  logic [2:0]                ex_funct3,
  input  logic                      ex_reg_write,
  input  wb_sel_e                   ex_wb_sel,
  input  logic                      ex_mem_read,
  input  logic                      ex_mem_write,
  // external data bus, byte addressed
  output logic [DATA_WIDTH-1:0]     dmem_addr,
  output logic [DATA_WIDTH-1:0]     dmem_wdata,
  output logic [DATA_WIDTH/8-1:0]   dmem_be,
  output logic                      dmem_we,
  output logic                      dmem_re,
  input  logic [DATA_WIDTH-1:0]     dmem_rdata,
  // taps for the forwarding unit, the WB-to-ID bypass and the register file
  output logic [DATA_WIDTH-1:0]     ex_mem_alu_result,
  output logic [REG_ADDR_WIDTH-1:0] ex_mem_rd,
  output logic                      ex_mem_reg_write,
  output logic [REG_ADDR_WIDTH-1:0] mem_wb_rd,
  output logic                      mem_wb_reg_write,
  output logic [DATA_WIDTH-1:0]     wb_data
);

  logic [DATA_WIDTH-1:0] ex_mem_store_data;
  logic [DATA_WIDTH-1:0] ex_mem_pc_plus4;
  logic [2:0]            ex_mem_funct3;
  logic [1:0]            ex_mem_addr_lo;
  wb_sel_e               ex_mem_wb_sel;
  logic                  ex_mem_mem_read;
  logic                  ex_mem_mem_write;

  logic [DATA_WIDTH-1:0] mem_wb_alu_result;
  logic [DATA_WIDTH-1:0] mem_wb_pc_plus4;
  logic [2:0]            mem_wb_funct3;
  logic [1:0]            mem_wb_addr_lo;
  wb_sel_e               mem_wb_wb_sel;
  logic                  mem_wb_mem_read;

  logic [DATA_WIDTH-1:0] load_data;

  // EX/MEM
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ex_mem_alu_result <= '0;
      ex_mem_store_data <= '0;
      ex_mem_pc_plus4   <= '0;
      ex_mem_rd         <= '0;
      ex_mem_funct3     <= '0;
      ex_mem_addr_lo    <= '0;
      ex_mem_reg_write  <= 1'b0;
      ex_mem_wb_sel     <= WB_ALU;
      ex_mem_mem_read   <= 1'b0;
      ex_mem_mem_write  <= 1'b0;
    end else begin
      ex_mem_alu_result <= ex_alu_result;
      ex_mem_store_data <= ex_store_data;
      ex_mem_pc_plus4   <= ex_pc_plus4;
      ex_mem_rd         <= ex_rd;
      ex_mem_funct3     <= ex_funct3;
      ex_mem_addr_lo    <= ex_alu_result[1:0];
      ex_mem_reg_write  <= ex_reg_write;
      ex_mem_wb_sel     <= ex_wb_sel;
      ex_mem_mem_read   <= ex_mem_read;
      ex_mem_mem_write  <= ex_mem_write;
    end
  end

  // Data bus ownership. dmem answers a cycle late: it captures the address at
  // the MEM/WB boundary edge and its output register holds the word through
  // WB. The instantiating level qualifies the read data with dmem_re and its
  // own address decode, so that word only reaches the core while the load's
  // address is still on the bus. A load therefore owns the bus for two
  // cycles, MEM and WB, and cpu_top's data bus stall keeps the MEM stage
  // empty of memory work during the second one, so the two never collide.
  // That also makes ex_mem_mem_read and mem_wb_mem_read mutually exclusive,
  // which is why this mux needs no priority beyond the load in WB.
  assign dmem_addr = mem_wb_mem_read ? mem_wb_alu_result : ex_mem_alu_result;
  assign dmem_re   = ex_mem_mem_read || mem_wb_mem_read;
  assign dmem_we   = ex_mem_mem_write;

  // MEM/WB. The load word itself needs no flop: the bus is still parked on
  // this load's address during WB, so both flavors of memory are readable
  // right there, the block RAM through its output register and mmio through
  // its combinational read.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mem_wb_alu_result <= '0;
      mem_wb_pc_plus4   <= '0;
      mem_wb_rd         <= '0;
      mem_wb_funct3     <= '0;
      mem_wb_addr_lo    <= '0;
      mem_wb_reg_write  <= 1'b0;
      mem_wb_wb_sel     <= WB_ALU;
      mem_wb_mem_read   <= 1'b0;
    end else begin
      mem_wb_alu_result <= ex_mem_alu_result;
      mem_wb_pc_plus4   <= ex_mem_pc_plus4;
      mem_wb_rd         <= ex_mem_rd;
      mem_wb_funct3     <= ex_mem_funct3;
      mem_wb_addr_lo    <= ex_mem_addr_lo;
      mem_wb_reg_write  <= ex_mem_reg_write;
      mem_wb_wb_sel     <= ex_mem_wb_sel;
      mem_wb_mem_read   <= ex_mem_mem_read;
    end
  end

  always_comb begin
    case (mem_wb_wb_sel)
      WB_MEM:  wb_data = load_data;
      WB_PC4:  wb_data = mem_wb_pc_plus4;
      default: wb_data = mem_wb_alu_result;
    endcase
  end

  // The lsu's store path and load path are independent logic that only share
  // the funct3 and addr_lo inputs, and here those come from different stages:
  // the store is in MEM while the load being extended is in WB. Two instances
  // with the unused half left open say that plainly and cost nothing, since
  // each one synthesizes to only the half that is actually read.
  lsu #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_lsu_store (
    .funct3     (ex_mem_funct3),
    .addr_lo    (ex_mem_addr_lo),
    .store_data (ex_mem_store_data),
    .mem_rdata  (dmem_rdata),
    .mem_wdata  (dmem_wdata),
    .mem_be     (dmem_be),
    .load_data  ()
  );

  lsu #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_lsu_load (
    .funct3     (mem_wb_funct3),
    .addr_lo    (mem_wb_addr_lo),
    .store_data ({DATA_WIDTH{1'b0}}),
    .mem_rdata  (dmem_rdata),
    .mem_wdata  (),
    .mem_be     (),
    .load_data  (load_data)
  );

endmodule
