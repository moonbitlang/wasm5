# wasm5: WebAssembly Virtual Machine in MoonBit

A WebAssembly interpreter implementation in MoonBit.

## Quick Start

```bash
# Check for errors
moon check --target native

# Build the project
moon build --target native

# Run tests
moon run test --target native

# Run a WebAssembly module -- invoking "_start" function
moon run cmd/main --target native -- run test/simple/fib.wasm
```

## Project Structure

```
src/
  ├── types.mbt     - WebAssembly type definitions
  ├── parse.mbt     - Binary format parser
  ├── runtime.mbt   - VM runtime and execution
  └── validate.mbt  - Validation logic

test/
  ├── main.mbt           - Test runner
  └── reference_tests/   - WebAssembly spec tests (.wast files)
```

## Features

- Binary format parser
- Stack-based runtime with error handling
- Type validation system
- i32/i64 operations (arithmetic, bitwise, comparison, control flow)
