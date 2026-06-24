// mem_wb_stage_tb: self-checking testbench for the pipeline back end.
// Covers the reset state, the EX/MEM and MEM/WB register hand-off, the store
// path byte enables, every load extension case, the writeback mux, and the
// two cycle data bus transaction that keeps a load's address on the bus
// through its writeback cycle.

`timescale 1ns / 1ps

module mem_wb_stage_tb;

  import rv32_pkg::*;

  localparam int DATA_WIDTH     = 32;
  localparam int BE_WIDTH       = DATA_WIDTH / 8;
  localparam int REG_ADDR_WIDTH = 5;
  localparam int CLK_PERIOD     = 10;

  // what dmem_rdata carries while a load is still in MEM: the real word only
  // shows up in WB, so anything sampled early would be this
  localparam logic [DATA_WIDTH-1:0] STALE = 32'hBADB_AD00;

  logic clk;
  logic rst_n;

  logic [DATA_WIDTH-1:0]     ex_alu_result;
  logic [DATA_WIDTH-1:0]     ex_store_data;
  logic [DATA_WIDTH-1:0]     ex_pc_plus4;
  logic [REG_ADDR_WIDTH-1:0] ex_rd;
  logic [2:0]                ex_funct3;
  logic                      ex_reg_write;
  wb_sel_e                   ex_wb_sel;
  logic                      ex_mem_read;
  logic                      ex_mem_write;

  logic [DATA_WIDTH-1:0]     dmem_addr;
  logic [DATA_WIDTH-1:0]     dmem_wdata;
  logic [BE_WIDTH-1:0]       dmem_be;
  logic                      dmem_we;
  logic                      dmem_re;
  logic [DATA_WIDTH-1:0]     dmem_rdata;

  logic [DATA_WIDTH-1:0]     ex_mem_alu_result;
  logic [REG_ADDR_WIDTH-1:0] ex_mem_rd;
  logic                      ex_mem_reg_write;
  logic [REG_ADDR_WIDTH-1:0] mem_wb_rd;
  logic                      mem_wb_reg_write;
  logic [DATA_WIDTH-1:0]     wb_data;

  int unsigned checks;

  mem_wb_stage #(
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH)
  ) dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .ex_alu_result     (ex_alu_result),
    .ex_store_data     (ex_store_data),
    .ex_pc_plus4       (ex_pc_plus4),
    .ex_rd             (ex_rd),
    .ex_funct3         (ex_funct3),
    .ex_reg_write      (ex_reg_write),
    .ex_wb_sel         (ex_wb_sel),
    .ex_mem_read       (ex_mem_read),
    .ex_mem_write      (ex_mem_write),
    .dmem_addr         (dmem_addr),
    .dmem_wdata        (dmem_wdata),
    .dmem_be           (dmem_be),
    .dmem_we           (dmem_we),
    .dmem_re           (dmem_re),
    .dmem_rdata        (dmem_rdata),
    .ex_mem_alu_result (ex_mem_alu_result),
    .ex_mem_rd         (ex_mem_rd),
    .ex_mem_reg_write  (ex_mem_reg_write),
    .mem_wb_rd         (mem_wb_rd),
    .mem_wb_reg_write  (mem_wb_reg_write),
    .wb_data           (wb_data)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // watchdog so a hung testbench fails instead of running forever
  initial begin
    #20000;
    $display("FAIL: timeout, testbench did not finish");
    $fatal(1);
  end

  task automatic chk(input string what, input logic [DATA_WIDTH-1:0] got,
                     input logic [DATA_WIDTH-1:0] exp);
    checks = checks + 1;
    if (got !== exp) begin
      $display("FAIL: %s: got 0x%08h expected 0x%08h at time %0t", what, got, exp, $time);
      $fatal(1);
    end
  endtask

  // drive the EX side of the boundary; the values land in EX/MEM on the next
  // rising edge, which is the instruction entering the MEM stage
  task automatic ex_drive(input logic [DATA_WIDTH-1:0]     alu,
                          input logic [DATA_WIDTH-1:0]     sdata,
                          input logic [DATA_WIDTH-1:0]     pc4,
                          input logic [REG_ADDR_WIDTH-1:0] rd,
                          input logic [2:0]                f3,
                          input logic                      rw,
                          input wb_sel_e                   sel,
                          input logic                      mr,
                          input logic                      mw);
    ex_alu_result = alu;
    ex_store_data = sdata;
    ex_pc_plus4   = pc4;
    ex_rd         = rd;
    ex_funct3     = f3;
    ex_reg_write  = rw;
    ex_wb_sel     = sel;
    ex_mem_read   = mr;
    ex_mem_write  = mw;
  endtask

  task automatic ex_bubble();
    ex_drive('0, '0, '0, '0, 3'b000, 1'b0, WB_ALU, 1'b0, 1'b0);
  endtask

  task automatic step();
    @(posedge clk);
    #1;
  endtask

  // one store: drive it, clock it into MEM, then check what the bus carries
  task automatic run_store(input string                 label,
                           input logic [DATA_WIDTH-1:0] addr,
                           input logic [DATA_WIDTH-1:0] sdata,
                           input logic [2:0]            f3,
                           input logic [DATA_WIDTH-1:0] exp_wdata,
                           input logic [BE_WIDTH-1:0]   exp_be);
    ex_drive(addr, sdata, '0, '0, f3, 1'b0, WB_ALU, 1'b0, 1'b1);
    step();
    chk({label, " bus addr"}, dmem_addr, addr);
    chk({label, " we"}, {31'd0, dmem_we}, 32'd1);
    chk({label, " re"}, {31'd0, dmem_re}, 32'd0);
    chk({label, " byte enables"}, {28'd0, dmem_be}, {28'd0, exp_be});
    chk({label, " wdata lanes"}, dmem_wdata & be_mask(exp_be),
        exp_wdata & be_mask(exp_be));
    // a store writes no register, in MEM or afterwards
    chk({label, " no reg write in MEM"}, {31'd0, ex_mem_reg_write}, 32'd0);
    ex_bubble();
    step();
    chk({label, " no reg write in WB"}, {31'd0, mem_wb_reg_write}, 32'd0);
    chk({label, " we released"}, {31'd0, dmem_we}, 32'd0);
  endtask

  // only the enabled lanes of mem_wdata are defined, the rest are don't care
  function automatic logic [DATA_WIDTH-1:0] be_mask(input logic [BE_WIDTH-1:0] be);
    for (int i = 0; i < BE_WIDTH; i++) be_mask[8*i +: 8] = {8{be[i]}};
  endfunction

  // one load: address in MEM, word extended in WB. The bus must still be
  // parked on this load's address during WB, because the external decode
  // qualifies the read data with dmem_re and the address.
  task automatic run_load(input string                 label,
                          input logic [DATA_WIDTH-1:0] addr,
                          input logic [2:0]            f3,
                          input logic [DATA_WIDTH-1:0] word,
                          input logic [DATA_WIDTH-1:0] exp);
    dmem_rdata = STALE;
    ex_drive(addr, '0, '0, 5'd9, f3, 1'b1, WB_MEM, 1'b1, 1'b0);
    step();
    chk({label, " MEM addr"}, dmem_addr, addr);
    chk({label, " MEM re"}, {31'd0, dmem_re}, 32'd1);
    chk({label, " MEM we"}, {31'd0, dmem_we}, 32'd0);
    // the load is behind the memory, so nothing may be captured yet
    ex_bubble();
    step();
    dmem_rdata = word;
    #1;
    chk({label, " WB addr held"}, dmem_addr, addr);
    chk({label, " WB re held"}, {31'd0, dmem_re}, 32'd1);
    chk({label, " wb_data"}, wb_data, exp);
    chk({label, " rd"}, {27'd0, mem_wb_rd}, 32'd9);
    chk({label, " reg write"}, {31'd0, mem_wb_reg_write}, 32'd1);
    step();
    chk({label, " bus released"}, {31'd0, dmem_re}, 32'd0);
  endtask

  initial begin
    $dumpfile("sim/build/mem_wb_stage_tb.vcd");
    $dumpvars(0, mem_wb_stage_tb);

    checks     = 0;
    dmem_rdata = STALE;
    ex_drive(32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 5'd31, 3'b111, 1'b1,
             WB_MEM, 1'b1, 1'b1);

    // 1. Reset holds both banks as bubbles no matter what EX is presenting
    rst_n = 1'b0;
    step();
    step();
    chk("reset ex_mem alu", ex_mem_alu_result, 32'd0);
    chk("reset ex_mem rd", {27'd0, ex_mem_rd}, 32'd0);
    chk("reset ex_mem reg write", {31'd0, ex_mem_reg_write}, 32'd0);
    chk("reset mem_wb rd", {27'd0, mem_wb_rd}, 32'd0);
    chk("reset mem_wb reg write", {31'd0, mem_wb_reg_write}, 32'd0);
    chk("reset wb_data", wb_data, 32'd0);
    chk("reset we", {31'd0, dmem_we}, 32'd0);
    chk("reset re", {31'd0, dmem_re}, 32'd0);

    rst_n = 1'b1;
    ex_bubble();
    step();

    // 2. An ALU instruction: forwarding taps in MEM, writeback mux in WB
    ex_drive(32'hDEAD_BEEF, '0, 32'h0000_0040, 5'd5, 3'b000, 1'b1, WB_ALU,
             1'b0, 1'b0);
    step();
    chk("alu ex_mem tap", ex_mem_alu_result, 32'hDEAD_BEEF);
    chk("alu ex_mem rd", {27'd0, ex_mem_rd}, 32'd5);
    chk("alu ex_mem reg write", {31'd0, ex_mem_reg_write}, 32'd1);
    chk("alu idle re", {31'd0, dmem_re}, 32'd0);
    chk("alu idle we", {31'd0, dmem_we}, 32'd0);
    ex_bubble();
    step();
    chk("alu wb_data", wb_data, 32'hDEAD_BEEF);
    chk("alu mem_wb rd", {27'd0, mem_wb_rd}, 32'd5);
    chk("alu mem_wb reg write", {31'd0, mem_wb_reg_write}, 32'd1);

    // 3. A jump: the link value comes from pc_plus4, not the ALU
    ex_drive(32'h0000_1234, '0, 32'h0000_0084, 5'd1, 3'b000, 1'b1, WB_PC4,
             1'b0, 1'b0);
    step();
    ex_bubble();
    step();
    chk("jump wb_data", wb_data, 32'h0000_0084);
    chk("jump mem_wb rd", {27'd0, mem_wb_rd}, 32'd1);

    // 4. Stores: lane steering and byte enables straight off EX/MEM
    run_store("sw", 32'h0000_1004, 32'hCAFE_F00D, F3_LW, 32'hCAFE_F00D, 4'b1111);
    run_store("sb lane 0", 32'h0000_1004, 32'h0000_0011, F3_LB, 32'h0000_0011, 4'b0001);
    run_store("sb lane 3", 32'h0000_1007, 32'hFFFF_FF86, F3_LB, 32'h8600_0000, 4'b1000);
    run_store("sh low", 32'h0000_1008, 32'h0000_1234, F3_LH, 32'h0000_1234, 4'b0011);
    run_store("sh high", 32'h0000_100A, 32'hFFFF_8001, F3_LH, 32'h8001_0000, 4'b1100);

    // 5. Loads: every extension case, each one proving the bus stayed parked
    run_load("lw", 32'h0000_1000, F3_LW, 32'hCAFE_F00D, 32'hCAFE_F00D);
    run_load("lb positive", 32'h0000_1004, F3_LB, 32'h8633_2211, 32'h0000_0011);
    run_load("lb negative", 32'h0000_1007, F3_LB, 32'h8633_2211, 32'hFFFF_FF86);
    run_load("lbu", 32'h0000_1007, F3_LBU, 32'h8633_2211, 32'h0000_0086);
    run_load("lh low", 32'h0000_1008, F3_LH, 32'h8001_1234, 32'h0000_1234);
    run_load("lh high", 32'h0000_100A, F3_LH, 32'h8001_1234, 32'hFFFF_8001);
    run_load("lhu high", 32'h0000_100A, F3_LHU, 32'h8001_1234, 32'h0000_8001);
    // an mmio style address works the same way; the core never decodes regions
    run_load("mmio word", 32'hFFFF_0004, F3_LW, 32'h0000_02A5, 32'h0000_02A5);

    // 6. Back to back loads, the case cpu_top's data bus stall guarantees is
    //    separated by a bubble: the second load's address must not appear on
    //    the bus until the first one has finished its writeback cycle
    dmem_rdata = STALE;
    ex_drive(32'h0000_1020, '0, '0, 5'd12, F3_LW, 1'b1, WB_MEM, 1'b1, 1'b0);
    step();
    chk("first load MEM addr", dmem_addr, 32'h0000_1020);
    ex_bubble();
    step();
    dmem_rdata = 32'h0BAD_F00D;
    #1;
    chk("first load WB addr held", dmem_addr, 32'h0000_1020);
    chk("first load wb_data", wb_data, 32'h0BAD_F00D);
    ex_drive(32'h0000_1030, '0, '0, 5'd13, F3_LW, 1'b1, WB_MEM, 1'b1, 1'b0);
    step();
    chk("second load MEM addr", dmem_addr, 32'h0000_1030);
    chk("second load re", {31'd0, dmem_re}, 32'd1);

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: mem_wb_stage");
    $finish;
  end

endmodule
