// alu_tb: self-checking testbench for the combinational ALU.
// Runs directed cases for all eleven ops plus a randomized cross-check
// against a behavioral reference, and prints one PASS line when clean.

`timescale 1ns / 1ps

module alu_tb;

  import rv32_pkg::*;

  localparam int DATA_WIDTH  = 32;
  localparam int RANDOM_RUNS = 2000;

  logic [DATA_WIDTH-1:0] a;
  logic [DATA_WIDTH-1:0] b;
  alu_op_e               op;
  logic [DATA_WIDTH-1:0] result;

  int unsigned checks;

  alu #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .a      (a),
    .b      (b),
    .op     (op),
    .result (result)
  );

  function automatic string op_name(input alu_op_e o);
    case (o)
      ALU_ADD:    op_name = "ALU_ADD";
      ALU_SUB:    op_name = "ALU_SUB";
      ALU_AND:    op_name = "ALU_AND";
      ALU_OR:     op_name = "ALU_OR";
      ALU_XOR:    op_name = "ALU_XOR";
      ALU_SLL:    op_name = "ALU_SLL";
      ALU_SRL:    op_name = "ALU_SRL";
      ALU_SRA:    op_name = "ALU_SRA";
      ALU_SLT:    op_name = "ALU_SLT";
      ALU_SLTU:   op_name = "ALU_SLTU";
      ALU_PASS_B: op_name = "ALU_PASS_B";
      default:    op_name = "UNKNOWN";
    endcase
  endfunction

  // behavioral reference, written independently of the RTL case statement
  function automatic logic [DATA_WIDTH-1:0] ref_result(
    input logic [DATA_WIDTH-1:0] ra,
    input logic [DATA_WIDTH-1:0] rb,
    input alu_op_e               ro
  );
    logic [4:0] sh;
    sh = rb[4:0];
    case (ro)
      ALU_ADD:    ref_result = ra + rb;
      ALU_SUB:    ref_result = ra - rb;
      ALU_AND:    ref_result = ra & rb;
      ALU_OR:     ref_result = ra | rb;
      ALU_XOR:    ref_result = ra ^ rb;
      ALU_SLL:    ref_result = ra << sh;
      ALU_SRL:    ref_result = ra >> sh;
      ALU_SRA:    ref_result = $signed(ra) >>> sh;
      ALU_SLT:    ref_result = ($signed(ra) < $signed(rb)) ? 32'd1 : 32'd0;
      ALU_SLTU:   ref_result = (ra < rb) ? 32'd1 : 32'd0;
      ALU_PASS_B: ref_result = rb;
      default:    ref_result = '0;
    endcase
  endfunction

  task automatic check(
    input logic [DATA_WIDTH-1:0] ta,
    input logic [DATA_WIDTH-1:0] tb_val,
    input alu_op_e               top,
    input logic [DATA_WIDTH-1:0] expected
  );
    a  = ta;
    b  = tb_val;
    op = top;
    #1;
    checks = checks + 1;
    if (result !== expected) begin
      $display("FAIL: a=0x%08h b=0x%08h op=%s got=0x%08h expected=0x%08h",
               ta, tb_val, op_name(top), result, expected);
      $fatal(1);
    end
  endtask

  initial begin
    $dumpfile("sim/build/alu_tb.vcd");
    $dumpvars(0, alu_tb);

    checks = 0;

    // ADD, including unsigned wraparound past the top of the range
    check(32'd0,          32'd0,          ALU_ADD, 32'd0);
    check(32'd7,          32'd35,         ALU_ADD, 32'd42);
    check(32'hFFFF_FFFF,  32'd1,          ALU_ADD, 32'd0);
    check(32'hFFFF_FFFF,  32'hFFFF_FFFF,  ALU_ADD, 32'hFFFF_FFFE);
    check(32'h7FFF_FFFF,  32'd1,          ALU_ADD, 32'h8000_0000);
    check(32'h8000_0000,  32'hFFFF_FFFF,  ALU_ADD, 32'h7FFF_FFFF);

    // SUB, including borrow through zero into a negative result
    check(32'd42,         32'd42,         ALU_SUB, 32'd0);
    check(32'd5,          32'd12,         ALU_SUB, 32'hFFFF_FFF9);
    check(32'd0,          32'd1,          ALU_SUB, 32'hFFFF_FFFF);
    check(32'h8000_0000,  32'd1,          ALU_SUB, 32'h7FFF_FFFF);

    // AND, OR, XOR with mixed bit patterns
    check(32'hF0F0_F0F0,  32'h0FF0_0FF0,  ALU_AND, 32'h00F0_00F0);
    check(32'hAAAA_AAAA,  32'h5555_5555,  ALU_AND, 32'h0000_0000);
    check(32'hDEAD_BEEF,  32'hFFFF_FFFF,  ALU_AND, 32'hDEAD_BEEF);
    check(32'hF0F0_F0F0,  32'h0FF0_0FF0,  ALU_OR,  32'hFFF0_FFF0);
    check(32'hAAAA_AAAA,  32'h5555_5555,  ALU_OR,  32'hFFFF_FFFF);
    check(32'hDEAD_BEEF,  32'h0000_0000,  ALU_OR,  32'hDEAD_BEEF);
    check(32'hF0F0_F0F0,  32'h0FF0_0FF0,  ALU_XOR, 32'hFF00_FF00);
    check(32'hDEAD_BEEF,  32'hDEAD_BEEF,  ALU_XOR, 32'h0000_0000);
    check(32'hDEAD_BEEF,  32'hFFFF_FFFF,  ALU_XOR, 32'h2152_4110);

    // SLL by 0, 1, 31, and with the shift amount truncated to b[4:0]
    check(32'h0000_0001,  32'd0,          ALU_SLL, 32'h0000_0001);
    check(32'h0000_0001,  32'd1,          ALU_SLL, 32'h0000_0002);
    check(32'h0000_0001,  32'd31,         ALU_SLL, 32'h8000_0000);
    check(32'hDEAD_BEEF,  32'd4,          ALU_SLL, 32'hEADB_EEF0);
    check(32'h0000_0001,  32'd32,         ALU_SLL, 32'h0000_0001);
    check(32'h0000_0001,  32'hFFFF_FFE1,  ALU_SLL, 32'h0000_0002);

    // SRL by 0, 1, 31 on a negative value, plus shift amount truncation
    check(32'h8000_0000,  32'd0,          ALU_SRL, 32'h8000_0000);
    check(32'h8000_0000,  32'd1,          ALU_SRL, 32'h4000_0000);
    check(32'h8000_0000,  32'd31,         ALU_SRL, 32'h0000_0001);
    check(32'hFFFF_FFFF,  32'd28,         ALU_SRL, 32'h0000_000F);
    check(32'h8000_0000,  32'd32,         ALU_SRL, 32'h8000_0000);

    // SRA on the same values as SRL above, results must differ where the sign bit is set
    check(32'h8000_0000,  32'd0,          ALU_SRA, 32'h8000_0000);
    check(32'h8000_0000,  32'd1,          ALU_SRA, 32'hC000_0000);
    check(32'h8000_0000,  32'd31,         ALU_SRA, 32'hFFFF_FFFF);
    check(32'hFFFF_FFFF,  32'd28,         ALU_SRA, 32'hFFFF_FFFF);
    check(32'h7FFF_FFFF,  32'd31,         ALU_SRA, 32'h0000_0000);
    check(32'hFFFF_FFF0,  32'd4,          ALU_SRA, 32'hFFFF_FFFF);
    check(32'h8000_0000,  32'd32,         ALU_SRA, 32'h8000_0000);

    // SLT signed versus SLTU unsigned, disagreeing around 0x80000000
    check(32'h8000_0000,  32'd1,          ALU_SLT,  32'd1);
    check(32'h8000_0000,  32'd1,          ALU_SLTU, 32'd0);
    check(32'hFFFF_FFFF,  32'd0,          ALU_SLT,  32'd1);
    check(32'hFFFF_FFFF,  32'd0,          ALU_SLTU, 32'd0);
    check(32'd1,          32'h8000_0000,  ALU_SLT,  32'd0);
    check(32'd1,          32'h8000_0000,  ALU_SLTU, 32'd1);
    check(32'd5,          32'd5,          ALU_SLT,  32'd0);
    check(32'd5,          32'd5,          ALU_SLTU, 32'd0);
    check(32'd5,          32'd6,          ALU_SLT,  32'd1);
    check(32'd5,          32'd6,          ALU_SLTU, 32'd1);
    check(32'h8000_0000,  32'h8000_0001,  ALU_SLT,  32'd1);
    check(32'h8000_0000,  32'h8000_0001,  ALU_SLTU, 32'd1);
    check(32'h7FFF_FFFF,  32'h8000_0000,  ALU_SLT,  32'd0);
    check(32'h7FFF_FFFF,  32'h8000_0000,  ALU_SLTU, 32'd1);

    // PASS_B ignores a entirely, used by lui
    check(32'hDEAD_BEEF,  32'h1234_5000,  ALU_PASS_B, 32'h1234_5000);
    check(32'h0000_0000,  32'h1234_5000,  ALU_PASS_B, 32'h1234_5000);
    check(32'hFFFF_FFFF,  32'h0000_0000,  ALU_PASS_B, 32'h0000_0000);

    // randomized cross-check against the reference, biased toward edge patterns
    begin
      logic [DATA_WIDTH-1:0] ra;
      logic [DATA_WIDTH-1:0] rb;
      alu_op_e               ro;
      for (int i = 0; i < RANDOM_RUNS; i++) begin
        ra = $random;
        rb = $random;
        case (i % 4)
          1: rb = {27'd0, rb[4:0]};              // small shift amounts
          2: ra = {1'b1, ra[DATA_WIDTH-2:0]};    // force the sign bit set
          3: rb = ra;                            // equal operands
          default: ;
        endcase
        ro = alu_op_e'(i % 11);
        check(ra, rb, ro, ref_result(ra, rb, ro));
      end
    end

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: alu");
    $finish;
  end

endmodule
