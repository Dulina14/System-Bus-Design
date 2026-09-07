# Slave-Side Modules — System Bus Design

This folder contains the **slave-side implementation** of the Serial System Bus project.

My responsibility is the design and verification of:

- `slave.v`
- `slave_port.v`
- `slave_memory.v`
- `slave_memory_bram.v`
- `slave_with_bram.v`
- `slave_port_tb.v`
- `slave_tb.v`

The slave side receives address/data from the serial bus, accesses the local memory, and returns read data back to the master.

---

## 1. Overall Architecture

```text
Serial Bus
    |
    v
+----------------+
|   slave_port   |
| Serial <->     |
| Parallel       |
| FSM control    |
+-------+--------+
        |
        | smemaddr / smemwdata
        | smemwen / smemren
        v
+----------------+
| slave_memory   |
|   2 KB / 4 KB  |
+-------+--------+
        |
        | smemrdata / rvalid
        v
+----------------+
|   slave_port   |
+-------+--------+
        |
        | srdata
        v
     Master
```

`slave.v` acts as the wrapper that connects `slave_port.v` and `slave_memory.v`.

---

## 2. Module Description

### `slave.v`

Top-level wrapper for one slave.

It connects:

```text
slave_port <-> slave_memory
```

Main external bus signals:

- `swdata` — serial address/write-data bit from the master
- `srdata` — serial read-data bit to the master
- `smode` — `0 = read`, `1 = write`
- `mvalid` — incoming serial bit is valid
- `svalid` — outgoing serial read bit is valid
- `sready` — slave is ready for a new transaction
- `ssplit` — split request
- `split_grant` — permission to resume a split transaction

---

### `slave_port.v`

This is the main slave-side protocol controller.

Responsibilities:

1. Receive the address serially from the master.
2. Reconstruct the full parallel address.
3. For a write, receive serial data and reconstruct the write-data word.
4. Generate memory read/write control signals.
5. Receive parallel read data from memory.
6. Serialize read data and return it to the master.
7. Support split transactions when `SPLIT_EN = 1`.

The serial bus transfers one bit at a time, while the memory interface is parallel.

Typical configuration:

```text
Address width = 12 bits
Data width    = 8 bits
```

---

## 3. Slave Port FSM

### Write transaction

```text
IDLE
  |
  v
ADDR
  |
  v
WDATA
  |
  v
SREADY
  |
  v
IDLE
```

Flow:

```text
Serial address
    ->
Reconstructed address
    ->
Serial write data
    ->
Reconstructed data
    ->
Memory write
```

### Normal read transaction

```text
IDLE
  |
  v
ADDR
  |
  v
SREADY
  |
  v
RVALID
  |
  v
RDATA
  |
  v
IDLE
```

Flow:

```text
Serial address
    ->
Memory read request
    ->
Parallel read data
    ->
Serialize data
    ->
Return data to master
```

### Split-enabled read transaction

When `SPLIT_EN = 1`:

```text
IDLE
  |
  v
ADDR
  |
  v
SREADY
  |
  v
SPLIT
  |
  v
WAIT
  |
  | split_grant
  v
RDATA
  |
  v
IDLE
```

During the `SPLIT` state:

```text
ssplit = 1
```

The slave temporarily releases the bus. It resumes when the arbiter asserts:

```text
split_grant = 1
```

---

## 4. `slave_memory.v`

This is the normal RTL memory implementation used mainly for functional simulation.

Interface:

```text
slave_port                    slave_memory

smemaddr  ------------------> addr
smemwdata ------------------> wdata
smemwen   ------------------> wen
smemren   ------------------> ren

smemrdata <------------------ rdata
rvalid    <------------------ rvalid
```

For a write:

```text
wen = 1
memory[addr] <- wdata
```

For a read:

```text
ren = 1
rdata <- memory[addr]
rvalid = 1
```

---

## 5. BRAM Version

### `slave_memory_bram.v`

This is the FPGA memory implementation.

Instead of implementing the memory using a Verilog register array, it uses the Cyclone IV FPGA's dedicated **Block RAM** resources.

Supported memory sizes:

- 4 KB
- 2 KB

This version is intended for implementation on the **DE0-Nano** board.

### `slave_with_bram.v`

This wrapper combines:

```text
slave_port + slave_memory_bram
```

Typical use:

```text
Simulation:
slave.v + slave_memory.v

DE0-Nano implementation:
slave_with_bram.v + slave_memory_bram.v
```

---

## 6. Memory Configurations

### 4 KB normal slave

```verilog
slave #(
    .MEM_SIZE(4096),
    .SPLIT_EN(0)
) slave_inst (...);
```

### 4 KB split-capable slave

```verilog
slave #(
    .MEM_SIZE(4096),
    .SPLIT_EN(1)
) slave_inst (...);
```

### 2 KB normal slave

```verilog
slave #(
    .MEM_SIZE(2048),
    .SPLIT_EN(0)
) slave_inst (...);
```

---

## 7. Reset

The control logic uses an **asynchronous active-low reset**:

```verilog
always @(posedge clk or negedge rstn)
```

When `rstn = 0`, the control registers reset immediately without waiting for the next clock edge.

The FPGA BRAM contents themselves are not asynchronously cleared, because doing so can prevent proper Block RAM inference.

---

## 8. Verification

### `slave_port_tb.v`

Tests the protocol controller independently.

Main checks:

- asynchronous reset
- serial address reception
- serial write-data reception
- memory write control
- memory read control
- serialization of read data
- normal non-split operation

### `slave_tb.v`

Tests the full slave:

```text
slave_port + slave_memory
```

Example test sequence:

```text
1. Reset the slave
2. Write 0xA5 to address 0x35A
3. Read address 0x35A
4. Confirm that 0xA5 is returned
```

---

## 9. Quartus / Questa Simulation

RTL files:

```text
rtl/
    slave.v
    slave_port.v
    slave_memory.v
```

Simulation-only file:

```text
tb/
    slave_tb.v
```

Quartus synthesis top-level:

```text
slave
```

Questa/ModelSim simulation top-level:

```text
slave_tb
```

Run:

```tcl
run -all
```

---

## 10. Summary

```text
Serial bus data <-> slave_port <-> parallel memory
```

| Module | Purpose |
|---|---|
| `slave.v` | Wrapper connecting the slave port and memory |
| `slave_port.v` | Serial protocol handling, FSM, read/write control, split support |
| `slave_memory.v` | RTL memory used for simulation |
| `slave_memory_bram.v` | FPGA Block RAM implementation |
| `slave_with_bram.v` | Wrapper for slave port + BRAM |
| `slave_port_tb.v` | Unit test for `slave_port` |
| `slave_tb.v` | End-to-end slave verification |
