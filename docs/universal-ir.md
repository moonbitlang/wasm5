# Universal IR Design

This document describes the Universal IR architecture that enables a single WebAssembly compiler to serve multiple runtime backends.

## Overview

```
┌─────────────────┐
│  WASM Module    │
│  (binary/text)  │
└────────┬────────┘
         │ parse
         ▼
┌─────────────────┐
│   @core.Module  │
│  (AST: Instr)   │
└────────┬────────┘
         │ compile
         ▼
┌─────────────────┐
│ CompiledModule  │
│ Array[Int64]    │  ← Universal IR (opcode tags + immediates)
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐  ┌────────────┐
│MoonBit │  │ C Runtime  │
│Runtime │  │            │
│        │  │ transform  │
│switch  │  │ opcode →   │
│dispatch│  │ fnptr      │
└────────┘  └────────────┘
```

## Design Goals

1. **Single Source of Truth**: One compiler produces code for all backends
2. **Portability**: MoonBit runtime avoids native-only FFI (`unsafe_function_to_uint64`)
3. **Performance**: C runtime uses threaded code with direct function pointers
4. **Maintainability**: Adding a new instruction requires changes in one compiler

## Core Data Structures

### CompiledModule (`src/core/types.mbt`)

```moonbit
pub struct CompiledModule {
  code : Array[Int64]         // Flat bytecode: opcodes + immediates
  func_entries : Array[Int]   // PC offset for each function
  func_num_locals : Array[Int]
  func_num_params : Array[Int]
  func_num_results : Array[Int]
  func_max_stack : Array[Int]
  exports : Map[String, Int]  // name → function index
  version : Int               // Format version for compatibility
}
```

### OpTag (`src/core/optag.mbt`)

Dense enumeration of all WebAssembly instructions:

```moonbit
pub enum OpTag {
  // Control (0-18)
  Unreachable     // 0
  Nop             // 1
  Return          // 2
  End             // 3
  FuncExit        // 4
  CopySlot        // 5
  SetSp           // 6
  Br              // 7
  BrIf            // 8
  If              // 9
  BrTable         // 10
  Call            // 11
  ...

  // Constants (20-23)
  I32Const        // 20
  I64Const        // 21
  ...

  // ~200 total opcodes
}
```

Each opcode has an associated immediate count:

```moonbit
pub fn get_immediate_count(opcode : Int64) -> Int {
  match opcode {
    0L => 0   // Unreachable: no immediates
    7L => 1   // Br: [target_pc]
    8L => 2   // BrIf: [target_pc, fallthrough_pc]
    11L => 2  // Call: [callee_pc, frame_offset]
    20L => 1  // I32Const: [value]
    ...
  }
}
```

## Bytecode Format

The `code` array is a flat sequence of opcodes and immediates:

```
[opcode₀, imm₀₁, imm₀₂, opcode₁, opcode₂, imm₂₁, ...]
```

Example: `(i32.const 42) (i32.const 10) (i32.add)`

```
[20, 42, 20, 10, 31]
 │   │   │   │   └── I32Add (opcode 31, 0 immediates)
 │   │   │   └────── immediate: 10
 │   │   └────────── I32Const (opcode 20, 1 immediate)
 │   └────────────── immediate: 42
 └────────────────── I32Const (opcode 20, 1 immediate)
```

### Function Structure

Each function in the bytecode has the following layout:

```
[Entry, num_locals, num_params, num_non_arg_locals, ...body..., End, num_results]
```

- `Entry`: Initializes the call frame (allocates locals, zeroes non-arg locals)
- `End`: Returns from function (copies results to caller's stack)

## Unified Compiler (`src/compile/`)

### Files

| File | Purpose |
|------|---------|
| `compiler.mbt` | Main compilation loop, function iteration |
| `context.mbt` | Slot tracking, control flow management |

### Slot-Based Stack Model

The compiler tracks operand locations at compile time:

```moonbit
struct CompileCtx {
  code : Array[Int64]              // Output bytecode
  slot_stack : Array[Int]          // Maps type stack position → slot number
  mut next_slot : Int              // Next available slot
  control_stack : Array[CtrlFrame] // Block/loop/if frames
  deferred_blocks : Array[...]     // br_if/br_table resolution
}
```

**Key insight**: WebAssembly's operand stack maps to numbered slots. The compiler assigns each value a slot number, enabling efficient stack frame layout.

Example compilation of `(local.get 0) (local.get 1) (i32.add)`:

```
Initial: slot_stack=[], next_slot=2 (assuming 2 locals)

local.get 0:
  emit [LocalGet, 0]
  slot_stack=[0], next_slot=2

local.get 1:
  emit [LocalGet, 1]
  slot_stack=[0, 1], next_slot=2

i32.add:
  emit [I32Add]
  pop_slot() → removes slot 1
  slot_stack=[0], next_slot=2  // Result overwrites first operand's slot
```

### Control Flow Compilation

Branches require knowing target addresses before they're compiled. The compiler uses:

1. **Forward patches**: Store placeholder, patch later when target is known
2. **Deferred resolution blocks**: For `br_if` where both paths need different handling

```moonbit
// br_if compilation
BrIf(label_idx) => {
  let target_frame = control_stack[control_stack.length() - 1 - label_idx]

  // Emit: [BrIf, taken_pc, fallthrough_pc]
  ctx.emit_op(OpTag::BrIf)
  let taken_patch = ctx.code.length()
  ctx.emit_idx(0)  // Placeholder for taken branch
  ctx.emit_idx(0)  // Placeholder for fallthrough

  // Create deferred block to resolve both paths
  ctx.deferred_blocks.push({
    taken_patch,
    fallthrough_patch: taken_patch + 1,
    target_label: label_idx,
    ...
  })
}
```

## Runtime Backends

### MoonBit Runtime (`src/runtime/`)

Uses switch-based dispatch:

```moonbit
fn dispatch(rt : Runtime) -> ReturnCode {
  let opcode = rt.ops.unsafe_get(rt.pc).reinterpret_as_int64()
  match opcode {
    0L => op_unreachable(rt)
    1L => op_nop(rt)
    2L => op_return(rt)
    ...
    31L => op_i32_add(rt)
    ...
  }
}

fn execute(rt : Runtime) -> Runtime {
  while rt.status is Running {
    rt.status = dispatch(rt)
  }
  rt
}
```

**Advantage**: No native FFI required. Works on all MoonBit targets (native, wasm32, wasmgc, js).

### C Runtime (`src/cruntime/`)

Transforms opcodes to function pointers for threaded execution:

```moonbit
// transform.mbt
pub fn transform_to_c_runtime(code : Array[Int64]) -> FixedArray[UInt64] {
  let result = FixedArray::make(code.length(), 0UL)
  let mut i = 0
  while i < code.length() {
    let opcode = code[i]
    result[i] = get_c_handler(opcode)  // FFI: returns C function pointer
    i += 1

    // Copy immediates unchanged
    let num_immediates = get_immediate_count(opcode)
    for _ in 0..<num_immediates {
      result[i] = code[i].reinterpret_as_uint64()
      i += 1
    }
  }
  result
}
```

C execution loop (threaded code):

```c
// op.c
#define NEXT() return ((OpHandler)crt->pc[0])(crt)

TrapCode op_i32_add(CRuntime* crt) {
    int64_t b = crt->sp[-1];
    int64_t a = crt->sp[-2];
    crt->sp--;
    crt->sp[-1] = (int32_t)a + (int32_t)b;
    crt->pc++;
    NEXT();
}
```

**Advantage**: Direct tail calls between handlers, minimal dispatch overhead.

## Stack Layout

Both runtimes use the same stack model:

```
┌─────────────────────────────────────────────┐
│ slot 0 │ slot 1 │ slot 2 │ slot 3 │ slot 4 │ ...
│ param0 │ param1 │ local0 │ operand│ operand│
└─────────────────────────────────────────────┘
          ▲                          ▲
          sp (frame pointer)         stack_top
```

- Slots 0..num_params-1: Function parameters
- Slots num_params..num_locals-1: Local variables
- Slots num_locals..: Operand stack

All values stored as 64-bit (`Int64`/`UInt64`) regardless of WebAssembly type.

## Adding a New Instruction

1. **Add OpTag variant** (`src/core/optag.mbt`):
   ```moonbit
   pub enum OpTag {
     ...
     I32Popcnt  // New opcode
   }
   ```

2. **Set immediate count** (`src/core/optag.mbt`):
   ```moonbit
   pub fn get_immediate_count(opcode : Int64) -> Int {
     ...
     59L => 0  // I32Popcnt: no immediates
   }
   ```

3. **Compile** (`src/compile/compiler.mbt`):
   ```moonbit
   I32Popcnt => ctx.emit_op(OpTag::I32Popcnt)
   ```

4. **MoonBit handler** (`src/runtime/ops_integer.mbt`):
   ```moonbit
   fn op_i32_popcnt(rt : Runtime) -> ReturnCode {
     let a = rt.stack[rt.stack_top - 1].to_uint()
     rt.stack[rt.stack_top - 1] = popcnt32(a).to_uint64()
     rt.pc += 1
     Running
   }
   ```

5. **MoonBit dispatch** (`src/runtime/compile_runtime.mbt`):
   ```moonbit
   59L => op_i32_popcnt(rt)
   ```

6. **C handler** (`src/cruntime/op.c`):
   ```c
   DEFINE_OP(op_i32_popcnt) {
     uint32_t a = (uint32_t)crt->sp[-1];
     crt->sp[-1] = __builtin_popcount(a);
     crt->pc++;
     NEXT();
   }
   ```

7. **C transform** (`src/cruntime/transform.mbt`):
   ```moonbit
   59L => op_i32_popcnt()  // FFI function
   ```

## Validation

The compiler includes IR validation (`src/cruntime/compiler.mbt:validate_universal_code`):

- Function entries are valid offsets
- Each function starts with `Entry` opcode
- All branch targets land on opcode boundaries
- Immediate counts match expected values

This catches compiler bugs before runtime execution.

## Future Work

1. **Multi-backend testing**: Verify on wasm32, wasmgc, and js targets
2. **Code generation**: Generate dispatch tables from OpTag to avoid triple-maintenance
3. **Computed max_stack**: Currently hardcoded to 16, should be computed during compilation
