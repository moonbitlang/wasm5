// Cross-target test: wasm-gc interprets linear wasm
// Tests that wasm5 (wasm-gc build) can interpret wasm5 (linear wasm build)
import { readFile } from 'fs/promises';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

function stringToBytes(str) {
  return new TextEncoder().encode(str);
}

async function main() {
  console.log("=== Cross-Target Test: wasm-gc interprets linear wasm ===\n");

  // Load wasm-gc version (outer interpreter)
  const wasmGcPath = join(__dirname, '../../target/wasm-gc/release/build/cmd/wasm/wasm.wasm');
  const wasmGcBytes = await readFile(wasmGcPath);
  console.log(`Loaded wasm5 (wasm-gc): ${wasmGcBytes.length} bytes`);

  // Load linear wasm version (to be interpreted)
  const wasmPath = join(__dirname, '../../target/wasm/release/build/cmd/wasm/wasm.wasm');
  const wasmBytes = await readFile(wasmPath);
  console.log(`Loaded wasm5 (linear wasm): ${wasmBytes.length} bytes`);

  // Create memory
  const memory = new WebAssembly.Memory({ initial: 512, maximum: 1024 });
  console.log(`Created memory: ${memory.buffer.byteLength / 1024 / 1024}MB`);

  const importObject = {
    env: { memory },
    spectest: {
      print_char: (c) => process.stdout.write(String.fromCharCode(c))
    }
  };

  // Compile and instantiate wasm-gc (outer)
  const wasmGcModule = await WebAssembly.compile(wasmGcBytes);
  const wasmGcInstance = await WebAssembly.instantiate(wasmGcModule, importObject);
  console.log("wasm5 (wasm-gc) outer instantiated\n");

  const { _start, alloc, parse_wasm_raw, run_wasm_raw, call_i32_raw } = wasmGcInstance.exports;

  _start();

  // Copy linear wasm into memory
  const wasmPtr = alloc(wasmBytes.length);
  new Uint8Array(memory.buffer).set(wasmBytes, wasmPtr);
  console.log(`Copied linear wasm to address ${wasmPtr}`);

  // Test 1: wasm-gc parses linear wasm
  console.log("\n" + "=".repeat(50));
  console.log("TEST 1: wasm-gc parses linear wasm");
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

  // Test 2: wasm-gc loads and compiles linear wasm
  console.log("\n" + "=".repeat(50));
  console.log("TEST 2: wasm-gc loads & compiles linear wasm");
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

  // Test 3: wasm-gc executes linear wasm's alloc()
  console.log("\n" + "=".repeat(50));
  console.log("TEST 3: wasm-gc executes linear wasm's alloc()");
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
  console.log("CROSS-TARGET TEST COMPLETE!");
  console.log("=".repeat(50));
  console.log("\nwasm5 (wasm-gc) successfully interpreted wasm5 (linear wasm):");
  console.log(`  - wasm-gc size: ${wasmGcBytes.length} bytes`);
  console.log(`  - linear wasm size: ${wasmBytes.length} bytes`);
}

main().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
