// cpu_top: the five stage RV32I pipeline, IF, ID, EX, MEM, WB. Holds the
// front end (fetch, decode, execute) and wires the decoder, register file,
// immediate generator, branch comparator, ALU, forwarding unit, hazard unit
// and the mem_wb_stage back end together. Memories stay outside so the same
// core fits the testbenches and the board top. One instruction retires per
// cycle except on a load-use stall, a data bus stall, and the two cycle
// flush a taken branch or a jump costs.

module cpu_top
  import rv32_pkg::*;
#(
  parameter int          DATA_WIDTH   = 32,
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
  input  logic                    clk,
  input  logic                    rst_n,
  // instruction bus, byte addressed
  output logic [DATA_WIDTH-1:0]   imem_addr,
  input  logic [DATA_WIDTH-1:0]   imem_rdata,
  // data bus, byte addressed
  output logic [DATA_WIDTH-1:0]   dmem_addr,
  output logic [DATA_WIDTH-1:0]   dmem_wdata,
  output logic [DATA_WIDTH/8-1:0] dmem_be,
  output logic                    dmem_we,
  output logic                    dmem_re,
  input  logic [DATA_WIDTH-1:0]   dmem_rdata
);

  localparam int REG_ADDR_WIDTH = 5;
  localparam int FWD_WIDTH      = 2;

  // addi x0, x0, 0. ID decodes this instead of the fetched word while IF/ID
  // carries a flush, because the imem output register cannot be cleared.
  localparam logic [DATA_WIDTH-1:0] NOP_INSTR = 32'h0000_0013;

  // forward_unit's select encoding, mirrored by the EX operand muxes
  localparam logic [FWD_WIDTH-1:0] FWD_REG    = 2'b00;
  localparam logic [FWD_WIDTH-1:0] FWD_EX_MEM = 2'b01;
  localparam logic [FWD_WIDTH-1:0] FWD_MEM_WB = 2'b10;

  // IF and IF/ID. The instruction itself lives in the imem output register,
  // so only the pc pair and the flush flag need flops here.
  logic [DATA_WIDTH-1:0] pc, pc_next, pc_plus4;
  logic [DATA_WIDTH-1:0] if_id_pc, if_id_pc_plus4;
  logic                  if_id_nop;

  // ID
  logic [DATA_WIDTH-1:0]     id_instr, id_imm;
  logic [DATA_WIDTH-1:0]     id_rs1_data, id_rs2_data, rf_rs1_data, rf_rs2_data;
  logic [REG_ADDR_WIDTH-1:0] id_rs1_addr, id_rs2_addr, id_rd_addr;
  logic [6:0]                id_opcode;
  logic [2:0]                id_funct3;
  logic                      id_funct7_b5;
  logic                      id_reg_write, id_alu_a_src, id_alu_b_src;
  alu_op_e                   id_alu_op;
  wb_sel_e                   id_wb_sel;
  logic                      id_mem_read, id_mem_write;
  logic                      id_branch, id_jump, id_jalr;
  logic                      id_uses_rs1, id_uses_rs2;
  logic                      wb_bypass_rs1, wb_bypass_rs2;

  // ID/EX
  logic [DATA_WIDTH-1:0]     id_ex_pc, id_ex_pc_plus4, id_ex_imm;
  logic [DATA_WIDTH-1:0]     id_ex_rs1_data, id_ex_rs2_data;
  logic [REG_ADDR_WIDTH-1:0] id_ex_rs1, id_ex_rs2, id_ex_rd;
  logic [2:0]                id_ex_funct3;
  logic                      id_ex_reg_write, id_ex_alu_a_src, id_ex_alu_b_src;
  alu_op_e                   id_ex_alu_op;
  wb_sel_e                   id_ex_wb_sel;
  logic                      id_ex_mem_read, id_ex_mem_write;
  logic                      id_ex_branch, id_ex_jump, id_ex_jalr;

  // EX
  logic [FWD_WIDTH-1:0]  fwd_a, fwd_b;
  logic [DATA_WIDTH-1:0] ex_rs1_fwd, ex_rs2_fwd;
  logic [DATA_WIDTH-1:0] alu_a, alu_b, alu_result, ex_target;
  logic                  ex_branch_taken, ex_redirect;

  // back end taps, driven by mem_wb_stage
  logic [DATA_WIDTH-1:0]     ex_mem_alu_result, wb_data;
  logic [REG_ADDR_WIDTH-1:0] ex_mem_rd, mem_wb_rd;
  logic                      ex_mem_reg_write, mem_wb_reg_write;

  // hazard control
  logic stall_pc, stall_if_id, flush_if_id, bubble_id_ex;
  logic bus_hazard, front_stall, id_ex_bubble;

  // ------------------------------------------------------------------ IF
  // The pc launches the address and imem captures it on the same rising edge,
  // so the fetched word lands in ID one cycle later.
  //
  // Holding the pc alone does not hold the instruction. By the time ID sees a
  // word the pc has already moved to the instruction after it, so a frozen pc
  // would re-fetch the wrong one and the stalled instruction would be lost.
  // The imem output register cannot be held either. Re-presenting if_id_pc,
  // the address of the instruction ID is looking at, makes the block RAM hand
  // back the same word next cycle, which is what holding IF/ID means here.
  assign imem_addr = front_stall ? if_id_pc : pc;
  assign pc_plus4  = pc + 32'd4;
  assign pc_next   = ex_redirect ? ex_target : pc_plus4;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc <= RESET_VECTOR;
    end else if (!front_stall) begin
      pc <= pc_next;
    end
  end

  // IF/ID. On reset the stage comes up as a bubble: if_id_nop makes ID decode
  // a nop while the reset cycle's fetch of the reset vector is still in
  // flight, so the first instruction is executed exactly once. On a redirect
  // the flag is set for the next cycle, which is when the wrong-path word the
  // redirect could not stop arrives in ID.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      if_id_pc       <= RESET_VECTOR;
      if_id_pc_plus4 <= RESET_VECTOR + 32'd4;
      if_id_nop      <= 1'b1;
    end else if (!front_stall) begin
      if_id_pc       <= pc;
      if_id_pc_plus4 <= pc_plus4;
      if_id_nop      <= flush_if_id;
    end
  end

  // ------------------------------------------------------------------ ID
  // field slicing, hoisted out of the port connections and procedural blocks
  // so Icarus does not flag the parameterized part selects
  assign id_instr     = if_id_nop ? NOP_INSTR : imem_rdata;
  assign id_opcode    = id_instr[6:0];
  assign id_rs1_addr  = id_instr[19:15];
  assign id_rs2_addr  = id_instr[24:20];
  assign id_rd_addr   = id_instr[11:7];
  assign id_funct3    = id_instr[14:12];
  assign id_funct7_b5 = id_instr[30];

  // WB-to-ID bypass. The register file writes on the same edge that ends this
  // cycle and has no internal write-through, so a read of the register WB is
  // writing has to take wb_data directly. x0 never bypasses.
  assign wb_bypass_rs1 = mem_wb_reg_write && (mem_wb_rd != '0) &&
                         (mem_wb_rd == id_rs1_addr);
  assign wb_bypass_rs2 = mem_wb_reg_write && (mem_wb_rd != '0) &&
                         (mem_wb_rd == id_rs2_addr);

  assign id_rs1_data = wb_bypass_rs1 ? wb_data : rf_rs1_data;
  assign id_rs2_data = wb_bypass_rs2 ? wb_data : rf_rs2_data;

  // ID/EX. A bubble zeroes the whole bank, so the injected instruction
  // neither writes, touches memory, redirects, nor matches any forwarding or
  // hazard comparison. Reset does exactly the same thing. This bank is never
  // held: a front end stall feeds it bubbles instead, which keeps the EX
  // operands from going stale while the pipeline drains past them.
  always_ff @(posedge clk) begin
    if (!rst_n || id_ex_bubble) begin
      id_ex_pc        <= '0;
      id_ex_pc_plus4  <= '0;
      id_ex_rs1_data  <= '0;
      id_ex_rs2_data  <= '0;
      id_ex_imm       <= '0;
      id_ex_rs1       <= '0;
      id_ex_rs2       <= '0;
      id_ex_rd        <= '0;
      id_ex_funct3    <= '0;
      id_ex_reg_write <= 1'b0;
      id_ex_alu_a_src <= 1'b0;
      id_ex_alu_b_src <= 1'b0;
      id_ex_alu_op    <= ALU_ADD;
      id_ex_wb_sel    <= WB_ALU;
      id_ex_mem_read  <= 1'b0;
      id_ex_mem_write <= 1'b0;
      id_ex_branch    <= 1'b0;
      id_ex_jump      <= 1'b0;
      id_ex_jalr      <= 1'b0;
    end else begin
      id_ex_pc        <= if_id_pc;
      id_ex_pc_plus4  <= if_id_pc_plus4;
      id_ex_rs1_data  <= id_rs1_data;
      id_ex_rs2_data  <= id_rs2_data;
      id_ex_imm       <= id_imm;
      id_ex_rs1       <= id_rs1_addr;
      id_ex_rs2       <= id_rs2_addr;
      id_ex_rd        <= id_rd_addr;
      id_ex_funct3    <= id_funct3;
      id_ex_reg_write <= id_reg_write;
      id_ex_alu_a_src <= id_alu_a_src;
      id_ex_alu_b_src <= id_alu_b_src;
      id_ex_alu_op    <= id_alu_op;
      id_ex_wb_sel    <= id_wb_sel;
      id_ex_mem_read  <= id_mem_read;
      id_ex_mem_write <= id_mem_write;
      id_ex_branch    <= id_branch;
      id_ex_jump      <= id_jump;
      id_ex_jalr      <= id_jalr;
    end
  end

  // ------------------------------------------------------------------ EX
  // Operand forwarding. The forwarded rs2 feeds both the alu_b mux and the
  // store data path, which is why a store whose data register was just
  // computed still gets the new value even though its alu_b is the immediate.
  always_comb begin
    case (fwd_a)
      FWD_EX_MEM: ex_rs1_fwd = ex_mem_alu_result;
      FWD_MEM_WB: ex_rs1_fwd = wb_data;
      default:    ex_rs1_fwd = id_ex_rs1_data;
    endcase

    case (fwd_b)
      FWD_EX_MEM: ex_rs2_fwd = ex_mem_alu_result;
      FWD_MEM_WB: ex_rs2_fwd = wb_data;
      default:    ex_rs2_fwd = id_ex_rs2_data;
    endcase
  end

  assign alu_a = id_ex_alu_a_src ? id_ex_pc  : ex_rs1_fwd;
  assign alu_b = id_ex_alu_b_src ? id_ex_imm : ex_rs2_fwd;

  // Control flow resolves here, one stage after decode, so the two younger
  // instructions already in flight are wrong-path and get flushed. jalr takes
  // the ALU result, which is the forwarded rs1 plus the immediate with bit 0
  // cleared; branches and jal take the dedicated pc + imm adder. branch_cmp
  // sees the forwarded operands, so a branch on a just computed register
  // decides on the new value.
  assign ex_target   = id_ex_jalr ? {alu_result[DATA_WIDTH-1:1], 1'b0}
                                  : (id_ex_pc + id_ex_imm);
  assign ex_redirect = id_ex_jalr || id_ex_jump ||
                       (id_ex_branch && ex_branch_taken);

  // -------------------------------------------------------------- hazards
  // Structural data bus hazard. The load in EX will be in WB two cycles from
  // now and needs the bus for its own address then, so no load or store may
  // be in MEM at that point. Holding the memory instruction in ID for one
  // cycle, exactly the way the load-use stall does, puts a bubble in front of
  // it and clears the slot. This is the pipeline's only structural stall, it
  // only fires when two memory instructions are back to back, and a load
  // never redirects so it can never fight flush_if_id.
  assign bus_hazard = id_ex_mem_read && (id_mem_read || id_mem_write);

  // The hazard unit drives the pc and IF/ID with one signal each; both hold
  // together, because holding one without the other would drop or duplicate
  // an instruction.
  assign front_stall  = stall_pc || stall_if_id || bus_hazard;
  assign id_ex_bubble = bubble_id_ex || bus_hazard;

  // ------------------------------------------------------------ instances
  control u_control (
    .opcode    (id_opcode),
    .funct3    (id_funct3),
    .funct7_b5 (id_funct7_b5),
    .reg_write (id_reg_write),
    .alu_a_src (id_alu_a_src),
    .alu_b_src (id_alu_b_src),
    .alu_op    (id_alu_op),
    .wb_sel    (id_wb_sel),
    .mem_read  (id_mem_read),
    .mem_write (id_mem_write),
    .branch    (id_branch),
    .jump      (id_jump),
    .jalr      (id_jalr),
    .uses_rs1  (id_uses_rs1),
    .uses_rs2  (id_uses_rs2)
  );

  reg_file #(
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (1 << REG_ADDR_WIDTH)
  ) u_reg_file (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (id_rs1_addr),
    .rs1_data (rf_rs1_data),
    .rs2_addr (id_rs2_addr),
    .rs2_data (rf_rs2_data),
    .rd_addr  (mem_wb_rd),
    .rd_data  (wb_data),
    .rd_we    (mem_wb_reg_write)
  );

  imm_gen #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_imm_gen (
    .instr (id_instr),
    .imm   (id_imm)
  );

  hazard_unit #(
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH)
  ) u_hazard_unit (
    .id_ex_mem_read (id_ex_mem_read),
    .id_ex_rd       (id_ex_rd),
    .if_id_rs1      (id_rs1_addr),
    .if_id_rs2      (id_rs2_addr),
    .if_id_uses_rs1 (id_uses_rs1),
    .if_id_uses_rs2 (id_uses_rs2),
    .ex_redirect    (ex_redirect),
    .stall_pc       (stall_pc),
    .stall_if_id    (stall_if_id),
    .flush_if_id    (flush_if_id),
    .bubble_id_ex   (bubble_id_ex)
  );

  forward_unit #(
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .FWD_WIDTH      (FWD_WIDTH)
  ) u_forward_unit (
    .id_ex_rs1        (id_ex_rs1),
    .id_ex_rs2        (id_ex_rs2),
    .ex_mem_rd        (ex_mem_rd),
    .ex_mem_reg_write (ex_mem_reg_write),
    .mem_wb_rd        (mem_wb_rd),
    .mem_wb_reg_write (mem_wb_reg_write),
    .fwd_a            (fwd_a),
    .fwd_b            (fwd_b)
  );

  branch_cmp #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_branch_cmp (
    .rs1_data (ex_rs1_fwd),
    .rs2_data (ex_rs2_fwd),
    .funct3   (id_ex_funct3),
    .taken    (ex_branch_taken)
  );

  alu #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_alu (
    .a      (alu_a),
    .b      (alu_b),
    .op     (id_ex_alu_op),
    .result (alu_result)
  );

  mem_wb_stage #(
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH)
  ) u_mem_wb_stage (
    .clk               (clk),
    .rst_n             (rst_n),
    .ex_alu_result     (alu_result),
    .ex_store_data     (ex_rs2_fwd),
    .ex_pc_plus4       (id_ex_pc_plus4),
    .ex_rd             (id_ex_rd),
    .ex_funct3         (id_ex_funct3),
    .ex_reg_write      (id_ex_reg_write),
    .ex_wb_sel         (id_ex_wb_sel),
    .ex_mem_read       (id_ex_mem_read),
    .ex_mem_write      (id_ex_mem_write),
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

endmodule
