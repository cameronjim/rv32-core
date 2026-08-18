// dmem: data memory, word addressed with one write enable per byte lane and a
// synchronous read port, the shape Quartus infers as M10K block RAM. Writes
// land on posedge clk for every enabled lane; reads capture the address on the
// same edge and present the whole word during the next cycle, leaving lane
// extraction to the lsu.

module dmem #(
  parameter int ADDR_WIDTH = 10,
  parameter int DATA_WIDTH = 32,
  // INIT_FILE is deliberately untyped: Icarus cannot bind a parameter
  // reference to a string-typed parameter port, which a board top needs to do
  // when it forwards its own program-selection parameter down to here.
  parameter     INIT_FILE  = ""
) (
  input  logic                    clk,
  input  logic [ADDR_WIDTH-1:0]   addr,
  input  logic [DATA_WIDTH-1:0]   wdata,
  // one enable per byte lane, so 4 bits for the 32 bit RV32I data word
  input  logic [DATA_WIDTH/8-1:0] byte_en,
  input  logic                    we,
  output logic [DATA_WIDTH-1:0]   rdata
);

  localparam int LANE_WIDTH = 8;
  localparam int NUM_LANES  = DATA_WIDTH / LANE_WIDTH;
  localparam int NUM_WORDS  = 1 << ADDR_WIDTH;

  // The array is a packed vector of lanes per word, not a flat 32 bit word,
  // and wdata gets the same view. Selecting a lane by index is the shape
  // Quartus matches to the M10K byte enable ports; the equivalent part select
  // on a flat word is not, and leaves the whole array in registers behind a
  // 1024 to 1 read mux.
  logic [NUM_LANES-1:0][LANE_WIDTH-1:0] mem[NUM_WORDS];
  logic [NUM_LANES-1:0][LANE_WIDTH-1:0] wdata_lanes;

  assign wdata_lanes = wdata;

  // Same sanctioned initial block as imem: Quartus reads it as block RAM
  // initial content, later useful for preloading a .data section.
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // The M10K template: one clocked process holding the lane writes and the
  // registered read, no reset, no enable, no write-forwarding bypass. The
  // address is captured on the rising edge and rdata holds that word for the
  // whole next cycle, which is why cpu_top gives every load a second cycle.
  //
  // Read during write to the same address on the same edge returns the OLD
  // word, because the read is nonblocking like the writes. Store then load
  // ordering is still correct for the core: the load stall puts a full cycle
  // between the store commit and the load capture, so a load in any later
  // cycle sees the stored data.
  //
  // No rst_n here: block RAM contents cannot be cleared by a reset signal, so
  // this sequential block is exempt from the synchronous reset rule.
  //
  // The four lane writes are spelled out instead of looped. Quartus only folds
  // a lane write into an M10K byte enable when the lane index is a literal: a
  // for loop over NUM_LANES leaves the array in registers, and a generate loop
  // splits it into one narrow altsyncram per lane. RV32I fixes the word at
  // four 8 bit lanes, so unrolling costs no generality here.
  always_ff @(posedge clk) begin
    if (we) begin
      if (byte_en[0]) mem[addr][0] <= wdata_lanes[0];
      if (byte_en[1]) mem[addr][1] <= wdata_lanes[1];
      if (byte_en[2]) mem[addr][2] <= wdata_lanes[2];
      if (byte_en[3]) mem[addr][3] <= wdata_lanes[3];
    end
    rdata <= mem[addr];
  end

endmodule
