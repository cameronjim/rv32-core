// mmio_sim: behavioral model of the board peripherals for simulation only.
// Implements the MMIO register map from claude-docs/architecture.md on a plain
// word access bus, including a UART transmitter modelled at real 8N1 timing so
// a testbench can decode uart_tx_o. Not synthesizable; rtl/mmio.sv is the
// hardware this mirrors.

`timescale 1ns / 1ps

module mmio_sim #(
  parameter int DATA_WIDTH = 32,
  parameter int BAUD_DIV   = 434
) (
  input  logic                  clk,
  input  logic                  rst_n,
  // word access bus; byte enables are not modelled because the map is word only
  input  logic [DATA_WIDTH-1:0] addr,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic                  we,
  input  logic                  re,
  output logic [DATA_WIDTH-1:0] rdata,
  // board inputs, 1 means pressed for keys just like the register map says
  input  logic [9:0]            sw_in,
  input  logic [3:0]            key_in,
  // register state, exposed so a testbench can check it without peeking inside
  output logic [9:0]            ledr_q,
  output logic [6:0]            hex0_q,
  output logic [6:0]            hex1_q,
  output logic [6:0]            hex2_q,
  output logic [6:0]            hex3_q,
  output logic [6:0]            hex4_q,
  output logic [6:0]            hex5_q,
  output logic [DATA_WIDTH-1:0] cycle_q,
  // uart state: the serial line itself plus the busy flag UART_STATUS reports
  output logic                  uart_tx_o,
  output logic                  uart_busy,
  // write strobes, registered so a testbench sampling just after the clock
  // edge sees the write that committed on that edge
  output logic                  wr_ledr,
  output logic [5:0]            wr_hex,
  output logic [DATA_WIDTH-1:0] wr_data
);

  localparam int LEDR_WIDTH = 10;
  localparam int SW_WIDTH   = 10;
  localparam int KEY_WIDTH  = 4;
  localparam int SEG_WIDTH  = 7;
  localparam int HEX_COUNT  = 6;
  localparam int UART_WIDTH = 8;
  // start bit, eight data bits, stop bit
  localparam int FRAME_BITS = UART_WIDTH + 2;

  localparam logic [DATA_WIDTH-1:0] ADDR_LEDR  = 32'hFFFF_0000;
  localparam logic [DATA_WIDTH-1:0] ADDR_SW    = 32'hFFFF_0004;
  localparam logic [DATA_WIDTH-1:0] ADDR_KEY   = 32'hFFFF_0008;
  localparam logic [DATA_WIDTH-1:0] ADDR_HEX0  = 32'hFFFF_0010;
  localparam logic [DATA_WIDTH-1:0] ADDR_HEX1  = 32'hFFFF_0014;
  localparam logic [DATA_WIDTH-1:0] ADDR_HEX2  = 32'hFFFF_0018;
  localparam logic [DATA_WIDTH-1:0] ADDR_HEX3  = 32'hFFFF_001C;
  localparam logic [DATA_WIDTH-1:0] ADDR_HEX4  = 32'hFFFF_0020;
  localparam logic [DATA_WIDTH-1:0] ADDR_HEX5  = 32'hFFFF_0024;
  localparam logic [DATA_WIDTH-1:0] ADDR_CYCLE = 32'hFFFF_0030;
  localparam logic [DATA_WIDTH-1:0] ADDR_UDATA = 32'hFFFF_0040;
  localparam logic [DATA_WIDTH-1:0] ADDR_USTAT = 32'hFFFF_0044;

  // set to 0 to silence the per-write trace
  logic log_writes;

  logic [SEG_WIDTH-1:0] hex_q[HEX_COUNT];

  assign hex0_q = hex_q[0];
  assign hex1_q = hex_q[1];
  assign hex2_q = hex_q[2];
  assign hex3_q = hex_q[3];
  assign hex4_q = hex_q[4];
  assign hex5_q = hex_q[5];

  initial log_writes = 1'b1;

  // read path: pure address decode, unmapped addresses read as zero
  always_comb begin
    rdata = '0;
    if (re) begin
      case (addr)
        ADDR_LEDR:  rdata = {{(DATA_WIDTH-LEDR_WIDTH){1'b0}}, ledr_q};
        ADDR_SW:    rdata = {{(DATA_WIDTH-SW_WIDTH){1'b0}}, sw_in};
        ADDR_KEY:   rdata = {{(DATA_WIDTH-KEY_WIDTH){1'b0}}, key_in};
        ADDR_HEX0:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[0]};
        ADDR_HEX1:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[1]};
        ADDR_HEX2:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[2]};
        ADDR_HEX3:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[3]};
        ADDR_HEX4:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[4]};
        ADDR_HEX5:  rdata = {{(DATA_WIDTH-SEG_WIDTH){1'b0}}, hex_q[5]};
        ADDR_CYCLE: rdata = cycle_q;
        // UART_DATA is write only and reads as zero
        ADDR_UDATA: rdata = '0;
        ADDR_USTAT: rdata = {{(DATA_WIDTH-1){1'b0}}, uart_busy};
        default:    rdata = '0;
      endcase
    end
  end

  // hex index for a write; hex_index is only meaningful when hex_hit is set
  logic [2:0] hex_index;
  logic       hex_hit;

  always_comb begin
    hex_hit   = 1'b1;
    hex_index = 3'd0;
    case (addr)
      ADDR_HEX0: hex_index = 3'd0;
      ADDR_HEX1: hex_index = 3'd1;
      ADDR_HEX2: hex_index = 3'd2;
      ADDR_HEX3: hex_index = 3'd3;
      ADDR_HEX4: hex_index = 3'd4;
      ADDR_HEX5: hex_index = 3'd5;
      default:   hex_hit   = 1'b0;
    endcase
  end

  // UART transmitter model, matching rtl/uart_tx.sv: a write to UART_DATA while
  // idle is accepted and one while busy is dropped; busy answers 1 in the same
  // cycle as the accepted write and then stays up for exactly
  // FRAME_BITS*BAUD_DIV clocks of shifting; uart_tx_o carries a real 8N1
  // waveform, still idling high through the write cycle and dropping to the
  // start bit on the edge that takes the write.
  logic                  uart_accept;
  logic                  uart_shifting;
  logic [FRAME_BITS-1:0] uart_frame;
  logic [3:0]            uart_bit;
  logic [31:0]           uart_baud;

  assign uart_accept = we && (addr == ADDR_UDATA) && !uart_shifting;
  assign uart_busy   = uart_shifting || uart_accept;

  always @(posedge clk) begin
    if (!rst_n) begin
      uart_shifting <= 1'b0;
      uart_tx_o     <= 1'b1;
      uart_frame    <= '1;
      uart_bit      <= '0;
      uart_baud     <= '0;
    end else if (!uart_shifting) begin
      if (uart_accept) begin
        uart_frame    <= {1'b1, wdata[UART_WIDTH-1:0], 1'b0};
        uart_tx_o     <= 1'b0;
        uart_shifting <= 1'b1;
        uart_bit      <= '0;
        uart_baud     <= '0;
      end
    end else if (uart_baud == BAUD_DIV - 1) begin
      uart_baud <= '0;
      if (uart_bit == FRAME_BITS - 1) begin
        uart_shifting <= 1'b0;
        uart_tx_o     <= 1'b1;
      end else begin
        uart_bit  <= uart_bit + 4'd1;
        uart_tx_o <= uart_frame[uart_bit + 4'd1];
      end
    end else begin
      uart_baud <= uart_baud + 32'd1;
    end
  end

  // cycle_q counts clock edges since reset was released, matching the CYCLE
  // register the demo programs read for their timing. Plain always, not
  // always_ff, because the write trace below is a simulation only $display.
  always @(posedge clk) begin
    wr_ledr <= 1'b0;
    wr_hex  <= '0;

    if (!rst_n) begin
      ledr_q  <= '0;
      cycle_q <= '0;
      wr_data <= '0;
      for (int i = 0; i < HEX_COUNT; i++) begin
        hex_q[i] <= '0;
      end
    end else begin
      cycle_q <= cycle_q + 32'd1;

      if (we) begin
        if (addr == ADDR_LEDR) begin
          ledr_q  <= wdata[LEDR_WIDTH-1:0];
          wr_ledr <= 1'b1;
          wr_data <= wdata;
          if (log_writes) begin
            $display("mmio %0d LEDR  <- 0x%08h", cycle_q + 32'd1, wdata);
          end
        end else if (hex_hit) begin
          hex_q[hex_index]  <= wdata[SEG_WIDTH-1:0];
          wr_hex[hex_index] <= 1'b1;
          wr_data           <= wdata;
          if (log_writes) begin
            $display("mmio %0d HEX%0d  <- 0x%08h", cycle_q + 32'd1, hex_index, wdata);
          end
        end else if (uart_accept) begin
          // no wr_* strobe: the uart has no register a testbench can read back
          if (log_writes) begin
            $display("mmio %0d UART  <- 0x%08h", cycle_q + 32'd1, wdata);
          end
        end
        // SW, KEY, CYCLE, UART_STATUS and every unmapped address ignore writes.
        // A UART_DATA write while busy is dropped, so it is not logged either.
      end
    end
  end

endmodule
