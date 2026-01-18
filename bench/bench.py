#!/usr/bin/env python3
"""
Benchmark script comparing wasmi and wasm5 execution performance.
Uses hyperfine for accurate measurements.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

# Benchmark configurations: (name, input)
BENCHMARKS = [
    ("counter", 1_000_000),
    ("fib.recursive", 30),
    ("fib.iterative", 2_000_000),
    ("primes", 1_000),
    ("matmul", 200),
    ("bulk-ops", 5_000),
]

BENCH_DIR = Path(__file__).parent
WAT_DIR = BENCH_DIR / "wat"
WASM_DIR = BENCH_DIR / "benches"


def convert_wat_files():
    """Convert all .wat files to .wasm using wasm-tools."""
    WASM_DIR.mkdir(exist_ok=True)

    wat_files = list(WAT_DIR.glob("*.wat"))
    if not wat_files:
        print(f"No .wat files found in {WAT_DIR}")
        sys.exit(1)

    for wat_file in wat_files:
        wasm_file = WASM_DIR / wat_file.with_suffix(".wasm").name
        try:
            subprocess.run(
                ["wasm-tools", "parse", str(wat_file), "-o", str(wasm_file)],
                check=True,
                capture_output=True,
                text=True,
            )
            print(f"Converted {wat_file.name} -> {wasm_file.name}")
        except subprocess.CalledProcessError as e:
            print(f"Error converting {wat_file.name}: {e.stderr}")
            sys.exit(1)
        except FileNotFoundError:
            print("Error: wasm-tools not found. Install it:")
            print("  cargo install wasm-tools")
            sys.exit(1)

    print(f"\nConverted {len(wat_files)} files to {WASM_DIR}")


def check_wasm_files():
    """Check that all required .wasm files exist."""
    missing = []
    for name, _ in BENCHMARKS:
        wasm_file = WASM_DIR / f"{name}.wasm"
        if not wasm_file.exists():
            missing.append(wasm_file.name)
    if missing:
        print(f"Error: Missing .wasm files: {', '.join(missing)}")
        print("Run 'python bench.py convert' first to generate them.")
        sys.exit(1)


def run_benchmarks(wasmi_bin: str, wasm5_bin: str, output: str, warmup: int, runs: int):
    """Run all benchmarks using hyperfine."""
    check_wasm_files()

    results = []

    for name, input_val in BENCHMARKS:
        wasm_file = WASM_DIR / f"{name}.wasm"
        tmp_json = f"/tmp/bench_{name}.json"

        wasmi_cmd = f"{wasmi_bin} {wasm_file} --invoke run {input_val}"
        wasm5_cmd = f"{wasm5_bin} {wasm_file} --invoke run {input_val}"

        print(f"\n{'='*60}")
        print(f"Benchmarking: {name} (input={input_val})")
        print(f"{'='*60}")

        try:
            subprocess.run(
                [
                    "hyperfine",
                    "--warmup", str(warmup),
                    "--min-runs", str(runs),
                    "--export-json", tmp_json,
                    "-n", "wasmi", wasmi_cmd,
                    "-n", "wasm5", wasm5_cmd,
                ],
                check=True,
            )
        except FileNotFoundError:
            print("Error: hyperfine not found. Install it:")
            print("  brew install hyperfine  # macOS")
            print("  cargo install hyperfine # via Cargo")
            sys.exit(1)
        except subprocess.CalledProcessError as e:
            print(f"Error running benchmark {name}: {e}")
            continue

        # Collect results
        try:
            with open(tmp_json) as f:
                data = json.load(f)
                results.append({
                    "benchmark": name,
                    "input": input_val,
                    "results": data,
                })
        except (FileNotFoundError, json.JSONDecodeError) as e:
            print(f"Warning: Could not read results for {name}: {e}")

    # Save combined results
    output_path = BENCH_DIR / output
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\n{'='*60}")
    print(f"Results saved to {output_path}")
    print(f"{'='*60}")

    # Print summary
    print_summary(results)


def print_summary(results: list):
    """Print a summary table of benchmark results."""
    if not results:
        return

    print("\nSummary:")
    print(f"{'Benchmark':<20} {'wasmi (ms)':<15} {'wasm5 (ms)':<15} {'Ratio':<10}")
    print("-" * 60)

    for r in results:
        name = r["benchmark"]
        data = r.get("results", {}).get("results", [])
        if len(data) >= 2:
            wasmi_time = data[0].get("mean", 0) * 1000  # Convert to ms
            wasm5_time = data[1].get("mean", 0) * 1000
            ratio = wasm5_time / wasmi_time if wasmi_time > 0 else float("inf")
            print(f"{name:<20} {wasmi_time:<15.2f} {wasm5_time:<15.2f} {ratio:<10.2f}x")


def run_all(wasmi_bin: str = "wasmi_cli", wasm5_bin: str = "wasm5"):
    """Run full benchmark workflow: convert, run, clean."""
    print("=== Converting .wat files to .wasm ===\n")
    convert_wat_files()

    print("\n=== Running benchmarks ===")
    run_benchmarks(wasmi_bin, wasm5_bin, "results.json", warmup=3, runs=10)

    print("\n=== Cleaning up ===\n")
    clean()


def clean():
    """Remove generated .wasm files and results."""
    removed = 0

    # Remove .wasm files
    if WASM_DIR.exists():
        for wasm_file in WASM_DIR.glob("*.wasm"):
            wasm_file.unlink()
            print(f"Removed {wasm_file.name}")
            removed += 1
        # Remove benches directory if empty
        try:
            WASM_DIR.rmdir()
            print(f"Removed {WASM_DIR.name}/")
        except OSError:
            pass  # Directory not empty or doesn't exist

    # Remove results.json
    results_file = BENCH_DIR / "results.json"
    if results_file.exists():
        results_file.unlink()
        print("Removed results.json")
        removed += 1

    if removed == 0:
        print("Nothing to clean.")
    else:
        print(f"\nCleaned {removed} file(s).")


def main():
    parser = argparse.ArgumentParser(
        description="Benchmark wasmi vs wasm5 performance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Convert subcommand
    subparsers.add_parser("convert", help="Convert .wat files to .wasm")

    # Clean subcommand
    subparsers.add_parser("clean", help="Remove generated .wasm files and results")

    # Run subcommand
    run_parser = subparsers.add_parser("run", help="Run benchmarks")
    run_parser.add_argument(
        "--wasmi",
        default="wasmi_cli",
        help="Path to wasmi binary (default: wasmi_cli)",
    )
    run_parser.add_argument(
        "--wasm5",
        default="wasm5",
        help="Path to wasm5 binary (default: wasm5)",
    )
    run_parser.add_argument(
        "--output",
        default="results.json",
        help="Output file for benchmark results (default: results.json)",
    )
    run_parser.add_argument(
        "--warmup",
        type=int,
        default=3,
        help="Number of warmup runs (default: 3)",
    )
    run_parser.add_argument(
        "--runs",
        type=int,
        default=10,
        help="Minimum number of benchmark runs (default: 10)",
    )

    args = parser.parse_args()

    if args.command == "convert":
        convert_wat_files()
    elif args.command == "clean":
        clean()
    elif args.command == "run":
        run_benchmarks(args.wasmi, args.wasm5, args.output, args.warmup, args.runs)
    elif args.command is None:
        # Default: run full workflow (convert -> run -> clean)
        run_all()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
