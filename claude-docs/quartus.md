# Quartus operations cheat sheet

Everything needed to build and program rv32-core by hand. All commands run
from the `quartus/` directory in PowerShell unless noted. Quartus lives at
`C:\intelFPGA_lite\23.1std`; add `C:\intelFPGA_lite\23.1std\quartus\bin64`
to PATH or use the full paths shown here.

## The three everyday commands

Check the board is powered and connected (USB cable in the USB Blaster port):

```
C:\intelFPGA_lite\23.1std\quartus\bin64\jtagconfig.exe
```

Healthy output lists `DE-SoC [USB-1]` with two devices: `SOCVHPS` (the ARM)
and `5CSE(BA5|MA5)...` (the FPGA). "No JTAG hardware available" means the
board is off, the USB cable is in the wrong port, or the USB-Blaster II
driver is missing (install from `quartus\drivers\usb-blaster-ii` via Device
Manager).

Full compile, RTL to bitstream (about 7 to 8 minutes):

```
C:\intelFPGA_lite\23.1std\quartus\bin64\quartus_sh.exe --flow compile rv32_core
```

Program the FPGA (volatile, lost at power off, takes seconds):

```
C:\intelFPGA_lite\23.1std\quartus\bin64\quartus_pgm.exe -m jtag -o "p;output_files/rv32_core.sof@2"
```

The `@2` targets the FPGA, which is device 2 in the JTAG chain behind the
ARM. After any power cycle the chip is blank until you program it again.

## Swapping which program the CPU runs

The program is baked into instruction memory at compile time. To change it:

1. Build the hardware flavor of the program (from the repo root):
   `C:\Users\CJ\opt\xpack-windows-build-tools-4.4.1-3\bin\make.exe -C programs counter`
2. Edit `quartus/rv32_core.qsf`: point the two `set_parameter` lines
   (`IMEM_INIT`, `DMEM_INIT`) at `../programs/build/counter.hex` and
   `../programs/build/counter_data.hex`.
3. Run the full compile, then program.
4. `git checkout -- rv32_core.qsf` afterward so the repo default
   (switch_mirror) stays canonical.

Demo names: led_blink, counter, switch_mirror, fibonacci, memtest, reaction.

## Reading the results

All reports land in `quartus/output_files/` (gitignored):

- `rv32_core.fit.summary`: ALM, register, and block RAM usage
- `rv32_core.sta.rpt`: timing; search "Fmax" (must exceed 50 MHz) and check
  setup/hold slack is positive
- `rv32_core.map.rpt`: synthesis detail; search "Inferred altsyncram" to
  confirm both memories landed in block RAM

## Using the GUI instead

Launch `C:\intelFPGA_lite\23.1std\quartus\bin64\quartus.exe` and open
`quartus\rv32_core.qpf`. Processing > Start Compilation is the compile;
Tools > Programmer, Hardware Setup: DE-SoC, then Start is the programmer
(the .sof at device 2 should load automatically; if the chain is empty use
Auto Detect, pick 5CSEMA5, then attach the .sof to it). Tools > Timing
Analyzer opens the timing reports interactively.

## Board buttons while a program runs

KEY3 (leftmost) is always the CPU reset. KEY0 to KEY2 and all ten switches
are readable by programs that choose to poll them. The red recessed button
by the power jack toggles board power; pulling the barrel jack is equally
safe since nothing on the board holds persistent state.
