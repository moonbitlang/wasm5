# WebAssembly VM Development Guide

## Quick Reference

```bash
moon check --target native                    # Check for errors
moon build --target native                    # Build project
moon run test --target native                 # Run all tests (~45 seconds)
timeout 45 moon run test --target native 2>&1 | grep "wast_file"  # Test specific file
timeout 45 moon run test --target native 2>&1 | tail -5           # See failure count
```

## Project Architecture

```
src/
  types.mbt     - Core type definitions & instruction enum (Instr, ValType, Module)
  parse.mbt     - Binary WASM parser (opcode → Instr mapping)
  runtime.mbt   - Instruction executor & runtime state (Runtime struct, execute_*)
  validate.mbt  - Validation engine (ValidationCtx, type checking, control flow)

test/
  main.mbt                     - Test harness (runs .wast.json tests)
  reference_tests/*.wast       - WebAssembly spec tests (human-readable)
  reference_tests/*.wast.json  - Compiled test data (loaded by harness)
```

### Key Data Structures

**Runtime State** (runtime.mbt):
```moonbit
struct Runtime {
  module_ : Module              // Loaded WASM module
  stack : Array[Value]          // Value stack (I32/I64/F32/F64/Ref)
  call_stack : Array[CallFrame] // Function call frames
  pc : Int                      // Program counter
  locals : Array[Value]         // Current function locals
  memory : Array[Byte]          // Linear memory
  globals : Array[Value]        // Global variables
  tables : Array[RuntimeTable]  // Function tables
  branch_targets : Array[Int]   // Branch target PCs
}
```

**Validation Context** (validate.mbt):
```moonbit
struct ValidationCtx {
  stack : Array[ValType]        // Type stack (not values!)
  control_stack : Array[(Array[ValType], Array[ValType])]  // (params, results)
  is_unreachable : Bool         // Polymorphic stack mode
  unreachable_stack_height : Int
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
moon run test --target native 2>&1 | grep "wast_file.wast"
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
sed -n 'start_line,end_line p' test/reference_tests/br_if.wast
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
- Check `src/runtime.mbt` - execution logic
- Add debug prints in `execute_*` functions
- Check stack state before/after instruction

**Validation failures** (`assert_invalid`):
- Check `src/validate.mbt` - validation logic
- Look at `validate_instruction()` for the specific opcode
- Check if we're missing a validation rule

**Parsing failures** (`assert_malformed`):
- Check `src/parse.mbt` - binary decoding
- Look at opcode mapping in `parse_instruction()`

## Adding New Instructions

Example: Adding `i32.popcnt` (count set bits)

### 1. Add enum variant (`src/types.mbt`)
```moonbit
pub enum Instr {
  // ... existing instructions ...
  I32Popcnt  // ← Add this
}
```

### 2. Add parser mapping (`src/parse.mbt`)
```moonbit
fn parse_instruction(parser) -> Instr {
  match opcode {
    // ... existing opcodes ...
    0x69 => I32Popcnt  // ← Map opcode to enum
  }
}
```

### 3. Add validation (`src/validate.mbt`)
```moonbit
fn validate_instruction(..., instr: Instr) {
  match instr {
    // ... existing cases ...
    I32Popcnt => {
      ctx.poly_pop_expect(I32, "i32.popcnt")  // Pop i32
      stack.push(I32)                          // Push i32 result
    }
  }
}
```

### 4. Add runtime (`src/runtime.mbt`)
```moonbit
fn execute_instruction(runtime, instr) {
  match instr {
    // ... existing cases ...
    I32Popcnt => {
      let a = runtime.stack.pop_i32()
      let result = count_bits(a)  // Actual implementation
      runtime.stack.push(Value::I32(result))
    }
  }
}
```

## Validation vs Runtime

**Important distinction**:

| Phase | When | What | Data |
|-------|------|------|------|
| **Validation** | Module load | Type checking | `ValidationCtx` with type stack |
| **Runtime** | Execution | Actual computation | `Runtime` with value stack |

Common mistake: Confusing `ValidationCtx::stack` (types) with `Runtime::stack` (values)

```moonbit
// VALIDATION (validate.mbt) - operates on TYPES
ctx.poly_pop_expect(I32, "operation")  // ✓ Check type is I32
stack.push(I32)                        // ✓ Push TYPE I32

// RUNTIME (runtime.mbt) - operates on VALUES
let val = runtime.stack.pop_i32()      // ✓ Pop actual value
runtime.stack.push(Value::I32(result)) // ✓ Push actual value
```

## Error Handling Patterns

### Use `raise`, not `abort`

```moonbit
// ✓ GOOD - Runtime errors
if b == 0 {
  raise RuntimeError::DivisionByZero
}

// ✓ GOOD - Validation errors
if stack.length() < 2 {
  raise ValidationError::TypeMismatch("i32.add needs 2 operands")
}

// ✗ BAD - Don't use abort for expected errors
if b == 0 {
  abort("division by zero")  // Wrong! Use raise
}
```

### Function signatures must declare errors

```moonbit
// ✓ Declares RuntimeError
fn execute_div(a: UInt, b: UInt) -> UInt raise RuntimeError {
  if b == 0 { raise RuntimeError::DivisionByZero }
  a / b
}

// ✓ Declares ValidationError
fn validate_binary_op(ctx: ValidationCtx) -> Unit raise ValidationError {
  if ctx.stack.length() < 2 {
    raise ValidationError::TypeMismatch("need 2 values")
  }
}
```

## Control Flow & Stack Polymorphism

### Unreachable Code

After `unreachable`, `br`, `return`, or unconditional branches, code is **unreachable**:

```wasm
(block
  (br 0)         ;; Branches away
  (i32.add)      ;; UNREACHABLE - can pop from empty stack (polymorphic)
)
```

In unreachable mode (`ctx.is_unreachable = true`):
- Stack operations succeed even with empty stack (polymorphic)
- Use `ctx.poly_pop_expect()` instead of direct pop
- Values popped from empty stack are assumed to match expected type

### Branch Target Types

**Critical distinction**:

```moonbit
// BLOCK - br targets the END (results)
Block(block_type, instrs) => {
  let (params, results) = get_block_type(block_type)
  ctx.push_control(params, results)  // br uses 'results'
}

// LOOP - br targets the START (params)
Loop(block_type, instrs) => {
  let (params, results) = get_block_type(block_type)
  ctx.push_control(params, params)   // br uses 'params' (restart loop)
}
```

This is why `br 0` inside a loop restarts the loop!

### Conditional Branches (br_if)

`br_if` is special - it doesn't clear the stack:

```moonbit
// br_if validation:
BrIf(label) => {
  let target_types = ctx.get_label_types(label)
  ctx.poly_pop_expect(I32, "br_if condition")  // Pop condition

  // Check target values are on stack, but DON'T pop them!
  // They stay for the fallthrough case
  validate_stack_has_types(target_types)

  // DON'T mark as unreachable (execution continues)
}
```

## Common Pitfalls

### 1. Binary operation operand order

```moonbit
// ✗ WRONG
let a = stack.pop()  // This is the SECOND operand!
let b = stack.pop()  // This is the FIRST operand!
a - b  // Wrong order!

// ✓ CORRECT
let b = stack.pop()  // Pop second operand first
let a = stack.pop()  // Then pop first operand
a - b  // Correct order
```

Stack is LIFO: `(i32.const 10) (i32.const 3) (i32.sub)` → stack is `[10, 3]` → pop `3`, then `10` → `10 - 3 = 7`

### 2. Validation context isolation

Each block creates a NEW validation context:

```moonbit
// ✓ CORRECT - new context for block
Block(block_type, instrs) => {
  let block_ctx = ValidationCtx::new()  // Fresh context

  // But COPY parent's control stack!
  for frame in ctx.control_stack {
    block_ctx.control_stack.push(frame)
  }
  block_ctx.push_control(params, results)

  // Validate block body with isolated stack
  for instr in instrs {
    validate_instruction(module_, func_type, code, block_ctx, instr)
  }
}
```

### 3. Array references in MoonBit

Arrays in tuples are references, not copies:

```moonbit
let (_, results) = control_stack[idx]
results  // This is a REFERENCE to the array in the tuple!
```

If you modify `results`, you modify the original! This can cause subtle bugs.

### 4. Nested expressions with branches

When `br` is inside an operand position:

```wasm
(i32.add
  (i32.const 5)
  (br 0 (i32.const 10))  ;; Branches immediately!
)
;; The i32.add NEVER executes - br jumps away
```

The branch happens during evaluation of the operand, so the outer operation never runs.

## Debugging Tips

### 1. Add targeted debug output

```moonbit
// In validate.mbt
BrTable(labels, default_label) => {
  println("Validating br_table: labels=\{labels}, default=\{default_label}")
  println("Control stack depth: \{ctx.control_stack.length()}")

  for i, label in labels {
    let types = ctx.get_label_types(label)
    println("  Label \{label} expects: \{types}")
  }
  // ... rest of validation
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

### 3. Test in isolation

Create minimal test cases:

```wasm
(module
  (func (export "test") (result i32)
    (block (result i32)
      (br_if 0 (i32.const 42) (i32.const 1))
      (i32.const 99)
    )
  )
)
```

### 4. Compare with reference implementation

When stuck, check the official WebAssembly spec:
- https://webassembly.github.io/spec/core/valid/instructions.html (validation)
- https://webassembly.github.io/spec/core/exec/instructions.html (execution)

## Performance Notes

- Validation happens ONCE at module load
- Runtime execution happens MANY times
- Optimize runtime, not validation
- Use `Array::unsafe_pop()` in hot paths (after validation ensures safety)

## Known Issues / TODOs

See `TODO.md` for detailed tracking, but key issues:

1. **Nested branch evaluation** - br/br_if inside operand positions don't properly abort outer expression
2. **br_table type checking** - Disabled due to `get_label_types()` returning inconsistent types
3. **Stack polymorphism edge cases** - Some unreachable code scenarios not fully handled
