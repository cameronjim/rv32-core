// cpu_top_tb: top level self checking testbench for the single-cycle core.
// Wraps cpu_top with imem and dmem, decoding dmem at 0x00001000, then runs the
// assembled programs in tb/programs and checks registers and memory afterward.

`timescale 1ns / 1ps

module cpu_top_tb;

  localparam int DATA_WIDTH     = 32;
  localparam int BE_WIDTH       = DATA_WIDTH / 8;
  localparam int MEM_ADDR_WIDTH = 10;
  localparam int NUM_WORDS      = 1 << MEM_ADDR_WIDTH;
  localparam int CYCLE_BUDGET   = 2000;

  // done convention: the magic word lands in the last dmem word, 0x00001FFC
  localparam logic [DATA_WIDTH-1:0] DONE_MAGIC = 32'h0000_600D;
  localparam logic [DATA_WIDTH-1:0] DONE_ADDR  = 32'h0000_1FFC;
  localparam int                    DONE_INDEX = NUM_WORDS - 1;

  // dmem is filled with this before every program so nothing can pass by
  // accidentally relying on memory reading back as zero
  localparam logic [DATA_WIDTH-1:0] POISON = 32'hA5A5_A5A5;

  localparam logic [19:0] DMEM_BASE_TAG = 20'h00001;

  logic clk;
  logic rst_n;

  logic [DATA_WIDTH-1:0] imem_addr;
  logic [DATA_WIDTH-1:0] imem_rdata;
  logic [DATA_WIDTH-1:0] dmem_addr;
  logic [DATA_WIDTH-1:0] dmem_wdata;
  logic [BE_WIDTH-1:0]   dmem_be;
  logic                  dmem_we;
  logic                  dmem_re;
  logic [DATA_WIDTH-1:0] dmem_rdata;

  logic                  dmem_sel;
  logic [DATA_WIDTH-1:0] dmem_raw_rdata;

  // address decode lives here, not in the core: dmem answers for 0x00001xxx
  assign dmem_sel   = (dmem_addr[31:12] == DMEM_BASE_TAG);
  assign dmem_rdata = (dmem_re && dmem_sel) ? dmem_raw_rdata : '0;

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

  // INIT_FILE stays empty; each program is loaded hierarchically below
  imem #(
    .ADDR_WIDTH (MEM_ADDR_WIDTH),
    .INIT_FILE  ("")
  ) u_imem (
    .clk   (clk),
    .addr  (imem_addr[MEM_ADDR_WIDTH+1:2]),
    .rdata (imem_rdata)
  );

  dmem #(
    .ADDR_WIDTH (MEM_ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .INIT_FILE  ("")
  ) u_dmem (
    .clk     (clk),
    .addr    (dmem_addr[MEM_ADDR_WIDTH+1:2]),
    .wdata   (dmem_wdata),
    .byte_en (dmem_be),
    .we      (dmem_we && dmem_sel),
    .rdata   (dmem_raw_rdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic check_reg(
    input string                 prog,
    input int                    idx,
    input logic [DATA_WIDTH-1:0] exp
  );
    logic [DATA_WIDTH-1:0] got;
    got = u_cpu.u_reg_file.regs[idx];
    if (got !== exp) begin
      $display("FAIL: %s: x%0d got 0x%08h expected 0x%08h", prog, idx, got, exp);
      $fatal(1);
    end
  endtask

  task automatic check_mem(
    input string                 prog,
    input logic [DATA_WIDTH-1:0] byte_addr,
    input logic [DATA_WIDTH-1:0] exp
  );
    logic [DATA_WIDTH-1:0] got;
    int                    idx;
    idx = int'((byte_addr % (4 * NUM_WORDS)) / 4);
    got = u_dmem.mem[idx];
    if (got !== exp) begin
      $display("FAIL: %s: dmem[0x%08h] got 0x%08h expected 0x%08h",
               prog, byte_addr, got, exp);
      $fatal(1);
    end
  endtask

  // load a program, reset the core, and run it until the done word appears
  task automatic run_program(input string prog, input string hex_file);
    int  cycles;
    logic done_seen;

    for (int i = 0; i < NUM_WORDS; i++) begin
      u_imem.mem[i] = '0;
      u_dmem.mem[i] = POISON;
    end
    $readmemh(hex_file, u_imem.mem);
    u_dmem.mem[DONE_INDEX] = '0;

    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    rst_n = 1'b1;

    cycles    = 0;
    done_seen = 1'b0;
    while (!done_seen) begin
      @(posedge clk);
      // let the nonblocking dmem write settle before sampling the done word
      #1;
      cycles    = cycles + 1;
      done_seen = (u_dmem.mem[DONE_INDEX] === DONE_MAGIC);
      if (!done_seen && (cycles >= CYCLE_BUDGET)) begin
        $display("FAIL: %s: no done word after %0d cycles, dmem[0x%08h] = 0x%08h",
                 prog, CYCLE_BUDGET, DONE_ADDR, u_dmem.mem[DONE_INDEX]);
        $fatal(1);
      end
    end
  endtask

  // expected values are documented line by line in tb/programs/arith.s
  task automatic check_arith(input string prog);
    check_reg(prog, 5,  32'h1234_5789);
    check_reg(prog, 6,  32'hFFFF_FFEF);
    check_reg(prog, 7,  32'h0000_0078);
    check_reg(prog, 8,  32'h1234_577F);
    check_reg(prog, 9,  32'h1234_5687);
    check_reg(prog, 10, 32'hEDCB_A987);
    check_reg(prog, 11, 32'h2345_6780);
    check_reg(prog, 12, 32'h0FFF_FFFF);
    check_reg(prog, 13, 32'hFFFF_FFFF);
    check_reg(prog, 14, 32'h0000_0001);
    check_reg(prog, 15, 32'h0000_0000);
    check_reg(prog, 16, 32'hF000_0000);
    check_reg(prog, 17, 32'h0F00_0000);
    check_reg(prog, 18, 32'hFF00_0000);
    check_reg(prog, 19, 32'h1234_5668);
    check_reg(prog, 20, 32'h1234_5669);
    check_reg(prog, 21, 32'h1000_0000);
    check_reg(prog, 22, 32'hF000_000F);
    check_reg(prog, 23, 32'hEDCB_A988);
    check_reg(prog, 24, 32'h2B3C_0000);
    check_reg(prog, 25, 32'h0001_E000);
    check_reg(prog, 26, 32'hFFFF_E000);
    check_reg(prog, 27, 32'h0000_0001);
    check_reg(prog, 28, 32'h0000_0000);
    check_reg(prog, 0,  32'h0000_0000);
    check_mem(prog, DONE_ADDR, DONE_MAGIC);
    // arith touches no other dmem word, so the poison must survive
    check_mem(prog, 32'h0000_1000, POISON);
  endtask

  // expected values are documented line by line in tb/programs/mem.s
  task automatic check_mem_prog(input string prog);
    check_reg(prog, 3,  32'h0000_1000);
    check_reg(prog, 5,  32'hCAFE_F00D);
    check_reg(prog, 6,  32'hCAFE_F00D);
    check_reg(prog, 7,  32'hFFFF_FF86);
    check_reg(prog, 8,  32'h8633_2211);
    check_reg(prog, 9,  32'hFFFF_FF86);
    check_reg(prog, 10, 32'h0000_0086);
    check_reg(prog, 11, 32'h0000_0011);
    check_reg(prog, 12, 32'h0000_1234);
    check_reg(prog, 13, 32'hFFFF_8001);
    check_reg(prog, 14, 32'h8001_1234);
    check_reg(prog, 15, 32'h0000_1234);
    check_reg(prog, 16, 32'hFFFF_8001);
    check_reg(prog, 17, 32'h0000_8001);
    check_reg(prog, 18, 32'h0000_1234);
    check_reg(prog, 19, 32'h0000_000C);
    check_reg(prog, 20, 32'h0008_0010);
    check_reg(prog, 21, 32'hCAFE_F019);
    check_reg(prog, 22, 32'h0000_005A);
    check_reg(prog, 23, 32'hCAFE_5A0D);
    check_reg(prog, 24, 32'h0000_1010);
    check_reg(prog, 25, 32'hCAFE_F00D);
    check_reg(prog, 28, 32'h0000_1FFC);
    check_reg(prog, 29, 32'h0000_600D);
    check_mem(prog, 32'h0000_1000, 32'hCAFE_F00D);
    check_mem(prog, 32'h0000_1004, 32'h8633_2211);
    check_mem(prog, 32'h0000_1008, 32'h8001_1234);
    check_mem(prog, 32'h0000_100C, 32'hCAFE_F019);
    check_mem(prog, 32'h0000_1010, 32'hCAFE_5A0D);
    check_mem(prog, 32'h0000_1014, POISON);
    check_mem(prog, DONE_ADDR, DONE_MAGIC);
  endtask

  // expected values are documented line by line in tb/programs/branch.s
  task automatic check_branch(input string prog);
    check_reg(prog, 1,  32'h0000_007C);
    check_reg(prog, 5,  32'h0000_0005);
    check_reg(prog, 6,  32'h0000_0005);
    check_reg(prog, 7,  32'hFFFF_FFFF);
    check_reg(prog, 8,  32'h0000_0001);
    check_reg(prog, 9,  32'h0000_1FFC);
    check_reg(prog, 10, 32'h0000_600D);
    check_reg(prog, 20, 32'h0000_0077);
    check_reg(prog, 21, 32'h0000_0033);
    check_reg(prog, 22, 32'h0000_0099);
    check_reg(prog, 23, 32'h0000_0095);
    check_reg(prog, 24, 32'h0000_0055);
    check_reg(prog, 25, 32'h0000_0098);
    check_reg(prog, 26, 32'h0000_0000);
    check_reg(prog, 27, 32'h0000_10A0);
    check_reg(prog, 28, 32'hABCD_E000);
    check_reg(prog, 29, 32'h8000_0000);
    // every not-taken branch fell through, no taken branch ran its wrong path
    check_reg(prog, 30, 32'h0000_0006);
    check_reg(prog, 31, 32'h0000_0000);
    check_mem(prog, DONE_ADDR, DONE_MAGIC);
  endtask

  initial begin
    $dumpfile("sim/build/cpu_top_tb.vcd");
    $dumpvars(0, cpu_top_tb);

    rst_n = 1'b0;

    run_program("arith", "tb/programs/arith.hex");
    check_arith("arith");

    run_program("mem", "tb/programs/mem.hex");
    check_mem_prog("mem");

    run_program("branch", "tb/programs/branch.hex");
    check_branch("branch");

    $display("PASS: cpu_top");
    $finish;
  end

endmodule
