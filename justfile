install:
  moon build cmd/main --target native --release
  cp _build/native/release/build/cmd/main/main.exe ~/.moon/bin/wasm5

run-wat WATFILE:
  wasm-tools parse {{WATFILE}} -o tmp.wasm  
  moon run cmd/main --target native --release -- run tmp.wasm
  rm tmp.wasm

fib-slow:
  moon run -C test/simple test/simple/fib.mbt --target wasm
  cp test/simple/_build/wasm/debug/build/single/single.wasm test/simple/fib_slow.wasm