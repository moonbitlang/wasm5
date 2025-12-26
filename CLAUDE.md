# WebAssembly VM Development Guide

## Quick Reference

```bash
moon check --target native                     # Check for errors
moon build --target native                     # Build project
moon test test --target native --release       # Run all tests
moon fmt                                       # Format code
```

## Project Architecture

```
src/
  core/
    types.mbt        - Core type definitions (ValType, Instr, Module, FuncType)

  parse/
    parse_*.mbt      - Binary WASM parser (opcode → Instr mapping)

  runtime/
    runtime.mbt      - Runtime struct, module loading, error types
    compile_*.mbt    - Threaded code compiler (Instr → MInstr)
    ops_*.mbt        - Instruction handlers (ops_integer, ops_float, ops_memory, ops_control)

  validate/
    validate_*.mbt   - Validation engine (type checking, control flow)

test/
  reference_tests/*.wast       - WebAssembly spec tests (human-readable)
  reference_tests/*.wast.json  - Compiled test data (loaded by harness)
```

### Key Data Structures

**Runtime State** (`src/runtime/runtime.mbt`):
```moonbit
struct Runtime {
  module_ : @core.Module           // Loaded WASM module
  ops : FixedArray[MInstr]         // Compiled threaded code
  stack : FixedArray[UInt64]       // Unified stack (locals + operands, tagless)
  mut stack_top : Int              // Next push position
  mut sp : Int                     // Stack pointer (first local)
  mut num_locals : Int             // Number of locals in current frame
  mut pc : Int                     // Program counter into ops
  mut status : RuntimeStatus       // Running, Terminated, or Trap
  call_stack : Array[CallFrame]    // Function call frames
  memory : Array[Byte]             // Linear memory
  globals : Array[Value]           // Global variables
  tables : Array[RuntimeTable]     // Function tables
  mut error_detail : String        // Error message on trap
}
```

**Instruction Format** (`src/runtime/compile_context.mbt`):
```moonbit
enum MInstr {
  WasmInstr((Runtime) -> Unit)  // Instruction handler function
  ImmediateI32(UInt)            // Inline i32 immediate
  ImmediateIdx(Int)             // Inline index immediate
}

enum RuntimeStatus {
  Running     // Execution continues
  Terminated  // Normal completion
  Trap        // Error occurred (check error_detail)
}
```

**Validation Context** (`src/validate/validate_context.mbt`):
```moonbit
struct ValidationCtx {
  stack : Array[ValType]           // Type stack (not values!)
  mut is_unreachable : Bool        // Polymorphic stack mode
  control_stack : Array[(Array[ValType], Array[ValType])]  // (params, results)
  initialized_locals : Array[Bool] // For non-defaultable types
}
```

## Runtime Execution Model

### Threaded Interpreter

The VM compiles WASM instructions to a flat array of `MInstr`:

```moonbit
// Compilation: Instr → MInstr array
Block(bt, body) → [
  WasmInstr(op_if),      // if handler
  ImmediateIdx(else_pc), // branch target
  ...body instructions...,
  WasmInstr(op_end),     // end handler
]

// Execution loop (compile_runtime.mbt)
fn Runtime::execute(self) {
  self.status = Running
  while self.status == Running {
    let WasmInstr(f) = self.ops[self.pc]
    f(self)  // handler may update pc, status
  }
  if self.status == Trap {
    raise RuntimeError::from_detail(self.error_detail)
  }
}
```

### Unified Stack

Locals and operand values share one stack:

```
stack: [local0, local1, local2, operand0, operand1, ...]
        ^sp                      ^stack_top
```

- `sp` points to first local
- `stack_top` is next push position
- Locals accessed via `stack[sp + idx]`
- Values stored as `UInt64` (tagless for performance)

### Instruction Handler Pattern

All handlers return `Unit` and use status for control flow:

```moonbit
fn op_i32_div_s(rt : Runtime) -> Unit {
  let b = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 2).to_uint()
  if b == 0U {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  let result = a.reinterpret_as_int() / b.reinterpret_as_int()
  rt.stack_top -= 1
  rt.stack.unsafe_set(rt.stack_top - 1, result.reinterpret_as_uint().to_uint64())
  rt.pc += 1
}

fn op_return(rt : Runtime) -> Unit {
  // ... copy results, restore frame ...
  if rt.call_stack.length() == 0 {
    rt.status = Terminated  // Entry function done
    return
  }
  // ... restore caller state ...
}
```

## Test File Structure

WebAssembly spec tests use a dual format:
1. **`.wast`** - S-expression source (human-readable, has line numbers)
2. **`.wast.json`** - JSON with embedded WASM modules (what test harness loads)

The test harness reads `.wast.json` but reports line numbers from `.wast`.

## Investigating Test Failures

### Step 1: Identify the failure

```bash
moon test test --target native --release 2>&1 | grep "wast_file.wast"
```

Example output:
```
[assert_return] br_if.wast:468: at result 0: expected I32(9), got I32(12)
[assert_invalid] br_if.wast:515: expected validation error 'type mismatch' but module was valid
```

### Step 2: View the test source

```bash
# See WebAssembly code around the failure
sed -n '465,475p' test/reference_tests/br_if.wast

# Find function definition
grep -n "func.*function-name" test/reference_tests/br_if.wast
```

### Step 3: Understand the test type

| Test Type | What it checks | Typical causes |
|-----------|----------------|----------------|
| `assert_return` | Function returns expected value | Runtime bug, wrong execution logic |
| `assert_trap` | Function raises expected error | Missing runtime error checks |
| `assert_invalid` | Module fails validation | Missing/incomplete validation rules |
| `assert_malformed` | Binary parsing fails | Parser doesn't reject invalid WASM |

### Step 4: Debug the right layer

**Runtime failures** (`assert_return`, `assert_trap`):
- Check `src/runtime/ops_*.mbt` - instruction handlers
- Check stack manipulation and pc updates
- Verify trap conditions are correct

**Validation failures** (`assert_invalid`):
- Check `src/validate/validate_instr_*.mbt`
- Look at the specific instruction validation
- Check control stack handling

**Parsing failures** (`assert_malformed`):
- Check `src/parse/parse_*.mbt`
- Look at opcode mapping

## Adding New Instructions

Example: Adding `i32.popcnt` (count set bits)

### 1. Add enum variant (`src/core/types.mbt`)
```moonbit
pub enum Instr {
  // ... existing instructions ...
  I32Popcnt  // ← Add this
}
```

### 2. Add parser mapping (`src/parse/parse_instr.mbt`)
```moonbit
0x69 => I32Popcnt  // ← Map opcode to enum
```

### 3. Add validation (`src/validate/validate_instr_numeric.mbt`)
```moonbit
I32Popcnt => {
  ctx.poly_pop_expect(I32, "i32.popcnt")
  stack.push(I32)
}
```

### 4. Add compilation (`src/runtime/compile_emit.mbt`)
```moonbit
I32Popcnt => ctx.emit_op(op_i32_popcnt)
```

### 5. Add runtime handler (`src/runtime/ops_integer.mbt`)
```moonbit
fn op_i32_popcnt(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let result = popcnt32(a)  // Count set bits
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
}
```

## Error Handling Patterns

### Runtime errors (instruction handlers)

```moonbit
// Set error detail and trap status, then return
if divisor == 0U {
  rt.error_detail = "division by zero"
  rt.status = Trap
  return
}

// For unrecoverable internal errors only
guard some_condition else {
  rt.error_detail = "unexpected state"
  rt.status = Trap
  return
}
```

### Validation errors

```moonbit
// Use raise for validation
if stack.length() < 2 {
  raise ValidationError::TypeMismatch("i32.add needs 2 operands")
}
```

## Common Pitfalls

### 1. Binary operation operand order

```moonbit
// Stack: [..., a, b] where a was pushed first, b second
// For a - b:
let b = rt.stack.unsafe_get(rt.stack_top - 1)  // Second operand
let a = rt.stack.unsafe_get(rt.stack_top - 2)  // First operand
let result = a - b  // Correct order
```

### 2. Stack pointer after operations

```moonbit
// Binary op: consume 2, produce 1
rt.stack_top -= 1  // Net effect: -1
rt.stack.unsafe_set(rt.stack_top - 1, result)

// Unary op: consume 1, produce 1
// stack_top unchanged, just update in place
rt.stack.unsafe_set(rt.stack_top - 1, result)
```

### 3. Don't forget to increment pc

```moonbit
fn op_some_instr(rt : Runtime) -> Unit {
  // ... do work ...
  rt.pc += 1  // Don't forget!
}
```

### 4. Status must be reset between calls

The `call_compiled` function resets status before execution to prevent
state leakage from previous trapped calls.

## Debugging Tips

### 1. Add targeted debug output

```moonbit
fn op_problematic(rt : Runtime) -> Unit {
  println("pc=\{rt.pc} stack_top=\{rt.stack_top}")
  // ... rest of handler
}
```

### 2. Inspect WASM structure

```bash
# Convert .wat to .wasm
wat2wasm test.wat -o test.wasm

# Print human-readable WASM
wasm-tools print test.wasm

# Dump detailed binary structure
wasm-tools dump test.wasm
```

### 3. Compare with reference implementation

- https://webassembly.github.io/spec/core/valid/instructions.html (validation)
- https://webassembly.github.io/spec/core/exec/instructions.html (execution)

## Performance Notes

- Stack uses `FixedArray[UInt64]` with tagless representation
- `unsafe_get`/`unsafe_set` used in hot paths (validation ensures safety)
- Threaded code avoids instruction dispatch overhead
- Branch targets pre-computed and embedded as immediates
