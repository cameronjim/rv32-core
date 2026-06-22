// dmem: data memory, word addressed with one write enable per byte lane and an
// asynchronous read port. Writes land on posedge clk for every enabled lane;
// reads return the whole word and leave lane extraction to the lsu.

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

  logic [DATA_WIDTH-1:0] mem[NUM_WORDS];

  // Same sanctioned initial block as imem: Quartus reads it as block RAM
  // initial content, later useful for preloading a .data section.
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // The read stays asynchronous, unlike imem. imem can register its read on the
  // negative edge because its address is the pc, a register output that is
  // stable from the rising edge onward. This address is alu_result, which only
  // settles after imem hands the instruction over at the falling edge, so there
  // is no clock edge left between the address being valid and the writeback at
  // the next rising edge. Registering this port would make every load return
  // the word addressed by the previous instruction. Giving loads their own
  // clock edge is a cpu_top change (a load stall, or the pipelined MEM stage),
  // so until then this memory costs registers instead of M10K bits.
  //
  // Store then load ordering: a write commits on the rising edge, so a load in
  // any later cycle sees the stored data.
  assign rdata = mem[addr];

  // No rst_n here: block RAM contents cannot be cleared by a reset signal, so
  // this sequential block is exempt from the synchronous reset rule.
  always_ff @(posedge clk) begin
    if (we) begin
      for (int i = 0; i < NUM_LANES; i++) begin
        if (byte_en[i]) begin
          mem[addr][i*LANE_WIDTH+:LANE_WIDTH] <= wdata[i*LANE_WIDTH+:LANE_WIDTH];
        end
      end
    end
  end

endmodule
