// reg_file_tb: self-checking testbench for the register file.
// Covers reset, both read ports, x0 hardwiring, write enable gating, and the
// no-bypass rule that a same-cycle read returns the pre-write value.

`timescale 1ns / 1ps

module reg_file_tb;

  localparam int DATA_WIDTH = 32;
  localparam int NUM_REGS = 32;
  localparam int ADDR_WIDTH = 5;
  localparam int CLK_PERIOD = 10;

  logic                  clk;
  logic                  rst_n;
  logic [ADDR_WIDTH-1:0] rs1_addr;
  logic [DATA_WIDTH-1:0] rs1_data;
  logic [ADDR_WIDTH-1:0] rs2_addr;
  logic [DATA_WIDTH-1:0] rs2_data;
  logic [ADDR_WIDTH-1:0] rd_addr;
  logic [DATA_WIDTH-1:0] rd_data;
  logic                  rd_we;

  reg_file #(
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_REGS  (NUM_REGS)
  ) dut (
      .clk     (clk),
      .rst_n   (rst_n),
      .rs1_addr(rs1_addr),
      .rs1_data(rs1_data),
      .rs2_addr(rs2_addr),
      .rs2_data(rs2_data),
      .rd_addr (rd_addr),
      .rd_data (rd_data),
      .rd_we   (rd_we)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Watchdog so a hung testbench fails instead of running forever
  initial begin
    #10000;
    $display("FAIL: timeout, testbench did not finish");
    $fatal(1);
  end

  // Drive one write and return one nanosecond after the capturing edge
  task automatic write_reg(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data);
    rd_addr = addr;
    rd_data = data;
    rd_we   = 1'b1;
    @(posedge clk);
    #1;
    rd_we = 1'b0;
  endtask

  task automatic check_rs1(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] expected,
                           input string label);
    rs1_addr = addr;
    #1;
    if (rs1_data !== expected) begin
      $display("FAIL: %s, rs1_addr=%0d expected 0x%08h got 0x%08h at time %0t", label, addr,
               expected, rs1_data, $time);
      $fatal(1);
    end
  endtask

  task automatic check_rs2(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] expected,
                           input string label);
    rs2_addr = addr;
    #1;
    if (rs2_data !== expected) begin
      $display("FAIL: %s, rs2_addr=%0d expected 0x%08h got 0x%08h at time %0t", label, addr,
               expected, rs2_data, $time);
      $fatal(1);
    end
  endtask

  task automatic check_both(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] expected,
                            input string label);
    check_rs1(addr, expected, label);
    check_rs2(addr, expected, label);
  endtask

  task automatic apply_reset();
    rst_n = 1'b0;
    rd_we = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;
  endtask

  logic [DATA_WIDTH-1:0] pattern;

  initial begin
    $dumpfile("sim/build/reg_file_tb.vcd");
    $dumpvars(0, reg_file_tb);

    rst_n    = 1'b1;
    rs1_addr = '0;
    rs2_addr = '0;
    rd_addr  = '0;
    rd_data  = '0;
    rd_we    = 1'b0;

    // 1. Reset clears every register
    apply_reset();
    for (int i = 0; i < NUM_REGS; i++) begin
      check_both(i[ADDR_WIDTH-1:0], 32'h0000_0000, "register not zero after reset");
    end

    // 2. Write then read back on both ports
    write_reg(5'd1, 32'hDEAD_BEEF);
    check_both(5'd1, 32'hDEAD_BEEF, "write to x1 did not read back");

    // 3. Writes to x0 are ignored
    write_reg(5'd0, 32'hFFFF_FFFF);
    check_both(5'd0, 32'h0000_0000, "write to x0 was not ignored");

    // 4. x0 reads zero while a write to x0 is being driven
    rd_addr  = 5'd0;
    rd_data  = 32'hA5A5_A5A5;
    rd_we    = 1'b1;
    rs1_addr = 5'd0;
    rs2_addr = 5'd0;
    #1;
    if ((rs1_data !== 32'h0) || (rs2_data !== 32'h0)) begin
      $display("FAIL: x0 read nonzero during write to x0, rs1=0x%08h rs2=0x%08h at time %0t",
               rs1_data, rs2_data, $time);
      $fatal(1);
    end
    @(posedge clk);
    #1;
    rd_we = 1'b0;
    check_both(5'd0, 32'h0000_0000, "x0 nonzero after asserted write to x0");

    // 5. Two different registers read at once on the two ports
    write_reg(5'd2, 32'h1234_5678);
    write_reg(5'd3, 32'h8765_4321);
    rs1_addr = 5'd2;
    rs2_addr = 5'd3;
    #1;
    if ((rs1_data !== 32'h1234_5678) || (rs2_data !== 32'h8765_4321)) begin
      $display("FAIL: simultaneous port read, rs1=0x%08h (exp 0x12345678) rs2=0x%08h (exp 0x87654321) at time %0t",
               rs1_data, rs2_data, $time);
      $fatal(1);
    end

    // 6. rd_we low leaves the target register untouched
    rd_addr = 5'd2;
    rd_data = 32'h0BAD_0BAD;
    rd_we   = 1'b0;
    @(posedge clk);
    #1;
    check_both(5'd2, 32'h1234_5678, "register changed while rd_we was low");

    // 7. No bypass: a read during a write to the same address sees the old value
    rd_addr  = 5'd2;
    rd_data  = 32'hCAFE_F00D;
    rd_we    = 1'b1;
    rs1_addr = 5'd2;
    rs2_addr = 5'd2;
    #1;
    if ((rs1_data !== 32'h1234_5678) || (rs2_data !== 32'h1234_5678)) begin
      $display("FAIL: read during write to x2 bypassed, rs1=0x%08h rs2=0x%08h expected 0x12345678 at time %0t",
               rs1_data, rs2_data, $time);
      $fatal(1);
    end
    @(posedge clk);
    #1;
    rd_we = 1'b0;
    check_both(5'd2, 32'hCAFE_F00D, "new value not visible after the write edge");

    // 8. Distinct patterns in several registers all survive
    for (int i = 1; i < NUM_REGS; i++) begin
      pattern = {24'h0, 8'hC0} ^ (32'h1111_1111 * i[7:0]);
      write_reg(i[ADDR_WIDTH-1:0], pattern);
    end
    for (int i = 1; i < NUM_REGS; i++) begin
      pattern = {24'h0, 8'hC0} ^ (32'h1111_1111 * i[7:0]);
      check_both(i[ADDR_WIDTH-1:0], pattern, "stored pattern corrupted");
    end
    check_both(5'd31, {24'h0, 8'hC0} ^ (32'h1111_1111 * 8'd31), "x31 pattern corrupted");

    // 9. Mid-test reset clears everything again
    apply_reset();
    for (int i = 0; i < NUM_REGS; i++) begin
      check_both(i[ADDR_WIDTH-1:0], 32'h0000_0000, "register not zero after mid-test reset");
    end

    // Writes still work after the second reset
    write_reg(5'd31, 32'hFFFF_0000);
    check_both(5'd31, 32'hFFFF_0000, "write after mid-test reset failed");
    check_both(5'd30, 32'h0000_0000, "neighbor register disturbed by write to x31");

    $display("PASS: reg_file");
    $finish;
  end

endmodule
