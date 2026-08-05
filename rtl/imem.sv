// imem: instruction memory, word addressed with an asynchronous read port.
// Read only. Contents come from an optional hex file so a program can be
// preloaded into block RAM at synthesis time.

module imem #(
  parameter int    ADDR_WIDTH = 10,
  parameter string INIT_FILE  = ""
) (
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

  assign rdata = mem[addr];

endmodule
