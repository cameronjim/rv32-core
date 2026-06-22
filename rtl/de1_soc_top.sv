// de1_soc_top: DE1-SoC board top. Wraps cpu_top with imem, dmem and mmio,
// synchronizes the board inputs, and fixes the pin polarities the board wants.
// The program that gets synthesized comes from IMEM_INIT and DMEM_INIT.

module de1_soc_top #(
  parameter string IMEM_INIT = "programs/hex/switch_mirror.hex",
  parameter string DMEM_INIT = "programs/hex/switch_mirror_data.hex"
) (
  // These port names are SCREAMING_SNAKE on purpose: they are the DE1-SoC pin
  // names from the board documentation, so the qsf assignments line up one for
  // one. This is the one sanctioned exception to the snake_case naming rule.
  input  logic       CLOCK_50,
  input  logic [3:0] KEY,
  input  logic [9:0] SW,
  output logic [9:0] LEDR,
  output logic [6:0] HEX0,
  output logic [6:0] HEX1,
  output logic [6:0] HEX2,
  output logic [6:0] HEX3,
  output logic [6:0] HEX4,
  output logic [6:0] HEX5
);

  localparam int DATA_WIDTH     = 32;
  localparam int BE_WIDTH       = DATA_WIDTH / 8;
  localparam int MEM_ADDR_WIDTH = 10;
  localparam int KEY_WIDTH      = 4;
  localparam int SW_WIDTH       = 10;

  // same address decode tb/demo_tb.sv uses, so simulation and hardware agree
  localparam logic [19:0] DMEM_BASE_TAG = 20'h00001;
  localparam logic [15:0] MMIO_BASE_TAG = 16'hFFFF;

  logic clk;
  logic rst_n;

  logic [KEY_WIDTH-1:0] key_meta;
  logic [KEY_WIDTH-1:0] key_sync;
  logic [SW_WIDTH-1:0]  sw_meta;
  logic [SW_WIDTH-1:0]  sw_sync;

  logic [DATA_WIDTH-1:0] imem_addr;
  logic [DATA_WIDTH-1:0] imem_rdata;
  logic [DATA_WIDTH-1:0] dmem_addr;
  logic [DATA_WIDTH-1:0] dmem_wdata;
  logic [BE_WIDTH-1:0]   dmem_be;
  logic                  dmem_we;
  logic                  dmem_re;
  logic [DATA_WIDTH-1:0] dmem_rdata;

  logic                  dmem_sel;
  logic                  mmio_sel;
  logic [DATA_WIDTH-1:0] dmem_raw_rdata;
  logic [DATA_WIDTH-1:0] mmio_rdata;

  logic [MEM_ADDR_WIDTH-1:0] imem_word_addr;
  logic [MEM_ADDR_WIDTH-1:0] dmem_word_addr;

  logic [SW_WIDTH-1:0]  mmio_sw_in;
  logic [KEY_WIDTH-1:0] mmio_key_in;
  logic [9:0]           mmio_ledr;
  logic [6:0]           mmio_hex0;
  logic [6:0]           mmio_hex1;
  logic [6:0]           mmio_hex2;
  logic [6:0]           mmio_hex3;
  logic [6:0]           mmio_hex4;
  logic [6:0]           mmio_hex5;

  assign clk = CLOCK_50;

  // Two flip flop synchronizers on every asynchronous board input. These have
  // no reset: rst_n is derived from this chain, so there is nothing to reset
  // them with. They settle after two clocks from power-up.
  always_ff @(posedge clk) begin
    key_meta <= KEY;
    key_sync <= key_meta;
    sw_meta  <= SW;
    sw_sync  <= sw_meta;
  end

  // KEY3 is the system reset button. Board keys are active low, so pressing it
  // pulls rst_n low with no inversion needed.
  assign rst_n = key_sync[3];

  // KEY0..KEY2 read 1 when pressed per the register map; bit 3 always reads 0
  // because that button is the reset and never reaches software.
  assign mmio_key_in = {1'b0, ~key_sync[2:0]};
  assign mmio_sw_in  = sw_sync;

  // LEDs are active high and pass straight through; the seven segment
  // displays are active low, so those drive the inverse of the mmio registers.
  assign LEDR = mmio_ledr;
  assign HEX0 = ~mmio_hex0;
  assign HEX1 = ~mmio_hex1;
  assign HEX2 = ~mmio_hex2;
  assign HEX3 = ~mmio_hex3;
  assign HEX4 = ~mmio_hex4;
  assign HEX5 = ~mmio_hex5;

  // word index part selects hoisted out of the port connections
  assign imem_word_addr = imem_addr[MEM_ADDR_WIDTH+1:2];
  assign dmem_word_addr = dmem_addr[MEM_ADDR_WIDTH+1:2];

  // dmem answers for 0x00001xxx and mmio for 0xFFFFxxxx; everything else reads
  // as zero and takes no write
  assign dmem_sel   = (dmem_addr[31:12] == DMEM_BASE_TAG);
  assign mmio_sel   = (dmem_addr[31:16] == MMIO_BASE_TAG);
  assign dmem_rdata = (dmem_re && dmem_sel) ? dmem_raw_rdata :
                      (dmem_re && mmio_sel) ? mmio_rdata : '0;

  cpu_top #(
    .DATA_WIDTH   (DATA_WIDTH),
    .RESET_VECTOR (32'h0000_0000)
  ) u_cpu (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (imem_addr),
    .imem_rdata (imem_rdata),
    .dmem_addr  (dmem_addr),
    .dmem_wdata (dmem_wdata),
    .dmem_be    (dmem_be),
    .dmem_we    (dmem_we),
    .dmem_re    (dmem_re),
    .dmem_rdata (dmem_rdata)
  );

  imem #(
    .ADDR_WIDTH (MEM_ADDR_WIDTH),
    .INIT_FILE  (IMEM_INIT)
  ) u_imem (
    .clk   (clk),
    .addr  (imem_word_addr),
    .rdata (imem_rdata)
  );

  dmem #(
    .ADDR_WIDTH (MEM_ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .INIT_FILE  (DMEM_INIT)
  ) u_dmem (
    .clk     (clk),
    .addr    (dmem_word_addr),
    .wdata   (dmem_wdata),
    .byte_en (dmem_be),
    .we      (dmem_we && dmem_sel),
    .rdata   (dmem_raw_rdata)
  );

  mmio #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_mmio (
    .clk      (clk),
    .rst_n    (rst_n),
    .addr     (dmem_addr),
    .wdata    (dmem_wdata),
    .we       (dmem_we && mmio_sel),
    .re       (dmem_re && mmio_sel),
    .rdata    (mmio_rdata),
    .sw_in    (mmio_sw_in),
    .key_in   (mmio_key_in),
    .ledr_out (mmio_ledr),
    .hex0_out (mmio_hex0),
    .hex1_out (mmio_hex1),
    .hex2_out (mmio_hex2),
    .hex3_out (mmio_hex3),
    .hex4_out (mmio_hex4),
    .hex5_out (mmio_hex5)
  );

endmodule
