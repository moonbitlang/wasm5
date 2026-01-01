// wasm-gc recursive self-hosting test
// Tests that wasm5 (wasm-gc) can parse, compile, and execute itself
// Run with: node --stack-size=8192 test/selfhost/test_wasm_gc_recursive.mjs
import { readFile } from 'fs/promises';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

function stringToBytes(str) {
  return new TextEncoder().encode(str);
}

async function main() {
  console.log("=== wasm5 (wasm-gc) Recursive Self-Hosting Test ===\n");

  // Load wasm-gc version
  const wasmPath = join(__dirname, '../../target/wasm-gc/release/build/cmd/wasm/wasm.wasm');
  const wasmBytes = await readFile(wasmPath);
  console.log(`Loaded wasm5 (wasm-gc): ${wasmBytes.length} bytes`);

  // Create memory (32MB for recursive self-hosting)
  const memory = new WebAssembly.Memory({ initial: 512, maximum: 1024 });
  console.log(`Created memory: ${memory.buffer.byteLength / 1024 / 1024}MB`);

  const importObject = {
    env: { memory },
    spectest: {
      print_char: (c) => process.stdout.write(String.fromCharCode(c))
    }
  };

  // Compile and instantiate
  const wasmModule = await WebAssembly.compile(wasmBytes);
  const wasmInstance = await WebAssembly.instantiate(wasmModule, importObject);
  console.log("wasm5 (wasm-gc) outer instantiated\n");

  const { _start, alloc, parse_wasm_raw, run_wasm_raw, call_i32_raw } = wasmInstance.exports;

  _start();

  // Copy wasm5 into memory for the interpreter
  const wasmPtr = alloc(wasmBytes.length);
  const wasmMemory = new Uint8Array(memory.buffer);
  wasmMemory.set(wasmBytes, wasmPtr);
  console.log(`Copied wasm5 (wasm-gc) to address ${wasmPtr}`);
  console.log(`Size: ${wasmBytes.length} bytes`);

  // Test 1: Parse itself
  console.log("\n" + "=".repeat(50));
  console.log("TEST 1: Parse wasm5 (wasm-gc)");
  console.log("=".repeat(50));

  let startTime = performance.now();
  const parseResult = parse_wasm_raw(wasmPtr, wasmBytes.length);
  let elapsed = performance.now() - startTime;

  if (parseResult === 1) {
    console.log(`✓ PASS: Parse successful (${elapsed.toFixed(2)}ms)`);
  } else {
    console.log("✗ FAIL: Parse failed");
    process.exit(1);
  }

  // Test 2: Load and compile itself
  console.log("\n" + "=".repeat(50));
  console.log("TEST 2: Load & compile wasm5 (wasm-gc)");
  console.log("=".repeat(50));

  const wasmPtr2 = alloc(wasmBytes.length);
  new Uint8Array(memory.buffer).set(wasmBytes, wasmPtr2);

  startTime = performance.now();
  const runResult = run_wasm_raw(wasmPtr2, wasmBytes.length);
  elapsed = performance.now() - startTime;

  if (runResult === 1) {
    console.log(`✓ PASS: Load & compile successful (${elapsed.toFixed(2)}ms)`);
  } else {
    console.log("✗ FAIL: Load & compile failed");
    process.exit(1);
  }

  // Test 3: Execute alloc on inner wasm5
  console.log("\n" + "=".repeat(50));
  console.log("TEST 3: Execute inner wasm5's alloc()");
  console.log("=".repeat(50));

  const wasmPtr3 = alloc(wasmBytes.length);
  new Uint8Array(memory.buffer).set(wasmBytes, wasmPtr3);
  const allocName = stringToBytes("alloc");
  const namePtr = alloc(allocName.length);
  new Uint8Array(memory.buffer).set(allocName, namePtr);

  startTime = performance.now();
  const allocResult = call_i32_raw(wasmPtr3, wasmBytes.length, namePtr, allocName.length, 100);
  elapsed = performance.now() - startTime;

  if (allocResult >= 2097152) {
    console.log(`✓ PASS: alloc(100) = ${allocResult} (${elapsed.toFixed(2)}ms)`);
  } else {
    console.log(`✗ FAIL: alloc returned ${allocResult}`);
    process.exit(1);
  }

  console.log("\n" + "=".repeat(50));
  console.log("wasm-gc RECURSIVE SELF-HOSTING COMPLETE!");
  console.log("=".repeat(50));
  console.log("\nwasm5 (wasm-gc) successfully:");
  console.log("  1. Parsed its own wasm-gc binary");
  console.log("  2. Compiled its own bytecode interpreter");
  console.log("  3. Executed its own alloc() function");
}

main().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
