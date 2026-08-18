// hazard_unit_tb: self-checking testbench for the pipeline hazard unit.
// Runs directed load-use, suppression and redirect cases, then sweeps every
// rd/rs1/rs2 combination against an independent reference model.

`timescale 1ns / 1ps

module hazard_unit_tb;

  localparam int REG_ADDR_WIDTH = 5;
  localparam int REG_COUNT      = 1 << REG_ADDR_WIDTH;

  logic                      id_ex_mem_read;
  logic [REG_ADDR_WIDTH-1:0] id_ex_rd;
  logic [REG_ADDR_WIDTH-1:0] if_id_rs1;
  logic [REG_ADDR_WIDTH-1:0] if_id_rs2;
  logic                      if_id_uses_rs1;
  logic                      if_id_uses_rs2;
  logic                      ex_redirect;
  logic                      stall_pc;
  logic                      stall_if_id;
  logic                      flush_if_id;
  logic                      bubble_id_ex;

  hazard_unit #(
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH)
  ) dut (
    .id_ex_mem_read (id_ex_mem_read),
    .id_ex_rd       (id_ex_rd),
    .if_id_rs1      (if_id_rs1),
    .if_id_rs2      (if_id_rs2),
    .if_id_uses_rs1 (if_id_uses_rs1),
    .if_id_uses_rs2 (if_id_uses_rs2),
    .ex_redirect    (ex_redirect),
    .stall_pc       (stall_pc),
    .stall_if_id    (stall_if_id),
    .flush_if_id    (flush_if_id),
    .bubble_id_ex   (bubble_id_ex)
  );

  // reference model, written from the contract rather than the DUT structure
  function automatic logic ref_load_use(input logic                      mem_read,
                                        input logic [REG_ADDR_WIDTH-1:0] rd,
                                        input logic [REG_ADDR_WIDTH-1:0] rs1,
                                        input logic [REG_ADDR_WIDTH-1:0] rs2,
                                        input logic                      uses_rs1,
                                        input logic                      uses_rs2);
    begin
      if (!mem_read || (rd == 5'd0)) begin
        ref_load_use = 1'b0;
      end else begin
        ref_load_use = (uses_rs1 && (rd == rs1)) || (uses_rs2 && (rd == rs2));
      end
    end
  endfunction

  // drive one input vector, settle combinationally, compare all four outputs
  task automatic check(input string                    label,
                       input logic                     mem_read,
                       input logic [REG_ADDR_WIDTH-1:0] rd,
                       input logic [REG_ADDR_WIDTH-1:0] rs1,
                       input logic [REG_ADDR_WIDTH-1:0] rs2,
                       input logic                     uses_rs1,
                       input logic                     uses_rs2,
                       input logic                     redirect,
                       input logic                     exp_stall_pc,
                       input logic                     exp_stall_if_id,
                       input logic                     exp_flush_if_id,
                       input logic                     exp_bubble_id_ex);
    begin
      id_ex_mem_read = mem_read;
      id_ex_rd       = rd;
      if_id_rs1      = rs1;
      if_id_rs2      = rs2;
      if_id_uses_rs1 = uses_rs1;
      if_id_uses_rs2 = uses_rs2;
      ex_redirect    = redirect;
      #1;
      if ((stall_pc     !== exp_stall_pc)    ||
          (stall_if_id  !== exp_stall_if_id) ||
          (flush_if_id  !== exp_flush_if_id) ||
          (bubble_id_ex !== exp_bubble_id_ex)) begin
        $display("FAIL: %0s", label);
        $display("  inputs: mem_read=%b rd=%0d rs1=%0d rs2=%0d uses_rs1=%b uses_rs2=%b redirect=%b",
                 mem_read, rd, rs1, rs2, uses_rs1, uses_rs2, redirect);
        $display("  got:      stall_pc=%b stall_if_id=%b flush_if_id=%b bubble_id_ex=%b",
                 stall_pc, stall_if_id, flush_if_id, bubble_id_ex);
        $display("  expected: stall_pc=%b stall_if_id=%b flush_if_id=%b bubble_id_ex=%b",
                 exp_stall_pc, exp_stall_if_id, exp_flush_if_id, exp_bubble_id_ex);
        $fatal(1);
      end
    end
  endtask

  // same drive, but expectations come from the reference model
  task automatic check_ref(input string                     label,
                           input logic                      mem_read,
                           input logic [REG_ADDR_WIDTH-1:0] rd,
                           input logic [REG_ADDR_WIDTH-1:0] rs1,
                           input logic [REG_ADDR_WIDTH-1:0] rs2,
                           input logic                      uses_rs1,
                           input logic                      uses_rs2,
                           input logic                      redirect);
    logic hazard;
    logic exp_stall;
    begin
      hazard    = ref_load_use(mem_read, rd, rs1, rs2, uses_rs1, uses_rs2);
      // redirect wins: the stalled instruction is wrong-path anyway
      exp_stall = hazard && !redirect;
      check(label, mem_read, rd, rs1, rs2, uses_rs1, uses_rs2, redirect,
            exp_stall, exp_stall, redirect, hazard || redirect);
    end
  endtask

  int sweep_combo;
  logic sweep_mem_read;
  logic sweep_uses_rs1;
  logic sweep_uses_rs2;

  initial begin
    $dumpfile("sim/build/hazard_unit_tb.vcd");
    $dumpvars(0, hazard_unit_tb);

    // idle: no load in EX, no redirect, nothing asserts
    check("idle, no load and no redirect",
          1'b0, 5'd0, 5'd0, 5'd0, 1'b0, 1'b0, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);
    check("idle, unrelated instruction in EX",
          1'b0, 5'd5, 5'd5, 5'd6, 1'b1, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);

    // load-use through rs1 only
    check("load-use via rs1",
          1'b1, 5'd7, 5'd7, 5'd9, 1'b1, 1'b1, 1'b0,
          1'b1, 1'b1, 1'b0, 1'b1);
    check("load-use via rs1, rs2 unused",
          1'b1, 5'd31, 5'd31, 5'd0, 1'b1, 1'b0, 1'b0,
          1'b1, 1'b1, 1'b0, 1'b1);

    // load-use through rs2 only
    check("load-use via rs2",
          1'b1, 5'd12, 5'd3, 5'd12, 1'b1, 1'b1, 1'b0,
          1'b1, 1'b1, 1'b0, 1'b1);
    check("load-use via rs2, rs1 unused",
          1'b1, 5'd1, 5'd1, 5'd1, 1'b0, 1'b1, 1'b0,
          1'b1, 1'b1, 1'b0, 1'b1);

    // load-use through both source registers at once
    check("load-use via rs1 and rs2",
          1'b1, 5'd20, 5'd20, 5'd20, 1'b1, 1'b1, 1'b0,
          1'b1, 1'b1, 1'b0, 1'b1);

    // no load in EX: an ALU result forwards, so a matching rd is not a hazard
    check("suppressed, mem_read low with rs1 match",
          1'b0, 5'd7, 5'd7, 5'd9, 1'b1, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);
    check("suppressed, mem_read low with rs2 match",
          1'b0, 5'd9, 5'd7, 5'd9, 1'b1, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);

    // a load into x0 discards its result, so x0 never hazards
    check("suppressed, rd is x0 with both sources x0",
          1'b1, 5'd0, 5'd0, 5'd0, 1'b1, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);
    check("suppressed, rd is x0 with rs1 x0 only",
          1'b1, 5'd0, 5'd0, 5'd4, 1'b1, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);
    check("suppressed, rd is x0 with rs2 x0 only",
          1'b1, 5'd0, 5'd4, 5'd0, 1'b1, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);

    // I-type: the rs2 field is immediate bits, uses_rs2 is low so it cannot match
    check("suppressed, I-type immediate field aliases load rd",
          1'b1, 5'd14, 5'd2, 5'd14, 1'b1, 1'b0, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);
    // lui and jal read neither source register
    check("suppressed, no source registers used",
          1'b1, 5'd14, 5'd14, 5'd14, 1'b0, 1'b0, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);
    // S-type reads rs1 and rs2, B-type too, but rs1 alone can be unused in decode
    check("suppressed, rs1 field matches but uses_rs1 low",
          1'b1, 5'd8, 5'd8, 5'd9, 1'b0, 1'b1, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);

    // redirect alone flushes IF/ID and bubbles ID/EX, no stalls
    check("redirect alone, EX clean",
          1'b0, 5'd0, 5'd0, 5'd0, 1'b0, 1'b0, 1'b1,
          1'b0, 1'b0, 1'b1, 1'b1);
    check("redirect alone, non-load in EX with rd match",
          1'b0, 5'd11, 5'd11, 5'd11, 1'b1, 1'b1, 1'b1,
          1'b0, 1'b0, 1'b1, 1'b1);

    // redirect wins: identical outputs to redirect alone despite the hazard
    check("redirect plus load-use via rs1",
          1'b1, 5'd7, 5'd7, 5'd9, 1'b1, 1'b1, 1'b1,
          1'b0, 1'b0, 1'b1, 1'b1);
    check("redirect plus load-use via rs2",
          1'b1, 5'd12, 5'd3, 5'd12, 1'b1, 1'b1, 1'b1,
          1'b0, 1'b0, 1'b1, 1'b1);
    check("redirect plus load-use via rs1 and rs2",
          1'b1, 5'd20, 5'd20, 5'd20, 1'b1, 1'b1, 1'b1,
          1'b0, 1'b0, 1'b1, 1'b1);

    // the sweep is a quarter million vectors, keep it out of the waveform
    $dumpoff;

    // exhaustive rd x rs1 x rs2 for all eight qualifier combinations
    for (sweep_combo = 0; sweep_combo < 8; sweep_combo++) begin
      sweep_mem_read = sweep_combo[2];
      sweep_uses_rs1 = sweep_combo[1];
      sweep_uses_rs2 = sweep_combo[0];
      for (int rd = 0; rd < REG_COUNT; rd++) begin
        for (int rs1 = 0; rs1 < REG_COUNT; rs1++) begin
          for (int rs2 = 0; rs2 < REG_COUNT; rs2++) begin
            check_ref("exhaustive sweep, redirect low",
                      sweep_mem_read, rd[REG_ADDR_WIDTH-1:0],
                      rs1[REG_ADDR_WIDTH-1:0], rs2[REG_ADDR_WIDTH-1:0],
                      sweep_uses_rs1, sweep_uses_rs2, 1'b0);
          end
        end
      end
    end

    // redirect high over the same qualifier combos, spot checked on rd and rs
    for (sweep_combo = 0; sweep_combo < 8; sweep_combo++) begin
      sweep_mem_read = sweep_combo[2];
      sweep_uses_rs1 = sweep_combo[1];
      sweep_uses_rs2 = sweep_combo[0];
      for (int rd = 0; rd < REG_COUNT; rd++) begin
        for (int rs1 = 0; rs1 < REG_COUNT; rs1++) begin
          check_ref("redirect-high spot check, rs2 equals rd",
                    sweep_mem_read, rd[REG_ADDR_WIDTH-1:0],
                    rs1[REG_ADDR_WIDTH-1:0], rd[REG_ADDR_WIDTH-1:0],
                    sweep_uses_rs1, sweep_uses_rs2, 1'b1);
          check_ref("redirect-high spot check, rs2 differs from rd",
                    sweep_mem_read, rd[REG_ADDR_WIDTH-1:0],
                    rs1[REG_ADDR_WIDTH-1:0], 5'd17,
                    sweep_uses_rs1, sweep_uses_rs2, 1'b1);
        end
      end
    end

    $dumpon;

    // settle back to idle so the waveform ends in a known state
    check("final idle",
          1'b0, 5'd0, 5'd0, 5'd0, 1'b0, 1'b0, 1'b0,
          1'b0, 1'b0, 1'b0, 1'b0);

    $display("PASS: hazard_unit");
    $finish;
  end

endmodule
