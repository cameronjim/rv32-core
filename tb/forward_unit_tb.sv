// forward_unit_tb: self-checking testbench for the EX stage forwarding unit.
// Runs directed hazard cases, an exhaustive sweep of every source/destination
// pair under all four reg_write patterns, and a randomized cross-check.

`timescale 1ns / 1ps

module forward_unit_tb;

  localparam int REG_ADDR_WIDTH = 5;
  localparam int FWD_WIDTH      = 2;
  localparam int REG_COUNT      = 1 << REG_ADDR_WIDTH;
  localparam int RANDOM_RUNS    = 5000;

  localparam logic [FWD_WIDTH-1:0] FWD_REG    = 2'b00;
  localparam logic [FWD_WIDTH-1:0] FWD_EX_MEM = 2'b01;
  localparam logic [FWD_WIDTH-1:0] FWD_MEM_WB = 2'b10;

  logic [REG_ADDR_WIDTH-1:0] id_ex_rs1;
  logic [REG_ADDR_WIDTH-1:0] id_ex_rs2;
  logic [REG_ADDR_WIDTH-1:0] ex_mem_rd;
  logic                      ex_mem_reg_write;
  logic [REG_ADDR_WIDTH-1:0] mem_wb_rd;
  logic                      mem_wb_reg_write;
  logic [FWD_WIDTH-1:0]      fwd_a;
  logic [FWD_WIDTH-1:0]      fwd_b;

  int unsigned checks;

  forward_unit #(
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .FWD_WIDTH      (FWD_WIDTH)
  ) dut (
    .id_ex_rs1        (id_ex_rs1),
    .id_ex_rs2        (id_ex_rs2),
    .ex_mem_rd        (ex_mem_rd),
    .ex_mem_reg_write (ex_mem_reg_write),
    .mem_wb_rd        (mem_wb_rd),
    .mem_wb_reg_write (mem_wb_reg_write),
    .fwd_a            (fwd_a),
    .fwd_b            (fwd_b)
  );

  function automatic string fwd_name(input logic [FWD_WIDTH-1:0] sel);
    case (sel)
      FWD_REG:    fwd_name = "FWD_REG";
      FWD_EX_MEM: fwd_name = "FWD_EX_MEM";
      FWD_MEM_WB: fwd_name = "FWD_MEM_WB";
      default:    fwd_name = "UNKNOWN";
    endcase
  endfunction

  // behavioral reference for one operand, written independently of the RTL
  function automatic logic [FWD_WIDTH-1:0] ref_sel(
    input logic [REG_ADDR_WIDTH-1:0] rs,
    input logic [REG_ADDR_WIDTH-1:0] ex_rd,
    input logic                      ex_we,
    input logic [REG_ADDR_WIDTH-1:0] wb_rd,
    input logic                      wb_we
  );
    logic ex_hit;
    logic wb_hit;
    // a write to x0 is discarded by the register file, so it never bypasses
    ex_hit = (ex_we === 1'b1) && (ex_rd != 5'd0) && (ex_rd == rs);
    wb_hit = (wb_we === 1'b1) && (wb_rd != 5'd0) && (wb_rd == rs);
    if (ex_hit) begin
      ref_sel = FWD_EX_MEM;
    end else if (wb_hit) begin
      ref_sel = FWD_MEM_WB;
    end else begin
      ref_sel = FWD_REG;
    end
  endfunction

  task automatic check(
    input logic [REG_ADDR_WIDTH-1:0] t_rs1,
    input logic [REG_ADDR_WIDTH-1:0] t_rs2,
    input logic [REG_ADDR_WIDTH-1:0] t_ex_rd,
    input logic                      t_ex_we,
    input logic [REG_ADDR_WIDTH-1:0] t_wb_rd,
    input logic                      t_wb_we,
    input logic [FWD_WIDTH-1:0]      exp_a,
    input logic [FWD_WIDTH-1:0]      exp_b
  );
    id_ex_rs1        = t_rs1;
    id_ex_rs2        = t_rs2;
    ex_mem_rd        = t_ex_rd;
    ex_mem_reg_write = t_ex_we;
    mem_wb_rd        = t_wb_rd;
    mem_wb_reg_write = t_wb_we;
    #1;
    checks = checks + 1;
    if (fwd_a !== exp_a || fwd_b !== exp_b) begin
      $display("FAIL: rs1=%0d rs2=%0d ex_mem_rd=%0d ex_mem_reg_write=%0b mem_wb_rd=%0d mem_wb_reg_write=%0b",
               t_rs1, t_rs2, t_ex_rd, t_ex_we, t_wb_rd, t_wb_we);
      $display("      fwd_a got=%s expected=%s, fwd_b got=%s expected=%s",
               fwd_name(fwd_a), fwd_name(exp_a), fwd_name(fwd_b), fwd_name(exp_b));
      $fatal(1);
    end
  endtask

  // same stimulus, expectations taken from the reference instead of by hand
  task automatic check_ref(
    input logic [REG_ADDR_WIDTH-1:0] t_rs1,
    input logic [REG_ADDR_WIDTH-1:0] t_rs2,
    input logic [REG_ADDR_WIDTH-1:0] t_ex_rd,
    input logic                      t_ex_we,
    input logic [REG_ADDR_WIDTH-1:0] t_wb_rd,
    input logic                      t_wb_we
  );
    check(t_rs1, t_rs2, t_ex_rd, t_ex_we, t_wb_rd, t_wb_we,
          ref_sel(t_rs1, t_ex_rd, t_ex_we, t_wb_rd, t_wb_we),
          ref_sel(t_rs2, t_ex_rd, t_ex_we, t_wb_rd, t_wb_we));
  endtask

  initial begin
    $dumpfile("sim/build/forward_unit_tb.vcd");
    $dumpvars(0, forward_unit_tb);

    checks = 0;

    // no hazard: neither stage writes, then writes that miss both sources
    check(5'd1,  5'd2,  5'd0,  1'b0, 5'd0,  1'b0, FWD_REG, FWD_REG);
    check(5'd10, 5'd11, 5'd12, 1'b1, 5'd13, 1'b1, FWD_REG, FWD_REG);
    check(5'd31, 5'd0,  5'd30, 1'b1, 5'd29, 1'b1, FWD_REG, FWD_REG);

    // EX/MEM hazard on rs1 only, rs2 only, then both
    check(5'd5,  5'd6,  5'd5,  1'b1, 5'd20, 1'b0, FWD_EX_MEM, FWD_REG);
    check(5'd6,  5'd5,  5'd5,  1'b1, 5'd20, 1'b0, FWD_REG,    FWD_EX_MEM);
    check(5'd5,  5'd5,  5'd5,  1'b1, 5'd20, 1'b0, FWD_EX_MEM, FWD_EX_MEM);
    check(5'd31, 5'd1,  5'd31, 1'b1, 5'd0,  1'b0, FWD_EX_MEM, FWD_REG);

    // MEM/WB hazard on rs1 only, rs2 only, then both
    check(5'd7,  5'd8,  5'd20, 1'b0, 5'd7,  1'b1, FWD_MEM_WB, FWD_REG);
    check(5'd8,  5'd7,  5'd20, 1'b0, 5'd7,  1'b1, FWD_REG,    FWD_MEM_WB);
    check(5'd7,  5'd7,  5'd20, 1'b0, 5'd7,  1'b1, FWD_MEM_WB, FWD_MEM_WB);
    check(5'd31, 5'd1,  5'd0,  1'b0, 5'd31, 1'b1, FWD_MEM_WB, FWD_REG);

    // both stages target the same register, the newer EX/MEM value must win
    check(5'd9,  5'd9,  5'd9,  1'b1, 5'd9,  1'b1, FWD_EX_MEM, FWD_EX_MEM);
    check(5'd9,  5'd4,  5'd9,  1'b1, 5'd9,  1'b1, FWD_EX_MEM, FWD_REG);
    // EX/MEM matches but does not write, so the older MEM/WB value is used
    check(5'd9,  5'd9,  5'd9,  1'b0, 5'd9,  1'b1, FWD_MEM_WB, FWD_MEM_WB);

    // a matching rd with reg_write low is not a hazard, one stage at a time
    check(5'd12, 5'd12, 5'd12, 1'b0, 5'd3,  1'b1, FWD_REG, FWD_REG);
    check(5'd12, 5'd12, 5'd3,  1'b1, 5'd12, 1'b0, FWD_REG, FWD_REG);
    check(5'd12, 5'd12, 5'd12, 1'b0, 5'd12, 1'b0, FWD_REG, FWD_REG);

    // rd == 0 never forwards, including a live write to x0 while reading x0
    check(5'd0,  5'd0,  5'd0,  1'b1, 5'd4,  1'b1, FWD_REG, FWD_REG);
    check(5'd0,  5'd0,  5'd4,  1'b1, 5'd0,  1'b1, FWD_REG, FWD_REG);
    check(5'd0,  5'd0,  5'd0,  1'b1, 5'd0,  1'b1, FWD_REG, FWD_REG);
    check(5'd0,  5'd2,  5'd0,  1'b1, 5'd2,  1'b1, FWD_REG, FWD_MEM_WB);

    // the two operands can take their values from different stages
    check(5'd14, 5'd15, 5'd14, 1'b1, 5'd15, 1'b1, FWD_EX_MEM, FWD_MEM_WB);
    check(5'd15, 5'd14, 5'd14, 1'b1, 5'd15, 1'b1, FWD_MEM_WB, FWD_EX_MEM);
    check(5'd14, 5'd16, 5'd14, 1'b1, 5'd15, 1'b1, FWD_EX_MEM, FWD_REG);
    check(5'd16, 5'd15, 5'd14, 1'b1, 5'd15, 1'b1, FWD_REG,    FWD_MEM_WB);

    // exhaustive sweep: every source register against every destination pair,
    // under all four combinations of the two reg_write flags
    begin
      logic [REG_ADDR_WIDTH-1:0] rs;
      logic [REG_ADDR_WIDTH-1:0] ex_rd;
      logic [REG_ADDR_WIDTH-1:0] wb_rd;
      logic                      ex_we;
      logic                      wb_we;
      for (int wp = 0; wp < 4; wp++) begin
        ex_we = wp[0];
        wb_we = wp[1];
        for (int e = 0; e < REG_COUNT; e++) begin
          ex_rd = e[REG_ADDR_WIDTH-1:0];
          for (int w = 0; w < REG_COUNT; w++) begin
            wb_rd = w[REG_ADDR_WIDTH-1:0];
            for (int s = 0; s < REG_COUNT; s++) begin
              rs = s[REG_ADDR_WIDTH-1:0];
              // rs2 walks the register file backwards so both operands see
              // every source/destination pairing over the full sweep
              check_ref(rs, ~rs, ex_rd, ex_we, wb_rd, wb_we);
            end
          end
        end
      end
    end

    // randomized cross-check over every input at once
    begin
      logic [31:0] r;
      for (int i = 0; i < RANDOM_RUNS; i++) begin
        r = $random;
        check_ref(r[4:0], r[9:5], r[14:10], r[20], r[19:15], r[21]);
      end
    end

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: forward_unit");
    $finish;
  end

endmodule
