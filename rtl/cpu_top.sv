// cpu_top: the single-cycle RV32I core. Wires the decoder, register file,
// immediate generator, branch comparator, ALU and load-store unit around a PC
// register. Every instruction takes one cycle except loads, which take two
// because dmem reads are synchronous (see the load stall below). Memories live
// outside so the same core fits the tb and a board top.

module cpu_top
  import rv32_pkg::*;
#(
  parameter int          DATA_WIDTH   = 32,
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
  input  logic                    clk,
  input  logic                    rst_n,
  // instruction bus, byte addressed; imem_addr is the pc
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

  logic [DATA_WIDTH-1:0] pc;
  logic [DATA_WIDTH-1:0] pc_next;
  logic [DATA_WIDTH-1:0] pc_plus4;
  logic [DATA_WIDTH-1:0] pc_target;
  logic [DATA_WIDTH-1:0] jalr_target;
  logic [DATA_WIDTH-1:0] instr;

  logic [6:0]                opcode;
  logic [2:0]                funct3;
  logic                      funct7_b5;
  logic [REG_ADDR_WIDTH-1:0] rs1_addr;
  logic [REG_ADDR_WIDTH-1:0] rs2_addr;
  logic [REG_ADDR_WIDTH-1:0] rd_addr;

  logic    reg_write;
  logic    alu_a_src;
  logic    alu_b_src;
  alu_op_e alu_op;
  wb_sel_e wb_sel;
  logic    mem_read;
  logic    mem_write;
  logic    branch;
  logic    jump;
  logic    jalr;

  logic [DATA_WIDTH-1:0] rs1_data;
  logic [DATA_WIDTH-1:0] rs2_data;
  logic [DATA_WIDTH-1:0] imm;
  logic [DATA_WIDTH-1:0] alu_a;
  logic [DATA_WIDTH-1:0] alu_b;
  logic [DATA_WIDTH-1:0] alu_result;
  logic [DATA_WIDTH-1:0] load_data;
  logic [DATA_WIDTH-1:0] wb_data;
  logic                  branch_taken;

  // load stall state: 0 during the first cycle of a load, 1 during the second
  logic                  load_wait;
  logic                  load_stall;
  logic                  reg_write_en;

  assign instr = imem_rdata;

  // field slicing, hoisted out of the procedural blocks so Icarus does not
  // flag the parameterized part selects
  assign opcode    = instr[6:0];
  assign funct3    = instr[14:12];
  assign funct7_b5 = instr[30];
  assign rs1_addr  = instr[19:15];
  assign rs2_addr  = instr[24:20];
  assign rd_addr   = instr[11:7];

  assign imem_addr = pc;
  assign pc_plus4  = pc + 32'd4;

  // dedicated branch/jal target adder, kept out of the ALU
  assign pc_target = pc + imm;

  // jalr clears bit 0 of the computed target per the ISA
  assign jalr_target = {alu_result[DATA_WIDTH-1:1], 1'b0};

  // Load stall. dmem registers its read address, so the data for a load only
  // shows up in the cycle after the address is presented. load_stall marks the
  // first cycle of a load: the PC holds so the same instruction is fetched
  // again, and the writeback is suppressed because dmem_rdata is still the
  // previous word. load_wait marks the second cycle, where the captured data
  // is valid, the register file writes, and the PC moves on. Only mem_read
  // instructions stall, so stores, branches and jumps are unaffected.
  assign load_stall   = mem_read && !load_wait;
  assign reg_write_en = reg_write && !load_stall;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      load_wait <= 1'b0;
    end else begin
      load_wait <= load_stall;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc <= RESET_VECTOR;
    end else if (!load_stall) begin
      pc <= pc_next;
    end
  end

  always_comb begin
    if (jalr) begin
      pc_next = jalr_target;
    end else if (jump || (branch && branch_taken)) begin
      pc_next = pc_target;
    end else begin
      pc_next = pc_plus4;
    end
  end

  assign alu_a = alu_a_src ? pc : rs1_data;
  assign alu_b = alu_b_src ? imm : rs2_data;

  always_comb begin
    case (wb_sel)
      WB_MEM:  wb_data = load_data;
      WB_PC4:  wb_data = pc_plus4;
      default: wb_data = alu_result;
    endcase
  end

  assign dmem_addr = alu_result;
  assign dmem_we   = mem_write;
  assign dmem_re   = mem_read;

  control u_control (
    .opcode    (opcode),
    .funct3    (funct3),
    .funct7_b5 (funct7_b5),
    .reg_write (reg_write),
    .alu_a_src (alu_a_src),
    .alu_b_src (alu_b_src),
    .alu_op    (alu_op),
    .wb_sel    (wb_sel),
    .mem_read  (mem_read),
    .mem_write (mem_write),
    .branch    (branch),
    .jump      (jump),
    .jalr      (jalr)
  );

  reg_file #(
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (1 << REG_ADDR_WIDTH)
  ) u_reg_file (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (rs1_addr),
    .rs1_data (rs1_data),
    .rs2_addr (rs2_addr),
    .rs2_data (rs2_data),
    .rd_addr  (rd_addr),
    .rd_data  (wb_data),
    .rd_we    (reg_write_en)
  );

  imm_gen #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_imm_gen (
    .instr (instr),
    .imm   (imm)
  );

  branch_cmp #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_branch_cmp (
    .rs1_data (rs1_data),
    .rs2_data (rs2_data),
    .funct3   (funct3),
    .taken    (branch_taken)
  );

  alu #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_alu (
    .a      (alu_a),
    .b      (alu_b),
    .op     (alu_op),
    .result (alu_result)
  );

  lsu #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_lsu (
    .funct3     (funct3),
    .addr_lo    (alu_result[1:0]),
    .store_data (rs2_data),
    .mem_rdata  (dmem_rdata),
    .mem_wdata  (dmem_wdata),
    .mem_be     (dmem_be),
    .load_data  (load_data)
  );

endmodule
