// lsu: pure combinational load-store unit between the datapath and word memory.
// Store path steers the byte or half into the addressed lanes and emits byte
// enables; load path extracts the addressed lane and sign or zero extends it.

module lsu
  import rv32_pkg::*;
#(
  parameter int DATA_WIDTH = 32
) (
  input  logic [2:0]              funct3,
  input  logic [1:0]              addr_lo,
  input  logic [DATA_WIDTH-1:0]   store_data,
  input  logic [DATA_WIDTH-1:0]   mem_rdata,
  output logic [DATA_WIDTH-1:0]   mem_wdata,
  output logic [DATA_WIDTH/8-1:0] mem_be,
  output logic [DATA_WIDTH-1:0]   load_data
);

  localparam int BYTE_WIDTH = 8;
  localparam int HALF_WIDTH = 16;
  localparam int BE_WIDTH   = DATA_WIDTH / BYTE_WIDTH;
  localparam int HALF_LANES = HALF_WIDTH / BYTE_WIDTH;

  // store and load funct3 encodings coincide for the common widths, so the
  // F3_LB/F3_LH/F3_LW constants also name sb/sh/sw
  logic [BE_WIDTH-1:0]   byte_be;
  logic [BE_WIDTH-1:0]   half_be;
  logic [BYTE_WIDTH-1:0] st_byte;
  logic [HALF_WIDTH-1:0] st_half;
  logic [BYTE_WIDTH-1:0] rd_byte;
  logic [HALF_WIDTH-1:0] rd_half;
  logic                  rd_byte_sign;
  logic                  rd_half_sign;

  assign byte_be = {{BE_WIDTH-1{1'b0}}, 1'b1} << addr_lo;

  // addr_lo[1] picks the upper or lower half; addr_lo[0] is ignored, a
  // misaligned halfword access is undefined behavior in this core
  assign half_be = addr_lo[1] ? {{HALF_LANES{1'b1}}, {HALF_LANES{1'b0}}}
                              : {{HALF_LANES{1'b0}}, {HALF_LANES{1'b1}}};

  assign st_byte = store_data[BYTE_WIDTH-1:0];
  assign st_half = store_data[HALF_WIDTH-1:0];

  // Store path. The byte or half is replicated across every lane and mem_be
  // decides which lanes actually land, so lanes outside the access are don't
  // care. This keeps the write data free of any barrel shifter.
  always_comb begin
    case (funct3)
      F3_LB: begin
        mem_wdata = {BE_WIDTH{st_byte}};
        mem_be    = byte_be;
      end
      F3_LH: begin
        mem_wdata = {(DATA_WIDTH/HALF_WIDTH){st_half}};
        mem_be    = half_be;
      end
      F3_LW: begin
        mem_wdata = store_data;
        mem_be    = '1;
      end
      default: begin
        mem_wdata = store_data;
        mem_be    = '0;
      end
    endcase
  end

  assign rd_byte = mem_rdata[BYTE_WIDTH*addr_lo +: BYTE_WIDTH];
  assign rd_half = addr_lo[1] ? mem_rdata[DATA_WIDTH-1 -: HALF_WIDTH]
                              : mem_rdata[HALF_WIDTH-1:0];

  assign rd_byte_sign = rd_byte[BYTE_WIDTH-1];
  assign rd_half_sign = rd_half[HALF_WIDTH-1];

  // Load path
  always_comb begin
    case (funct3)
      F3_LB:   load_data = {{DATA_WIDTH-BYTE_WIDTH{rd_byte_sign}}, rd_byte};
      F3_LH:   load_data = {{DATA_WIDTH-HALF_WIDTH{rd_half_sign}}, rd_half};
      F3_LW:   load_data = mem_rdata;
      F3_LBU:  load_data = {{DATA_WIDTH-BYTE_WIDTH{1'b0}}, rd_byte};
      F3_LHU:  load_data = {{DATA_WIDTH-HALF_WIDTH{1'b0}}, rd_half};
      default: load_data = '0;
    endcase
  end

endmodule
