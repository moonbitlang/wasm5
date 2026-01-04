// wasm-gc interpreter execution test
// Tests that wasm5 (wasm-gc build) can interpret and execute wasm modules
import { readFile } from 'fs/promises';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

function stringToBytes(str) {
  return new TextEncoder().encode(str);
}

async function main() {
  console.log("=== wasm5 (wasm-gc) Interpreter Test ===\n");

  // Load wasm-gc version
  const wasmPath = join(__dirname, '../../target/wasm-gc/release/build/cmd/wasm/wasm.wasm');
  const wasmBytes = await readFile(wasmPath);
  console.log(`Loaded wasm5 (wasm-gc): ${wasmBytes.length} bytes`);

  // Load add.wasm to test
  const addWasmPath = join(__dirname, 'add.wasm');
  const addWasmBytes = await readFile(addWasmPath);
  console.log(`Loaded add.wasm: ${addWasmBytes.length} bytes`);

  // Create memory and import object
  const memory = new WebAssembly.Memory({ initial: 256, maximum: 1024 });
  const importObject = {
    env: { memory },
    spectest: {
      print_char: (c) => process.stdout.write(String.fromCharCode(c))
    }
  };

  // Compile and instantiate
  const wasmModule = await WebAssembly.compile(wasmBytes);
  const wasmInstance = await WebAssembly.instantiate(wasmModule, importObject);
  console.log("wasm5 (wasm-gc) instantiated\n");

  const { _start, alloc, call_i32_i32_raw, call_i32_raw } = wasmInstance.exports;

  _start();

  // Allocate and copy add.wasm
  const wasmPtr = alloc(addWasmBytes.length);
  const wasmMemory = new Uint8Array(memory.buffer);
  wasmMemory.set(addWasmBytes, wasmPtr);
  console.log(`Copied add.wasm to address ${wasmPtr}`);

  // Test 1: add(3, 4)
  console.log("\n=== Test 1: add(3, 4) ===");
  const addName = stringToBytes("add");
  const namePtr = alloc(addName.length);
  new Uint8Array(memory.buffer).set(addName, namePtr);

  const result1 = call_i32_i32_raw(wasmPtr, addWasmBytes.length, namePtr, addName.length, 3, 4);
  console.log(`Result: ${result1}`);
  if (result1 === 7) {
    console.log("✓ PASS: add(3, 4) = 7");
  } else {
    console.log(`✗ FAIL: expected 7, got ${result1}`);
    process.exit(1);
  }

  // Test 2: double(21)
  console.log("\n=== Test 2: double(21) ===");
  const wasmPtr2 = alloc(addWasmBytes.length);
  new Uint8Array(memory.buffer).set(addWasmBytes, wasmPtr2);
  const doubleName = stringToBytes("double");
  const namePtr2 = alloc(doubleName.length);
  new Uint8Array(memory.buffer).set(doubleName, namePtr2);

  const result2 = call_i32_raw(wasmPtr2, addWasmBytes.length, namePtr2, doubleName.length, 21);
  console.log(`Result: ${result2}`);
  if (result2 === 42) {
    console.log("✓ PASS: double(21) = 42");
  } else {
    console.log(`✗ FAIL: expected 42, got ${result2}`);
    process.exit(1);
  }

  console.log("\n" + "=".repeat(50));
  console.log("wasm-gc INTERPRETER TEST PASSED!");
  console.log("=".repeat(50));
}

main().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
