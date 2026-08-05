// lsu_tb: self checking testbench for the load-store unit.
// Directed cases per access size and byte lane, store/load round trips through
// a modeled write merge, and a randomized cross check against a reference model.

`timescale 1ns / 1ps

module lsu_tb;

  import rv32_pkg::*;

  localparam int DATA_WIDTH = 32;
  localparam int BE_WIDTH   = DATA_WIDTH / 8;
  localparam int RAND_ITERS = 500;

  logic [2:0]            funct3;
  logic [1:0]            addr_lo;
  logic [DATA_WIDTH-1:0] store_data;
  logic [DATA_WIDTH-1:0] mem_rdata;
  logic [DATA_WIDTH-1:0] mem_wdata;
  logic [BE_WIDTH-1:0]   mem_be;
  logic [DATA_WIDTH-1:0] load_data;

  integer rand_seed = 32'd20260804;

  lsu #(
    .DATA_WIDTH (DATA_WIDTH)
  ) dut (
    .funct3     (funct3),
    .addr_lo    (addr_lo),
    .store_data (store_data),
    .mem_rdata  (mem_rdata),
    .mem_wdata  (mem_wdata),
    .mem_be     (mem_be),
    .load_data  (load_data)
  );

  // models the dmem lane write: enabled lanes take the new word, others keep old
  function automatic logic [DATA_WIDTH-1:0] merge_word(
    input logic [DATA_WIDTH-1:0] old_word,
    input logic [DATA_WIDTH-1:0] new_word,
    input logic [BE_WIDTH-1:0]   be
  );
    logic [DATA_WIDTH-1:0] result;
    for (int i = 0; i < BE_WIDTH; i++) begin
      result[8*i +: 8] = be[i] ? new_word[8*i +: 8] : old_word[8*i +: 8];
    end
    return result;
  endfunction

  // reference model, written independently of the dut structure
  function automatic logic [BE_WIDTH-1:0] ref_be(
    input logic [2:0] f3,
    input logic [1:0] al
  );
    case (f3)
      F3_LB:   return 4'b0001 << al;
      F3_LH:   return al[1] ? 4'b1100 : 4'b0011;
      F3_LW:   return 4'b1111;
      default: return 4'b0000;
    endcase
  endfunction

  function automatic logic [DATA_WIDTH-1:0] ref_stored_word(
    input logic [2:0]            f3,
    input logic [1:0]            al,
    input logic [DATA_WIDTH-1:0] sd,
    input logic [DATA_WIDTH-1:0] old_word
  );
    logic [DATA_WIDTH-1:0] result;
    result = old_word;
    case (f3)
      F3_LB:   result[8*al +: 8] = sd[7:0];
      F3_LH:   if (al[1]) result[31:16] = sd[15:0];
               else       result[15:0]  = sd[15:0];
      F3_LW:   result = sd;
      default: result = old_word;
    endcase
    return result;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] ref_load(
    input logic [2:0]            f3,
    input logic [1:0]            al,
    input logic [DATA_WIDTH-1:0] rdata
  );
    logic [7:0]  b;
    logic [15:0] h;
    b = rdata[8*al +: 8];
    h = al[1] ? rdata[31:16] : rdata[15:0];
    case (f3)
      F3_LB:   return {{24{b[7]}}, b};
      F3_LH:   return {{16{h[15]}}, h};
      F3_LW:   return rdata;
      F3_LBU:  return {24'd0, b};
      F3_LHU:  return {16'd0, h};
      default: return 32'd0;
    endcase
  endfunction

  task automatic check32(
    input string                 what,
    input logic [DATA_WIDTH-1:0] got,
    input logic [DATA_WIDTH-1:0] exp
  );
    if (got !== exp) begin
      $display("FAIL: %s: got 0x%08h expected 0x%08h", what, got, exp);
      $fatal(1);
    end
  endtask

  task automatic check_be(
    input string               what,
    input logic [BE_WIDTH-1:0] got,
    input logic [BE_WIDTH-1:0] exp
  );
    if (got !== exp) begin
      $display("FAIL: %s: got be 4'b%04b expected 4'b%04b", what, got, exp);
      $fatal(1);
    end
  endtask

  // drive the store path and check the byte enables plus the lanes that land
  task automatic store_case(
    input string                 name,
    input logic [2:0]            f3,
    input logic [1:0]            al,
    input logic [DATA_WIDTH-1:0] sd,
    input logic [BE_WIDTH-1:0]   exp_be,
    input logic [DATA_WIDTH-1:0] old_word,
    input logic [DATA_WIDTH-1:0] exp_merged
  );
    funct3     = f3;
    addr_lo    = al;
    store_data = sd;
    #1;
    check_be(name, mem_be, exp_be);
    check32($sformatf("%s merged", name), merge_word(old_word, mem_wdata, mem_be), exp_merged);
  endtask

  task automatic load_case(
    input string                 name,
    input logic [2:0]            f3,
    input logic [1:0]            al,
    input logic [DATA_WIDTH-1:0] rdata,
    input logic [DATA_WIDTH-1:0] exp
  );
    funct3    = f3;
    addr_lo   = al;
    mem_rdata = rdata;
    #1;
    check32(name, load_data, exp);
  endtask

  // store then read the merged word back through the load path
  task automatic round_trip(
    input string                 name,
    input logic [2:0]            store_f3,
    input logic [2:0]            load_f3,
    input logic [1:0]            al,
    input logic [DATA_WIDTH-1:0] sd,
    input logic [DATA_WIDTH-1:0] old_word,
    input logic [DATA_WIDTH-1:0] exp_merged,
    input logic [DATA_WIDTH-1:0] exp_load
  );
    logic [DATA_WIDTH-1:0] merged;
    funct3     = store_f3;
    addr_lo    = al;
    store_data = sd;
    #1;
    merged = merge_word(old_word, mem_wdata, mem_be);
    check32($sformatf("%s merged", name), merged, exp_merged);
    load_case($sformatf("%s loadback", name), load_f3, al, merged, exp_load);
  endtask

  logic [2:0]            r_f3;
  logic [1:0]            r_al;
  logic [DATA_WIDTH-1:0] r_sd;
  logic [DATA_WIDTH-1:0] r_old;
  logic [DATA_WIDTH-1:0] r_rdata;

  initial begin
    $dumpfile("sim/build/lsu_tb.vcd");
    $dumpvars(0, lsu_tb);

    funct3     = F3_LW;
    addr_lo    = 2'd0;
    store_data = 32'd0;
    mem_rdata  = 32'd0;
    #1;

    // sb into each lane, one-hot byte enable, addressed lane takes sd[7:0]
    store_case("sb lane0", F3_LB, 2'd0, 32'hDEADBEA5, 4'b0001, 32'h0000_0000, 32'h0000_00A5);
    store_case("sb lane1", F3_LB, 2'd1, 32'hDEADBEA5, 4'b0010, 32'h0000_0000, 32'h0000_A500);
    store_case("sb lane2", F3_LB, 2'd2, 32'hDEADBEA5, 4'b0100, 32'h0000_0000, 32'h00A5_0000);
    store_case("sb lane3", F3_LB, 2'd3, 32'hDEADBEA5, 4'b1000, 32'h0000_0000, 32'hA500_0000);

    // sb must not disturb the other lanes of an existing word
    store_case("sb lane2 over old", F3_LB, 2'd2, 32'h0000_0099, 4'b0100,
               32'h1122_3344, 32'h1199_3344);

    // sh into both halves
    store_case("sh low",  F3_LH, 2'd0, 32'hDEAD1234, 4'b0011, 32'h0000_0000, 32'h0000_1234);
    store_case("sh high", F3_LH, 2'd2, 32'hDEAD1234, 4'b1100, 32'h0000_0000, 32'h1234_0000);
    store_case("sh high over old", F3_LH, 2'd2, 32'h0000_ABCD, 4'b1100,
               32'h1122_3344, 32'hABCD_3344);

    // sw writes every lane regardless of the low address bits being zero
    store_case("sw", F3_LW, 2'd0, 32'hCAFEF00D, 4'b1111, 32'hFFFF_FFFF, 32'hCAFE_F00D);

    // undefined store funct3 writes nothing
    store_case("store f3 011", 3'b011, 2'd1, 32'hFFFFFFFF, 4'b0000, 32'h1122_3344, 32'h1122_3344);
    store_case("store f3 100", 3'b100, 2'd1, 32'hFFFFFFFF, 4'b0000, 32'h1122_3344, 32'h1122_3344);
    store_case("store f3 101", 3'b101, 2'd1, 32'hFFFFFFFF, 4'b0000, 32'h1122_3344, 32'h1122_3344);
    store_case("store f3 110", 3'b110, 2'd1, 32'hFFFFFFFF, 4'b0000, 32'h1122_3344, 32'h1122_3344);
    store_case("store f3 111", 3'b111, 2'd1, 32'hFFFFFFFF, 4'b0000, 32'h1122_3344, 32'h1122_3344);

    // lb sign extension across the four lanes of 0x80FF017F
    load_case("lb lane0 +127", F3_LB, 2'd0, 32'h80FF017F, 32'h0000_007F);
    load_case("lb lane1 +1",   F3_LB, 2'd1, 32'h80FF017F, 32'h0000_0001);
    load_case("lb lane2 -1",   F3_LB, 2'd2, 32'h80FF017F, 32'hFFFF_FFFF);
    load_case("lb lane3 -128", F3_LB, 2'd3, 32'h80FF017F, 32'hFFFF_FF80);

    // lbu zero extends the same lanes
    load_case("lbu lane0", F3_LBU, 2'd0, 32'h80FF017F, 32'h0000_007F);
    load_case("lbu lane1", F3_LBU, 2'd1, 32'h80FF017F, 32'h0000_0001);
    load_case("lbu lane2", F3_LBU, 2'd2, 32'h80FF017F, 32'h0000_00FF);
    load_case("lbu lane3", F3_LBU, 2'd3, 32'h80FF017F, 32'h0000_0080);

    // lh vs lhu on a word whose upper half is negative
    load_case("lh low",   F3_LH,  2'd0, 32'h80007FFF, 32'h0000_7FFF);
    load_case("lh high",  F3_LH,  2'd2, 32'h80007FFF, 32'hFFFF_8000);
    load_case("lhu low",  F3_LHU, 2'd0, 32'h80007FFF, 32'h0000_7FFF);
    load_case("lhu high", F3_LHU, 2'd2, 32'h80007FFF, 32'h0000_8000);

    // halves that sit exactly on the sign boundary
    load_case("lh 0xFFFF",  F3_LH,  2'd0, 32'h0000FFFF, 32'hFFFF_FFFF);
    load_case("lhu 0xFFFF", F3_LHU, 2'd0, 32'h0000FFFF, 32'h0000_FFFF);

    // lw passthrough
    load_case("lw",      F3_LW, 2'd0, 32'hDEADBEEF, 32'hDEAD_BEEF);
    load_case("lw zero", F3_LW, 2'd0, 32'h00000000, 32'h0000_0000);

    // undefined load funct3 reads as zero
    load_case("load f3 011", 3'b011, 2'd0, 32'hFFFFFFFF, 32'h0000_0000);
    load_case("load f3 110", 3'b110, 2'd2, 32'hFFFFFFFF, 32'h0000_0000);
    load_case("load f3 111", 3'b111, 2'd3, 32'hFFFFFFFF, 32'h0000_0000);

    // round trips: store into an old word, load the merged result back
    round_trip("rt sb/lb lane1",  F3_LB, F3_LB,  2'd1, 32'h000000EF,
               32'hAABBCCDD, 32'hAABB_EFDD, 32'hFFFF_FFEF);
    round_trip("rt sb/lbu lane1", F3_LB, F3_LBU, 2'd1, 32'h000000EF,
               32'hAABBCCDD, 32'hAABB_EFDD, 32'h0000_00EF);
    round_trip("rt sb/lb lane3",  F3_LB, F3_LB,  2'd3, 32'h12345612,
               32'hAABBCCDD, 32'h12BB_CCDD, 32'h0000_0012);
    round_trip("rt sb/lb lane0",  F3_LB, F3_LB,  2'd0, 32'h00000080,
               32'hAABBCCDD, 32'hAABB_CC80, 32'hFFFF_FF80);
    round_trip("rt sh/lh high",   F3_LH, F3_LH,  2'd2, 32'hFFFF8001,
               32'hAABBCCDD, 32'h8001_CCDD, 32'hFFFF_8001);
    round_trip("rt sh/lhu high",  F3_LH, F3_LHU, 2'd2, 32'hFFFF8001,
               32'hAABBCCDD, 32'h8001_CCDD, 32'h0000_8001);
    round_trip("rt sh/lh low",    F3_LH, F3_LH,  2'd0, 32'hAAAA7002,
               32'hAABBCCDD, 32'hAABB_7002, 32'h0000_7002);
    round_trip("rt sw/lw",        F3_LW, F3_LW,  2'd0, 32'h01020304,
               32'hAABBCCDD, 32'h0102_0304, 32'h0102_0304);

    // randomized cross check against the reference model
    for (int i = 0; i < RAND_ITERS; i++) begin
      r_f3    = $random(rand_seed);
      r_al    = $random(rand_seed);
      r_sd    = $random(rand_seed);
      r_old   = $random(rand_seed);
      r_rdata = $random(rand_seed);

      funct3     = r_f3;
      addr_lo    = r_al;
      store_data = r_sd;
      mem_rdata  = r_rdata;
      #1;

      check_be($sformatf("rand %0d be (f3=%03b al=%02b)", i, r_f3, r_al),
               mem_be, ref_be(r_f3, r_al));
      check32($sformatf("rand %0d stored word (f3=%03b al=%02b)", i, r_f3, r_al),
              merge_word(r_old, mem_wdata, mem_be),
              ref_stored_word(r_f3, r_al, r_sd, r_old));
      check32($sformatf("rand %0d load (f3=%03b al=%02b)", i, r_f3, r_al),
              load_data, ref_load(r_f3, r_al, r_rdata));
    end

    $display("PASS: lsu");
    $finish;
  end

endmodule
