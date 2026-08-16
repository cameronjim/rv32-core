// imem: instruction memory, word addressed, read only. The read port is
// registered on the negative clock edge so Quartus infers M10K block RAM.
// Contents come from an optional hex file so a program can be preloaded into
// block RAM at synthesis time.

module imem #(
  parameter int ADDR_WIDTH = 10,
  // INIT_FILE is deliberately untyped: Icarus cannot bind a parameter
  // reference to a string-typed parameter port, which a board top needs to do
  // when it forwards its own program-selection parameter down to here.
  parameter     INIT_FILE  = ""
) (
  input  logic                  clk,
  input  logic [ADDR_WIDTH-1:0] addr,
  // RV32I instructions are fixed at 32 bits, so this width is not a parameter
  output logic [31:0]           rdata
);

  localparam int INSTR_WIDTH = 32;
  localparam int NUM_WORDS   = 1 << ADDR_WIDTH;

  logic [INSTR_WIDTH-1:0] mem[NUM_WORDS];

  // The one sanctioned initial block in synthesizable code: Quartus reads it
  // as block RAM initial content, which is how programs get preloaded.
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Negative edge read. The core launches the address at the rising edge, the
  // memory captures it half a period later at the falling edge, and rdata is
  // stable well before the next rising edge, so a fetch still costs one full
  // cycle. This exact shape, a single always_ff with no reset and no write
  // bypass, is the pattern Quartus recognizes as M10K block RAM; an
  // asynchronous read instead synthesized to a wall of registers and a giant
  // read mux (33904 registers, 0 block memory bits at first synthesis).
  always_ff @(negedge clk) begin
    rdata <= mem[addr];
  end

endmodule
