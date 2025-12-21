///|
priv enum FuncRef {
  Index(UInt)
  Name(Bytes)
}

///|
priv enum IndexRef {
  Index(UInt)
  Name(Bytes)
}

///|
priv enum WatInstr {
  Core(@core.Instr)
  GlobalGet(IndexRef)
  GlobalSet(IndexRef)
  Call(FuncRef)
}

///|
priv enum MemArg {
  Align(UInt)
  Offset(UInt)
}

///|
priv struct WatFunc {
  name : Bytes?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
  locals : Array[@core.ValType]
  body : Array[WatInstr]
  exports : Array[Bytes]
}

///|
priv struct WatImportFunc {
  module_ : Bytes
  name : Bytes
  func_name : Bytes?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
}

///|
priv struct WatImportMem {
  module_ : Bytes
  name : Bytes
  mem_name : Bytes?
  limits : @core.Limits
}

///|
priv struct WatImportGlobal {
  module_ : Bytes
  name : Bytes
  global_name : Bytes?
  type_ : @core.GlobalType
}

///|
priv struct WatMemory {
  name : Bytes?
  limits : @core.Limits
  exports : Array[Bytes]
}

///|
priv struct WatGlobal {
  name : Bytes?
  type_ : @core.GlobalType
  init : Array[WatInstr]
  exports : Array[Bytes]
}

///|
priv struct WatData {
  offset : Array[WatInstr]
  init : Bytes
}

///|
priv enum WatExportDesc {
  Func(FuncRef)
  Mem(IndexRef)
  Global(IndexRef)
}

///|
priv struct WatExport {
  name : Bytes
  desc : WatExportDesc
}

///|
priv struct WatModule {
  func_imports : Array[WatImportFunc]
  mem_imports : Array[WatImportMem]
  global_imports : Array[WatImportGlobal]
  funcs : Array[WatFunc]
  mems : Array[WatMemory]
  globals : Array[WatGlobal]
  datas : Array[WatData]
  exports : Array[WatExport]
  mut start : FuncRef?
}

///|
pub fn wat_to_wasm(text : String) -> Bytes raise WatError {
  let module_ = wat_to_module(text)
  @encode.encode(module_) catch {
    e => raise WatError::Encode("\{e}")
  }
}

///|
pub fn wat_to_module(text : String) -> @core.Module raise WatError {
  let exprs = parse_sexprs(text)
  guard exprs.length() == 1 else {
    raise WatError::InvalidSyntax("expected single module")
  }
  let module_expr = exprs[0]
  let wat_module = parse_module(module_expr)
  build_module(wat_module)
}

///|
fn parse_module(expr : SExpr) -> WatModule raise WatError {
  let module_ = WatModule::{
    func_imports: [],
    mem_imports: [],
    global_imports: [],
    funcs: [],
    mems: [],
    globals: [],
    datas: [],
    exports: [],
    start: None,
  }
  match expr {
    List(items) => {
      guard items.length() > 0 else {
        raise WatError::InvalidSyntax("empty module")
      }
      guard items[0] is Atom(head) && head == b"module" else {
        raise WatError::InvalidSyntax("expected module")
      }
      let mut idx = 1
      if idx < items.length() && items[idx] is Atom(name) && is_name(name) {
        idx = idx + 1
      }
      for i in idx..<items.length() {
        match items[i] {
          List(field_items) => parse_module_field(module_, field_items)
          Atom(_) | StringLit(_) =>
            raise WatError::InvalidSyntax("unexpected module item")
        }
      }
    }
    _ => raise WatError::InvalidSyntax("expected module list")
  }
  module_
}

///|
fn parse_module_field(
  module_ : WatModule,
  items : Array[SExpr],
) -> Unit raise WatError {
  guard items.length() > 0 else { raise WatError::InvalidSyntax("empty field") }
  guard items[0] is Atom(head) else {
    raise WatError::InvalidSyntax("field head must be atom")
  }
  match head {
    b"func" => {
      let func = parse_func(items)
      let func_index = (module_.func_imports.length() + module_.funcs.length()).reinterpret_as_uint()
      for name in func.exports {
        module_.exports.push({
          name,
          desc: WatExportDesc::Func(FuncRef::Index(func_index)),
        })
      }
      module_.funcs.push({
        name: func.name,
        params: func.params,
        results: func.results,
        locals: func.locals,
        body: func.body,
        exports: [],
      })
    }
    b"import" => parse_import(module_, items)
    b"memory" => {
      let mem = parse_memory(items)
      let mem_index = (module_.mem_imports.length() + module_.mems.length()).reinterpret_as_uint()
      for name in mem.exports {
        module_.exports.push({
          name,
          desc: WatExportDesc::Mem(IndexRef::Index(mem_index)),
        })
      }
      module_.mems.push({ name: mem.name, limits: mem.limits, exports: [] })
    }
    b"global" => {
      let global_ = parse_global(items)
      let global_index = (module_.global_imports.length() +
      module_.globals.length()).reinterpret_as_uint()
      for name in global_.exports {
        module_.exports.push({
          name,
          desc: WatExportDesc::Global(IndexRef::Index(global_index)),
        })
      }
      module_.globals.push({
        name: global_.name,
        type_: global_.type_,
        init: global_.init,
        exports: [],
      })
    }
    b"data" => module_.datas.push(parse_data(items))
    b"export" => module_.exports.push(parse_export(items))
    b"start" => module_.start = Some(parse_start(items))
    _ => raise WatError::Unsupported("module field \{head}")
  }
}

///|
fn parse_func(items : Array[SExpr]) -> WatFunc raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let params : Array[@core.ValType] = []
  let param_names : Array[Bytes?] = []
  let results : Array[@core.ValType] = []
  let locals : Array[@core.ValType] = []
  let local_names : Array[Bytes?] = []
  let exports : Array[Bytes] = []
  let instr_items : Array[SExpr] = []
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 else {
          raise WatError::InvalidSyntax("empty func item")
        }
        guard list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("func item tag must be atom")
        }
        match tag {
          b"param" => append_named_types(params, param_names, list_items)
          b"result" => append_types(results, list_items, allow_names=false)
          b"local" => append_named_types(locals, local_names, list_items)
          b"export" => exports.push(parse_inline_export(list_items))
          _ => instr_items.push(items[i])
        }
      }
      Atom(_) => instr_items.push(items[i])
      StringLit(_) => raise WatError::InvalidSyntax("unexpected string in func")
    }
  }
  let local_map = Map::new()
  for i in 0..<param_names.length() {
    match param_names[i] {
      Some(name) => {
        ensure_unique_name(local_map, name, "local")
        local_map[name] = i.reinterpret_as_uint()
      }
      None => ()
    }
  }
  let base = params.length()
  for i in 0..<local_names.length() {
    match local_names[i] {
      Some(name) => {
        ensure_unique_name(local_map, name, "local")
        local_map[name] = (base + i).reinterpret_as_uint()
      }
      None => ()
    }
  }
  let body = parse_instrs(instr_items, local_map)
  WatFunc::{ name, params, results, locals, body, exports }
}

///|
fn parse_import(
  module_ : WatModule,
  items : Array[SExpr],
) -> Unit raise WatError {
  guard items.length() >= 4 else {
    raise WatError::InvalidSyntax("import expects module/name/desc")
  }
  let module_name = expect_string(items[1])
  let field_name = expect_string(items[2])
  guard items[3] is List(desc_items) else {
    raise WatError::InvalidSyntax("import desc must be list")
  }
  guard desc_items.length() > 0 && desc_items[0] is Atom(desc_tag) else {
    raise WatError::InvalidSyntax("import desc tag must be atom")
  }
  match desc_tag {
    b"func" => {
      let (func_name, params, results) = parse_func_typeuse(desc_items)
      module_.func_imports.push({
        module_: module_name,
        name: field_name,
        func_name,
        params,
        results,
      })
    }
    b"memory" => {
      let mut idx = 1
      let mut mem_name : Bytes? = None
      if idx < desc_items.length() &&
        desc_items[idx] is Atom(atom) &&
        is_name(atom) {
        mem_name = Some(atom)
        idx = idx + 1
      }
      let limits = parse_limits(desc_items, start=idx)
      module_.mem_imports.push({
        module_: module_name,
        name: field_name,
        mem_name,
        limits,
      })
    }
    b"global" => {
      let mut idx = 1
      let mut global_name : Bytes? = None
      if idx < desc_items.length() &&
        desc_items[idx] is Atom(atom) &&
        is_name(atom) {
        global_name = Some(atom)
        idx = idx + 1
      }
      guard idx < desc_items.length() else {
        raise WatError::InvalidSyntax("global import expects type")
      }
      let global_type = parse_global_type(desc_items[idx])
      guard idx + 1 == desc_items.length() else {
        raise WatError::InvalidSyntax("global import expects only type")
      }
      module_.global_imports.push({
        module_: module_name,
        name: field_name,
        global_name,
        type_: global_type,
      })
    }
    _ => raise WatError::Unsupported("import desc \{desc_tag}")
  }
}

///|
fn parse_memory(items : Array[SExpr]) -> WatMemory raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let exports : Array[Bytes] = []
  let limit_atoms : Array[Bytes] = []
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("memory item tag must be atom")
        }
        match tag {
          b"export" => exports.push(parse_inline_export(list_items))
          _ => raise WatError::Unsupported("memory field \{tag}")
        }
      }
      Atom(atom) => limit_atoms.push(atom)
      StringLit(_) =>
        raise WatError::InvalidSyntax("unexpected string in memory")
    }
  }
  let limits = parse_limits_from_atoms(limit_atoms)
  WatMemory::{ name, limits, exports }
}

///|
fn parse_global(items : Array[SExpr]) -> WatGlobal raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let exports : Array[Bytes] = []
  let mut type_item : SExpr? = None
  let init_items : Array[SExpr] = []
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("global item tag must be atom")
        }
        match tag {
          b"export" => exports.push(parse_inline_export(list_items))
          b"mut" => {
            if type_item is Some(_) {
              raise WatError::InvalidSyntax("duplicate global type")
            }
            type_item = Some(items[i])
          }
          _ =>
            if type_item is None {
              type_item = Some(items[i])
            } else {
              init_items.push(items[i])
            }
        }
      }
      Atom(_) =>
        if type_item is None {
          type_item = Some(items[i])
        } else {
          init_items.push(items[i])
        }
      StringLit(_) =>
        raise WatError::InvalidSyntax("unexpected string in global")
    }
  }
  guard type_item is Some(type_expr) else {
    raise WatError::InvalidSyntax("global type missing")
  }
  let global_type = parse_global_type(type_expr)
  guard init_items.length() > 0 else {
    raise WatError::InvalidSyntax("global init missing")
  }
  let init_instrs = parse_instrs(init_items, Map::new())
  WatGlobal::{ name, type_: global_type, init: init_instrs, exports }
}

///|
fn parse_data(items : Array[SExpr]) -> WatData raise WatError {
  guard items.length() >= 3 else {
    raise WatError::InvalidSyntax("data expects offset and bytes")
  }
  let offset_expr = match items[1] {
    List(list_items) => parse_instrs([List(list_items)], Map::new())
    Atom(_) => parse_instrs([items[1]], Map::new())
    StringLit(_) => raise WatError::InvalidSyntax("invalid data offset")
  }
  let data_bytes : Array[Byte] = []
  for i in 2..<items.length() {
    match items[i] {
      StringLit(bytes) =>
        for b in bytes {
          data_bytes.push(b)
        }
      _ => raise WatError::InvalidSyntax("data expects string literals")
    }
  }
  WatData::{ offset: offset_expr, init: Bytes::from_array(data_bytes) }
}

///|
fn parse_export(items : Array[SExpr]) -> WatExport raise WatError {
  guard items.length() >= 3 else {
    raise WatError::InvalidSyntax("export expects name and desc")
  }
  let name = expect_string(items[1])
  guard items[2] is List(desc_items) else {
    raise WatError::InvalidSyntax("export desc must be list")
  }
  guard desc_items.length() >= 2 && desc_items[0] is Atom(tag) else {
    raise WatError::InvalidSyntax("export desc missing")
  }
  let ref_atom = expect_atom(desc_items[1])
  let desc = match tag {
    b"func" => WatExportDesc::Func(parse_func_ref(ref_atom))
    b"memory" => WatExportDesc::Mem(parse_index_ref(ref_atom))
    b"global" => WatExportDesc::Global(parse_index_ref(ref_atom))
    _ => raise WatError::Unsupported("export desc \{tag}")
  }
  WatExport::{ name, desc }
}

///|
fn parse_start(items : Array[SExpr]) -> FuncRef raise WatError {
  guard items.length() >= 2 else {
    raise WatError::InvalidSyntax("start expects function")
  }
  let target = expect_atom(items[1])
  parse_func_ref(target)
}

///|
fn parse_inline_export(items : Array[SExpr]) -> Bytes raise WatError {
  guard items.length() == 2 else {
    raise WatError::InvalidSyntax("export expects single name")
  }
  expect_string(items[1])
}

///|
fn parse_func_typeuse(
  items : Array[SExpr],
) -> (Bytes?, Array[@core.ValType], Array[@core.ValType]) raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("func type item tag must be atom")
        }
        match tag {
          b"param" => append_types(params, list_items, allow_names=true)
          b"result" => append_types(results, list_items, allow_names=false)
          _ => raise WatError::Unsupported("func type item \{tag}")
        }
      }
      _ => raise WatError::InvalidSyntax("unexpected item in func typeuse")
    }
  }
  (name, params, results)
}

///|
fn parse_global_type(expr : SExpr) -> @core.GlobalType raise WatError {
  match expr {
    List(list_items) => {
      guard list_items.length() == 2 && list_items[0] is Atom(tag) else {
        raise WatError::InvalidSyntax("global type list invalid")
      }
      guard tag == b"mut" else { raise WatError::InvalidSyntax("expected mut") }
      let val_type = parse_valtype(expect_atom(list_items[1]))
      @core.GlobalType::{ val_type, mutable: true }
    }
    Atom(atom) => {
      let val_type = parse_valtype(atom)
      @core.GlobalType::{ val_type, mutable: false }
    }
    _ => raise WatError::InvalidSyntax("global type invalid")
  }
}

///|
fn append_types(
  dst : Array[@core.ValType],
  items : Array[SExpr],
  allow_names~ : Bool,
) -> Unit raise WatError {
  for i in 1..<items.length() {
    match items[i] {
      Atom(atom) => {
        if allow_names && is_name(atom) {
          continue
        }
        dst.push(parse_valtype(atom))
      }
      _ => raise WatError::InvalidSyntax("expected type atom")
    }
  }
}

///|
fn append_named_types(
  dst_types : Array[@core.ValType],
  dst_names : Array[Bytes?],
  items : Array[SExpr],
) -> Unit raise WatError {
  let mut pending : Bytes? = None
  for i in 1..<items.length() {
    match items[i] {
      Atom(atom) => {
        if is_name(atom) && pending is None {
          pending = Some(atom)
          continue
        }
        dst_types.push(parse_valtype(atom))
        dst_names.push(pending)
        pending = None
      }
      _ => raise WatError::InvalidSyntax("expected type atom")
    }
  }
  match pending {
    Some(_) => raise WatError::InvalidSyntax("dangling name without type")
    None => ()
  }
}

///|
fn parse_limits(
  items : Array[SExpr],
  start~ : Int,
) -> @core.Limits raise WatError {
  let atoms : Array[Bytes] = []
  for i in start..<items.length() {
    match items[i] {
      Atom(atom) => atoms.push(atom)
      _ => raise WatError::InvalidSyntax("limits must be atoms")
    }
  }
  parse_limits_from_atoms(atoms)
}

///|
fn parse_limits_from_atoms(atoms : Array[Bytes]) -> @core.Limits raise WatError {
  guard atoms.length() >= 1 && atoms.length() <= 2 else {
    raise WatError::InvalidSyntax("limits expects 1 or 2 values")
  }
  let min = parse_uint(atoms[0])
  let max = if atoms.length() == 2 { Some(parse_uint(atoms[1])) } else { None }
  { min, max }
}

///|
fn parse_instrs(
  items : Array[SExpr],
  local_map : Map[Bytes, UInt],
) -> Array[WatInstr] raise WatError {
  let instrs : Array[WatInstr] = []
  let mut i = 0
  while i < items.length() {
    match items[i] {
      Atom(op) => {
        let (instr, next_idx) = parse_instr_from_atom(items, i, op, local_map)
        instrs.push(instr)
        i = next_idx
      }
      List(list_items) => {
        instrs.push(parse_instr_from_list(list_items, local_map))
        i = i + 1
      }
      StringLit(_) =>
        raise WatError::InvalidSyntax("unexpected string in instr")
    }
  }
  instrs
}

///|
fn parse_instr_from_atom(
  items : Array[SExpr],
  idx : Int,
  op : Bytes,
  local_map : Map[Bytes, UInt],
) -> (WatInstr, Int) raise WatError {
  match op {
    b"i32.const" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(
          @core.Instr::I32Const(parse_int(imm).reinterpret_as_uint()),
        ),
        idx + 2,
      )
    }
    b"i64.const" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(
          @core.Instr::I64Const(parse_int64(imm).reinterpret_as_uint64()),
        ),
        idx + 2,
      )
    }
    b"f32.const" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::Core(@core.Instr::F32Const(parse_float(imm))), idx + 2)
    }
    b"f64.const" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::Core(@core.Instr::F64Const(parse_double(imm))), idx + 2)
    }
    b"local.get" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::LocalGet(parse_local_ref(imm, local_map))),
        idx + 2,
      )
    }
    b"local.set" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::LocalSet(parse_local_ref(imm, local_map))),
        idx + 2,
      )
    }
    b"local.tee" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::LocalTee(parse_local_ref(imm, local_map))),
        idx + 2,
      )
    }
    b"global.get" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::GlobalGet(parse_index_ref(imm)), idx + 2)
    }
    b"global.set" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::GlobalSet(parse_index_ref(imm)), idx + 2)
    }
    b"call" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::Call(parse_func_ref(imm)), idx + 2)
    }
    b"memory.size" => {
      let (mem_idx, next_idx) = parse_mem_index_from_items(items, idx + 1)
      (WatInstr::Core(@core.Instr::MemorySize(mem_idx)), next_idx)
    }
    b"memory.grow" => {
      let (mem_idx, next_idx) = parse_mem_index_from_items(items, idx + 1)
      (WatInstr::Core(@core.Instr::MemoryGrow(mem_idx)), next_idx)
    }
    _ =>
      match parse_mem_instr_from_atom(items, idx, op) {
        Some((instr, next_idx)) => (instr, next_idx)
        None =>
          match parse_simple_op(op) {
            Some(instr) => (WatInstr::Core(instr), idx + 1)
            None => raise WatError::Unsupported("instruction \{op}")
          }
      }
  }
}

///|
fn parse_instr_from_list(
  list_items : Array[SExpr],
  local_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  guard list_items.length() > 0 else {
    raise WatError::InvalidSyntax("empty instruction list")
  }
  guard list_items[0] is Atom(op) else {
    raise WatError::InvalidSyntax("instruction head must be atom")
  }
  match op {
    b"select" =>
      if list_items.length() == 1 {
        WatInstr::Core(@core.Instr::Select)
      } else {
        guard list_items.length() == 2 else {
          raise WatError::InvalidSyntax("select expects optional result types")
        }
        let result_list = list_items[1]
        guard result_list is List(result_items) else {
          raise WatError::InvalidSyntax("select result types must be a list")
        }
        guard result_items.length() >= 1 &&
          result_items[0] is Atom(head) &&
          head == b"result" else {
          raise WatError::InvalidSyntax(
            "select result types must start with result",
          )
        }
        let types : Array[@core.ValType] = []
        for i in 1..<result_items.length() {
          types.push(parse_valtype(expect_atom(result_items[i])))
        }
        WatInstr::Core(@core.Instr::SelectTyped(types))
      }
    b"i32.const" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("i32.const expects one operand")
      }
      WatInstr::Core(
        @core.Instr::I32Const(
          parse_int(expect_atom(list_items[1])).reinterpret_as_uint(),
        ),
      )
    }
    b"i64.const" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("i64.const expects one operand")
      }
      WatInstr::Core(
        @core.Instr::I64Const(
          parse_int64(expect_atom(list_items[1])).reinterpret_as_uint64(),
        ),
      )
    }
    b"f32.const" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("f32.const expects one operand")
      }
      WatInstr::Core(
        @core.Instr::F32Const(parse_float(expect_atom(list_items[1]))),
      )
    }
    b"f64.const" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("f64.const expects one operand")
      }
      WatInstr::Core(
        @core.Instr::F64Const(parse_double(expect_atom(list_items[1]))),
      )
    }
    b"local.get" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("local.get expects one operand")
      }
      WatInstr::Core(
        @core.Instr::LocalGet(
          parse_local_ref(expect_atom(list_items[1]), local_map),
        ),
      )
    }
    b"local.set" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("local.set expects one operand")
      }
      WatInstr::Core(
        @core.Instr::LocalSet(
          parse_local_ref(expect_atom(list_items[1]), local_map),
        ),
      )
    }
    b"local.tee" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("local.tee expects one operand")
      }
      WatInstr::Core(
        @core.Instr::LocalTee(
          parse_local_ref(expect_atom(list_items[1]), local_map),
        ),
      )
    }
    b"global.get" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("global.get expects one operand")
      }
      WatInstr::GlobalGet(parse_index_ref(expect_atom(list_items[1])))
    }
    b"global.set" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("global.set expects one operand")
      }
      WatInstr::GlobalSet(parse_index_ref(expect_atom(list_items[1])))
    }
    b"call" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("call expects one operand")
      }
      WatInstr::Call(parse_func_ref(expect_atom(list_items[1])))
    }
    b"memory.size" => {
      guard list_items.length() <= 2 else {
        raise WatError::InvalidSyntax("memory.size expects zero or one operand")
      }
      let mem_idx = if list_items.length() == 2 {
        parse_uint(expect_atom(list_items[1]))
      } else {
        0U
      }
      WatInstr::Core(@core.Instr::MemorySize(mem_idx))
    }
    b"memory.grow" => {
      guard list_items.length() <= 2 else {
        raise WatError::InvalidSyntax("memory.grow expects zero or one operand")
      }
      let mem_idx = if list_items.length() == 2 {
        parse_uint(expect_atom(list_items[1]))
      } else {
        0U
      }
      WatInstr::Core(@core.Instr::MemoryGrow(mem_idx))
    }
    _ =>
      match parse_mem_instr_from_list(list_items, op) {
        Some(instr) => instr
        None =>
          match parse_simple_op(op) {
            Some(instr) => {
              guard list_items.length() == 1 else {
                raise WatError::InvalidSyntax(
                  "instruction \{op} takes no operands",
                )
              }
              WatInstr::Core(instr)
            }
            None => raise WatError::Unsupported("instruction \{op}")
          }
      }
  }
}

///|
fn parse_mem_instr_from_atom(
  items : Array[SExpr],
  idx : Int,
  op : Bytes,
) -> (WatInstr, Int)? raise WatError {
  match memarg_default_align(op) {
    Some(default_align) => {
      let (align, offset, next_idx) = parse_memarg_from_items(
        items,
        idx + 1,
        default_align,
      )
      let instr = match make_mem_instr(op, align, offset) {
        Some(mem_instr) => mem_instr
        None => raise WatError::Unsupported("instruction \{op}")
      }
      Some((WatInstr::Core(instr), next_idx))
    }
    None => None
  }
}

///|
fn parse_mem_instr_from_list(
  list_items : Array[SExpr],
  op : Bytes,
) -> WatInstr? raise WatError {
  match memarg_default_align(op) {
    Some(default_align) => {
      let (align, offset) = parse_memarg_from_list(list_items, 1, default_align)
      let instr = match make_mem_instr(op, align, offset) {
        Some(mem_instr) => mem_instr
        None => raise WatError::Unsupported("instruction \{op}")
      }
      Some(WatInstr::Core(instr))
    }
    None => None
  }
}

///|
fn parse_memarg_from_items(
  items : Array[SExpr],
  start : Int,
  default_align : UInt,
) -> (UInt, UInt, Int) raise WatError {
  let mut align = default_align
  let mut offset = 0U
  let mut seen_align = false
  let mut seen_offset = false
  let mut idx = start
  while idx < items.length() {
    match items[idx] {
      Atom(atom) =>
        match parse_memarg_atom(atom) {
          Some(Align(value)) => {
            guard not(seen_align) else {
              raise WatError::InvalidSyntax("duplicate align")
            }
            align = value
            seen_align = true
            idx = idx + 1
          }
          Some(Offset(value)) => {
            guard not(seen_offset) else {
              raise WatError::InvalidSyntax("duplicate offset")
            }
            offset = value
            seen_offset = true
            idx = idx + 1
          }
          None => break
        }
      _ => break
    }
  }
  (align, offset, idx)
}

///|
fn parse_memarg_from_list(
  list_items : Array[SExpr],
  start : Int,
  default_align : UInt,
) -> (UInt, UInt) raise WatError {
  let mut align = default_align
  let mut offset = 0U
  let mut seen_align = false
  let mut seen_offset = false
  for i in start..<list_items.length() {
    match list_items[i] {
      Atom(atom) =>
        match parse_memarg_atom(atom) {
          Some(Align(value)) => {
            guard not(seen_align) else {
              raise WatError::InvalidSyntax("duplicate align")
            }
            align = value
            seen_align = true
          }
          Some(Offset(value)) => {
            guard not(seen_offset) else {
              raise WatError::InvalidSyntax("duplicate offset")
            }
            offset = value
            seen_offset = true
          }
          None =>
            raise WatError::InvalidSyntax(
              "memory operands must be offset= or align=",
            )
        }
      _ => raise WatError::InvalidSyntax("memory operands must be atoms")
    }
  }
  (align, offset)
}

///|
fn parse_memarg_atom(atom : Bytes) -> MemArg? raise WatError {
  if bytes_starts_with(atom, b"offset=") {
    let value = parse_uint_from_bytes(atom, b"offset=".length())
    return Some(Offset(value))
  }
  if bytes_starts_with(atom, b"align=") {
    let align_bytes = parse_uint_from_bytes(atom, b"align=".length())
    let align = align_bytes_to_log2(align_bytes)
    return Some(Align(align))
  }
  None
}

///|
fn memarg_default_align(op : Bytes) -> UInt? {
  match op {
    b"i32.load" | b"f32.load" | b"i32.store" | b"f32.store" => Some(2U)
    b"i64.load" | b"f64.load" | b"i64.store" | b"f64.store" => Some(3U)
    b"i32.load8_s"
    | b"i32.load8_u"
    | b"i64.load8_s"
    | b"i64.load8_u"
    | b"i32.store8"
    | b"i64.store8" => Some(0U)
    b"i32.load16_s"
    | b"i32.load16_u"
    | b"i64.load16_s"
    | b"i64.load16_u"
    | b"i32.store16"
    | b"i64.store16" => Some(1U)
    b"i64.load32_s" | b"i64.load32_u" | b"i64.store32" => Some(2U)
    _ => None
  }
}

///|
fn make_mem_instr(op : Bytes, align : UInt, offset : UInt) -> @core.Instr? {
  match op {
    b"i32.load" => Some(@core.Instr::I32Load(align, offset))
    b"i64.load" => Some(@core.Instr::I64Load(align, offset))
    b"f32.load" => Some(@core.Instr::F32Load(align, offset))
    b"f64.load" => Some(@core.Instr::F64Load(align, offset))
    b"i32.load8_s" => Some(@core.Instr::I32Load8S(align, offset))
    b"i32.load8_u" => Some(@core.Instr::I32Load8U(align, offset))
    b"i32.load16_s" => Some(@core.Instr::I32Load16S(align, offset))
    b"i32.load16_u" => Some(@core.Instr::I32Load16U(align, offset))
    b"i64.load8_s" => Some(@core.Instr::I64Load8S(align, offset))
    b"i64.load8_u" => Some(@core.Instr::I64Load8U(align, offset))
    b"i64.load16_s" => Some(@core.Instr::I64Load16S(align, offset))
    b"i64.load16_u" => Some(@core.Instr::I64Load16U(align, offset))
    b"i64.load32_s" => Some(@core.Instr::I64Load32S(align, offset))
    b"i64.load32_u" => Some(@core.Instr::I64Load32U(align, offset))
    b"i32.store" => Some(@core.Instr::I32Store(align, offset))
    b"i64.store" => Some(@core.Instr::I64Store(align, offset))
    b"f32.store" => Some(@core.Instr::F32Store(align, offset))
    b"f64.store" => Some(@core.Instr::F64Store(align, offset))
    b"i32.store8" => Some(@core.Instr::I32Store8(align, offset))
    b"i32.store16" => Some(@core.Instr::I32Store16(align, offset))
    b"i64.store8" => Some(@core.Instr::I64Store8(align, offset))
    b"i64.store16" => Some(@core.Instr::I64Store16(align, offset))
    b"i64.store32" => Some(@core.Instr::I64Store32(align, offset))
    _ => None
  }
}

///|
fn align_bytes_to_log2(align_bytes : UInt) -> UInt raise WatError {
  guard align_bytes > 0U else {
    raise WatError::InvalidNumber("alignment must be positive")
  }
  let mut value = align_bytes
  let mut log = 0U
  while value > 1U {
    guard (value & 1U) == 0U else {
      raise WatError::InvalidNumber("alignment must be a power of two")
    }
    value = value >> 1
    log = log + 1U
  }
  log
}

///|
fn parse_mem_index_from_items(
  items : Array[SExpr],
  start : Int,
) -> (UInt, Int) raise WatError {
  guard start < items.length() else { return (0U, start) }
  match items[start] {
    Atom(atom) => {
      if is_name(atom) {
        raise WatError::Unsupported("memory index names not supported")
      }
      if is_uint_atom(atom) {
        (parse_uint(atom), start + 1)
      } else {
        (0U, start)
      }
    }
    _ => (0U, start)
  }
}

///|
fn parse_simple_op(op : Bytes) -> @core.Instr? {
  match op {
    b"unreachable" => Some(@core.Instr::Unreachable)
    b"nop" => Some(@core.Instr::Nop)
    b"drop" => Some(@core.Instr::Drop)
    b"select" => Some(@core.Instr::Select)
    b"return" => Some(@core.Instr::Return)
    b"memory.copy" => Some(@core.Instr::MemoryCopy)
    b"memory.fill" => Some(@core.Instr::MemoryFill)
    b"ref.is_null" => Some(@core.Instr::RefIsNull)
    b"i32.eqz" => Some(@core.Instr::I32Eqz)
    b"i32.eq" => Some(@core.Instr::I32Eq)
    b"i32.ne" => Some(@core.Instr::I32Ne)
    b"i32.lt_s" => Some(@core.Instr::I32LtS)
    b"i32.lt_u" => Some(@core.Instr::I32LtU)
    b"i32.gt_s" => Some(@core.Instr::I32GtS)
    b"i32.gt_u" => Some(@core.Instr::I32GtU)
    b"i32.le_s" => Some(@core.Instr::I32LeS)
    b"i32.le_u" => Some(@core.Instr::I32LeU)
    b"i32.ge_s" => Some(@core.Instr::I32GeS)
    b"i32.ge_u" => Some(@core.Instr::I32GeU)
    b"i64.eqz" => Some(@core.Instr::I64Eqz)
    b"i64.eq" => Some(@core.Instr::I64Eq)
    b"i64.ne" => Some(@core.Instr::I64Ne)
    b"i64.lt_s" => Some(@core.Instr::I64LtS)
    b"i64.lt_u" => Some(@core.Instr::I64LtU)
    b"i64.gt_s" => Some(@core.Instr::I64GtS)
    b"i64.gt_u" => Some(@core.Instr::I64GtU)
    b"i64.le_s" => Some(@core.Instr::I64LeS)
    b"i64.le_u" => Some(@core.Instr::I64LeU)
    b"i64.ge_s" => Some(@core.Instr::I64GeS)
    b"i64.ge_u" => Some(@core.Instr::I64GeU)
    b"f32.eq" => Some(@core.Instr::F32Eq)
    b"f32.ne" => Some(@core.Instr::F32Ne)
    b"f32.lt" => Some(@core.Instr::F32Lt)
    b"f32.gt" => Some(@core.Instr::F32Gt)
    b"f32.le" => Some(@core.Instr::F32Le)
    b"f32.ge" => Some(@core.Instr::F32Ge)
    b"f64.eq" => Some(@core.Instr::F64Eq)
    b"f64.ne" => Some(@core.Instr::F64Ne)
    b"f64.lt" => Some(@core.Instr::F64Lt)
    b"f64.gt" => Some(@core.Instr::F64Gt)
    b"f64.le" => Some(@core.Instr::F64Le)
    b"f64.ge" => Some(@core.Instr::F64Ge)
    b"i32.clz" => Some(@core.Instr::I32Clz)
    b"i32.ctz" => Some(@core.Instr::I32Ctz)
    b"i32.popcnt" => Some(@core.Instr::I32Popcnt)
    b"i32.add" => Some(@core.Instr::I32Add)
    b"i32.sub" => Some(@core.Instr::I32Sub)
    b"i32.mul" => Some(@core.Instr::I32Mul)
    b"i32.div_s" => Some(@core.Instr::I32DivS)
    b"i32.div_u" => Some(@core.Instr::I32DivU)
    b"i32.rem_s" => Some(@core.Instr::I32RemS)
    b"i32.rem_u" => Some(@core.Instr::I32RemU)
    b"i32.and" => Some(@core.Instr::I32And)
    b"i32.or" => Some(@core.Instr::I32Or)
    b"i32.xor" => Some(@core.Instr::I32Xor)
    b"i32.shl" => Some(@core.Instr::I32Shl)
    b"i32.shr_s" => Some(@core.Instr::I32ShrS)
    b"i32.shr_u" => Some(@core.Instr::I32ShrU)
    b"i32.rotl" => Some(@core.Instr::I32Rotl)
    b"i32.rotr" => Some(@core.Instr::I32Rotr)
    b"i64.clz" => Some(@core.Instr::I64Clz)
    b"i64.ctz" => Some(@core.Instr::I64Ctz)
    b"i64.popcnt" => Some(@core.Instr::I64Popcnt)
    b"i64.add" => Some(@core.Instr::I64Add)
    b"i64.sub" => Some(@core.Instr::I64Sub)
    b"i64.mul" => Some(@core.Instr::I64Mul)
    b"i64.div_s" => Some(@core.Instr::I64DivS)
    b"i64.div_u" => Some(@core.Instr::I64DivU)
    b"i64.rem_s" => Some(@core.Instr::I64RemS)
    b"i64.rem_u" => Some(@core.Instr::I64RemU)
    b"i64.and" => Some(@core.Instr::I64And)
    b"i64.or" => Some(@core.Instr::I64Or)
    b"i64.xor" => Some(@core.Instr::I64Xor)
    b"i64.shl" => Some(@core.Instr::I64Shl)
    b"i64.shr_s" => Some(@core.Instr::I64ShrS)
    b"i64.shr_u" => Some(@core.Instr::I64ShrU)
    b"i64.rotl" => Some(@core.Instr::I64Rotl)
    b"i64.rotr" => Some(@core.Instr::I64Rotr)
    b"f32.abs" => Some(@core.Instr::F32Abs)
    b"f32.neg" => Some(@core.Instr::F32Neg)
    b"f32.ceil" => Some(@core.Instr::F32Ceil)
    b"f32.floor" => Some(@core.Instr::F32Floor)
    b"f32.trunc" => Some(@core.Instr::F32Trunc)
    b"f32.nearest" => Some(@core.Instr::F32Nearest)
    b"f32.sqrt" => Some(@core.Instr::F32Sqrt)
    b"f32.add" => Some(@core.Instr::F32Add)
    b"f32.sub" => Some(@core.Instr::F32Sub)
    b"f32.mul" => Some(@core.Instr::F32Mul)
    b"f32.div" => Some(@core.Instr::F32Div)
    b"f32.min" => Some(@core.Instr::F32Min)
    b"f32.max" => Some(@core.Instr::F32Max)
    b"f32.copysign" => Some(@core.Instr::F32Copysign)
    b"f64.abs" => Some(@core.Instr::F64Abs)
    b"f64.neg" => Some(@core.Instr::F64Neg)
    b"f64.ceil" => Some(@core.Instr::F64Ceil)
    b"f64.floor" => Some(@core.Instr::F64Floor)
    b"f64.trunc" => Some(@core.Instr::F64Trunc)
    b"f64.nearest" => Some(@core.Instr::F64Nearest)
    b"f64.sqrt" => Some(@core.Instr::F64Sqrt)
    b"f64.add" => Some(@core.Instr::F64Add)
    b"f64.sub" => Some(@core.Instr::F64Sub)
    b"f64.mul" => Some(@core.Instr::F64Mul)
    b"f64.div" => Some(@core.Instr::F64Div)
    b"f64.min" => Some(@core.Instr::F64Min)
    b"f64.max" => Some(@core.Instr::F64Max)
    b"f64.copysign" => Some(@core.Instr::F64Copysign)
    b"i32.wrap_i64" => Some(@core.Instr::I32WrapI64)
    b"i32.trunc_f32_s" => Some(@core.Instr::I32TruncF32S)
    b"i32.trunc_f32_u" => Some(@core.Instr::I32TruncF32U)
    b"i32.trunc_f64_s" => Some(@core.Instr::I32TruncF64S)
    b"i32.trunc_f64_u" => Some(@core.Instr::I32TruncF64U)
    b"i64.extend_i32_s" => Some(@core.Instr::I64ExtendI32S)
    b"i64.extend_i32_u" => Some(@core.Instr::I64ExtendI32U)
    b"i64.trunc_f32_s" => Some(@core.Instr::I64TruncF32S)
    b"i64.trunc_f32_u" => Some(@core.Instr::I64TruncF32U)
    b"i64.trunc_f64_s" => Some(@core.Instr::I64TruncF64S)
    b"i64.trunc_f64_u" => Some(@core.Instr::I64TruncF64U)
    b"f32.convert_i32_s" => Some(@core.Instr::F32ConvertI32S)
    b"f32.convert_i32_u" => Some(@core.Instr::F32ConvertI32U)
    b"f32.convert_i64_s" => Some(@core.Instr::F32ConvertI64S)
    b"f32.convert_i64_u" => Some(@core.Instr::F32ConvertI64U)
    b"f32.demote_f64" => Some(@core.Instr::F32DemoteF64)
    b"f64.convert_i32_s" => Some(@core.Instr::F64ConvertI32S)
    b"f64.convert_i32_u" => Some(@core.Instr::F64ConvertI32U)
    b"f64.convert_i64_s" => Some(@core.Instr::F64ConvertI64S)
    b"f64.convert_i64_u" => Some(@core.Instr::F64ConvertI64U)
    b"f64.promote_f32" => Some(@core.Instr::F64PromoteF32)
    b"i32.reinterpret_f32" => Some(@core.Instr::I32ReinterpretF32)
    b"i64.reinterpret_f64" => Some(@core.Instr::I64ReinterpretF64)
    b"f32.reinterpret_i32" => Some(@core.Instr::F32ReinterpretI32)
    b"f64.reinterpret_i64" => Some(@core.Instr::F64ReinterpretI64)
    b"i32.extend8_s" => Some(@core.Instr::I32Extend8S)
    b"i32.extend16_s" => Some(@core.Instr::I32Extend16S)
    b"i64.extend8_s" => Some(@core.Instr::I64Extend8S)
    b"i64.extend16_s" => Some(@core.Instr::I64Extend16S)
    b"i64.extend32_s" => Some(@core.Instr::I64Extend32S)
    b"i32.trunc_sat_f32_s" => Some(@core.Instr::I32TruncSatF32S)
    b"i32.trunc_sat_f32_u" => Some(@core.Instr::I32TruncSatF32U)
    b"i32.trunc_sat_f64_s" => Some(@core.Instr::I32TruncSatF64S)
    b"i32.trunc_sat_f64_u" => Some(@core.Instr::I32TruncSatF64U)
    b"i64.trunc_sat_f32_s" => Some(@core.Instr::I64TruncSatF32S)
    b"i64.trunc_sat_f32_u" => Some(@core.Instr::I64TruncSatF32U)
    b"i64.trunc_sat_f64_s" => Some(@core.Instr::I64TruncSatF64S)
    b"i64.trunc_sat_f64_u" => Some(@core.Instr::I64TruncSatF64U)
    _ => None
  }
}

///|
fn build_module(wat : WatModule) -> @core.Module raise WatError {
  let func_map = Map::new()
  let mem_map = Map::new()
  let global_map = Map::new()
  let mut func_index = 0U
  for imp in wat.func_imports {
    if imp.func_name is Some(name) {
      ensure_unique_name(func_map, name, "func")
      func_map[name] = func_index
    }
    func_index = func_index + 1U
  }
  for func in wat.funcs {
    if func.name is Some(name) {
      ensure_unique_name(func_map, name, "func")
      func_map[name] = func_index
    }
    func_index = func_index + 1U
  }
  let mut mem_index = 0U
  for imp in wat.mem_imports {
    if imp.mem_name is Some(name) {
      ensure_unique_name(mem_map, name, "memory")
      mem_map[name] = mem_index
    }
    mem_index = mem_index + 1U
  }
  for mem in wat.mems {
    if mem.name is Some(name) {
      ensure_unique_name(mem_map, name, "memory")
      mem_map[name] = mem_index
    }
    mem_index = mem_index + 1U
  }
  let mut global_index = 0U
  for imp in wat.global_imports {
    if imp.global_name is Some(name) {
      ensure_unique_name(global_map, name, "global")
      global_map[name] = global_index
    }
    global_index = global_index + 1U
  }
  for global_ in wat.globals {
    if global_.name is Some(name) {
      ensure_unique_name(global_map, name, "global")
      global_map[name] = global_index
    }
    global_index = global_index + 1U
  }
  let types : Array[@core.FuncType] = []
  let imports : Array[@core.Import] = []
  for imp in wat.func_imports {
    let type_idx = type_index(types, imp.params, imp.results)
    imports.push({
      module_: imp.module_,
      name: imp.name,
      desc: @core.ImportDesc::Func(type_idx),
    })
  }
  for imp in wat.mem_imports {
    imports.push({
      module_: imp.module_,
      name: imp.name,
      desc: @core.ImportDesc::Mem({ limits: imp.limits }),
    })
  }
  for imp in wat.global_imports {
    imports.push({
      module_: imp.module_,
      name: imp.name,
      desc: @core.ImportDesc::Global(imp.type_),
    })
  }
  let funcs : Array[UInt] = []
  let codes : Array[@core.Code] = []
  for func in wat.funcs {
    let type_idx = type_index(types, func.params, func.results)
    funcs.push(type_idx)
    let instrs = resolve_instrs(func.body, func_map, global_map)
    let code : @core.Code = {
      locals: func.locals,
      body: @core.Expr::{ instrs, },
      compiled: None,
    }
    codes.push(code)
  }
  let globals : Array[@core.Global] = []
  for global_ in wat.globals {
    let init_instrs = resolve_const_instrs(
      global_.init,
      global_map,
      wat.global_imports,
    )
    globals.push({
      type_: global_.type_,
      init: @core.Expr::{ instrs: init_instrs },
    })
  }
  let mems : Array[@core.MemType] = []
  for mem in wat.mems {
    mems.push({ limits: mem.limits })
  }
  let exports : Array[@core.Export] = []
  for export_ in wat.exports {
    exports.push(resolve_export(export_, func_map, mem_map, global_map))
  }
  let datas : Array[@core.Data] = []
  for data in wat.datas {
    let offset_instrs = resolve_offset_instrs(
      data.offset,
      global_map,
      wat.global_imports,
    )
    datas.push({
      mem_idx: 0U,
      offset: @core.Expr::{ instrs: offset_instrs },
      init: data.init.sub(),
      is_active: true,
    })
  }
  let start = match wat.start {
    Some(func_ref) => Some(resolve_func_ref(func_ref, func_map))
    None => None
  }
  @core.Module::{
    types,
    funcs,
    tables: [],
    mems,
    globals,
    elems: [],
    datas,
    start,
    imports,
    exports,
    codes,
  }
}

///|
fn resolve_instrs(
  instrs : Array[WatInstr],
  func_map : Map[Bytes, UInt],
  global_map : Map[Bytes, UInt],
) -> Array[@core.Instr] raise WatError {
  let out : Array[@core.Instr] = []
  for instr in instrs {
    out.push(resolve_instr(instr, func_map, global_map))
  }
  out
}

///|
fn resolve_const_instrs(
  instrs : Array[WatInstr],
  global_map : Map[Bytes, UInt],
  imported_globals : Array[WatImportGlobal],
) -> Array[@core.Instr] raise WatError {
  let out : Array[@core.Instr] = []
  for instr in instrs {
    match instr {
      WatInstr::Core(core_instr) =>
        match core_instr {
          I32Const(_) | I64Const(_) | F32Const(_) | F64Const(_) =>
            out.push(core_instr)
          _ => raise WatError::Unsupported("non-const init expression")
        }
      WatInstr::GlobalGet(global_ref) => {
        let idx = resolve_global_ref(global_ref, global_map)
        guard idx < imported_globals.length().reinterpret_as_uint() else {
          raise WatError::Unsupported(
            "global.get must reference imported global",
          )
        }
        let imp = imported_globals[idx.reinterpret_as_int()]
        guard not(imp.type_.mutable) else {
          raise WatError::Unsupported(
            "global.get must reference immutable global",
          )
        }
        out.push(@core.Instr::GlobalGet(idx))
      }
      _ => raise WatError::Unsupported("non-const init expression")
    }
  }
  out
}

///|
fn resolve_offset_instrs(
  instrs : Array[WatInstr],
  global_map : Map[Bytes, UInt],
  imported_globals : Array[WatImportGlobal],
) -> Array[@core.Instr] raise WatError {
  let out : Array[@core.Instr] = []
  for instr in instrs {
    match instr {
      WatInstr::Core(core_instr) =>
        match core_instr {
          I32Const(_) => out.push(core_instr)
          _ =>
            raise WatError::Unsupported(
              "data offset expects i32.const/global.get",
            )
        }
      WatInstr::GlobalGet(global_ref) => {
        let idx = resolve_global_ref(global_ref, global_map)
        guard idx < imported_globals.length().reinterpret_as_uint() else {
          raise WatError::Unsupported(
            "global.get must reference imported global",
          )
        }
        let imp = imported_globals[idx.reinterpret_as_int()]
        guard not(imp.type_.mutable) else {
          raise WatError::Unsupported(
            "global.get must reference immutable global",
          )
        }
        guard imp.type_.val_type == I32 else {
          raise WatError::Unsupported("data offset global must be i32")
        }
        out.push(@core.Instr::GlobalGet(idx))
      }
      _ =>
        raise WatError::Unsupported("data offset expects i32.const/global.get")
    }
  }
  out
}

///|
fn resolve_instr(
  instr : WatInstr,
  func_map : Map[Bytes, UInt],
  global_map : Map[Bytes, UInt],
) -> @core.Instr raise WatError {
  match instr {
    WatInstr::Core(core_instr) => core_instr
    WatInstr::GlobalGet(global_ref) =>
      @core.Instr::GlobalGet(resolve_global_ref(global_ref, global_map))
    WatInstr::GlobalSet(global_ref) =>
      @core.Instr::GlobalSet(resolve_global_ref(global_ref, global_map))
    WatInstr::Call(func_ref) =>
      @core.Instr::Call(resolve_func_ref(func_ref, func_map))
  }
}

///|
fn resolve_export(
  export_ : WatExport,
  func_map : Map[Bytes, UInt],
  mem_map : Map[Bytes, UInt],
  global_map : Map[Bytes, UInt],
) -> @core.Export raise WatError {
  match export_.desc {
    Func(func_ref) => {
      let idx = resolve_func_ref(func_ref, func_map)
      { name: export_.name, desc: @core.ExportDesc::Func(idx) }
    }
    Mem(mem_ref) => {
      let idx = resolve_index_ref(mem_ref, mem_map, "memory")
      { name: export_.name, desc: @core.ExportDesc::Mem(idx) }
    }
    Global(global_ref) => {
      let idx = resolve_index_ref(global_ref, global_map, "global")
      { name: export_.name, desc: @core.ExportDesc::Global(idx) }
    }
  }
}

///|
fn resolve_func_ref(
  func_ref : FuncRef,
  func_map : Map[Bytes, UInt],
) -> UInt raise WatError {
  match func_ref {
    Index(idx) => idx
    Name(name) =>
      match func_map.get(name) {
        Some(idx) => idx
        None => raise WatError::UnknownIdentifier("func \{name}")
      }
  }
}

///|
fn resolve_global_ref(
  global_ref : IndexRef,
  global_map : Map[Bytes, UInt],
) -> UInt raise WatError {
  resolve_index_ref(global_ref, global_map, "global")
}

///|
fn resolve_index_ref(
  ref_ : IndexRef,
  map : Map[Bytes, UInt],
  kind : String,
) -> UInt raise WatError {
  match ref_ {
    Index(idx) => idx
    Name(name) =>
      match map.get(name) {
        Some(idx) => idx
        None => raise WatError::UnknownIdentifier("\{kind} \{name}")
      }
  }
}

///|
fn ensure_unique_name(
  map : Map[Bytes, UInt],
  name : Bytes,
  kind : String,
) -> Unit raise WatError {
  match map.get(name) {
    Some(_) => raise WatError::InvalidSyntax("duplicate \{kind} name \{name}")
    None => ()
  }
}

///|
fn type_index(
  types : Array[@core.FuncType],
  params : Array[@core.ValType],
  results : Array[@core.ValType],
) -> UInt {
  for i in 0..<types.length() {
    if same_sig(types[i], params, results) {
      return i.reinterpret_as_uint()
    }
  }
  types.push({ params, results })
  (types.length() - 1).reinterpret_as_uint()
}

///|
fn same_sig(
  func_type : @core.FuncType,
  params : Array[@core.ValType],
  results : Array[@core.ValType],
) -> Bool {
  if func_type.params.length() != params.length() {
    return false
  }
  if func_type.results.length() != results.length() {
    return false
  }
  for i in 0..<params.length() {
    if func_type.params[i] != params[i] {
      return false
    }
  }
  for i in 0..<results.length() {
    if func_type.results[i] != results[i] {
      return false
    }
  }
  true
}

///|
fn parse_func_ref(atom : Bytes) -> FuncRef raise WatError {
  if is_name(atom) {
    Name(atom)
  } else {
    Index(parse_uint(atom))
  }
}

///|
fn parse_index_ref(atom : Bytes) -> IndexRef raise WatError {
  if is_name(atom) {
    Name(atom)
  } else {
    Index(parse_uint(atom))
  }
}

///|
fn parse_local_ref(
  atom : Bytes,
  local_map : Map[Bytes, UInt],
) -> UInt raise WatError {
  if is_name(atom) {
    match local_map.get(atom) {
      Some(idx) => idx
      None => raise WatError::UnknownIdentifier("local \{atom}")
    }
  } else {
    parse_uint(atom)
  }
}

///|
fn parse_valtype(atom : Bytes) -> @core.ValType raise WatError {
  match atom {
    b"i32" => I32
    b"i64" => I64
    b"f32" => F32
    b"f64" => F64
    b"v128" => V128
    b"funcref" => FuncRef
    b"externref" => ExternRef
    _ => raise WatError::Unsupported("valtype \{atom}")
  }
}

///|
fn bytes_starts_with(bytes : Bytes, prefix : Bytes) -> Bool {
  if bytes.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if bytes[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn parse_uint_from_bytes(bytes : Bytes, start : Int) -> UInt raise WatError {
  guard start < bytes.length() else {
    raise WatError::InvalidNumber("missing number")
  }
  let mut value = 0U
  for i in start..<bytes.length() {
    let b = bytes[i]
    guard b >= b'0' && b <= b'9' else {
      raise WatError::InvalidNumber("invalid number \{bytes}")
    }
    value = value * 10U + (b.to_uint() - b'0'.to_uint())
  }
  value
}

///|
fn is_uint_atom(atom : Bytes) -> Bool {
  if atom.length() == 0 {
    return false
  }
  for b in atom {
    if b < b'0' || b > b'9' {
      return false
    }
  }
  true
}

///|
fn parse_uint(atom : Bytes) -> UInt raise WatError {
  let value = parse_int(atom)
  guard value >= 0 else {
    raise WatError::InvalidNumber("expected unsigned, got \{atom}")
  }
  value.reinterpret_as_uint()
}

///|
fn parse_int(atom : Bytes) -> Int raise WatError {
  let text = bytes_to_string(atom)
  @strconv.parse_int(text) catch {
    _ => raise WatError::InvalidNumber("invalid integer \{atom}")
  }
}

///|
fn parse_int64(atom : Bytes) -> Int64 raise WatError {
  let text = bytes_to_string(atom)
  @strconv.parse_int64(text) catch {
    _ => raise WatError::InvalidNumber("invalid int64 \{atom}")
  }
}

///|
fn parse_float(atom : Bytes) -> Float raise WatError {
  let value = parse_double(atom)
  Float::from_double(value)
}

///|
fn parse_double(atom : Bytes) -> Double raise WatError {
  let text = bytes_to_string(atom)
  @strconv.parse_double(text) catch {
    _ => raise WatError::InvalidNumber("invalid float \{atom}")
  }
}

///|
fn bytes_to_string(bytes : Bytes) -> String raise WatError {
  @encoding/utf8.decode(bytes) catch {
    _ => raise WatError::InvalidSyntax("invalid utf8")
  }
}

///|
fn expect_atom(expr : SExpr) -> Bytes raise WatError {
  match expr {
    Atom(atom) => atom
    _ => raise WatError::InvalidSyntax("expected atom")
  }
}

///|
fn expect_atom_at(items : Array[SExpr], idx : Int) -> Bytes raise WatError {
  guard idx < items.length() else {
    raise WatError::InvalidSyntax("missing operand")
  }
  expect_atom(items[idx])
}

///|
fn expect_string(expr : SExpr) -> Bytes raise WatError {
  match expr {
    StringLit(bytes) => bytes
    _ => raise WatError::InvalidSyntax("expected string")
  }
}

///|
fn is_name(atom : Bytes) -> Bool {
  atom.length() > 0 && atom[0] == b'$'
}
