// Test wasm-gc build of wasm5
import { readFile } from 'fs/promises';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  console.log("=== wasm5 wasm-gc Build Test ===\n");

  // Load wasm-gc version
  const wasmPath = join(__dirname, '../../target/wasm-gc/release/build/cmd/wasm/wasm.wasm');
  const wasmBytes = await readFile(wasmPath);
  console.log(`Loaded wasm5 (wasm-gc): ${wasmBytes.length} bytes`);

  // Load simple.wasm to test
  const simpleWasmPath = join(__dirname, 'simple.wasm');
  const simpleWasmBytes = await readFile(simpleWasmPath);
  console.log(`Loaded simple.wasm: ${simpleWasmBytes.length} bytes`);

  // Create memory and import object
  const memory = new WebAssembly.Memory({ initial: 256, maximum: 1024 });
  const importObject = {
    env: { memory },
    spectest: {
      print_char: (c) => process.stdout.write(String.fromCharCode(c))
    }
  };

  // Compile and instantiate
  try {
    const wasmModule = await WebAssembly.compile(wasmBytes);
    console.log("\nwasm5 (wasm-gc) compiled successfully");

    const wasmInstance = await WebAssembly.instantiate(wasmModule, importObject);
    console.log("wasm5 (wasm-gc) instantiated successfully");

    console.log("\nExports:", Object.keys(wasmInstance.exports));

    // Check if parse_wasm exists (MoonBit-style interface)
    if (wasmInstance.exports.parse_wasm) {
      console.log("\nparse_wasm export found - wasm-gc uses MoonBit Bytes interface");
    }

    if (wasmInstance.exports._start) {
      wasmInstance.exports._start();
      console.log("_start() called successfully");
    }

  } catch (err) {
    console.error("Error:", err.message);
    process.exit(1);
  }

  console.log("\n" + "=".repeat(50));
  console.log("wasm-gc build test completed");
  console.log("=".repeat(50));
}

main().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
