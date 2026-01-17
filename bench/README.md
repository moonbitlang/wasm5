# wasm5 Benchmark Suite

Benchmark suite comparing execution performance of `wasmi` and `wasm5` WebAssembly runtimes.

## Dependencies

- Python 3.8+
- [hyperfine](https://github.com/sharkdp/hyperfine) - CLI benchmarking tool
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools) - WebAssembly tooling
- wasmi_cli: `cargo install wasmi_cli`

### Installation

```bash
# macOS
brew install hyperfine
cargo install wasm-tools wasmi_cli

# Linux
cargo install hyperfine wasm-tools wasmi_cli
```

## Usage

### 1. Convert .wat files to .wasm

```bash
python bench.py convert
```

This converts all `.wat` files in `wat/` to `.wasm` binary format in `benches/`.

### 2. Run benchmarks

```bash
python bench.py run --wasmi wasmi_cli --wasm5 /path/to/wasm5
```

Options:
- `--wasmi`: Path to wasmi binary (or `wasmi_cli` if in PATH)
- `--wasm5`: Path to wasm5 binary
- `--output`: Output file for results (default: `results.json`)
- `--warmup`: Number of warmup runs (default: 3)
- `--runs`: Minimum number of benchmark runs (default: 10)

### 3. View results

```bash
cat results.json
```

## Benchmarks

| Benchmark | Input | Description |
|-----------|-------|-------------|
| counter | 1,000,000 | Simple loop counter |
| fib.recursive | 30 | Recursive Fibonacci |
| fib.iterative | 2,000,000 | Iterative Fibonacci |
| primes | 1,000 | Prime number sieve |
| matmul | 200 | Matrix multiplication |
| bulk-ops | 5,000 | Bulk memory operations |

## Manual Verification

Test each runtime individually:

```bash
# Test wasmi
wasmi_cli benches/counter.wasm --invoke run 100

# Test wasm5
/path/to/wasm5 benches/counter.wasm --invoke run 100
```

## Project Structure

```
bench/
├── bench.py          # Benchmark script (convert + run)
├── README.md         # This file
├── benches/          # Generated .wasm files
│   └── *.wasm
└── wat/              # Source .wat files
    └── *.wat
```

## Notes

- The `fib.tailrec` benchmark is excluded (wasm5 doesn't support tail calls yet)
- The `argon2` benchmark is excluded (requires pre-compiled .wasm with import dependencies)
- hyperfine handles warmup and statistical analysis automatically

## CLI Specifications

Both runtimes use the same CLI pattern:

```bash
<runtime> <file.wasm> --invoke <function> [args...]
```

Examples:
```bash
wasmi_cli counter.wasm --invoke run 1000000
wasm5 counter.wasm --invoke run 1000000
```
