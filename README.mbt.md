# wasm5: WebAssembly Virtual Machine in MoonBit

A WebAssembly virtual machine implementation in MoonBit.

## Status

The virtual machine passes most WebAssembly specification tests with 11 individual tests skipped due to known limitations.

### Supported Features

**WebAssembly 1.0 Core:**
- All basic instructions (arithmetic, logic, comparison, conversion)
- Memory operations (load, store, memory.grow, memory.size)
- Control flow (block, loop, if, br, br_if, br_table, call, call_indirect, return)
- Local and global variables
- Tables

**Extension Proposals:**
- **Reference Types** - funcref, externref, ref.null, ref.is_null, ref.func, typed function references
- **Tail Call** - return_call, return_call_indirect, return_call_ref
- **Bulk Memory Operations** - memory.copy, memory.fill, memory.init, data.drop
- **Multi-value** - Functions can return multiple values

## Quick Start

```bash
# Run tests (requires wasm-tools to be installed)
moon run test --target native

# Run a WebAssembly module (invokes _start function)
moon run cmd/main -- run test/simple/print42.wasm
```
