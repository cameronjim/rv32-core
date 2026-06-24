# Single-cycle datapath architecture

Design decisions for the single-cycle RV32I core. This is the contract the RTL
implements. Updated as the design evolves; last touched 2026-08-04 (phase 2,
memory system and core integration).

## Datapath overview

One instruction per clock. The PC feeds instruction memory, the instruction is
decoded combinationally, the register file is read, the ALU computes, data
memory is accessed, and the result is written back to the register file on the
next rising edge. No pipeline registers.

```
        +-----+   +------+   +----------+   +-----+   +------+   +--------+
 pc --> |imem | ->|decode| ->| reg_file | ->| alu | ->| dmem | ->|writeback|--+
        +-----+   +------+   +----------+   +-----+   +------+   +--------+  |
   ^                                            |                            |
   +--- next-pc logic (branch_cmp, adders) <----+                            |
                              reg_file write port <--------------------------+
```

Next-PC selection:

- default: pc + 4
- branch taken or jal: pc + imm (dedicated adder in cpu_top, not the ALU)
- jalr: (rs1 + imm) & ~1, taken from the ALU result with bit 0 cleared

The ALU computes the jalr target (rs1 + imm) so no third adder is needed.
Branches are resolved by a dedicated comparator (branch_cmp), not the ALU, so
the ALU stays free of condition-flag logic.

## Modules (phase 1)

All synthesizable modules import `rv32_pkg`. Widths are parameterized with
`DATA_WIDTH` (32) where it aids readability.

### rv32_pkg (package, rtl/rv32_pkg.sv)

Shared types and constants:

- `alu_op_e`: enum `logic [3:0]` with ALU_ADD, ALU_SUB, ALU_AND, ALU_OR,
  ALU_XOR, ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU, ALU_PASS_B
- opcodes (7 bit): OP_LUI, OP_AUIPC, OP_JAL, OP_JALR, OP_BRANCH, OP_LOAD,
  OP_STORE, OP_IMM, OP_REG
- funct3 constants for branches (F3_BEQ, F3_BNE, F3_BLT, F3_BGE, F3_BLTU,
  F3_BGEU), loads/stores (F3_LB, F3_LH, F3_LW, F3_LBU, F3_LHU), and ALU
  selection (F3_ADD_SUB, F3_SLL, F3_SLT, F3_SLTU, F3_XOR, F3_SRL_SRA, F3_OR,
  F3_AND)
- `wb_sel_e`: enum `logic [1:0]` with WB_ALU, WB_MEM, WB_PC4

### alu (rtl/alu.sv)

Pure combinational. Inputs `a`, `b` (32 bit), `op` (alu_op_e). Output `result`.
Shifts use `b[4:0]` as the amount. ALU_SLT and ALU_SLTU produce 32'd0 or 32'd1.
ALU_PASS_B outputs `b` unchanged (used by lui). No flags, no zero output.

### reg_file (rtl/reg_file.sv)

32 registers of 32 bits. Two combinational read ports (`rs1_addr` ->
`rs1_data`, `rs2_addr` -> `rs2_data`), one synchronous write port (`rd_addr`,
`rd_data`, `rd_we`) on posedge clk. x0 is hardwired: reads of address 0 return
0, writes to address 0 are ignored. Synchronous active-low reset clears all
registers to zero.

### imm_gen (rtl/imm_gen.sv)

Pure combinational. Input `instr` (32 bit), output `imm` (32 bit, sign
extended). Format selected by opcode:

- I: OP_LOAD, OP_IMM, OP_JALR
- S: OP_STORE
- B: OP_BRANCH
- U: OP_LUI, OP_AUIPC (imm = upper 20 bits, low 12 zero)
- J: OP_JAL

Unknown opcode produces 0.

### branch_cmp (rtl/branch_cmp.sv)

Pure combinational. Inputs `rs1_data`, `rs2_data`, `funct3`. Output `taken`.
Implements beq, bne, blt (signed), bge (signed), bltu, bgeu. Undefined funct3
values produce taken = 0.

### control (rtl/control.sv)

Pure combinational decoder. Inputs `opcode` (instr[6:0]), `funct3`
(instr[14:12]), `funct7_b5` (instr[30]). Outputs and their meaning:

| signal      | width    | meaning                                    |
| ----------- | -------- | ------------------------------------------ |
| reg_write   | 1        | write rd this cycle                        |
| alu_a_src   | 1        | 0 = rs1_data, 1 = pc                       |
| alu_b_src   | 1        | 0 = rs2_data, 1 = imm                      |
| alu_op      | alu_op_e | ALU operation                              |
| wb_sel      | wb_sel_e | writeback source: ALU, MEM, or PC+4        |
| mem_read    | 1        | data memory read (loads)                   |
| mem_write   | 1        | data memory write (stores)                 |
| branch      | 1        | conditional branch, next pc uses branch_cmp|
| jump        | 1        | jal, next pc = pc + imm                    |
| jalr        | 1        | jalr, next pc = alu result with bit 0 clear|

Decode table:

| instr class | alu_a | alu_b | alu_op         | reg_write | wb_sel | mem_read | mem_write | branch | jump | jalr |
| ----------- | ----- | ----- | -------------- | --------- | ------ | -------- | --------- | ------ | ---- | ---- |
| R-type      | rs1   | rs2   | funct3/funct7  | 1         | ALU    | 0        | 0         | 0      | 0    | 0    |
| I-arith     | rs1   | imm   | funct3 (+b30 for srai) | 1 | ALU    | 0        | 0         | 0      | 0    | 0    |
| load        | rs1   | imm   | ADD            | 1         | MEM    | 1        | 0         | 0      | 0    | 0    |
| store       | rs1   | imm   | ADD            | 0         | x      | 0        | 1         | 0      | 0    | 0    |
| branch      | x     | x     | x              | 0         | x      | 0        | 0         | 1      | 0    | 0    |
| jal         | x     | x     | x              | 1         | PC4    | 0        | 0         | 0      | 1    | 0    |
| jalr        | rs1   | imm   | ADD            | 1         | PC4    | 0        | 0         | 0      | 0    | 1    |
| lui         | x     | imm   | PASS_B         | 1         | ALU    | 0        | 0         | 0      | 0    | 0    |
| auipc       | pc    | imm   | ADD            | 1         | ALU    | 0        | 0         | 0      | 0    | 0    |

ALU op from funct3 for R-type and I-arith: 000 ADD (SUB when R-type and
instr[30]), 001 SLL, 010 SLT, 011 SLTU, 100 XOR, 101 SRL (SRA when instr[30]),
110 OR, 111 AND. For I-arith, instr[30] only matters for shifts (srai); addi
ignores it because it is part of the immediate.

Unknown opcodes decode to all zeros (a nop that writes nothing).

## Memory map

| region | base        | size            | notes                          |
| ------ | ----------- | --------------- | ------------------------------ |
| imem   | 0x0000_0000 | 4 KB, 1024 words| reset vector is 0x0000_0000    |
| dmem   | 0x0000_1000 | 4 KB, 1024 words| read/write data                |
| mmio   | 0xFFFF_0000 | 64 KB window    | peripheral registers, map below|

Address decode lives outside cpu_top: the core emits full 32-bit byte
addresses, and the instantiating level (testbench now, board top later) maps
them onto memories and peripherals. The dmem word index is addr[11:2] within
its region. Misaligned accesses are not supported and have undefined behavior;
there is no trap machinery.

## Modules (phase 2)

### imem (rtl/imem.sv)

Instruction memory, word addressed, read only. Parameters ADDR_WIDTH (word
index width, default 10) and INIT_FILE (hex file loaded with $readmemh when
nonempty). Ports: `clk`, `addr` (word index), `rdata` (32 bit).

The read port is registered on the NEGATIVE clock edge. The core presents the
address combinationally after each rising edge, the memory captures it at the
falling edge, and rdata is stable before the next rising edge, so the core
still fetches and executes in one full cycle. This registered read is what
lets Quartus infer M10K block RAM; a fully asynchronous read synthesized to
tens of thousands of registers and a giant read mux (learned the hard way at
first synthesis: 33904 registers, 0 block memory bits). The cost is that the
memory path gets half a clock period instead of a full one, which is fine at
50 MHz.

Initialization uses an `initial $readmemh` block. This is the one sanctioned
use of `initial` in synthesizable code: Quartus honors it as block RAM initial
content, which is exactly how programs get preloaded at synthesis time.

### dmem (rtl/dmem.sv)

Data memory, word addressed with per-byte write lanes, synchronous read:
the read address is captured on the rising edge and rdata holds the addressed
word for the following cycle (standard M10K simple dual port shape). Writes
commit on the rising edge; a read capturing the same address on the same edge
returns the old word, which is fine because the core never needs same-edge
read-after-write (the load stall below separates them by a full cycle).

Hardware bring-up history, kept because each step taught something: a fully
asynchronous read synthesized to 33904 registers plus a 17000 LE read mux and
the fitter could not route it. Registering the read on the falling edge like
imem broke loads, because the load address is the ALU result and only settles
after imem hands the instruction over mid-cycle. Steering the array into
MLABs with a ramstyle attribute was silently ignored: Cyclone V MLABs also
require a registered read address, so this family simply has no
asynchronous-read memory. The synchronous read plus a one cycle load stall in
cpu_top is the correct and final shape.
Parameters ADDR_WIDTH (default 10), DATA_WIDTH (32), INIT_FILE (optional
$readmemh preload, later useful for .data sections). Ports: `clk`, `addr`
(word index), `wdata`, `byte_en` (4 bit), `we`, `rdata`. Writes happen on
posedge clk for each lane where `we && byte_en[i]`. Reads return the full
word; lane extraction is the lsu's job.

The memory array has no reset. Block RAM contents cannot be cleared by a reset
signal, so this sequential block is exempt from the rst_n rule. Contents are
undefined at power-up unless INIT_FILE is given.

### lsu (rtl/lsu.sv)

Load-store unit, pure combinational, sits between the core datapath and raw
word memory. Handles lane steering and extension for byte and halfword access.

Store path: inputs `funct3`, `addr_lo` (addr[1:0]), `store_data` (rs2 value).
Outputs `mem_wdata` (store data shifted into the correct lanes) and `mem_be`
(4-bit byte enable). sb enables one lane, sh enables two (addr_lo[1] picks the
half), sw enables all four. Undefined funct3 produces mem_be = 0 so nothing is
written.

Load path: inputs `funct3`, `addr_lo`, `mem_rdata` (raw word). Output
`load_data`: lb/lbu select the addressed byte and sign/zero extend, lh/lhu the
addressed halfword, lw passes through. Undefined funct3 produces 0.

### cpu_top (rtl/cpu_top.sv)

The single-cycle core: all phase 1 modules plus the lsu, PC register, and
muxes. Memories stay outside so the same core drops into the testbench now and
the board top with MMIO decode later. Parameter RESET_VECTOR (default
32'h0000_0000).

Ports: `clk`, `rst_n`; instruction bus `imem_addr` (byte address, the PC) and
`imem_rdata`; data bus `dmem_addr` (byte address), `dmem_wdata`, `dmem_be`,
`dmem_we`, `dmem_re`, `dmem_rdata`.

Internals:

- PC register, synchronous active-low reset to RESET_VECTOR
- pc_plus4 adder and a branch-target adder (pc + imm) shared by branches and jal
- instruction field slicing: rs1 = instr[19:15], rs2 = instr[24:20],
  rd = instr[11:7], funct3 = instr[14:12], funct7_b5 = instr[30]
- ALU input muxes per control: a = rs1_data or pc, b = rs2_data or imm
- next-pc priority mux: jalr takes alu_result with bit 0 cleared, else jump or
  taken branch takes pc + imm, else pc_plus4
- writeback mux per wb_sel: alu_result, lsu load_data, or pc_plus4
- dmem_addr = alu_result, dmem_we = mem_write, dmem_re = mem_read, byte
  enables and wdata from the lsu store path
- load stall: dmem reads are synchronous (data arrives the cycle after the
  address), so a load occupies two cycles. A load_wait flag makes the first
  load cycle hold the PC and suppress reg_write; the second cycle writes back
  the captured read data and releases the PC. The fetched instruction does
  not change while the PC holds, so decode and the ALU address stay stable.
  Every other instruction, including stores and mmio reads, is one cycle
  (mmio rdata is combinational but simply gets sampled a cycle late through
  the same uniform two cycle load path)

### cpu_top_tb (tb/cpu_top_tb.sv)

Instantiates cpu_top, imem, and dmem, decoding dmem at 0x1000 (addr[31:12] ==
20'h00001). Runs a list of assembled test programs. Per test: load the hex
into imem with $readmemh, pulse reset, run until the program signals done or a
cycle budget expires, then check architectural state through hierarchical
references into the register file and dmem array.

Done convention: a finished test program stores the magic word 32'h0000600D to
the last dmem word (byte address 0x1FFC). Timeout is a test failure.

Test programs live in tb/programs/ as assembly source plus committed .hex
files (regenerated with the cross toolchain via a make target, committed so
`make test` does not require the toolchain):

- arith: R-type and I-type results landing in known registers
- mem: sw/lw, sb/lb/lbu, sh/lh/lhu across byte lanes, sign extension cases
- branch: each branch taken and not taken, jal/jalr call and return, lui/auipc

## MMIO register map

The mmio region is selected when addr[31:16] == 16'hFFFF. Word access only.
Loads from unmapped mmio addresses return 0; stores to them are ignored. The
map is fixed here in phase 3 so programs and the simulation model agree; the
synthesizable mmio block in phase 4 implements the same map.

| address     | name  | access | meaning                                        |
| ----------- | ----- | ------ | ---------------------------------------------- |
| 0xFFFF_0000 | LEDR  | R/W    | bits 9:0 drive the red LEDs, readable for RMW  |
| 0xFFFF_0004 | SW    | R      | bits 9:0, current slide switch positions       |
| 0xFFFF_0008 | KEY   | R      | bits 3:0, pushbuttons, 1 means pressed (the hardware normalizes the board's active-low pins) |
| 0xFFFF_0010 | HEX0  | R/W    | bits 6:0, segments a..g active high (hardware inverts for the board's active-low displays) |
| 0xFFFF_0014 | HEX1  | R/W    | same layout                                    |
| 0xFFFF_0018 | HEX2  | R/W    | same layout                                    |
| 0xFFFF_001C | HEX3  | R/W    | same layout                                    |
| 0xFFFF_0020 | HEX4  | R/W    | same layout                                    |
| 0xFFFF_0024 | HEX5  | R/W    | same layout                                    |
| 0xFFFF_0030 | CYCLE | R      | free-running 32 bit cycle counter, 0 at reset  |

Software conventions (linker layout, crt0, build flow, sim vs hardware
builds) live in claude-docs/software.md.

## Modules (phase 4)

### mmio (rtl/mmio.sv)

Synthesizable, board-agnostic implementation of the MMIO register map. The
behavioral tb/lib/mmio_sim.sv is its reference model; both implement the same
map and the mmio testbench cross-checks them against each other.

Ports: clk, rst_n; bus side addr (32), wdata (32), we, re, rdata (32,
combinational read like dmem so loads stay single cycle); peripheral side
sw_in (10), key_in (4, already synchronized and normalized so 1 means
pressed), ledr_out (10), hex0_out..hex5_out (7 each, active high).

LEDR and HEX0..HEX5 are read/write registers, reset to 0. SW and KEY reads
reflect the inputs. CYCLE is a free-running counter, 0 at reset. Unmapped
reads return 0, unmapped writes are ignored. External decode gates we/re, so
the block does not check addr[31:16] itself; it decodes addr[15:0] only.

### de1_soc_top (rtl/de1_soc_top.sv)

The board top. Ports use the DE1-SoC pin names exactly as the qsf assigns
them (CLOCK_50, KEY, SW, LEDR, HEX0..HEX5); this is the one sanctioned
exception to snake_case port naming, so the pin assignment file lines up with
the board documentation.

- Every KEY and SW input passes through a two flip-flop synchronizer.
- Reset: KEY[3] is the system reset button. The board keys are active low, so
  the synchronized KEY[3] drives rst_n directly (pressed pulls it low).
- mmio key_in = {1'b0, inverted synchronized KEY[2:0]}: bits 2:0 read 1 when
  pressed, bit 3 always reads 0 because that button is the reset. The
  software doc carries the same note. reaction.c polls bit 0, which is KEY0.
- HEX displays on the board are active low, so each hexN port drives the
  inverse of the mmio register (segments lit where the register bit is 1).
- Instantiates cpu_top, imem, dmem, mmio with the same address decode as
  tb/demo_tb.sv: dmem when addr[31:12] == 20'h00001, mmio when addr[31:16] ==
  16'hFFFF.
- Parameters IMEM_INIT and DMEM_INIT choose the synthesized program, default
  programs/hex/switch_mirror.hex and its data hex (switch_mirror has no
  delay constants, so the committed sim flavor behaves identically on the
  board).
- Clocking: the CPU domain runs at 25 MHz, CLOCK_50 divided by two through a
  toggle register (cpu_clk). First timing analysis put the single-cycle
  core's Fmax at 29 MHz: the imem read, decode, register read, ALU and
  next-pc selection all share one cycle, and that chain is about 34 ns of
  logic. That is the single-cycle architecture's honest cost, not a bug; the
  phase 5 pipeline is what buys the clock rate back. The sdc declares
  cpu_clk with create_generated_clock -divide_by 2 so timing signs off at
  the real operating frequency. Software cycle constants (config.h) use
  25 MHz.

### de1_soc_tb (tb/de1_soc_tb.sv)

Board-level simulation: loads switch_mirror, releases reset through KEY[3],
drives SW patterns, and checks LEDR pins follow and HEX pins carry the
active-low inverse of the expected digit patterns. Also checks reset
re-assertion mid-run restarts the program cleanly.

## Quartus project (quartus/)

Hand-written project files, no wizard output: rv32_core.qpf, rv32_core.qsf
(device 5CSEMA5F31C6, top level de1_soc_top, the rtl file list, and pin plus
IO standard assignments for CLOCK_50, KEY, SW, LEDR, HEX0..HEX5 taken from
the DE1-SoC documentation), and rv32_core.sdc (50 MHz create_clock on
CLOCK_50, false paths on the synchronized inputs and the LED and HEX
outputs). Synthesis itself waits on the Quartus Prime Lite 23.1std install.

## Pipeline (phase 5)

The single-cycle core refactors into a classic five stage pipeline: IF, ID,
EX, MEM, WB. The cpu_top port list does not change, so cpu_top_tb, demo_tb
and de1_soc_tb keep working as regression suites. Architectural results must
be identical; only cycle counts change (timing-tolerant testbench checks may
be retuned with justification, architectural checks may not).

What the pipeline buys back, learned during hardware bring-up: the 25 MHz
clock divider goes away (each stage is a fraction of the old 34 ns critical
path, so the core targets CLOCK_50 directly), and the load stall goes away
(loads become CPI 1; only a dependent instruction immediately after a load
stalls). The board top drops the divider, the sdc drops the generated clock,
and config.h returns to 50 MHz constants.

Stage assignment and how the synchronous memories fold in:

- IF: the PC register feeds imem, which moves from negedge to posedge
  synchronous read. The block RAM's mandatory output register IS the IF/ID
  instruction register: the pc register launches the address, the M10K
  captures it on the same rising edge, and the instruction appears in ID the
  next cycle. No separate instr flop, no negedge trick. A 1-bit flush flag
  registered alongside makes ID treat the incoming instruction as a NOP when
  the previous cycle redirected (BRAM output cannot be cleared directly).
  On a stall the fetch address switches to the IF/ID pc rather than the PC:
  the PC already points one past the stalled instruction, so a frozen PC
  would re-fetch the wrong word and silently drop the stalled instruction
  (found the hard way; the mem program's lb caught it). The BRAM re-reads
  the stalled instruction's address until the stall clears.
- ID: decode (control), register file read, WB-to-ID bypass, imm_gen.
- EX: forwarding muxes, ALU, branch_cmp, branch/jal target adder, all
  control flow resolution (branch, jal, jalr redirect from here; static
  predict not taken, taken costs a two cycle flush).
- MEM: the dmem access cycle. The EX/MEM register launches the address and
  the existing synchronous dmem (unchanged from phase 4) captures it on that
  edge; load data lands exactly at the MEM/WB boundary. The lsu store path
  sits in EX/MEM, the load extension path in WB off the arriving word.
  Structural rule: a load owns the external data bus for two cycles, MEM and
  WB, because the read data only exists during WB and the external decode
  (which cannot be replicated inside the core) resolves it off the live bus
  address. The hazard logic inserts one bubble when a memory instruction
  immediately follows a load, exactly like a load-use stall. Isolated loads
  stay CPI 1; only adjacent memory operations pay. This also means mmio
  reads need no capture register: the bus holds still while the value is
  consumed.
- WB: writeback mux to the register file.

Pipeline registers and their flush/stall behavior:

- IF/ID: pc and pc_plus4 in flops, instr in the imem output register, plus
  the flush-to-NOP flag. Stalls (holds) on load-use; flushes on EX redirect.
- ID/EX: pc, pc_plus4, rs1/rs2 data, rs1/rs2/rd addresses, imm, control
  bundle, uses_rs1/uses_rs2 flags from the decoder. Bubbles (controls
  zeroed) on load-use stall or EX redirect.
- EX/MEM: alu_result, forwarded store data, rd, funct3, pc_plus4, control
  (reg_write, wb_sel, mem_read, mem_write).
- MEM/WB: alu_result, pc_plus4, rd, funct3, addr_lo, reg_write, wb_sel. The
  load word itself is not registered here: it arrives on the bus during WB
  (dmem's output register, or mmio's combinational read held stable by the
  bus rule above).
- The cpu_top load_wait stall from phase 4 is deleted; the MEM stage
  supersedes it.

Hazard handling, in two new leaf modules with their own testbenches:

- forward_unit: compares ID/EX rs1/rs2 against EX/MEM.rd and MEM/WB.rd
  (reg_write set, rd nonzero). Two 2-bit selects per operand: register value,
  EX/MEM alu_result, or MEM/WB wb_data, newest wins (EX/MEM beats MEM/WB).
  Store data (rs2) uses the same forwarding. Loads never forward from EX/MEM
  (their data does not exist yet); the load-use stall guarantees a dependent
  instruction only ever needs the MEM/WB path.
- hazard_unit: load-use detection: ID/EX.mem_read and ID/EX.rd matches a
  register the IF/ID instruction actually reads (uses_rs1/uses_rs2 qualify
  the match) stalls PC and IF/ID one cycle and bubbles ID/EX. EX redirect
  flushes IF/ID and ID/EX. Redirect wins over stall.
- WB-to-ID bypass in the datapath (the reg_file has no internal
  write-through): if WB writes the register ID is reading, ID takes wb_data.

The register file, ALU, imm_gen, branch_cmp, control, lsu, dmem and mmio are
unchanged; imem changes read edge only. x0 never forwards (rd == 0 never
matches). jalr uses the forwarded rs1 in EX. The back end (EX/MEM, bus,
MEM/WB, writeback, both lsu instances) lives in its own module,
mem_wb_stage, to respect the 400 line rule; cpu_top keeps the front end.
Interrupts, exceptions and CSRs remain out of scope.

## Deferred to later phases

- UART transmitter peripheral (phase 5b)
- HPS bridge integration (phase 5c)

## Testing strategy

Every module has a self-checking testbench in tb/ that prints one final
"PASS: <module>" line or "FAIL: <detail>" lines and exits nonzero on failure
via $fatal. Testbenches dump VCD waveforms for GTKWave. `make test` builds and
runs every testbench in Icarus Verilog and fails loudly if any test fails.
Directed cases cover each instruction or operation the module handles, plus
edge cases: x0 behavior, sign extension boundaries, shift amounts of 0 and 31,
signed/unsigned comparison around 0x80000000, and negative immediates.
