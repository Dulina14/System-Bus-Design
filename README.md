# Member 2: Serial Bus Interconnect

This folder contains the bus-interconnect portion of the two-master,
three-slave serial bus assignment. It is derived from the architecture of the
Anuki16 `ads-system-bus` project, with asynchronous active-low reset, complete
split routing, safer response gating, and a decoder that does not treat a
slave's initial ready level as transaction completion.

## RTL files

- `rtl/bus_mux2.v`: selects Master 1 or Master 2.
- `rtl/bus_mux3.v`: selects one of three slave responses.
- `rtl/bus_slave_valid_decoder.v`: enables exactly one slave.
- `rtl/bus_arbiter.v`: fixed Master 1 priority and split ownership.
- `rtl/serial_address_decoder.v`: receives the serial device ID and maintains
  the selected slave connection.
- `rtl/serial_bus_m2_s3.v`: complete Member 2 integration module.

## Interface contract

The default 16-bit logical address is transferred as four device-ID bits
followed by twelve local-address bits. All multi-bit fields are sent least
significant bit first.

| Device ID | Slave | Required capacity | Behaviour |
|---|---|---:|---|
| `4'b0000` | Slave 1 | 2 KB | Normal |
| `4'b0001` | Slave 2 | 4 KB | Normal |
| `4'b0010` | Slave 3 | 4 KB | Split capable |

The master must keep `breq` asserted until its transaction is complete. After
receiving `ack`, it must produce at least one clock with `mvalid = 0` before
sending the twelve local-address bits. Data/address bits use `wdata`; read bits
return on `rdata`. Slave 3 is the only source of `s3_split`.

The teammate implementing Slave 3 must connect both split wires:

```verilog
.ssplit(s3_split),
.split_grant(split_grant)
```

All stateful endpoint modules must use `reset_n` as an asynchronous active-low
reset so they match the interconnect.

## Self-checking simulation

The testbench `tb/tb_serial_bus_m2_s3.sv` verifies:

1. asynchronous reset, including reset between clock edges;
2. Master 1 priority when both masters request simultaneously;
3. Slave 1 and Slave 2 address selection;
4. master and slave data/control multiplexing;
5. invalid device-address rejection;
6. Slave 3 split and resumption for both possible split owners;
7. use of the bus by the other master while Slave 3 remains busy;
8. a one-clock `split_grant` pulse;
9. response and acknowledgement isolation from the inactive master.

Example Icarus Verilog commands:

```text
iverilog -g2012 -o member2_sim member2/rtl/*.v member2/tb/tb_serial_bus_m2_s3.sv
vvp member2_sim
```

Example Questa commands from a separate simulation directory:

```text
vlib work
vlog -sv ../rtl/bus_mux2.v ../rtl/bus_mux3.v ../rtl/bus_slave_valid_decoder.v ../rtl/bus_arbiter.v ../rtl/serial_address_decoder.v ../rtl/serial_bus_m2_s3.v ../tb/tb_serial_bus_m2_s3.sv
vsim -c -voptargs=+acc work.tb_serial_bus_m2_s3 -do "run -all; quit -f"
```

The `+acc` option keeps the internal signals visible so Questa can populate the
VCD requested by `$dumpvars`. The testbench creates
`tb_serial_bus_m2_s3.vcd` in the directory from which `vsim` is run. Questa may
print one benign optimization warning because `+acc` intentionally preserves
waveform visibility.

A verified waveform is preserved in `results/tb_serial_bus_m2_s3.vcd`, with its
important transitions explained in `results/WAVEFORM_ANALYSIS.md`.

## Quartus and DE0-Nano flow

The `quartus/member2_de0_nano.qpf` project targets the DE0-Nano's Cyclone IV E
`EP4CE22F17C6` device. The package marking on the physical FPGA is
`EP4CE22F17C6N`; Quartus uses the part name without the final packaging suffix.
The project contains the correct 50 MHz clock, key, switch, and LED pin
assignments and a complete timing-constraint file.

Run the complete command-line flows from PowerShell at the workspace root:

```powershell
& .\member2\scripts\run_simulation.ps1
& .\member2\scripts\build_quartus.ps1
& .\member2\scripts\program_de0_nano.ps1
```

The build script temporarily maps the workspace to a free drive letter because
Quartus 25.1 can misread command-line project paths containing spaces. The map
is removed automatically after compilation. Use, for example,
`-BuildDrive R:` if `Q:` is already occupied.

The equivalent GUI procedure is:

1. Open `quartus/member2_de0_nano.qpf` in Quartus Prime Standard 25.1.
2. Select **Processing > Start Compilation**. A successful build creates
   `quartus/output_files/member2_de0_nano.sof`.
3. Power the DE0-Nano and connect its USB-Blaster USB port.
4. Select **Tools > Programmer**, choose **USB-Blaster** under Hardware Setup,
   and select **JTAG** mode.
5. Add the generated `.sof`, enable **Program/Configure**, and press **Start**.

The standalone board diagnostic uses these controls:

- `KEY0`: asynchronous active-low reset.
- `KEY1`: start one transaction.
- `SW0`: choose Master 1 (`0`) or Master 2 (`1`).
- `SW1`: request both masters, showing Master 1 priority.
- `SW3:2`: choose Slave 1 (`00`), Slave 2 (`01`), split Slave 3 (`10`), or an
  invalid device address (`11`).

After pressing `KEY1`, LEDs latch the result: `LED0/1` show the granted master,
`LED2/3/4` show the selected slave, `LED5` is acknowledgement, `LED6` is split,
and `LED7` is completion. For example, `SW3:0 = 4'b1000` tests Master 1 with
split Slave 3 and should finish with `LED7:0 = 8'b11110001`.

This board top contains small synthesizable master and slave stimulus models so
Member 2 can be checked independently. In the final team design, keep the
interconnect and replace those models with the actual master and slave modules.
The completed compile results are recorded in `QUARTUS_RESULTS.md`.
