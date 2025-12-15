# wasm5: WebAssembly Virtual Machine in MoonBit

A WebAssembly interpreter implementation in MoonBit.

## Quick Start

```bash
# Run tests
moon run test --target native

# Run a WebAssembly module -- invoking "_start" function
moon run cmd/main -- run test/simple/print42.wasm
```

**Note:** Running tests requires `wasm-tools` to be installed.
