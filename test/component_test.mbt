// ============================================================================
// Test Helper Functions
// ============================================================================

///|
/// Load a component from a file path
async fn load_component(path : String) -> @wasm5_core.Component raise Error {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let bytes = file.read_all().binary()
  @wasm5_parse.parse_component(bytes)
}

///|
/// Load and instantiate a component without imports
async fn load_and_instantiate(
  path : String,
) -> @wasm5_component.ComponentRuntime raise Error {
  let component = load_component(path)
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()
  rt
}

///|
/// Load and instantiate a component with imports
async fn load_and_instantiate_with_imports(
  path : String,
  resolver : @wasm5_component.ComponentImportResolver,
) -> @wasm5_component.ComponentRuntime raise Error {
  let component = load_component(path)
  let rt = @wasm5_component.ComponentRuntime::new_with_imports(
    component, resolver,
  )
  rt.instantiate()
  rt
}

///|
/// Shorthand for creating S32 component value
fn s32(n : Int) -> @wasm5_component.ComponentValue {
  @wasm5_component.ComponentValue::S32(n)
}

///|
/// Shorthand for creating U32 component value
fn u32(n : UInt) -> @wasm5_component.ComponentValue {
  @wasm5_component.ComponentValue::U32(n)
}

// ============================================================================
// Component Execution Tests
// ============================================================================

///|
async test "execute component with imports" {
  let resolver = @wasm5_component.ComponentImportResolver::new()
  resolver.add_func("host:math", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match (args[0], args[1]) {
        (S32(a), S32(b)) => [s32(a + b)]
        _ => []
      }
    },
  })
  let rt = load_and_instantiate_with_imports(
    "test/component/with-import.wasm", resolver,
  )
  let result = rt.call("compute", [s32(5)])
  assert_eq(result, [s32(15)])
}

///|
async test "execute component with start section" {
  let rt = load_and_instantiate("test/component/with-start.wasm")
  let result = rt.call("is-initialized", [])
  assert_eq(result, [s32(1)])
}

///|
async test "execute simple component with add function" {
  let rt = load_and_instantiate("test/component/with-canon.wasm")
  let result = rt.call("add", [s32(3), s32(5)])
  assert_eq(result, [s32(8)])
}

// ============================================================================
// Unified Import Resolver Tests
// ============================================================================

///|
/// Helper: Create a simple Module that exports an add function
fn make_add_module() -> @wasm5_core.Module {
  // func add(a: i32, b: i32) -> i32 { return a + b }
  let func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  let code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::I32Add,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  @wasm5_core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @wasm5_core.Export::{
        name: b"add",
        desc: @wasm5_core.ExportDesc::Func(0U),
      },
    ],
    codes: [code],
  }
}

///|
/// Helper: Create a Module that imports a function and calls it
fn make_import_module(
  import_module : Bytes,
  import_name : Bytes,
) -> @wasm5_core.Module {
  // Import type: (i32, i32) -> i32
  let func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  // Local function that calls the imported function with extra offset
  // func use_imported(a: i32, b: i32) -> i32 { return imported(a + 1, b + 2) }
  let code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::I32Const(1U),
        @wasm5_core.Instr::I32Add,
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::I32Const(2U),
        @wasm5_core.Instr::I32Add,
        @wasm5_core.Instr::Call(0U), // Call imported function (index 0)
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let import_ : @wasm5_core.Import = {
    module_: import_module,
    name: import_name,
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  @wasm5_core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U], // One local function (plus one imported)
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_],
    exports: [
      @wasm5_core.Export::{
        name: b"use_imported",
        desc: @wasm5_core.ExportDesc::Func(1U),
      },
    ],
    codes: [code],
  }
}

///|
test "unified resolver: module imports from another module" {
  // Create a provider module (exports "add")
  let provider = make_add_module()
  let provider_rt = @wasm5_runtime.Runtime::load(provider)
  let provider_exec = @wasm5_component.WasmExecutable::Module(provider_rt)

  // Register provider module in unified resolver
  let unified = @wasm5_component.UnifiedImportResolver::new()
  unified.register("math", provider_exec)

  // Create consumer module that imports "math"."add"
  let consumer = make_import_module(b"math", b"add")

  // Load consumer with unified resolver
  let mod_resolver = unified.to_module_resolver()
  let consumer_rt = @wasm5_runtime.Runtime::load_with_resolver(
    consumer, mod_resolver,
  )

  // Call use_imported(3, 5) = imported(3+1, 5+2) = imported(4, 7) = 4 + 7 = 11
  let results = consumer_rt.call_compiled(b"use_imported", [
    @wasm5_runtime.Value::I32(3U),
    @wasm5_runtime.Value::I32(5U),
  ])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(11U))
}

///|
async test "unified resolver: module imports from component" {
  // Load component with-canon.wasm (exports "add")
  let component = load_component("test/component/with-canon.wasm")
  let comp_rt = @wasm5_component.ComponentRuntime::new(component)
  comp_rt.instantiate()
  let comp_exec = @wasm5_component.WasmExecutable::Component(comp_rt)

  // Register component in unified resolver
  let unified = @wasm5_component.UnifiedImportResolver::new()
  unified.register("calc", comp_exec)

  // Create consumer module that imports "calc"."add"
  let consumer = make_import_module(b"calc", b"add")

  // Load consumer with unified resolver
  let mod_resolver = unified.to_module_resolver()
  let consumer_rt = @wasm5_runtime.Runtime::load_with_resolver(
    consumer, mod_resolver,
  )

  // Call use_imported(3, 5) = imported(3+1, 5+2) = imported(4, 7) = 4 + 7 = 11
  let results = consumer_rt.call_compiled(b"use_imported", [
    @wasm5_runtime.Value::I32(3U),
    @wasm5_runtime.Value::I32(5U),
  ])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(11U))
}

///|
test "unified resolver: host function for module" {
  // Create unified resolver with a host function
  let unified = @wasm5_component.UnifiedImportResolver::new()
  unified.add_host_func("host", "double", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match args[0] {
        @wasm5_component.ComponentValue::S32(n) =>
          [@wasm5_component.ComponentValue::S32(n * 2)]
        _ => []
      }
    },
  })

  // Create a module that imports host.double and uses it
  let func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  let code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [@wasm5_core.Instr::LocalGet(0U), @wasm5_core.Instr::Call(0U)],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let import_ : @wasm5_core.Import = {
    module_: b"host",
    name: b"double",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let module_ : @wasm5_core.Module = {
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_],
    exports: [
      @wasm5_core.Export::{
        name: b"call_double",
        desc: @wasm5_core.ExportDesc::Func(1U),
      },
    ],
    codes: [code],
  }

  // Load module with unified resolver
  let mod_resolver = unified.to_module_resolver()
  let rt = @wasm5_runtime.Runtime::load_with_resolver(module_, mod_resolver)

  // Call call_double(7) = double(7) = 14
  let results = rt.call_compiled(b"call_double", [@wasm5_runtime.Value::I32(7U)])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(14U))
}

///|
async test "unified resolver: component imports from module" {
  // Create provider module (exports "add")
  let provider = make_add_module()
  let provider_rt = @wasm5_runtime.Runtime::load(provider)
  // Compile provider upfront

  // Register provider in unified resolver with name that matches component import
  let unified = @wasm5_component.UnifiedImportResolver::new()
  // The component with-import.wasm imports "host:math" which expects an "add" function
  // We register our module's add function under that name
  unified.add_host_func("", "host:math", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match (args[0], args[1]) {
        (
          @wasm5_component.ComponentValue::S32(a),
          @wasm5_component.ComponentValue::S32(b),
        ) => {
          // Call the provider's add function (already compiled)
          let results = provider_rt.call_compiled(b"add", [
            @wasm5_runtime.Value::I32(a.reinterpret_as_uint()),
            @wasm5_runtime.Value::I32(b.reinterpret_as_uint()),
          ]) catch {
            _ => return []
          }
          match results[0] {
            @wasm5_runtime.Value::I32(n) =>
              [@wasm5_component.ComponentValue::S32(n.reinterpret_as_int())]
            _ => []
          }
        }
        _ => []
      }
    },
  })

  // Load with-import.wasm which imports "host:math" add function
  let file = @fs.open("test/component/with-import.wasm", mode=ReadOnly)
  defer file.close()
  let bytes = file.read_all().binary()
  let comp_resolver = unified.to_component_resolver()
  let component = @wasm5_parse.parse_component(bytes)
  let rt = @wasm5_component.ComponentRuntime::new_with_imports(
    component, comp_resolver,
  )
  rt.instantiate()

  // Call compute(5) which should call add(5, 10) = 15
  let result = rt.call("compute", [s32(5)])
  assert_eq(result, [s32(15)])
}

// ============================================================================
// Cross-call Tests: Module <-> Component mutual invocation
// ============================================================================

///|
/// Helper: Create a Module that imports "math"."add" and exports "double_add"
/// double_add(a, b) = add(a, b) * 2
fn make_module_double_add() -> @wasm5_core.Module {
  // Import type: (i32, i32) -> i32
  let func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  // double_add(a, b) = add(a, b) * 2
  let code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(0U), // Call imported add
        @wasm5_core.Instr::I32Const(2U),
        @wasm5_core.Instr::I32Mul,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let import_ : @wasm5_core.Import = {
    module_: b"math",
    name: b"add",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  @wasm5_core.Module::{
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_],
    exports: [
      @wasm5_core.Export::{
        name: b"double_add",
        desc: @wasm5_core.ExportDesc::Func(1U),
      },
    ],
    codes: [code],
  }
}

///|
async test "cross-call: Module -> Component -> Module chain" {
  // Chain: consumer_module -> component(add)
  //
  // 1. component exports "add(a, b) = a + b" (with-canon.wasm has its own core module)
  // 2. consumer_module imports "math"."add" from component, exports "double_add"
  //
  // Flow: double_add(3, 5) -> component.add(3, 5) = 8 -> 8 * 2 = 16

  // Step 1: Load component (with-canon.wasm exports "add")
  let component = load_component("test/component/with-canon.wasm")
  let comp_rt = @wasm5_component.ComponentRuntime::new(component)
  comp_rt.instantiate()

  // Step 2: Register component in unified resolver with name "math"
  // (consumer module imports from "math"."add")
  let unified = @wasm5_component.UnifiedImportResolver::new()
  unified.register("math", @wasm5_component.WasmExecutable::Component(comp_rt))

  // Step 3: Create consumer module that uses component's add
  let consumer = make_module_double_add()
  let mod_resolver = unified.to_module_resolver()
  let consumer_rt = @wasm5_runtime.Runtime::load_with_resolver(
    consumer, mod_resolver,
  )

  // Call double_add(3, 5) = add(3, 5) * 2 = 8 * 2 = 16
  let results = consumer_rt.call_compiled(b"double_add", [
    @wasm5_runtime.Value::I32(3U),
    @wasm5_runtime.Value::I32(5U),
  ])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(16U))
}

///|
test "cross-call: Module A -> Module B -> Module C chain" {
  // Chain: A calls B, B calls C
  //
  // C: add(a, b) = a + b
  // B: imports C.add, exports double_add(a, b) = add(a, b) * 2
  // A: imports B.double_add, exports quad_add(a, b) = double_add(a, b) * 2
  //
  // quad_add(3, 5) -> double_add(3, 5) -> add(3, 5) = 8 -> 8 * 2 = 16 -> 16 * 2 = 32

  // Module C: base add
  let module_c = make_add_module()
  let rt_c = @wasm5_runtime.Runtime::load(module_c)

  // Module B: imports from C, double_add
  let unified_b = @wasm5_component.UnifiedImportResolver::new()
  unified_b.register("math", @wasm5_component.WasmExecutable::Module(rt_c))
  let resolver_b = unified_b.to_module_resolver()
  let module_b = make_module_double_add()
  let rt_b = @wasm5_runtime.Runtime::load_with_resolver(module_b, resolver_b)

  // Module A: imports from B, quad_add
  // quad_add(a, b) = double_add(a, b) * 2
  let func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  let code_a : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(0U), // Call imported double_add
        @wasm5_core.Instr::I32Const(2U),
        @wasm5_core.Instr::I32Mul,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let import_a : @wasm5_core.Import = {
    module_: b"helper",
    name: b"double_add",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let module_a : @wasm5_core.Module = {
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_a],
    exports: [
      @wasm5_core.Export::{
        name: b"quad_add",
        desc: @wasm5_core.ExportDesc::Func(1U),
      },
    ],
    codes: [code_a],
  }
  let unified_a = @wasm5_component.UnifiedImportResolver::new()
  unified_a.register("helper", @wasm5_component.WasmExecutable::Module(rt_b))
  let resolver_a = unified_a.to_module_resolver()
  let rt_a = @wasm5_runtime.Runtime::load_with_resolver(module_a, resolver_a)

  // Call quad_add(3, 5)
  // = double_add(3, 5) * 2
  // = (add(3, 5) * 2) * 2
  // = (8 * 2) * 2
  // = 16 * 2
  // = 32
  let results = rt_a.call_compiled(b"quad_add", [
    @wasm5_runtime.Value::I32(3U),
    @wasm5_runtime.Value::I32(5U),
  ])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(32U))
}

///|
async test "cross-call: bidirectional Module <-> Component" {
  // Test bidirectional calls:
  // 1. Module exports "multiply(a, b) = a * b"
  // 2. Component exports "add(a, b) = a + b"
  // 3. Another Module imports both and computes: combined(a, b) = add(a, b) + multiply(a, b)
  //
  // combined(3, 5) = add(3, 5) + multiply(3, 5) = 8 + 15 = 23

  // Module: multiply
  let mul_func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  let mul_code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::I32Mul,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let mul_module : @wasm5_core.Module = {
    types: [mul_func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [
      @wasm5_core.Export::{
        name: b"multiply",
        desc: @wasm5_core.ExportDesc::Func(0U),
      },
    ],
    codes: [mul_code],
  }
  let mul_rt = @wasm5_runtime.Runtime::load(mul_module)

  // Component: add (from with-canon.wasm)
  let component = load_component("test/component/with-canon.wasm")
  let comp_rt = @wasm5_component.ComponentRuntime::new(component)
  comp_rt.instantiate()

  // Consumer module: imports both add (from component) and multiply (from module)
  // combined(a, b) = add(a, b) + multiply(a, b)
  let combined_func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  let combined_code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        // add(a, b)
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(0U), // imported add at index 0
        // multiply(a, b)
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(1U), // imported multiply at index 1
        // add results
        @wasm5_core.Instr::I32Add,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let import_add : @wasm5_core.Import = {
    module_: b"comp",
    name: b"add",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let import_mul : @wasm5_core.Import = {
    module_: b"mod",
    name: b"multiply",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let combined_module : @wasm5_core.Module = {
    types: [combined_func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_add, import_mul],
    exports: [
      @wasm5_core.Export::{
        name: b"combined",
        desc: @wasm5_core.ExportDesc::Func(2U),
      },
    ],
    codes: [combined_code],
  }

  // Register both in unified resolver
  let unified = @wasm5_component.UnifiedImportResolver::new()
  unified.register("comp", @wasm5_component.WasmExecutable::Component(comp_rt))
  unified.register("mod", @wasm5_component.WasmExecutable::Module(mul_rt))
  let resolver = unified.to_module_resolver()
  let combined_rt = @wasm5_runtime.Runtime::load_with_resolver(
    combined_module, resolver,
  )

  // Call combined(3, 5) = add(3, 5) + multiply(3, 5) = 8 + 15 = 23
  let results = combined_rt.call_compiled(b"combined", [
    @wasm5_runtime.Value::I32(3U),
    @wasm5_runtime.Value::I32(5U),
  ])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(23U))
}

///|
test "cross-call: unified WasmExecutable call interface" {
  // Test that WasmExecutable::call works uniformly for both Module and Component
  // using the unified load function

  // Create a simple add module
  let module_ = make_add_module()
  let rt = @wasm5_runtime.Runtime::load(module_)
  let exec = @wasm5_component.WasmExecutable::Module(rt)

  // Call via unified interface
  let results = exec.call("add", [s32(10), s32(20)])
  assert_eq(results.length(), 1)
  assert_eq(results[0], s32(30))
}

///|
async test "cross-call: Module calls calculator component" {
  // Test Module importing calculator.wasm's add, sub, mul functions
  // Module computes: compute(a, b) = add(a, b) + mul(a, b) - sub(a, b)
  // compute(10, 3) = add(10, 3) + mul(10, 3) - sub(10, 3)
  //                = 13 + 30 - 7 = 36

  // Load calculator component
  let component = load_component("test/component/calculator.wasm")
  let calc_rt = @wasm5_component.ComponentRuntime::new(component)
  calc_rt.instantiate()

  // Register calculator component
  let unified = @wasm5_component.UnifiedImportResolver::new()
  unified.register("calc", @wasm5_component.WasmExecutable::Component(calc_rt))

  // Create Module that imports calc.add, calc.sub, calc.mul
  // compute(a, b) = add(a, b) + mul(a, b) - sub(a, b)
  let func_type : @wasm5_core.TypeDef = @wasm5_core.TypeDef::Func(@wasm5_core.FuncType::{
    params: [@wasm5_core.ValType::I32, @wasm5_core.ValType::I32],
    results: [@wasm5_core.ValType::I32],
  })
  let code : @wasm5_core.Code = {
    locals: [],
    body: @wasm5_core.Expr::{
      instrs: [
        // add(a, b)
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(0U),
        // mul(a, b)
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(2U),
        // add + mul
        @wasm5_core.Instr::I32Add,
        // sub(a, b)
        @wasm5_core.Instr::LocalGet(0U),
        @wasm5_core.Instr::LocalGet(1U),
        @wasm5_core.Instr::Call(1U),
        // (add + mul) - sub
        @wasm5_core.Instr::I32Sub,
      ],
    },
    compiled: None,
    max_stack_height: 0,
  }
  let import_add : @wasm5_core.Import = {
    module_: b"calc",
    name: b"add",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let import_sub : @wasm5_core.Import = {
    module_: b"calc",
    name: b"sub",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let import_mul : @wasm5_core.Import = {
    module_: b"calc",
    name: b"mul",
    desc: @wasm5_core.ImportDesc::Func(0U),
  }
  let module_ : @wasm5_core.Module = {
    types: [func_type],
    type_groups: [],
    customs: [],
    funcs: [0U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [import_add, import_sub, import_mul],
    exports: [
      @wasm5_core.Export::{
        name: b"compute",
        desc: @wasm5_core.ExportDesc::Func(3U),
      },
    ],
    codes: [code],
  }

  // Load module with unified resolver
  let resolver = unified.to_module_resolver()
  let rt = @wasm5_runtime.Runtime::load_with_resolver(module_, resolver)

  // Call compute(10, 3) = add(10, 3) + mul(10, 3) - sub(10, 3) = 13 + 30 - 7 = 36
  let results = rt.call_compiled(b"compute", [
    @wasm5_runtime.Value::I32(10U),
    @wasm5_runtime.Value::I32(3U),
  ])
  assert_eq(results.length(), 1)
  assert_eq(results[0], @wasm5_runtime.Value::I32(36U))
}

///|
async test "canonical ABI: string length" {
  // Test passing a string to a component function
  // The string-length component returns the byte length of the input string

  let component = load_component("test/component/string-length.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Call string-length with "hello" (5 bytes)
  let result = rt.call("string-length", [
    @wasm5_component.ComponentValue::String("hello"),
  ])

  // With type information, lift returns the correct type (u32 as defined in WAT)
  assert_eq(result, [u32(5U)])
}

///|
async test "canonical ABI: string with unicode" {
  // Test string with unicode characters
  let component = load_component("test/component/string-length.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Call string-length with "日本語" (9 bytes in UTF-8: 3 chars * 3 bytes each)
  let result = rt.call("string-length", [
    @wasm5_component.ComponentValue::String("日本語"),
  ])
  assert_eq(result, [u32(9U)])
}

///|
async test "canonical ABI: string echo (return string)" {
  // Test returning a string from a component function
  let component = load_component("test/component/string-echo.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Call echo with "hello world"
  let result = rt.call("echo", [
    @wasm5_component.ComponentValue::String("hello world"),
  ])
  assert_eq(result, [@wasm5_component.ComponentValue::String("hello world")])
}

///|
async test "cross-call: unified WasmExecutable call for component" {
  // Test that WasmExecutable::call works for Component too

  let component = load_component("test/component/with-canon.wasm")
  let comp_rt = @wasm5_component.ComponentRuntime::new(component)
  comp_rt.instantiate()
  let exec = @wasm5_component.WasmExecutable::Component(comp_rt)

  // Call via unified interface
  let results = exec.call("add", [s32(10), s32(20)])
  assert_eq(results.length(), 1)
  assert_eq(results[0], s32(30))
}

///|
async test "canonical ABI: list" {
  let component = load_component("test/component/list-sum.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Sum of [1, 2, 3, 4, 5] = 15
  assert_eq(
    rt.call("sum", [
      @wasm5_component.ComponentValue::List([
        s32(1),
        s32(2),
        s32(3),
        s32(4),
        s32(5),
      ]),
    ]),
    [s32(15)],
  )
  // Empty list = 0
  assert_eq(rt.call("sum", [@wasm5_component.ComponentValue::List([])]), [
    s32(0),
  ])
}

///|
async test "canonical ABI: record distance squared" {
  // Test passing a record to a component function
  // The record-point component calculates x*x + y*y for a point record

  let component = load_component("test/component/record-point.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Call distance-squared with point (3, 4) = 3*3 + 4*4 = 9 + 16 = 25
  let result = rt.call("distance-squared", [
    @wasm5_component.ComponentValue::Record([("x", s32(3)), ("y", s32(4))]),
  ])
  assert_eq(result, [s32(25)])
}

///|
async test "canonical ABI: record add points" {
  // Test passing two records and getting a record back
  // add_points(p1, p2) = {x: p1.x + p2.x, y: p1.y + p2.y}

  let component = load_component("test/component/record-point.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Call add-points with (1, 2) + (3, 4) = (4, 6)
  let result = rt.call("add-points", [
    @wasm5_component.ComponentValue::Record([("x", s32(1)), ("y", s32(2))]),
    @wasm5_component.ComponentValue::Record([("x", s32(3)), ("y", s32(4))]),
  ])

  // With type information, record is lifted as a proper Record
  assert_eq(result, [
    @wasm5_component.ComponentValue::Record([("x", s32(4)), ("y", s32(6))]),
  ])
}

///|
async test "canonical ABI: option types" {
  let component = load_component("test/component/option-double.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Some value
  assert_eq(
    rt.call("double-option", [
      @wasm5_component.ComponentValue::OptionSome(s32(21)),
    ]),
    [@wasm5_component.ComponentValue::OptionSome(s32(42))],
  )
  // None value
  assert_eq(
    rt.call("double-option", [@wasm5_component.ComponentValue::OptionNone]),
    [@wasm5_component.ComponentValue::OptionNone],
  )
  // Zero value (edge case)
  assert_eq(
    rt.call("double-option", [
      @wasm5_component.ComponentValue::OptionSome(s32(0)),
    ]),
    [@wasm5_component.ComponentValue::OptionSome(s32(0))],
  )
  // Negative value
  assert_eq(
    rt.call("double-option", [
      @wasm5_component.ComponentValue::OptionSome(s32(-5)),
    ]),
    [@wasm5_component.ComponentValue::OptionSome(s32(-10))],
  )
}

///|
async test "canonical ABI: result types" {
  let component = load_component("test/component/result-divide.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Ok case: 10 / 2 = 5
  assert_eq(rt.call("safe-divide", [s32(10), s32(2)]), [
    @wasm5_component.ComponentValue::ResultOk(Some(s32(5))),
  ])
  // Err case: division by zero
  assert_eq(rt.call("safe-divide", [s32(10), s32(0)]), [
    @wasm5_component.ComponentValue::ResultErr(Some(s32(0))),
  ])
  // Large numbers: 100 / 7 = 14
  assert_eq(rt.call("safe-divide", [s32(100), s32(7)]), [
    @wasm5_component.ComponentValue::ResultOk(Some(s32(14))),
  ])
  // Negative numbers: -20 / 4 = -5
  assert_eq(rt.call("safe-divide", [s32(-20), s32(4)]), [
    @wasm5_component.ComponentValue::ResultOk(Some(s32(-5))),
  ])
}

///|
async test "canonical ABI: enum" {
  let component = load_component("test/component/enum-color.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Cycle through all enum values: red -> green -> blue -> red
  assert_eq(
    rt.call("next-color", [@wasm5_component.ComponentValue::Enum(0, "red")]),
    [@wasm5_component.ComponentValue::Enum(1, "green")],
  )
  assert_eq(
    rt.call("next-color", [@wasm5_component.ComponentValue::Enum(1, "green")]),
    [@wasm5_component.ComponentValue::Enum(2, "blue")],
  )
  assert_eq(
    rt.call("next-color", [@wasm5_component.ComponentValue::Enum(2, "blue")]),
    [@wasm5_component.ComponentValue::Enum(0, "red")],
  )
}

///|
async test "canonical ABI: flags" {
  let component = load_component("test/component/flags-permissions.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // toggle-read: empty -> ["read"]
  assert_eq(
    rt.call("toggle-read", [@wasm5_component.ComponentValue::Flags([])]),
    [@wasm5_component.ComponentValue::Flags(["read"])],
  )
  // toggle-read: ["read"] -> [] (toggle off)
  assert_eq(
    rt.call("toggle-read", [@wasm5_component.ComponentValue::Flags(["read"])]),
    [@wasm5_component.ComponentValue::Flags([])],
  )
  // has-write: ["read", "write"] -> true
  assert_eq(
    rt.call("has-write", [
      @wasm5_component.ComponentValue::Flags(["read", "write"]),
    ]),
    [@wasm5_component.ComponentValue::Bool(true)],
  )
  // has-write: empty -> false
  assert_eq(
    rt.call("has-write", [@wasm5_component.ComponentValue::Flags([])]),
    [@wasm5_component.ComponentValue::Bool(false)],
  )
}

///|
test "resource table operations" {
  // Test basic resource table operations without a component
  // Create a minimal component for testing
  let component = @wasm5_core.Component::{ sections: [] }
  let rt = @wasm5_component.ComponentRuntime::new(component)

  // Test resource_new
  let handle1 = rt.resource_new(0U, 42U)
  assert_eq(handle1, 0)

  // Test resource_rep
  let rep1 = rt.resource_rep(handle1)
  assert_eq(rep1, 42)

  // Create another resource
  let handle2 = rt.resource_new(0U, 100U)
  assert_eq(handle2, 1)
  let rep2 = rt.resource_rep(handle2)
  assert_eq(rep2, 100)

  // Test resource_drop
  let dropped = rt.resource_drop(handle1)
  assert_eq(dropped, Some(42))

  // Verify handle1 is now invalid
  let should_fail = try {
    let _ = rt.resource_rep(handle1)
    false // Should not reach here
  } catch {
    _ => true // Expected to fail
  }
  assert_true(should_fail)

  // But handle2 should still be valid
  let rep2_again = rt.resource_rep(handle2)
  assert_eq(rep2_again, 100)
}

///|
test "resource borrow operations" {
  let component = @wasm5_core.Component::{ sections: [] }
  let rt = @wasm5_component.ComponentRuntime::new(component)

  // Create an owned resource
  let owned_handle = rt.resource_new(0U, 55U)
  assert_eq(owned_handle, 0)

  // Create a borrow from the owned handle
  let borrow_handle = rt.resource_borrow(owned_handle)
  assert_eq(borrow_handle, 1)

  // Both should return the same rep
  let owned_rep = rt.resource_rep(owned_handle)
  assert_eq(owned_rep, 55)
  let borrow_rep = rt.resource_rep(borrow_handle)
  assert_eq(borrow_rep, 55)

  // Dropping a borrow should not return rep
  let borrow_drop_result = rt.resource_drop(borrow_handle)
  assert_eq(borrow_drop_result, None)

  // Owned should still be valid
  let owned_rep_after = rt.resource_rep(owned_handle)
  assert_eq(owned_rep_after, 55)

  // Now drop the owned handle
  let owned_drop_result = rt.resource_drop(owned_handle)
  assert_eq(owned_drop_result, Some(55))
}

///|
test "ComponentValue Own and Borrow" {
  // Test Own and Borrow component value creation and type inference
  let own_val = @wasm5_component.ComponentValue::Own(0U, 42U)
  assert_eq(own_val, @wasm5_component.ComponentValue::Own(0U, 42U))
  let borrow_val = @wasm5_component.ComponentValue::Borrow(1U, 100U)
  assert_eq(borrow_val, @wasm5_component.ComponentValue::Borrow(1U, 100U))
}

///|
async test "composed component with nested instantiation" {
  // Load composed.wasm which has:
  // - An inner component that provides "add"
  // - An outer component that uses the inner's add to implement "double-add"
  let component = load_component("test/component/composed.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Call double-add(3, 4) which should return (3 + 4) * 2 = 14
  let result = rt.call("double-add", [s32(3), s32(4)])
  assert_eq(result, [s32(14)])
}

///|
async test "multi-nested component composition" {
  // Load multi-nested.wasm which has:
  // - Three inner components (adder, subber, multiplier)
  // - An outer that computes diff-squares(a, b) = (a+b) * (a-b) = a² - b²
  let component = load_component("test/component/multi-nested.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // diff-squares(5, 3) = (5+3) * (5-3) = 8 * 2 = 16
  // Also equals 5² - 3² = 25 - 9 = 16
  let result = rt.call("diff-squares", [s32(5), s32(3)])
  assert_eq(result, [s32(16)])
}

///|
async test "multi-nested component with larger values" {
  let component = load_component("test/component/multi-nested.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // diff-squares(10, 6) = (10+6) * (10-6) = 16 * 4 = 64
  // Also equals 10² - 6² = 100 - 36 = 64
  let result = rt.call("diff-squares", [s32(10), s32(6)])
  assert_eq(result, [s32(64)])
}

///|
test "resource double drop error" {
  // Test that dropping a resource twice raises an error
  let component = @wasm5_core.Component::{ sections: [] }
  let rt = @wasm5_component.ComponentRuntime::new(component)
  let handle = rt.resource_new(0U, 42U)

  // First drop should succeed
  let first_drop = rt.resource_drop(handle) catch { _ => None }
  assert_eq(first_drop, Some(42))

  // Second drop should fail
  let second_drop_failed = try {
    let _ = rt.resource_drop(handle)
    false
  } catch {
    _ => true
  }
  assert_true(second_drop_failed)
}

///|
test "resource rep after drop error" {
  // Test that getting rep of dropped resource raises an error
  let component = @wasm5_core.Component::{ sections: [] }
  let rt = @wasm5_component.ComponentRuntime::new(component)
  let handle = rt.resource_new(0U, 99U)

  // Rep should work before drop
  let rep_before = rt.resource_rep(handle) catch { _ => 0U }
  assert_eq(rep_before, 99)

  // Drop the resource
  let _ = rt.resource_drop(handle) catch { _ => None }

  // Rep should fail after drop
  let rep_after_failed = try {
    let _ = rt.resource_rep(handle)
    false
  } catch {
    _ => true
  }
  assert_true(rep_after_failed)
}

///|
test "multiple resources independent lifecycle" {
  // Test that multiple resources can be created and dropped independently
  let component = @wasm5_core.Component::{ sections: [] }
  let rt = @wasm5_component.ComponentRuntime::new(component)

  // Create three resources
  let h1 = rt.resource_new(0U, 10U)
  let h2 = rt.resource_new(0U, 20U)
  let h3 = rt.resource_new(0U, 30U)
  assert_eq(h1, 0)
  assert_eq(h2, 1)
  assert_eq(h3, 2)

  // Drop h2 first
  let drop2 = rt.resource_drop(h2) catch { _ => None }
  assert_eq(drop2, Some(20))

  // h1 and h3 should still work
  let rep1 = rt.resource_rep(h1) catch { _ => 0U }
  let rep3 = rt.resource_rep(h3) catch { _ => 0U }
  assert_eq(rep1, 10)
  assert_eq(rep3, 30)

  // h2 should not work
  let h2_failed = try {
    let _ = rt.resource_rep(h2)
    false
  } catch {
    _ => true
  }
  assert_true(h2_failed)

  // Drop h1
  let drop1 = rt.resource_drop(h1) catch { _ => None }
  assert_eq(drop1, Some(10))

  // h3 should still work
  let rep3_again = rt.resource_rep(h3) catch { _ => 0U }
  assert_eq(rep3_again, 30)

  // Drop h3
  let drop3 = rt.resource_drop(h3) catch { _ => None }
  assert_eq(drop3, Some(30))
}

///|
test "borrow does not extend owned lifetime" {
  // Test that dropping owned resource invalidates borrows
  let component = @wasm5_core.Component::{ sections: [] }
  let rt = @wasm5_component.ComponentRuntime::new(component)
  let owned = rt.resource_new(0U, 77U)
  let borrowed = rt.resource_borrow(owned) catch { _ => 0U }

  // Both should work
  let owned_rep = rt.resource_rep(owned) catch { _ => 0U }
  let borrowed_rep = rt.resource_rep(borrowed) catch { _ => 0U }
  assert_eq(owned_rep, 77)
  assert_eq(borrowed_rep, 77)

  // Drop borrowed first (does not return rep for borrows)
  let borrow_drop = rt.resource_drop(borrowed) catch { _ => None }
  assert_eq(borrow_drop, None)

  // Owned should still work
  let owned_rep2 = rt.resource_rep(owned) catch { _ => 0U }
  assert_eq(owned_rep2, 77)

  // Borrowed should not work after drop
  let borrowed_failed = try {
    let _ = rt.resource_rep(borrowed)
    false
  } catch {
    _ => true
  }
  assert_true(borrowed_failed)
}

///|
async test "variant with different cases" {
  let component = load_component("test/component/variant-shape.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Test circle: area = radius * radius * 3
  // Circle with radius 4: area = 4 * 4 * 3 = 48
  let circle_result = rt.call("area", [
    @wasm5_component.ComponentValue::Variant(0, "circle", Some(s32(4))),
  ])
  assert_eq(circle_result, [s32(48)])

  // Test rectangle: area = width * height
  // Rectangle 3x5: area = 15
  let rect_result = rt.call("area", [
    @wasm5_component.ComponentValue::Variant(
      1,
      "rectangle",
      Some(@wasm5_component.ComponentValue::Tuple([s32(3), s32(5)])),
    ),
  ])
  assert_eq(rect_result, [s32(15)])
}

///|
async test "memory export between core modules" {
  // Test that memory can be exported from one core module and imported by another
  let component = load_component("test/component/memory-export.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Write value 21 to offset 0
  let _ = rt.call("write", [s32(0), s32(21)])

  // Read value from offset 0 - should be 21
  let read1 = rt.call("read", [s32(0)])
  assert_eq(read1, [s32(21)])

  // Double the value at offset 0 (consumer uses shared memory)
  let _ = rt.call("double", [s32(0)])

  // Read again - should be 42 (21 * 2)
  let read2 = rt.call("read", [s32(0)])
  assert_eq(read2, [s32(42)])
}

// ============================================================================
// Calculator Component Tests
// ============================================================================

///|
async test "calculator component: all operations" {
  let component = load_component("test/component/calculator.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Basic operations
  assert_eq(rt.call("add", [s32(3), s32(5)]), [s32(8)])
  assert_eq(rt.call("sub", [s32(10), s32(3)]), [s32(7)])
  assert_eq(rt.call("mul", [s32(4), s32(7)]), [s32(28)])

  // Edge cases: negative numbers
  assert_eq(rt.call("add", [s32(-5), s32(3)]), [s32(-2)])
  assert_eq(rt.call("sub", [s32(3), s32(10)]), [s32(-7)])
  assert_eq(rt.call("mul", [s32(-3), s32(4)]), [s32(-12)])

  // Edge cases: zero
  assert_eq(rt.call("add", [s32(0), s32(5)]), [s32(5)])
  assert_eq(rt.call("mul", [s32(0), s32(100)]), [s32(0)])
}

///|
async test "introspection: get_func_names and get_export_names" {
  let component = load_component("test/component/calculator.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Test get_export_names
  let export_names = rt.get_export_names()
  // calculator.wasm exports: add, sub, mul
  assert_true(export_names.contains("add"))
  assert_true(export_names.contains("sub"))
  assert_true(export_names.contains("mul"))

  // Test get_func_names - should return all functions with their kinds
  let func_names = rt.get_func_names()
  assert_true(func_names.length() > 0)

  // Verify each function has index, name, and kind
  for info in func_names {
    let (idx, name, kind) = info
    assert_true(idx >= 0)
    assert_true(name.length() > 0)
    assert_true(kind == "lifted" || kind == "imported")
  }

  // Test get_func_name by index
  for info in func_names {
    let (idx, expected_name, _) = info
    let name = rt.get_func_name(idx.reinterpret_as_uint())
    match name {
      Some(n) => assert_eq(n, expected_name)
      None => assert_true(false) // should not happen
    }
  }

  // Test get_func_name with invalid index
  let invalid_name = rt.get_func_name(9999U)
  assert_true(invalid_name is None)
}

///|
async test "introspection: imported function names" {
  let component = load_component("test/component/with-import.wasm")

  // Create resolver with a host function (must match import name in with-import.wasm)
  let resolver = @wasm5_component.ComponentImportResolver::new()
  resolver.add_func("host:math", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match (args[0], args[1]) {
        (
          @wasm5_component.ComponentValue::S32(a),
          @wasm5_component.ComponentValue::S32(b),
        ) => [@wasm5_component.ComponentValue::S32(a + b)]
        _ => []
      }
    },
  })
  let rt = @wasm5_component.ComponentRuntime::new_with_imports(
    component, resolver,
  )
  rt.instantiate()

  // Check that get_func_names includes imported functions
  let func_names = rt.get_func_names()
  let mut has_imported = false
  for info in func_names {
    let (_, _, kind) = info
    if kind == "imported" {
      has_imported = true
      break
    }
  }
  assert_true(has_imported)
}

// ============================================================================
// Table and Global Tests (with-table-global.wasm)
// ============================================================================

///|
async test "table-global: counter operations" {
  let component = load_component("test/component/with-table-global.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Initial counter value should be 0
  assert_eq(rt.call("get-counter", []), [u32(0U)])

  // Increment counter once -> 1
  let _ = rt.call("inc-counter", [])
  assert_eq(rt.call("get-counter", []), [u32(1U)])

  // Increment 4 more times -> 5
  for _ in 0..<4 {
    let _ = rt.call("inc-counter", [])

  }
  assert_eq(rt.call("get-counter", []), [u32(5U)])
}

// ============================================================================
// Nested Component Tests (nested.wasm)
// ============================================================================

///|
async test "nested: quadruple function" {
  // nested.wasm: inner "double" component called twice -> quadruple(x) = x * 4
  let component = load_component("test/component/nested.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Test various inputs
  assert_eq(rt.call("quadruple", [s32(3)]), [s32(12)])
  assert_eq(rt.call("quadruple", [s32(0)]), [s32(0)])
  assert_eq(rt.call("quadruple", [s32(-5)]), [s32(-20)])
  assert_eq(rt.call("quadruple", [s32(100)]), [s32(400)])
}

// ============================================================================
// Multi Import/Export Tests (multi-import-export.wasm)
// ============================================================================

///|
async test "multi-import-export: all functions" {
  // multi-import-export.wasm imports math:ops (add, sub, mul) and exports:
  // - add-mul(a, b, c) = (a + b) * c
  // - square(x) = x * x
  // - diff-squared(a, b) = (a - b)^2
  let component = load_component("test/component/multi-import-export.wasm")
  let resolver = @wasm5_component.ComponentImportResolver::new()
  resolver.add_func("math:ops", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match (args[0], args[1]) {
        (
          @wasm5_component.ComponentValue::S32(a),
          @wasm5_component.ComponentValue::S32(b),
        ) => [@wasm5_component.ComponentValue::S32(a + b)]
        _ => []
      }
    },
  })
  resolver.add_func("math:ops", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match (args[0], args[1]) {
        (
          @wasm5_component.ComponentValue::S32(a),
          @wasm5_component.ComponentValue::S32(b),
        ) => [@wasm5_component.ComponentValue::S32(a - b)]
        _ => []
      }
    },
  })
  resolver.add_func("math:ops", @wasm5_component.ImportedComponentFunc::{
    func: fn(args) {
      match (args[0], args[1]) {
        (
          @wasm5_component.ComponentValue::S32(a),
          @wasm5_component.ComponentValue::S32(b),
        ) => [@wasm5_component.ComponentValue::S32(a * b)]
        _ => []
      }
    },
  })
  let rt = @wasm5_component.ComponentRuntime::new_with_imports(
    component, resolver,
  )
  rt.instantiate()

  // Test all exported functions
  assert_eq(rt.call("add-mul", [s32(2), s32(3), s32(4)]), [s32(20)]) // (2+3)*4
  assert_eq(rt.call("square", [s32(7)]), [s32(49)]) // 7*7
  assert_eq(rt.call("diff-squared", [s32(10), s32(7)]), [s32(9)]) // (10-7)^2
}

// ============================================================================
// Resource Counter Tests (resource-counter.wasm)
// ============================================================================

///|
async test "resource-counter: all operations" {
  let component = load_component("test/component/resource-counter.wasm")
  let rt = @wasm5_component.ComponentRuntime::new(component)
  rt.instantiate()

  // Create a counter (initial value 0)
  let c0 = rt.call("create", [])
  assert_eq(c0, [@wasm5_component.ComponentValue::Own(0U, 0U)])

  // Increment: 0 -> 1
  let c1 = rt.call("increment", [c0[0]])
  assert_eq(c1, [@wasm5_component.ComponentValue::Own(0U, 1U)])

  // Increment again: 1 -> 2
  let c2 = rt.call("increment", [c1[0]])
  assert_eq(c2, [@wasm5_component.ComponentValue::Own(0U, 2U)])

  // Add 5: 2 -> 7
  let c3 = rt.call("add", [c2[0], s32(5)])
  assert_eq(c3, [@wasm5_component.ComponentValue::Own(0U, 7U)])

  // Add 10: 7 -> 17
  let c4 = rt.call("add", [c3[0], s32(10)])
  assert_eq(c4, [@wasm5_component.ComponentValue::Own(0U, 17U)])
}
