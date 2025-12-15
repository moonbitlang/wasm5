install:
  moon build cmd/main --target native --release
  cp target/native/release/build/cmd/main/main.exe ~/.moon/bin/wasm5

run-wat WATFILE:
  wasm-tools parse {{WATFILE}} -o tmp.wasm  
  moon run cmd/main --target native --release -- run tmp.wasm
  rm tmp.wasm