///|
async fn collect_wasm_files(dir : String) -> Array[String] {
  let wasm_files : Array[String] = []
  let entries = @fs.readdir(dir)
  for entry in entries {
    if entry.has_suffix(".wasm") {
      wasm_files.push(entry)
    }
  }
  wasm_files
}

///|
async test {
  let files = collect_wasm_files("smith")
  for file in files {
    let path = @path.Path("smith").join(file).to_string()
    @stdio.stdout.write("Testing parse/validate of file: \{path}\n")
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    let bytes = file.read_all().binary()
    let _ = parse(bytes)

    // Successfully parsed and validated
  }
}
