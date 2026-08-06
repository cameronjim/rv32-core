// mmio: synthesizable memory mapped IO block holding LEDR, HEX0..HEX5 and the
// free-running CYCLE counter, plus read-only views of SW and KEY. Board
// agnostic: input synchronizers and pin polarity fixes live in the board top.

module mmio #(
  parameter int DATA_WIDTH = 32
) (
  input  logic                  clk,
  input  logic                  rst_n,
  // word access bus; the map is word only so there are no byte enables
  input  logic [DATA_WIDTH-1:0] addr,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic                  we,
  input  logic                  re,
  output logic [DATA_WIDTH-1:0] rdata,
  // board inputs, already synchronized; key_in is 1 for a pressed button
  input  logic [9:0]            sw_in,
  input  logic [3:0]            key_in,
  // board outputs, active high; the top inverts what the pins need
  output logic [9:0]            ledr_out,
  output logic [6:0]            hex0_out,
  output logic [6:0]            hex1_out,
  output logic [6:0]            hex2_out,
  output logic [6:0]            hex3_out,
  output logic [6:0]            hex4_out,
  output logic [6:0]            hex5_out
);

  localparam int OFF_WIDTH  = 16;
  localparam int LEDR_WIDTH = 10;
  localparam int SW_WIDTH   = 10;
  localparam int KEY_WIDTH  = 4;
  localparam int SEG_WIDTH  = 7;
  localparam int HEX_COUNT  = 6;

  localparam logic [OFF_WIDTH-1:0] OFF_LEDR  = 16'h0000;
  localparam logic [OFF_WIDTH-1:0] OFF_SW    = 16'h0004;
  localparam logic [OFF_WIDTH-1:0] OFF_KEY   = 16'h0008;
  localparam logic [OFF_WIDTH-1:0] OFF_HEX0  = 16'h0010;
  localparam logic [OFF_WIDTH-1:0] OFF_HEX1  = 16'h0014;
  localparam logic [OFF_WIDTH-1:0] OFF_HEX2  = 16'h0018;
  localparam logic [OFF_WIDTH-1:0] OFF_HEX3  = 16'h001C;
  localparam logic [OFF_WIDTH-1:0] OFF_HEX4  = 16'h0020;
  localparam logic [OFF_WIDTH-1:0] OFF_HEX5  = 16'h0024;
  localparam logic [OFF_WIDTH-1:0] OFF_CYCLE = 16'h0030;

  logic [LEDR_WIDTH-1:0] ledr_q;
  logic [SEG_WIDTH-1:0]  hex_q[HEX_COUNT];
  logic [DATA_WIDTH-1:0] cycle_q;

  // External decode already picked this block out of the address space, so the
  // upper address bits are not checked here.
  logic [OFF_WIDTH-1:0]  off;
  logic [LEDR_WIDTH-1:0] wdata_ledr;
  logic [SEG_WIDTH-1:0]  wdata_seg;

  assign off        = addr[OFF_WIDTH-1:0];
  assign wdata_ledr = wdata[LEDR_WIDTH-1:0];
  assign wdata_seg  = wdata[SEG_WIDTH-1:0];

  assign ledr_out = ledr_q;
  assign hex0_out = hex_q[0];
  assign hex1_out = hex_q[1];
  assign hex2_out = hex_q[2];
  assign hex3_out = hex_q[3];
  assign hex4_out = hex_q[4];
  assign hex5_out = hex_q[5];

  // hex_index is only meaningful while hex_hit is set
  logic [2:0] hex_index;
  logic       hex_hit;

  always_comb begin
    hex_hit   = 1'b1;
    hex_index = 3'd0;
    case (off)
      OFF_HEX0: hex_index = 3'd0;
      OFF_HEX1: hex_index = 3'd1;
      OFF_HEX2: hex_index = 3'd2;
      OFF_HEX3: hex_index = 3'd3;
      OFF_HEX4: hex_index = 3'd4;
      OFF_HEX5: hex_index = 3'd5;
      default:  hex_hit   = 1'b0;
    endcase
  end

  // Combinational read so a load stays single cycle, same as dmem. Narrow
  // registers zero-extend; unmapped offsets and re low both read as zero.
  always_comb begin
    rdata = '0;
    if (re) begin
      case (off)
        OFF_LEDR:  rdata = {{(DATA_WIDTH-LEDR_WIDTH){1'b0}}, ledr_q};
        OFF_SW:    rdata = {{(DATA_WIDTH-SW_WIDTH){1'b0}}, sw_in};
        OFF_KEY:   rdata = {{(DATA_WIDTH-KEY_WIDTH){1'b0}}, key_in};
        OFF_HEX0:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[0]};
        OFF_HEX1:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[1]};
        OFF_HEX2:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[2]};
        OFF_HEX3:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[3]};
        OFF_HEX4:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[4]};
        OFF_HEX5:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[5]};
        OFF_CYCLE: rdata = cycle_q;
        default:   rdata = '0;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ledr_q  <= '0;
      cycle_q <= '0;
      for (int i = 0; i < HEX_COUNT; i++) begin
        hex_q[i] <= '0;
      end
    end else begin
      cycle_q <= cycle_q + 32'd1;

      if (we) begin
        if (off == OFF_LEDR) begin
          ledr_q <= wdata_ledr;
        end else if (hex_hit) begin
          hex_q[hex_index] <= wdata_seg;
        end
        // SW, KEY, CYCLE and every unmapped offset ignore writes
      end
    end
  end

endmodule
