# Quartus Prime 25.1 Build Results

The DE0-Nano diagnostic project was compiled with Quartus Prime Standard
25.1std.0 Build 1129 for Cyclone IV E `EP4CE22F17C6`.

## Result

- Analysis and Synthesis: passed, 0 errors.
- Fitter: passed, 0 errors.
- Assembler: passed and generated `output_files/member2_de0_nano.sof`.
- Timing Analyzer: passed, 0 errors; setup and hold requirements are fully
  constrained.
- Full compilation: passed with 0 errors and 2 non-blocking warnings.

## Implementation use

- 194 of 22,320 logic elements: less than 1%.
- 79 registers.
- 15 of 154 pins: 10%.
- No RAM blocks or PLLs.

All state registers in the interconnect and diagnostic controller use an
asynchronous active-low clear. Quartus recognized a two-register synchronizer
for the start pushbutton.

## Timing at 50 MHz

- Worst setup slack: +14.396 ns.
- Worst hold slack: +0.186 ns across the analyzed corners.
- Worst minimum pulse-width slack: +9.270 ns.
- Total negative slack: 0 ns.

Positive slack means the implemented hardware meets the required 20 ns clock
period with margin.

## Remaining warnings

The LogicLock warning states that the feature requires a subscription. This
project does not use LogicLock. The second warning refers to Cyclone IV AN 447
for 3.3-V LVTTL interfaces. The DE0-Nano schematic uses these board connections,
and all clock, key, switch, and LED pins have explicit locations and I/O
standards. Neither warning blocks generation of the `.sof` file.

## Board programming

The DE0-Nano was detected as `USB-Blaster [USB-0]` with JTAG ID `0x020F30DD`.
Quartus Programmer loaded `member2_de0_nano.sof` into device index 1 and
reported `Configuration succeeded -- 1 device(s) configured`, with 0 errors
and 0 warnings.

The `.sof` configuration is held in the FPGA's volatile configuration memory.
It must be loaded again after the DE0-Nano loses power.
