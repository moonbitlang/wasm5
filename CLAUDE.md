# WebAssembly VM Development Guide

## Commands

```bash
moon check --target native     # Check for errors
moon build --target native     # Build project
moon run test --target native  # Run tests
```

## Project Structure

```
src/
  types.mbt     - Type definitions & instruction enum
  parse.mbt     - Binary format parsing & opcode mapping
  runtime.mbt   - Instruction execution & runtime errors
  validate.mbt  - Validation logic & public API

test/
  main.mbt                     - Test runner
  reference_tests/*.wast       - WebAssembly spec test sources
```

## Test File Structure

WebAssembly reference tests use `.wast` files which are converted to JSON + WASM:

- `xxx.wast` - Human-readable test source with line numbers
- `xxx/xxx.json` - Test metadata mapping tests to wasm files
- `xxx/*.wasm` - Binary modules (main module + invalid modules for validation tests)

## Investigating Test Failures

When a test fails at line N in `xxx.wast`:

```bash
# Check test metadata
grep -A5 '"line": N' test/reference_tests/xxx/xxx.json

# See actual WebAssembly code
sed -n '<N-3>,<N+5>p' test/reference_tests/xxx.wast
```

## Test Types

| Type | What it checks | Failure means |
|------|----------------|---------------|
| `assert_return` | Function returns expected value | Wrong runtime result |
| `assert_trap` | Function raises expected error | Missing error handling |
| `assert_invalid` | Module fails validation | Missing validation check |

## Adding New Instructions

1. **Add enum variant** (`src/types.mbt`)
2. **Add parser mapping** (`src/parse.mbt`)
3. **Add runtime** (`src/runtime.mbt`)
4. **Add validation** (`src/validate.mbt`)

## Error Handling

Use `raise`, not `abort`:

```moonbit
// Runtime errors
if b == 0 {
  raise RuntimeError::DivisionByZero
}

// Validation errors
if stack.length() < 2 {
  raise ValidationError::TypeMismatch("need 2 operands")
}
```

Functions must declare error types:

```moonbit
fn my_function() -> Value raise RuntimeError {
  // can use raise here
}
```

## Common Pitfalls

- Use `raise` not `abort()` for errors
- Declare `raise ErrorType` in function signatures
- Binary ops: second pop is first operand
- Validate instructions inside blocks recursively
