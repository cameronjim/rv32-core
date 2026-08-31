// uart_tx: synthesizable 8N1 serial transmitter. A baud counter divides clk by
// BAUD_DIV per bit and a shift register drives the start bit, the data bits LSB
// first and the stop bit onto tx. A start pulse while busy is ignored.

module uart_tx #(
  parameter int DATA_WIDTH = 8,
  parameter int BAUD_DIV   = 434
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic [DATA_WIDTH-1:0] data,
  // single cycle pulse, taken only while the transmitter is idle
  input  logic                  start,
  // serial line, idles high
  output logic                  tx,
  output logic                  busy
);

  // +1 keeps the counter at least one bit wide when BAUD_DIV is 1
  localparam int CNT_WIDTH = $clog2(BAUD_DIV + 1);
  localparam int IDX_WIDTH = $clog2(DATA_WIDTH);

  // Terminal counts, sized by their declarations so the comparisons below stay
  // the same width as the counters
  localparam logic [CNT_WIDTH-1:0] BAUD_LAST = BAUD_DIV - 1;
  localparam logic [IDX_WIDTH-1:0] IDX_LAST  = DATA_WIDTH - 1;

  typedef enum logic [1:0] {
    S_IDLE  = 2'd0,
    S_START = 2'd1,
    S_DATA  = 2'd2,
    S_STOP  = 2'd3
  } state_e;

  state_e                state_q;
  logic [CNT_WIDTH-1:0]  baud_cnt_q;
  logic [IDX_WIDTH-1:0]  bit_idx_q;
  logic [DATA_WIDTH-1:0] shift_q;
  logic                  tx_q;

  // one clock wide pulse on the last cycle of every bit period
  logic bit_done;
  // a start pulse that the idle transmitter actually takes
  logic take_start;

  assign bit_done   = (baud_cnt_q == BAUD_LAST);
  assign take_start = (state_q == S_IDLE) && start;

  assign tx = tx_q;
  // high from the taken start pulse until the stop bit has been sent
  assign busy = (state_q != S_IDLE) || take_start;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q    <= S_IDLE;
      baud_cnt_q <= '0;
      bit_idx_q  <= '0;
      shift_q    <= '0;
      tx_q       <= 1'b1;
    end else begin
      case (state_q)
        // idle: line held high, a start pulse latches the byte and drops tx
        S_IDLE: begin
          baud_cnt_q <= '0;
          bit_idx_q  <= '0;
          if (start) begin
            shift_q <= data;
            tx_q    <= 1'b0;
            state_q <= S_START;
          end else begin
            tx_q <= 1'b1;
          end
        end
        // start bit: hold low one bit period, then present data bit 0
        S_START: begin
          if (bit_done) begin
            baud_cnt_q <= '0;
            bit_idx_q  <= '0;
            tx_q       <= shift_q[0];
            state_q    <= S_DATA;
          end else begin
            baud_cnt_q <= baud_cnt_q + 1'b1;
          end
        end
        // data bits: one shift per bit period; after the last one, drive stop
        S_DATA: begin
          if (bit_done) begin
            baud_cnt_q <= '0;
            if (bit_idx_q == IDX_LAST) begin
              tx_q    <= 1'b1;
              state_q <= S_STOP;
            end else begin
              // the shift lands on this same edge, so shift_q[1] is the bit
              // that becomes the new LSB and therefore the next bit on the wire
              shift_q   <= {1'b0, shift_q[DATA_WIDTH-1:1]};
              tx_q      <= shift_q[1];
              bit_idx_q <= bit_idx_q + 1'b1;
            end
          end else begin
            baud_cnt_q <= baud_cnt_q + 1'b1;
          end
        end
        // stop bit: one bit period high, then the frame is over
        S_STOP: begin
          if (bit_done) begin
            baud_cnt_q <= '0;
            state_q    <= S_IDLE;
          end else begin
            baud_cnt_q <= baud_cnt_q + 1'b1;
          end
        end
        // unreachable with a two bit state, kept so synthesis stays safe
        default: begin
          state_q <= S_IDLE;
          tx_q    <= 1'b1;
        end
      endcase
    end
  end

endmodule
