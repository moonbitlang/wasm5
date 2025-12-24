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
priv enum WatCatchClause {
  Catch(IndexRef, UInt)
  CatchRef(IndexRef, UInt)
  CatchAll(UInt)
  CatchAllRef(UInt)
}

///|
priv enum WatInstr {
  Core(@core.Instr)
  GlobalGet(IndexRef)
  GlobalSet(IndexRef)
  Call(FuncRef)
  ReturnCall(FuncRef)
  CallIndirect(WatCallIndirect)
  ReturnCallIndirect(WatCallIndirect)
  CallRef(WatTypeUse)
  ReturnCallRef(WatTypeUse)
  RefFunc(FuncRef)
  TableGet(IndexRef)
  TableSet(IndexRef)
  TableSize(IndexRef)
  TableGrow(IndexRef)
  TableInit(IndexRef, IndexRef)
  TableCopy(IndexRef, IndexRef)
  TableFill(IndexRef)
  ElemDrop(IndexRef)
  MemorySize(IndexRef)
  MemoryGrow(IndexRef)
  MemoryInit(IndexRef, IndexRef)
  DataDrop(IndexRef)
  MemoryCopy(IndexRef, IndexRef)
  MemoryFill(IndexRef)
  Throw(IndexRef)
  Rethrow(UInt)
  Block(WatBlockType, Array[WatInstr])
  Loop(WatBlockType, Array[WatInstr])
  If(WatBlockType, Array[WatInstr], Array[WatInstr])
  TryTable(WatBlockType, Array[WatCatchClause], Array[WatInstr])
}

///|
priv enum WatBlockType {
  Empty
  Results(Array[@core.ValType])
  TypeUse(WatTypeUse)
}

///|
priv enum WatTypeRef {
  Index(UInt)
  Name(Bytes)
}

///|
priv struct WatTypeUse {
  type_ref : WatTypeRef?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
}

///|
priv struct WatCallIndirect {
  type_ref : WatTypeRef?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
  table_ref : IndexRef
}

///|
priv struct WatTypeDef {
  name : Bytes?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
}

///|
priv enum MemArg {
  Align(UInt)
  Offset(UInt)
}

///|
priv struct WatFunc {
  name : Bytes?
  type_idx : UInt?
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
  type_idx : UInt?
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
priv struct WatImportTable {
  module_ : Bytes
  name : Bytes
  table_name : Bytes?
  table_type : @core.TableType
}

///|
priv struct WatImportGlobal {
  module_ : Bytes
  name : Bytes
  global_name : Bytes?
  type_ : @core.GlobalType
}

///|
priv struct WatImportTag {
  module_ : Bytes
  name : Bytes
  tag_name : Bytes?
  type_idx : UInt?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
}

///|
priv struct WatMemory {
  name : Bytes?
  limits : @core.Limits
  exports : Array[Bytes]
}

///|
priv struct WatTable {
  name : Bytes?
  table_type : @core.TableType
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
priv struct WatTag {
  name : Bytes?
  type_idx : UInt?
  params : Array[@core.ValType]
  results : Array[@core.ValType]
  exports : Array[Bytes]
}

///|
priv struct WatData {
  name : Bytes?
  mem_ref : IndexRef
  offset : Array[WatInstr]
  init : Bytes
  is_active : Bool
}

///|
priv struct WatElem {
  name : Bytes?
  table_ref : IndexRef
  offset : Array[WatInstr]
  init : Array[FuncRef]
  is_active : Bool
  elem_type : @core.RefType
}

///|
priv enum WatExportDesc {
  Func(FuncRef)
  Mem(IndexRef)
  Global(IndexRef)
  Table(IndexRef)
  Tag(IndexRef)
}

///|
priv struct WatExport {
  name : Bytes
  desc : WatExportDesc
}

///|
priv struct WatModule {
  type_defs : Array[WatTypeDef]
  func_imports : Array[WatImportFunc]
  mem_imports : Array[WatImportMem]
  table_imports : Array[WatImportTable]
  global_imports : Array[WatImportGlobal]
  tag_imports : Array[WatImportTag]
  funcs : Array[WatFunc]
  mems : Array[WatMemory]
  tables : Array[WatTable]
  globals : Array[WatGlobal]
  tags : Array[WatTag]
  elems : Array[WatElem]
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
fn parse_block_instr(
  list_items : Array[SExpr],
  local_map : Map[Bytes, UInt],
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  let (label, idx) = parse_optional_label(list_items, 1)
  let (block_type, next_idx) = parse_block_type(list_items, idx, type_map)
  let body_items = slice_sexprs(list_items, next_idx)
  let nested_labels = push_label(labels, label)
  let body = parse_instrs(body_items, local_map, nested_labels, type_map)
  WatInstr::Block(block_type, body)
}

///|
fn parse_loop_instr(
  list_items : Array[SExpr],
  local_map : Map[Bytes, UInt],
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  let (label, idx) = parse_optional_label(list_items, 1)
  let (block_type, next_idx) = parse_block_type(list_items, idx, type_map)
  let body_items = slice_sexprs(list_items, next_idx)
  let nested_labels = push_label(labels, label)
  let body = parse_instrs(body_items, local_map, nested_labels, type_map)
  WatInstr::Loop(block_type, body)
}

///|
fn parse_if_instr(
  list_items : Array[SExpr],
  local_map : Map[Bytes, UInt],
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  let (label, idx) = parse_optional_label(list_items, 1)
  let (block_type, next_idx) = parse_block_type(list_items, idx, type_map)
  let mut then_items : Array[SExpr] = []
  let mut else_items : Array[SExpr] = []
  let mut seen_then = false
  let mut seen_else = false
  for i in next_idx..<list_items.length() {
    match list_items[i] {
      List(inner) => {
        guard inner.length() > 0 && inner[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("if expects then/else lists")
        }
        match tag {
          b"then" => {
            guard not(seen_then) else {
              raise WatError::InvalidSyntax("duplicate then")
            }
            then_items = slice_sexprs(inner, 1)
            seen_then = true
          }
          b"else" => {
            guard not(seen_else) else {
              raise WatError::InvalidSyntax("duplicate else")
            }
            else_items = slice_sexprs(inner, 1)
            seen_else = true
          }
          _ => raise WatError::InvalidSyntax("if expects then/else lists")
        }
      }
      _ => raise WatError::InvalidSyntax("if expects then/else lists")
    }
  }
  guard seen_then else { raise WatError::InvalidSyntax("if missing then") }
  let nested_labels = push_label(labels, label)
  let then_body = parse_instrs(then_items, local_map, nested_labels, type_map)
  let else_body = parse_instrs(else_items, local_map, nested_labels, type_map)
  WatInstr::If(block_type, then_body, else_body)
}

///|
fn parse_try_table_instr(
  list_items : Array[SExpr],
  local_map : Map[Bytes, UInt],
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  let (block_type, next_idx) = parse_block_type(list_items, 1, type_map)
  let catches : Array[WatCatchClause] = []
  let mut idx = next_idx
  while idx < list_items.length() {
    match list_items[idx] {
      List(catch_items) => {
        guard catch_items.length() > 0 && catch_items[0] is Atom(tag) else {
          break
        }
        match tag {
          b"catch" => {
            guard catch_items.length() == 3 else {
              raise WatError::InvalidSyntax("catch expects tag and label")
            }
            let tag_ref = parse_index_ref(expect_atom(catch_items[1]))
            let label = resolve_label_ref(expect_atom(catch_items[2]), labels)
            catches.push(WatCatchClause::Catch(tag_ref, label))
            idx = idx + 1
          }
          b"catch_ref" => {
            guard catch_items.length() == 3 else {
              raise WatError::InvalidSyntax("catch_ref expects tag and label")
            }
            let tag_ref = parse_index_ref(expect_atom(catch_items[1]))
            let label = resolve_label_ref(expect_atom(catch_items[2]), labels)
            catches.push(WatCatchClause::CatchRef(tag_ref, label))
            idx = idx + 1
          }
          b"catch_all" => {
            guard catch_items.length() == 2 else {
              raise WatError::InvalidSyntax("catch_all expects label")
            }
            let label = resolve_label_ref(expect_atom(catch_items[1]), labels)
            catches.push(WatCatchClause::CatchAll(label))
            idx = idx + 1
          }
          b"catch_all_ref" => {
            guard catch_items.length() == 2 else {
              raise WatError::InvalidSyntax("catch_all_ref expects label")
            }
            let label = resolve_label_ref(expect_atom(catch_items[1]), labels)
            catches.push(WatCatchClause::CatchAllRef(label))
            idx = idx + 1
          }
          _ => break
        }
      }
      _ => break
    }
  }
  let body_items = slice_sexprs(list_items, idx)
  let body = parse_instrs(body_items, local_map, labels, type_map)
  WatInstr::TryTable(block_type, catches, body)
}

///|
fn parse_call_indirect(
  list_items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  WatInstr::CallIndirect(
    parse_call_indirect_items(list_items, type_map, "call_indirect"),
  )
}

///|
fn parse_call_indirect_from_items(
  items : Array[SExpr],
  start : Int,
  type_map : Map[Bytes, UInt],
) -> (WatInstr, Int) raise WatError {
  let (call_indirect, idx) = parse_call_indirect_items_from_items(
    items, start, type_map, b"call_indirect", "call_indirect",
  )
  (WatInstr::CallIndirect(call_indirect), idx)
}

///|
fn parse_call_indirect_items_from_items(
  items : Array[SExpr],
  start : Int,
  type_map : Map[Bytes, UInt],
  op_tag : Bytes,
  context : String,
) -> (WatCallIndirect, Int) raise WatError {
  let list_items : Array[SExpr] = []
  list_items.push(Atom(op_tag))
  let mut idx = start
  if idx < items.length() {
    match items[idx] {
      Atom(atom) if is_name(atom) || is_uint_atom(atom) => {
        list_items.push(items[idx])
        idx = idx + 1
      }
      _ => ()
    }
  }
  while idx < items.length() {
    match items[idx] {
      List(inner) =>
        if inner.length() > 0 &&
          inner[0] is Atom(tag) &&
          (
            tag == b"type" ||
            tag == b"param" ||
            tag == b"result" ||
            tag == b"table"
          ) {
          list_items.push(items[idx])
          idx = idx + 1
        } else {
          break
        }
      _ => break
    }
  }
  (parse_call_indirect_items(list_items, type_map, context), idx)
}

///|
fn parse_call_indirect_items(
  list_items : Array[SExpr],
  type_map : Map[Bytes, UInt],
  context : String,
) -> WatCallIndirect raise WatError {
  guard list_items.length() >= 2 else {
    raise WatError::InvalidSyntax("\{context} expects typeuse")
  }
  let mut idx = 1
  let mut type_ref : WatTypeRef? = None
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  let mut table_ref = IndexRef::Index(0U)
  let mut seen_table = false
  if idx < list_items.length() {
    match list_items[idx] {
      Atom(atom) if is_name(atom) || is_uint_atom(atom) => {
        table_ref = parse_index_ref(atom)
        seen_table = true
        idx = idx + 1
      }
      _ => ()
    }
  }
  for i in idx..<list_items.length() {
    match list_items[i] {
      List(items) => {
        guard items.length() > 0 && items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("\{context} expects lists")
        }
        match tag {
          b"type" => {
            guard type_ref is None else {
              raise WatError::InvalidSyntax("duplicate type in \{context}")
            }
            type_ref = Some(parse_type_ref(items))
          }
          b"param" => append_types(params, items, type_map, allow_names=true)
          b"result" => append_types(results, items, type_map, allow_names=true)
          b"table" => {
            guard not(seen_table) else {
              raise WatError::InvalidSyntax("duplicate table in \{context}")
            }
            guard items.length() == 2 else {
              raise WatError::InvalidSyntax("table expects one index")
            }
            table_ref = parse_index_ref(expect_atom(items[1]))
            seen_table = true
          }
          _ => raise WatError::InvalidSyntax("\{context} expects typeuse")
        }
      }
      _ => raise WatError::InvalidSyntax("\{context} expects lists")
    }
  }
  guard type_ref is Some(_) || params.length() > 0 || results.length() > 0 else {
    raise WatError::InvalidSyntax("\{context} missing typeuse")
  }
  { type_ref, params, results, table_ref }
}

///|
fn parse_call_ref_typeuse_from_items(
  items : Array[SExpr],
  start : Int,
  type_map : Map[Bytes, UInt],
  op_tag : Bytes,
  context : String,
) -> (WatTypeUse, Int) raise WatError {
  let list_items : Array[SExpr] = []
  list_items.push(Atom(op_tag))
  let mut idx = start
  if idx < items.length() {
    match items[idx] {
      Atom(atom) if is_name(atom) || is_uint_atom(atom) => {
        list_items.push(items[idx])
        idx = idx + 1
      }
      _ => ()
    }
  }
  while idx < items.length() {
    match items[idx] {
      List(inner) =>
        if inner.length() > 0 &&
          inner[0] is Atom(tag) &&
          (tag == b"type" || tag == b"param" || tag == b"result") {
          list_items.push(items[idx])
          idx = idx + 1
        } else {
          break
        }
      _ => break
    }
  }
  (parse_typeuse(list_items, 1, type_map, context), idx)
}

///|
fn parse_typeuse(
  list_items : Array[SExpr],
  start : Int,
  type_map : Map[Bytes, UInt],
  context : String,
) -> WatTypeUse raise WatError {
  guard list_items.length() > start else {
    raise WatError::InvalidSyntax("\{context} expects typeuse")
  }
  let mut idx = start
  let mut type_ref : WatTypeRef? = None
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  if idx < list_items.length() {
    match list_items[idx] {
      Atom(atom) if is_name(atom) || is_uint_atom(atom) => {
        type_ref = Some(parse_type_ref_atom(atom))
        idx = idx + 1
      }
      _ => ()
    }
  }
  for i in idx..<list_items.length() {
    match list_items[i] {
      List(items) => {
        guard items.length() > 0 && items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("\{context} expects lists")
        }
        match tag {
          b"type" => {
            guard type_ref is None else {
              raise WatError::InvalidSyntax("duplicate type in \{context}")
            }
            type_ref = Some(parse_type_ref(items))
          }
          b"param" => append_types(params, items, type_map, allow_names=true)
          b"result" => append_types(results, items, type_map, allow_names=true)
          _ => raise WatError::InvalidSyntax("\{context} expects typeuse")
        }
      }
      _ => raise WatError::InvalidSyntax("\{context} expects lists")
    }
  }
  guard type_ref is Some(_) || params.length() > 0 || results.length() > 0 else {
    raise WatError::InvalidSyntax("\{context} missing typeuse")
  }
  { type_ref, params, results }
}

///|
fn parse_optional_label(items : Array[SExpr], start : Int) -> (Bytes?, Int) {
  if start < items.length() {
    match items[start] {
      Atom(atom) if is_name(atom) => return (Some(atom), start + 1)
      _ => ()
    }
  }
  (None, start)
}

///|
fn parse_block_type(
  items : Array[SExpr],
  start : Int,
  type_map : Map[Bytes, UInt],
) -> (WatBlockType, Int) raise WatError {
  let mut idx = start
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  let mut type_ref : WatTypeRef? = None
  while idx < items.length() {
    match items[idx] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          break
        }
        match tag {
          b"result" => {
            append_types(results, list_items, type_map, allow_names=false)
            idx = idx + 1
          }
          b"param" => {
            append_types(params, list_items, type_map, allow_names=true)
            idx = idx + 1
          }
          b"type" => {
            guard type_ref is None else {
              raise WatError::InvalidSyntax("duplicate type in block type")
            }
            type_ref = Some(parse_type_ref(list_items))
            idx = idx + 1
          }
          _ => break
        }
      }
      _ => break
    }
  }
  let block_type = if type_ref is None && params.length() == 0 {
    if results.length() == 0 {
      WatBlockType::Empty
    } else {
      WatBlockType::Results(results)
    }
  } else {
    WatBlockType::TypeUse({ type_ref, params, results })
  }
  (block_type, idx)
}

///|
fn parse_br_table_from_items(
  items : Array[SExpr],
  start : Int,
  labels : Array[Bytes?],
) -> (Array[UInt], UInt, Int) raise WatError {
  let all : Array[UInt] = []
  let mut idx = start
  while idx < items.length() {
    match items[idx] {
      Atom(atom) =>
        if is_name(atom) || is_uint_atom(atom) {
          all.push(resolve_label_ref(atom, labels))
          idx = idx + 1
        } else {
          break
        }
      _ => break
    }
  }
  guard all.length() >= 1 else {
    raise WatError::InvalidSyntax("br_table expects labels")
  }
  let default_target = all[all.length() - 1]
  let targets : Array[UInt] = []
  for i in 0..<(all.length() - 1) {
    targets.push(all[i])
  }
  (targets, default_target, idx)
}

///|
fn parse_br_table_from_list(
  list_items : Array[SExpr],
  labels : Array[Bytes?],
) -> (Array[UInt], UInt) raise WatError {
  let all : Array[UInt] = []
  for i in 1..<list_items.length() {
    all.push(resolve_label_ref(expect_atom(list_items[i]), labels))
  }
  guard all.length() >= 1 else {
    raise WatError::InvalidSyntax("br_table expects labels")
  }
  let default_target = all[all.length() - 1]
  let targets : Array[UInt] = []
  for i in 0..<(all.length() - 1) {
    targets.push(all[i])
  }
  (targets, default_target)
}

///|
fn resolve_label_ref(
  atom : Bytes,
  labels : Array[Bytes?],
) -> UInt raise WatError {
  if is_name(atom) {
    let mut idx = labels.length() - 1
    while idx >= 0 {
      match labels[idx] {
        Some(name) =>
          if name == atom {
            return (labels.length() - 1 - idx).reinterpret_as_uint()
          }
        None => ()
      }
      idx = idx - 1
    }
    raise WatError::UnknownIdentifier("label \{atom}")
  } else {
    let depth = parse_uint(atom)
    guard depth < labels.length().reinterpret_as_uint() else {
      raise WatError::InvalidSyntax("label depth out of range")
    }
    depth
  }
}

///|
fn push_label(labels : Array[Bytes?], label : Bytes?) -> Array[Bytes?] {
  let out : Array[Bytes?] = []
  for item in labels {
    out.push(item)
  }
  out.push(label)
  out
}

///|
fn slice_sexprs(items : Array[SExpr], start : Int) -> Array[SExpr] {
  let out : Array[SExpr] = []
  for i in start..<items.length() {
    out.push(items[i])
  }
  out
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
    type_defs: [],
    func_imports: [],
    mem_imports: [],
    table_imports: [],
    global_imports: [],
    tag_imports: [],
    funcs: [],
    mems: [],
    tables: [],
    globals: [],
    tags: [],
    elems: [],
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
      let type_items : Array[Array[SExpr]] = []
      for i in idx..<items.length() {
        match items[i] {
          List(field_items) => {
            guard field_items.length() > 0 && field_items[0] is Atom(head) else {
              raise WatError::InvalidSyntax("field head must be atom")
            }
            if head == b"type" {
              type_items.push(field_items)
            }
          }
          Atom(_) | StringLit(_) =>
            raise WatError::InvalidSyntax("unexpected module item")
        }
      }
      let type_map = Map::new()
      for i in 0..<type_items.length() {
        let type_item = type_items[i]
        if type_item.length() > 1 && type_item[1] is Atom(name) && is_name(name) {
          ensure_unique_name(type_map, name, "type")
          type_map[name] = i.reinterpret_as_uint()
        }
      }
      for type_item in type_items {
        module_.type_defs.push(parse_type_def(type_item, type_map))
      }
      for i in idx..<items.length() {
        match items[i] {
          List(field_items) => {
            guard field_items.length() > 0 && field_items[0] is Atom(head) else {
              raise WatError::InvalidSyntax("field head must be atom")
            }
            if head == b"type" {
              continue
            }
            parse_module_field(module_, field_items, type_map)
          }
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
  type_map : Map[Bytes, UInt],
) -> Unit raise WatError {
  guard items.length() > 0 else { raise WatError::InvalidSyntax("empty field") }
  guard items[0] is Atom(head) else {
    raise WatError::InvalidSyntax("field head must be atom")
  }
  match head {
    b"func" => {
      let func = parse_func(items, module_.type_defs, type_map)
      let func_index = (module_.func_imports.length() + module_.funcs.length()).reinterpret_as_uint()
      for name in func.exports {
        module_.exports.push({
          name,
          desc: WatExportDesc::Func(FuncRef::Index(func_index)),
        })
      }
      module_.funcs.push({
        name: func.name,
        type_idx: func.type_idx,
        params: func.params,
        results: func.results,
        locals: func.locals,
        body: func.body,
        exports: [],
      })
    }
    b"import" => parse_import(module_, items, type_map)
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
    b"table" => {
      let table = parse_table(items, type_map)
      let table_index = (module_.table_imports.length() +
      module_.tables.length()).reinterpret_as_uint()
      for name in table.exports {
        module_.exports.push({
          name,
          desc: WatExportDesc::Table(IndexRef::Index(table_index)),
        })
      }
      module_.tables.push({
        name: table.name,
        table_type: table.table_type,
        exports: [],
      })
    }
    b"global" => {
      let global_ = parse_global(items, type_map)
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
    b"tag" => {
      let tag = parse_tag(items, module_.type_defs, type_map)
      let tag_index = (module_.tag_imports.length() + module_.tags.length()).reinterpret_as_uint()
      for name in tag.exports {
        module_.exports.push({
          name,
          desc: WatExportDesc::Tag(IndexRef::Index(tag_index)),
        })
      }
      module_.tags.push({
        name: tag.name,
        type_idx: tag.type_idx,
        params: tag.params,
        results: tag.results,
        exports: [],
      })
    }
    b"elem" => module_.elems.push(parse_elem(items, type_map))
    b"data" => module_.datas.push(parse_data(items, type_map))
    b"export" => module_.exports.push(parse_export(items))
    b"start" => module_.start = Some(parse_start(items))
    b"type" => ()
    _ => raise WatError::Unsupported("module field \{head}")
  }
}

///|
fn parse_func(
  items : Array[SExpr],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
) -> WatFunc raise WatError {
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
  let mut type_ref : WatTypeRef? = None
  let mut in_body = false
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) =>
        if in_body {
          instr_items.push(items[i])
        } else {
          guard list_items.length() > 0 else {
            raise WatError::InvalidSyntax("empty func item")
          }
          guard list_items[0] is Atom(tag) else {
            raise WatError::InvalidSyntax("func item tag must be atom")
          }
          match tag {
            b"type" => {
              guard type_ref is None else {
                raise WatError::InvalidSyntax("duplicate type in func")
              }
              type_ref = Some(parse_type_ref(list_items))
            }
            b"param" =>
              append_named_types(params, param_names, list_items, type_map)
            b"result" =>
              append_types(results, list_items, type_map, allow_names=false)
            b"local" =>
              append_named_types(locals, local_names, list_items, type_map)
            b"export" => exports.push(parse_inline_export(list_items))
            _ => {
              in_body = true
              instr_items.push(items[i])
            }
          }
        }
      Atom(_) => {
        in_body = true
        instr_items.push(items[i])
      }
      StringLit(_) => raise WatError::InvalidSyntax("unexpected string in func")
    }
  }
  let (type_idx, resolved_params, resolved_results) = resolve_type_use(
    type_ref, params, results, type_defs, type_map,
  )
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
  let base = resolved_params.length()
  for i in 0..<local_names.length() {
    match local_names[i] {
      Some(name) => {
        ensure_unique_name(local_map, name, "local")
        local_map[name] = (base + i).reinterpret_as_uint()
      }
      None => ()
    }
  }
  let body = parse_instrs(instr_items, local_map, [], type_map)
  WatFunc::{
    name,
    type_idx,
    params: resolved_params,
    results: resolved_results,
    locals,
    body,
    exports,
  }
}

///|
fn parse_import(
  module_ : WatModule,
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
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
      let (func_name, type_idx, params, results) = parse_func_typeuse(
        desc_items,
        module_.type_defs,
        type_map,
      )
      module_.func_imports.push({
        module_: module_name,
        name: field_name,
        func_name,
        type_idx,
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
    b"table" => {
      let mut idx = 1
      let mut table_name : Bytes? = None
      if idx < desc_items.length() &&
        desc_items[idx] is Atom(atom) &&
        is_name(atom) {
        table_name = Some(atom)
        idx = idx + 1
      }
      let table_type = parse_table_type(desc_items, idx, type_map)
      module_.table_imports.push({
        module_: module_name,
        name: field_name,
        table_name,
        table_type,
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
      let global_type = parse_global_type(desc_items[idx], type_map)
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
    b"tag" => {
      let (tag_name, type_idx, params, results) = parse_func_typeuse(
        desc_items,
        module_.type_defs,
        type_map,
      )
      guard results.length() == 0 else {
        raise WatError::InvalidSyntax("tag must not have results")
      }
      module_.tag_imports.push({
        module_: module_name,
        name: field_name,
        tag_name,
        type_idx,
        params,
        results,
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
fn parse_table(
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> WatTable raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let exports : Array[Bytes] = []
  let limit_atoms : Array[Bytes] = []
  let mut elem_type : @core.RefType? = None
  let mut elem_nullable : Bool? = None
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("table item tag must be atom")
        }
        match tag {
          b"export" => exports.push(parse_inline_export(list_items))
          _ => {
            let (ref_type, nullable) = parse_reftype_expr(items[i], type_map)
            guard elem_type is None else {
              raise WatError::InvalidSyntax("duplicate table elem type")
            }
            elem_type = Some(ref_type)
            elem_nullable = Some(nullable)
          }
        }
      }
      Atom(atom) =>
        if is_uint_atom(atom) {
          limit_atoms.push(atom)
        } else {
          let (ref_type, nullable) = parse_reftype_expr(items[i], type_map)
          guard elem_type is None else {
            raise WatError::InvalidSyntax("duplicate table elem type")
          }
          elem_type = Some(ref_type)
          elem_nullable = Some(nullable)
        }
      StringLit(_) =>
        raise WatError::InvalidSyntax("unexpected string in table")
    }
  }
  guard elem_type is Some(elem_type) else {
    raise WatError::InvalidSyntax("table element type missing")
  }
  let nullable = match elem_nullable {
    Some(value) => value
    None => true
  }
  let limits = parse_limits_from_atoms(limit_atoms)
  let table_type : @core.TableType = { elem_type, limits, init: None, nullable }
  WatTable::{ name, table_type, exports }
}

///|
fn parse_table_type(
  items : Array[SExpr],
  start : Int,
  type_map : Map[Bytes, UInt],
) -> @core.TableType raise WatError {
  let limit_atoms : Array[Bytes] = []
  let mut elem_type : @core.RefType? = None
  let mut elem_nullable : Bool? = None
  for i in start..<items.length() {
    match items[i] {
      Atom(atom) =>
        if is_uint_atom(atom) {
          limit_atoms.push(atom)
        } else {
          let (ref_type, nullable) = parse_reftype_expr(items[i], type_map)
          guard elem_type is None else {
            raise WatError::InvalidSyntax("duplicate table elem type")
          }
          elem_type = Some(ref_type)
          elem_nullable = Some(nullable)
        }
      List(_) => {
        let (ref_type, nullable) = parse_reftype_expr(items[i], type_map)
        guard elem_type is None else {
          raise WatError::InvalidSyntax("duplicate table elem type")
        }
        elem_type = Some(ref_type)
        elem_nullable = Some(nullable)
      }
      _ => raise WatError::InvalidSyntax("table type expects atoms")
    }
  }
  guard elem_type is Some(elem_type) else {
    raise WatError::InvalidSyntax("table element type missing")
  }
  let limits = parse_limits_from_atoms(limit_atoms)
  let nullable = match elem_nullable {
    Some(value) => value
    None => true
  }
  { elem_type, limits, init: None, nullable }
}

///|
fn parse_global(
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> WatGlobal raise WatError {
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
  let global_type = parse_global_type(type_expr, type_map)
  guard init_items.length() > 0 else {
    raise WatError::InvalidSyntax("global init missing")
  }
  let init_instrs = parse_instrs(init_items, Map::new(), [], type_map)
  WatGlobal::{ name, type_: global_type, init: init_instrs, exports }
}

///|
fn parse_tag(
  items : Array[SExpr],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
) -> WatTag raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let exports : Array[Bytes] = []
  let mut type_ref : WatTypeRef? = None
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("tag item tag must be atom")
        }
        match tag {
          b"export" => exports.push(parse_inline_export(list_items))
          b"type" => {
            guard type_ref is None else {
              raise WatError::InvalidSyntax("duplicate type in tag")
            }
            type_ref = Some(parse_type_ref(list_items))
          }
          b"param" =>
            append_types(params, list_items, type_map, allow_names=true)
          b"result" =>
            append_types(results, list_items, type_map, allow_names=false)
          _ => raise WatError::Unsupported("tag item \{tag}")
        }
      }
      Atom(_) | StringLit(_) =>
        raise WatError::InvalidSyntax("unexpected tag item")
    }
  }
  let (type_idx, resolved_params, resolved_results) = resolve_type_use(
    type_ref, params, results, type_defs, type_map,
  )
  guard resolved_results.length() == 0 else {
    raise WatError::InvalidSyntax("tag must not have results")
  }
  WatTag::{
    name,
    type_idx,
    params: resolved_params,
    results: resolved_results,
    exports,
  }
}

///|
fn parse_data(
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> WatData raise WatError {
  guard items.length() >= 2 else {
    raise WatError::InvalidSyntax("data expects bytes")
  }
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let mut mem_ref = IndexRef::Index(0U)
  let mut offset_expr : Array[WatInstr] = []
  let mut is_active = false
  if idx < items.length() {
    match items[idx] {
      List(list_items) =>
        if list_items.length() > 0 &&
          list_items[0] is Atom(tag) &&
          tag == b"memory" {
          guard list_items.length() == 2 else {
            raise WatError::InvalidSyntax("memory expects one index")
          }
          mem_ref = parse_index_ref(expect_atom(list_items[1]))
          idx = idx + 1
        }
      _ => ()
    }
  }
  if idx < items.length() {
    match items[idx] {
      List(list_items) =>
        if list_items.length() > 0 &&
          list_items[0] is Atom(tag) &&
          tag == b"offset" {
          let offset_items = slice_sexprs(list_items, 1)
          offset_expr = parse_instrs(offset_items, Map::new(), [], type_map)
          is_active = true
          idx = idx + 1
        } else {
          offset_expr = parse_instrs([items[idx]], Map::new(), [], type_map)
          is_active = true
          idx = idx + 1
        }
      Atom(_) => {
        offset_expr = parse_instrs([items[idx]], Map::new(), [], type_map)
        is_active = true
        idx = idx + 1
      }
      StringLit(_) => ()
    }
  }
  let data_bytes : Array[Byte] = []
  for i in idx..<items.length() {
    match items[i] {
      StringLit(bytes) =>
        for b in bytes {
          data_bytes.push(b)
        }
      _ => raise WatError::InvalidSyntax("data expects string literals")
    }
  }
  WatData::{
    name,
    mem_ref,
    offset: offset_expr,
    init: Bytes::from_array(data_bytes),
    is_active,
  }
}

///|
fn parse_elem(
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> WatElem raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let mut table_ref = IndexRef::Index(0U)
  let mut offset_instrs : Array[WatInstr] = []
  let mut is_active = false
  let elem_type = @core.RefType::Func
  if idx < items.length() {
    match items[idx] {
      List(list_items) =>
        if list_items.length() > 0 &&
          list_items[0] is Atom(tag) &&
          tag == b"table" {
          guard list_items.length() == 2 else {
            raise WatError::InvalidSyntax("table expects one index")
          }
          table_ref = parse_index_ref(expect_atom(list_items[1]))
          idx = idx + 1
        }
      _ => ()
    }
  }
  if idx < items.length() {
    match items[idx] {
      List(list_items) =>
        if list_items.length() > 0 &&
          list_items[0] is Atom(tag) &&
          tag == b"offset" {
          let offset_items = slice_sexprs(list_items, 1)
          offset_instrs = parse_instrs(offset_items, Map::new(), [], type_map)
          is_active = true
          idx = idx + 1
        } else if list_items.length() > 0 &&
          list_items[0] is Atom(tag) &&
          tag == b"func" {
          ()
        } else {
          offset_instrs = parse_instrs([items[idx]], Map::new(), [], type_map)
          is_active = true
          idx = idx + 1
        }
      Atom(atom) =>
        if atom == b"func" {
          ()
        } else {
          offset_instrs = parse_instrs([items[idx]], Map::new(), [], type_map)
          is_active = true
          idx = idx + 1
        }
      _ => ()
    }
  }
  if idx < items.length() && items[idx] is Atom(atom) && atom == b"func" {
    idx = idx + 1
  }
  let init : Array[FuncRef] = []
  for i in idx..<items.length() {
    match items[i] {
      Atom(atom) => init.push(parse_func_ref(atom))
      List(list_items) => {
        guard list_items.length() == 2 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("elem expects func indices")
        }
        guard tag == b"func" else {
          raise WatError::InvalidSyntax("elem expects func indices")
        }
        init.push(parse_func_ref(expect_atom(list_items[1])))
      }
      _ => raise WatError::InvalidSyntax("elem expects func indices")
    }
  }
  WatElem::{
    name,
    table_ref,
    offset: offset_instrs,
    init,
    is_active,
    elem_type,
  }
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
    b"table" => WatExportDesc::Table(parse_index_ref(ref_atom))
    b"tag" => WatExportDesc::Tag(parse_index_ref(ref_atom))
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
fn parse_type_def(
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> WatTypeDef raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  guard idx < items.length() && items[idx] is List(list_items) else {
    raise WatError::InvalidSyntax("type expects func")
  }
  guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
    raise WatError::InvalidSyntax("type func head must be atom")
  }
  guard tag == b"func" else {
    raise WatError::InvalidSyntax("type expects func")
  }
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  for i in 1..<list_items.length() {
    match list_items[i] {
      List(inner) => {
        guard inner.length() > 0 && inner[0] is Atom(inner_tag) else {
          raise WatError::InvalidSyntax("func type item tag must be atom")
        }
        match inner_tag {
          b"param" => append_types(params, inner, type_map, allow_names=true)
          b"result" => append_types(results, inner, type_map, allow_names=false)
          _ => raise WatError::Unsupported("func type item \{inner_tag}")
        }
      }
      _ => raise WatError::InvalidSyntax("unexpected item in type")
    }
  }
  WatTypeDef::{ name, params, results }
}

///|
fn parse_type_ref(items : Array[SExpr]) -> WatTypeRef raise WatError {
  guard items.length() == 2 else {
    raise WatError::InvalidSyntax("type expects one index")
  }
  let atom = expect_atom(items[1])
  parse_type_ref_atom(atom)
}

///|
fn parse_type_ref_atom(atom : Bytes) -> WatTypeRef raise WatError {
  if is_name(atom) {
    WatTypeRef::Name(atom)
  } else {
    WatTypeRef::Index(parse_uint(atom))
  }
}

///|
fn resolve_type_use(
  type_ref : WatTypeRef?,
  inline_params : Array[@core.ValType],
  inline_results : Array[@core.ValType],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
) -> (UInt?, Array[@core.ValType], Array[@core.ValType]) raise WatError {
  match type_ref {
    Some(ref_) => {
      let idx = resolve_type_ref(ref_, type_map)
      guard idx < type_defs.length().reinterpret_as_uint() else {
        raise WatError::UnknownIdentifier("type \{idx}")
      }
      let def = type_defs[idx.reinterpret_as_int()]
      if inline_params.length() > 0 || inline_results.length() > 0 {
        guard same_sig_arrays(
          inline_params,
          inline_results,
          def.params,
          def.results,
        ) else {
          raise WatError::InvalidSyntax("typeuse does not match type")
        }
      }
      (Some(idx), def.params, def.results)
    }
    None => (None, inline_params, inline_results)
  }
}

///|
fn resolve_type_ref(
  type_ref : WatTypeRef,
  type_map : Map[Bytes, UInt],
) -> UInt raise WatError {
  match type_ref {
    Index(idx) => idx
    Name(name) =>
      match type_map.get(name) {
        Some(idx) => idx
        None => raise WatError::UnknownIdentifier("type \{name}")
      }
  }
}

///|
fn resolve_type_use_index(
  type_ref : WatTypeRef?,
  params : Array[@core.ValType],
  results : Array[@core.ValType],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
  types : Array[@core.FuncType],
) -> UInt raise WatError {
  match type_ref {
    Some(ref_) => {
      let idx = resolve_type_ref(ref_, type_map)
      guard idx < type_defs.length().reinterpret_as_uint() else {
        raise WatError::UnknownIdentifier("type \{idx}")
      }
      let def = type_defs[idx.reinterpret_as_int()]
      if params.length() > 0 || results.length() > 0 {
        guard same_sig_arrays(params, results, def.params, def.results) else {
          raise WatError::InvalidSyntax("typeuse does not match type")
        }
      }
      idx
    }
    None => type_index(types, params, results)
  }
}

///|
fn parse_func_typeuse(
  items : Array[SExpr],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
) -> (Bytes?, UInt?, Array[@core.ValType], Array[@core.ValType]) raise WatError {
  let mut idx = 1
  let mut name : Bytes? = None
  if idx < items.length() && items[idx] is Atom(atom) && is_name(atom) {
    name = Some(atom)
    idx = idx + 1
  }
  let mut type_ref : WatTypeRef? = None
  let params : Array[@core.ValType] = []
  let results : Array[@core.ValType] = []
  for i in idx..<items.length() {
    match items[i] {
      List(list_items) => {
        guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
          raise WatError::InvalidSyntax("func type item tag must be atom")
        }
        match tag {
          b"type" => {
            guard type_ref is None else {
              raise WatError::InvalidSyntax("duplicate type in func typeuse")
            }
            type_ref = Some(parse_type_ref(list_items))
          }
          b"param" =>
            append_types(params, list_items, type_map, allow_names=true)
          b"result" =>
            append_types(results, list_items, type_map, allow_names=false)
          _ => raise WatError::Unsupported("func type item \{tag}")
        }
      }
      _ => raise WatError::InvalidSyntax("unexpected item in func typeuse")
    }
  }
  let (type_idx, resolved_params, resolved_results) = resolve_type_use(
    type_ref, params, results, type_defs, type_map,
  )
  (name, type_idx, resolved_params, resolved_results)
}

///|
fn parse_global_type(
  expr : SExpr,
  type_map : Map[Bytes, UInt],
) -> @core.GlobalType raise WatError {
  match expr {
    List(list_items) => {
      guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
        raise WatError::InvalidSyntax("global type list invalid")
      }
      if tag == b"mut" {
        guard list_items.length() == 2 else {
          raise WatError::InvalidSyntax("global mut type invalid")
        }
        let val_type = parse_valtype_expr(list_items[1], type_map)
        @core.GlobalType::{ val_type, mutable: true }
      } else {
        let val_type = parse_valtype_expr(expr, type_map)
        @core.GlobalType::{ val_type, mutable: false }
      }
    }
    Atom(atom) => {
      let val_type = parse_valtype_atom(atom, type_map)
      @core.GlobalType::{ val_type, mutable: false }
    }
    _ => raise WatError::InvalidSyntax("global type invalid")
  }
}

///|
fn append_types(
  dst : Array[@core.ValType],
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
  allow_names~ : Bool,
) -> Unit raise WatError {
  let mut pending = false
  for i in 1..<items.length() {
    match items[i] {
      Atom(atom) => {
        if allow_names && is_name(atom) {
          guard not(pending) else {
            raise WatError::InvalidSyntax("duplicate name without type")
          }
          pending = true
          continue
        }
        dst.push(parse_valtype_atom(atom, type_map))
        pending = false
      }
      List(_) => {
        dst.push(parse_valtype_expr(items[i], type_map))
        pending = false
      }
      _ => raise WatError::InvalidSyntax("expected type")
    }
  }
  if pending {
    raise WatError::InvalidSyntax("dangling name without type")
  }
}

///|
fn append_named_types(
  dst_types : Array[@core.ValType],
  dst_names : Array[Bytes?],
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> Unit raise WatError {
  let mut pending : Bytes? = None
  for i in 1..<items.length() {
    match items[i] {
      Atom(atom) => {
        if is_name(atom) {
          guard pending is None else {
            raise WatError::InvalidSyntax("duplicate name without type")
          }
          pending = Some(atom)
          continue
        }
        dst_types.push(parse_valtype_atom(atom, type_map))
        dst_names.push(pending)
        pending = None
      }
      List(_) => {
        dst_types.push(parse_valtype_expr(items[i], type_map))
        dst_names.push(pending)
        pending = None
      }
      _ => raise WatError::InvalidSyntax("expected type")
    }
  }
  if pending is Some(_) {
    raise WatError::InvalidSyntax("dangling name without type")
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
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> Array[WatInstr] raise WatError {
  let instrs : Array[WatInstr] = []
  let mut i = 0
  while i < items.length() {
    match items[i] {
      Atom(op) => {
        let (instr, next_idx) = parse_instr_from_atom(
          items, i, op, local_map, labels, type_map,
        )
        instrs.push(instr)
        i = next_idx
      }
      List(list_items) => {
        instrs.push(
          parse_instr_from_list(list_items, local_map, labels, type_map),
        )
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
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> (WatInstr, Int) raise WatError {
  match parse_simd_instr_from_atom(items, idx, op) {
    Some(result) => return result
    None => ()
  }
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
    b"return_call" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::ReturnCall(parse_func_ref(imm)), idx + 2)
    }
    b"call_indirect" => parse_call_indirect_from_items(items, idx + 1, type_map)
    b"return_call_indirect" => {
      let (call_indirect, next_idx) = parse_call_indirect_items_from_items(
        items,
        idx + 1,
        type_map,
        b"return_call_indirect",
        "return_call_indirect",
      )
      (WatInstr::ReturnCallIndirect(call_indirect), next_idx)
    }
    b"call_ref" => {
      let (typeuse, next_idx) = parse_call_ref_typeuse_from_items(
        items,
        idx + 1,
        type_map,
        b"call_ref",
        "call_ref",
      )
      (WatInstr::CallRef(typeuse), next_idx)
    }
    b"return_call_ref" => {
      let (typeuse, next_idx) = parse_call_ref_typeuse_from_items(
        items,
        idx + 1,
        type_map,
        b"return_call_ref",
        "return_call_ref",
      )
      (WatInstr::ReturnCallRef(typeuse), next_idx)
    }
    b"ref.null" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::RefNull(parse_heaptype_atom(imm, type_map))),
        idx + 2,
      )
    }
    b"ref.func" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::RefFunc(parse_func_ref(imm)), idx + 2)
    }
    b"table.get" => {
      let (table_ref, next_idx) = parse_table_index_from_items(items, idx + 1)
      (WatInstr::TableGet(table_ref), next_idx)
    }
    b"table.set" => {
      let (table_ref, next_idx) = parse_table_index_from_items(items, idx + 1)
      (WatInstr::TableSet(table_ref), next_idx)
    }
    b"table.size" => {
      let (table_ref, next_idx) = parse_table_index_from_items(items, idx + 1)
      (WatInstr::TableSize(table_ref), next_idx)
    }
    b"table.grow" => {
      let (table_ref, next_idx) = parse_table_index_from_items(items, idx + 1)
      (WatInstr::TableGrow(table_ref), next_idx)
    }
    b"table.init" => {
      let (table_ref, elem_ref, next_idx) = parse_table_init_from_items(
        items,
        idx + 1,
      )
      (WatInstr::TableInit(table_ref, elem_ref), next_idx)
    }
    b"table.copy" => {
      let (dst_ref, src_ref, next_idx) = parse_table_copy_from_items(
        items,
        idx + 1,
      )
      (WatInstr::TableCopy(dst_ref, src_ref), next_idx)
    }
    b"table.fill" => {
      let (table_ref, next_idx) = parse_table_index_from_items(items, idx + 1)
      (WatInstr::TableFill(table_ref), next_idx)
    }
    b"elem.drop" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::ElemDrop(parse_index_ref(imm)), idx + 2)
    }
    b"memory.init" => {
      let (data_ref, mem_ref, next_idx) = parse_memory_init_from_items(
        items,
        idx + 1,
      )
      (WatInstr::MemoryInit(data_ref, mem_ref), next_idx)
    }
    b"data.drop" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::DataDrop(parse_index_ref(imm)), idx + 2)
    }
    b"memory.copy" => {
      let (dst_ref, src_ref, next_idx) = parse_memory_copy_from_items(
        items,
        idx + 1,
      )
      (WatInstr::MemoryCopy(dst_ref, src_ref), next_idx)
    }
    b"memory.fill" => {
      let (mem_ref, next_idx) = parse_memory_index_from_items(items, idx + 1)
      (WatInstr::MemoryFill(mem_ref), next_idx)
    }
    b"throw" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::Throw(parse_index_ref(imm)), idx + 2)
    }
    b"rethrow" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::Rethrow(resolve_label_ref(imm, labels)), idx + 2)
    }
    b"br" => {
      let imm = expect_atom_at(items, idx + 1)
      (WatInstr::Core(@core.Instr::Br(resolve_label_ref(imm, labels))), idx + 2)
    }
    b"br_if" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::BrIf(resolve_label_ref(imm, labels))),
        idx + 2,
      )
    }
    b"br_on_null" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::BrOnNull(resolve_label_ref(imm, labels))),
        idx + 2,
      )
    }
    b"br_on_non_null" => {
      let imm = expect_atom_at(items, idx + 1)
      (
        WatInstr::Core(@core.Instr::BrOnNonNull(resolve_label_ref(imm, labels))),
        idx + 2,
      )
    }
    b"br_table" => {
      let (targets, default_target, next_idx) = parse_br_table_from_items(
        items,
        idx + 1,
        labels,
      )
      (WatInstr::Core(@core.Instr::BrTable(targets, default_target)), next_idx)
    }
    b"memory.size" => {
      let (mem_ref, next_idx) = parse_memory_index_from_items(items, idx + 1)
      (WatInstr::MemorySize(mem_ref), next_idx)
    }
    b"memory.grow" => {
      let (mem_ref, next_idx) = parse_memory_index_from_items(items, idx + 1)
      (WatInstr::MemoryGrow(mem_ref), next_idx)
    }
    b"select" => {
      if idx + 1 < items.length() {
        match items[idx + 1] {
          List(result_items) =>
            if result_items.length() > 0 &&
              result_items[0] is Atom(head) &&
              head == b"result" {
              let types : Array[@core.ValType] = []
              for i in 1..<result_items.length() {
                types.push(parse_valtype_expr(result_items[i], type_map))
              }
              return (WatInstr::Core(@core.Instr::SelectTyped(types)), idx + 2)
            }
          _ => ()
        }
      }
      (WatInstr::Core(@core.Instr::Select), idx + 1)
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
  labels : Array[Bytes?],
  type_map : Map[Bytes, UInt],
) -> WatInstr raise WatError {
  match parse_simd_instr_from_list(list_items) {
    Some(result) => return result
    None => ()
  }
  guard list_items.length() > 0 else {
    raise WatError::InvalidSyntax("empty instruction list")
  }
  guard list_items[0] is Atom(op) else {
    raise WatError::InvalidSyntax("instruction head must be atom")
  }
  match op {
    b"block" => parse_block_instr(list_items, local_map, labels, type_map)
    b"loop" => parse_loop_instr(list_items, local_map, labels, type_map)
    b"if" => parse_if_instr(list_items, local_map, labels, type_map)
    b"try_table" =>
      parse_try_table_instr(list_items, local_map, labels, type_map)
    b"call_indirect" => parse_call_indirect(list_items, type_map)
    b"return_call_indirect" =>
      WatInstr::ReturnCallIndirect(
        parse_call_indirect_items(list_items, type_map, "return_call_indirect"),
      )
    b"ref.null" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("ref.null expects one operand")
      }
      WatInstr::Core(
        @core.Instr::RefNull(
          parse_heaptype_atom(expect_atom(list_items[1]), type_map),
        ),
      )
    }
    b"ref.func" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("ref.func expects one operand")
      }
      WatInstr::RefFunc(parse_func_ref(expect_atom(list_items[1])))
    }
    b"table.get" => {
      let table_ref = parse_table_index_from_list(list_items, 1)
      WatInstr::TableGet(table_ref)
    }
    b"table.set" => {
      let table_ref = parse_table_index_from_list(list_items, 1)
      WatInstr::TableSet(table_ref)
    }
    b"table.size" => {
      let table_ref = parse_table_index_from_list(list_items, 1)
      WatInstr::TableSize(table_ref)
    }
    b"table.grow" => {
      let table_ref = parse_table_index_from_list(list_items, 1)
      WatInstr::TableGrow(table_ref)
    }
    b"table.init" => {
      let (table_ref, elem_ref) = parse_table_init_from_list(list_items)
      WatInstr::TableInit(table_ref, elem_ref)
    }
    b"table.copy" => {
      let (dst_ref, src_ref) = parse_table_copy_from_list(list_items)
      WatInstr::TableCopy(dst_ref, src_ref)
    }
    b"table.fill" => {
      let table_ref = parse_table_index_from_list(list_items, 1)
      WatInstr::TableFill(table_ref)
    }
    b"elem.drop" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("elem.drop expects one operand")
      }
      WatInstr::ElemDrop(parse_index_ref(expect_atom(list_items[1])))
    }
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
          types.push(parse_valtype_expr(result_items[i], type_map))
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
    b"return_call" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("return_call expects one operand")
      }
      WatInstr::ReturnCall(parse_func_ref(expect_atom(list_items[1])))
    }
    b"call_ref" =>
      WatInstr::CallRef(parse_typeuse(list_items, 1, type_map, "call_ref"))
    b"return_call_ref" =>
      WatInstr::ReturnCallRef(
        parse_typeuse(list_items, 1, type_map, "return_call_ref"),
      )
    b"br" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("br expects one operand")
      }
      WatInstr::Core(
        @core.Instr::Br(resolve_label_ref(expect_atom(list_items[1]), labels)),
      )
    }
    b"br_if" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("br_if expects one operand")
      }
      WatInstr::Core(
        @core.Instr::BrIf(resolve_label_ref(expect_atom(list_items[1]), labels)),
      )
    }
    b"br_on_null" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("br_on_null expects one operand")
      }
      WatInstr::Core(
        @core.Instr::BrOnNull(
          resolve_label_ref(expect_atom(list_items[1]), labels),
        ),
      )
    }
    b"br_on_non_null" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("br_on_non_null expects one operand")
      }
      WatInstr::Core(
        @core.Instr::BrOnNonNull(
          resolve_label_ref(expect_atom(list_items[1]), labels),
        ),
      )
    }
    b"br_table" => {
      guard list_items.length() >= 2 else {
        raise WatError::InvalidSyntax("br_table expects operands")
      }
      let (targets, default_target) = parse_br_table_from_list(
        list_items, labels,
      )
      WatInstr::Core(@core.Instr::BrTable(targets, default_target))
    }
    b"memory.size" => {
      guard list_items.length() <= 2 else {
        raise WatError::InvalidSyntax("memory.size expects zero or one operand")
      }
      let mem_ref = parse_memory_index_from_list(list_items, 1)
      WatInstr::MemorySize(mem_ref)
    }
    b"memory.grow" => {
      guard list_items.length() <= 2 else {
        raise WatError::InvalidSyntax("memory.grow expects zero or one operand")
      }
      let mem_ref = parse_memory_index_from_list(list_items, 1)
      WatInstr::MemoryGrow(mem_ref)
    }
    b"memory.init" => {
      let (data_ref, mem_ref) = parse_memory_init_from_list(list_items)
      WatInstr::MemoryInit(data_ref, mem_ref)
    }
    b"data.drop" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("data.drop expects one operand")
      }
      WatInstr::DataDrop(parse_index_ref(expect_atom(list_items[1])))
    }
    b"memory.copy" => {
      let (dst_ref, src_ref) = parse_memory_copy_from_list(list_items)
      WatInstr::MemoryCopy(dst_ref, src_ref)
    }
    b"memory.fill" => {
      let mem_ref = parse_memory_index_from_list(list_items, 1)
      WatInstr::MemoryFill(mem_ref)
    }
    b"throw" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("throw expects one operand")
      }
      WatInstr::Throw(parse_index_ref(expect_atom(list_items[1])))
    }
    b"rethrow" => {
      guard list_items.length() == 2 else {
        raise WatError::InvalidSyntax("rethrow expects one operand")
      }
      WatInstr::Rethrow(resolve_label_ref(expect_atom(list_items[1]), labels))
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
fn simd_memarg_default_align(op : Bytes) -> UInt? {
  match op {
    b"v128.load" | b"v128.store" => Some(4U)
    b"v128.load8x8_s"
    | b"v128.load8x8_u"
    | b"v128.load16x4_s"
    | b"v128.load16x4_u"
    | b"v128.load32x2_s"
    | b"v128.load32x2_u"
    | b"v128.load64_splat" => Some(3U)
    b"v128.load8_splat" | b"v128.load8_lane" | b"v128.store8_lane" => Some(0U)
    b"v128.load16_splat" | b"v128.load16_lane" | b"v128.store16_lane" =>
      Some(1U)
    b"v128.load32_splat"
    | b"v128.load32_lane"
    | b"v128.store32_lane"
    | b"v128.load32_zero" => Some(2U)
    b"v128.load64_lane" | b"v128.store64_lane" | b"v128.load64_zero" => Some(3U)
    _ => None
  }
}

///|
fn simd_lane_count(op : Bytes) -> UInt? {
  if bytes_starts_with(op, b"i8x16.") {
    return Some(16U)
  }
  if bytes_starts_with(op, b"i16x8.") {
    return Some(8U)
  }
  if bytes_starts_with(op, b"i32x4.") || bytes_starts_with(op, b"f32x4.") {
    return Some(4U)
  }
  if bytes_starts_with(op, b"i64x2.") || bytes_starts_with(op, b"f64x2.") {
    return Some(2U)
  }
  match op {
    b"v128.load8_lane" | b"v128.store8_lane" => Some(16U)
    b"v128.load16_lane" | b"v128.store16_lane" => Some(8U)
    b"v128.load32_lane" | b"v128.store32_lane" => Some(4U)
    b"v128.load64_lane" | b"v128.store64_lane" => Some(2U)
    _ => None
  }
}

///|
fn parse_simd_lane(op : Bytes, atom : Bytes) -> UInt raise WatError {
  let lane = parse_uint(atom)
  match simd_lane_count(op) {
    Some(limit) =>
      if lane >= limit {
        raise WatError::InvalidSyntax("lane out of range")
      }
    None => ()
  }
  lane
}

///|
fn append_u16_le(bytes : Array[Byte], value : UInt) -> Unit {
  bytes.push((value & 0xFFU).to_byte())
  bytes.push(((value >> 8) & 0xFFU).to_byte())
}

///|
fn append_u32_le(bytes : Array[Byte], value : UInt) -> Unit {
  bytes.push((value & 0xFFU).to_byte())
  bytes.push(((value >> 8) & 0xFFU).to_byte())
  bytes.push(((value >> 16) & 0xFFU).to_byte())
  bytes.push(((value >> 24) & 0xFFU).to_byte())
}

///|
fn append_u64_le(bytes : Array[Byte], value : UInt64) -> Unit {
  bytes.push((value & 0xFFUL).to_byte())
  bytes.push(((value >> 8) & 0xFFUL).to_byte())
  bytes.push(((value >> 16) & 0xFFUL).to_byte())
  bytes.push(((value >> 24) & 0xFFUL).to_byte())
  bytes.push(((value >> 32) & 0xFFUL).to_byte())
  bytes.push(((value >> 40) & 0xFFUL).to_byte())
  bytes.push(((value >> 48) & 0xFFUL).to_byte())
  bytes.push(((value >> 56) & 0xFFUL).to_byte())
}

///|
fn parse_v128_const_from_items(
  items : Array[SExpr],
  start : Int,
) -> (Array[Byte], Int) raise WatError {
  let lane_type = expect_atom_at(items, start)
  let mut idx = start + 1
  let bytes : Array[Byte] = []
  match lane_type {
    b"i8x16" =>
      for _ in 0..<16 {
        let atom = expect_atom_at(items, idx)
        let val = parse_int(atom).reinterpret_as_uint()
        bytes.push((val & 0xFFU).to_byte())
        idx = idx + 1
      }
    b"i16x8" =>
      for _ in 0..<8 {
        let atom = expect_atom_at(items, idx)
        let val = parse_int(atom).reinterpret_as_uint()
        append_u16_le(bytes, val)
        idx = idx + 1
      }
    b"i32x4" =>
      for _ in 0..<4 {
        let atom = expect_atom_at(items, idx)
        let val = parse_int(atom).reinterpret_as_uint()
        append_u32_le(bytes, val)
        idx = idx + 1
      }
    b"i64x2" =>
      for _ in 0..<2 {
        let atom = expect_atom_at(items, idx)
        let val = parse_int64(atom).reinterpret_as_uint64()
        append_u64_le(bytes, val)
        idx = idx + 1
      }
    b"f32x4" =>
      for _ in 0..<4 {
        let atom = expect_atom_at(items, idx)
        let val = parse_float(atom)
        append_u32_le(bytes, val.reinterpret_as_uint())
        idx = idx + 1
      }
    b"f64x2" =>
      for _ in 0..<2 {
        let atom = expect_atom_at(items, idx)
        let val = parse_double(atom)
        append_u64_le(bytes, val.reinterpret_as_uint64())
        idx = idx + 1
      }
    _ => raise WatError::InvalidSyntax("v128.const expects lane type")
  }
  (bytes, idx)
}

///|
fn parse_simd_shuffle_from_items(
  items : Array[SExpr],
  start : Int,
) -> (Array[Byte], Int) raise WatError {
  let bytes : Array[Byte] = []
  let mut idx = start
  for _ in 0..<16 {
    let atom = expect_atom_at(items, idx)
    let lane = parse_uint(atom)
    guard lane <= 31U else {
      raise WatError::InvalidSyntax("shuffle lane out of range")
    }
    bytes.push(lane.to_byte())
    idx = idx + 1
  }
  (bytes, idx)
}

///|
fn parse_simd_instr_from_atom(
  items : Array[SExpr],
  idx : Int,
  op : Bytes,
) -> (WatInstr, Int)? raise WatError {
  match @core.simd_spec_by_name(op) {
    None => None
    Some(spec) => {
      let (imm, next_idx) = match spec.imm {
        None => (@core.SimdImmediate::None, idx + 1)
        Lane => {
          let lane_atom = expect_atom_at(items, idx + 1)
          let lane = parse_simd_lane(op, lane_atom)
          (@core.SimdImmediate::Lane(lane), idx + 2)
        }
        MemArg => {
          let default_align = match simd_memarg_default_align(op) {
            Some(value) => value
            None => raise WatError::Unsupported("instruction \{op}")
          }
          let (align, offset, next_idx) = parse_memarg_from_items(
            items,
            idx + 1,
            default_align,
          )
          (@core.SimdImmediate::MemArg(align, offset), next_idx)
        }
        MemArgLane => {
          let default_align = match simd_memarg_default_align(op) {
            Some(value) => value
            None => raise WatError::Unsupported("instruction \{op}")
          }
          let (align, offset, next_idx) = parse_memarg_from_items(
            items,
            idx + 1,
            default_align,
          )
          let lane_atom = expect_atom_at(items, next_idx)
          let lane = parse_simd_lane(op, lane_atom)
          (@core.SimdImmediate::MemArgLane(align, offset, lane), next_idx + 1)
        }
        Shuffle => {
          let (bytes, next_idx) = parse_simd_shuffle_from_items(items, idx + 1)
          (@core.SimdImmediate::Shuffle(bytes), next_idx)
        }
        V128Const => {
          let (bytes, next_idx) = parse_v128_const_from_items(items, idx + 1)
          (@core.SimdImmediate::V128Const(bytes), next_idx)
        }
      }
      let simd = @core.SimdInstr::{ opcode: spec.opcode, imm }
      Some((WatInstr::Core(@core.Instr::Simd(simd)), next_idx))
    }
  }
}

///|
fn parse_simd_instr_from_list(
  list_items : Array[SExpr],
) -> WatInstr? raise WatError {
  guard list_items.length() > 0 && list_items[0] is Atom(op) else {
    return None
  }
  match @core.simd_spec_by_name(op) {
    None => None
    Some(spec) => {
      let imm = match spec.imm {
        None => {
          guard list_items.length() == 1 else {
            raise WatError::InvalidSyntax("unexpected operands for \{op}")
          }
          @core.SimdImmediate::None
        }
        Lane => {
          guard list_items.length() == 2 else {
            raise WatError::InvalidSyntax("lane expects one operand")
          }
          let lane_atom = expect_atom(list_items[1])
          @core.SimdImmediate::Lane(parse_simd_lane(op, lane_atom))
        }
        MemArg => {
          let default_align = match simd_memarg_default_align(op) {
            Some(value) => value
            None => raise WatError::Unsupported("instruction \{op}")
          }
          let (align, offset, next_idx) = parse_memarg_from_items(
            list_items, 1, default_align,
          )
          guard next_idx == list_items.length() else {
            raise WatError::InvalidSyntax("unexpected operands for \{op}")
          }
          @core.SimdImmediate::MemArg(align, offset)
        }
        MemArgLane => {
          let default_align = match simd_memarg_default_align(op) {
            Some(value) => value
            None => raise WatError::Unsupported("instruction \{op}")
          }
          let (align, offset, next_idx) = parse_memarg_from_items(
            list_items, 1, default_align,
          )
          guard next_idx + 1 == list_items.length() else {
            raise WatError::InvalidSyntax("lane expects one operand")
          }
          let lane_atom = expect_atom(list_items[next_idx])
          let lane = parse_simd_lane(op, lane_atom)
          @core.SimdImmediate::MemArgLane(align, offset, lane)
        }
        Shuffle => {
          guard list_items.length() == 17 else {
            raise WatError::InvalidSyntax("shuffle expects 16 lanes")
          }
          let (bytes, next_idx) = parse_simd_shuffle_from_items(list_items, 1)
          guard next_idx == list_items.length() else {
            raise WatError::InvalidSyntax("shuffle expects 16 lanes")
          }
          @core.SimdImmediate::Shuffle(bytes)
        }
        V128Const => {
          let (bytes, next_idx) = parse_v128_const_from_items(list_items, 1)
          guard next_idx == list_items.length() else {
            raise WatError::InvalidSyntax("v128.const operand count mismatch")
          }
          @core.SimdImmediate::V128Const(bytes)
        }
      }
      let simd = @core.SimdInstr::{ opcode: spec.opcode, imm }
      Some(WatInstr::Core(@core.Instr::Simd(simd)))
    }
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

///|
fn parse_table_index_from_items(
  items : Array[SExpr],
  start : Int,
) -> (IndexRef, Int) raise WatError {
  guard start < items.length() else { return (IndexRef::Index(0U), start) }
  match items[start] {
    Atom(atom) =>
      if is_name(atom) || is_uint_atom(atom) {
        (parse_index_ref(atom), start + 1)
      } else {
        (IndexRef::Index(0U), start)
      }
    _ => (IndexRef::Index(0U), start)
  }
}

///|
fn parse_table_index_from_list(
  list_items : Array[SExpr],
  start : Int,
) -> IndexRef raise WatError {
  if list_items.length() == start {
    return IndexRef::Index(0U)
  }
  guard list_items.length() == start + 1 else {
    raise WatError::InvalidSyntax("table index expects one operand")
  }
  parse_index_ref(expect_atom(list_items[start]))
}

///|
fn parse_table_init_from_items(
  items : Array[SExpr],
  start : Int,
) -> (IndexRef, IndexRef, Int) raise WatError {
  guard start < items.length() else {
    raise WatError::InvalidSyntax("table.init expects operands")
  }
  let first = expect_atom_at(items, start)
  let first_ref = parse_index_ref(first)
  if start + 1 < items.length() {
    match items[start + 1] {
      Atom(atom) =>
        if is_name(atom) || is_uint_atom(atom) {
          let second_ref = parse_index_ref(atom)
          return (first_ref, second_ref, start + 2)
        }
      _ => ()
    }
  }
  (IndexRef::Index(0U), first_ref, start + 1)
}

///|
fn parse_table_init_from_list(
  list_items : Array[SExpr],
) -> (IndexRef, IndexRef) raise WatError {
  if list_items.length() == 2 {
    let elem_ref = parse_index_ref(expect_atom(list_items[1]))
    return (IndexRef::Index(0U), elem_ref)
  }
  guard list_items.length() == 3 else {
    raise WatError::InvalidSyntax("table.init expects one or two operands")
  }
  let table_ref = parse_index_ref(expect_atom(list_items[1]))
  let elem_ref = parse_index_ref(expect_atom(list_items[2]))
  (table_ref, elem_ref)
}

///|
fn parse_table_copy_from_items(
  items : Array[SExpr],
  start : Int,
) -> (IndexRef, IndexRef, Int) raise WatError {
  guard start <= items.length() else {
    raise WatError::InvalidSyntax("table.copy expects operands")
  }
  if start == items.length() {
    return (IndexRef::Index(0U), IndexRef::Index(0U), start)
  }
  if start + 1 < items.length() {
    match items[start] {
      Atom(first) =>
        if is_name(first) || is_uint_atom(first) {
          match items[start + 1] {
            Atom(second) =>
              if is_name(second) || is_uint_atom(second) {
                let dst = parse_index_ref(first)
                let src = parse_index_ref(second)
                return (dst, src, start + 2)
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  (IndexRef::Index(0U), IndexRef::Index(0U), start)
}

///|
fn parse_table_copy_from_list(
  list_items : Array[SExpr],
) -> (IndexRef, IndexRef) raise WatError {
  if list_items.length() == 1 {
    return (IndexRef::Index(0U), IndexRef::Index(0U))
  }
  guard list_items.length() == 3 else {
    raise WatError::InvalidSyntax("table.copy expects zero or two operands")
  }
  let dst = parse_index_ref(expect_atom(list_items[1]))
  let src = parse_index_ref(expect_atom(list_items[2]))
  (dst, src)
}

///|
fn parse_memory_index_from_items(
  items : Array[SExpr],
  start : Int,
) -> (IndexRef, Int) raise WatError {
  guard start < items.length() else { return (IndexRef::Index(0U), start) }
  match items[start] {
    Atom(atom) =>
      if is_name(atom) || is_uint_atom(atom) {
        (parse_index_ref(atom), start + 1)
      } else {
        (IndexRef::Index(0U), start)
      }
    _ => (IndexRef::Index(0U), start)
  }
}

///|
fn parse_memory_index_from_list(
  list_items : Array[SExpr],
  start : Int,
) -> IndexRef raise WatError {
  if list_items.length() == start {
    return IndexRef::Index(0U)
  }
  guard list_items.length() == start + 1 else {
    raise WatError::InvalidSyntax("memory index expects one operand")
  }
  parse_index_ref(expect_atom(list_items[start]))
}

///|
fn parse_memory_init_from_items(
  items : Array[SExpr],
  start : Int,
) -> (IndexRef, IndexRef, Int) raise WatError {
  guard start < items.length() else {
    raise WatError::InvalidSyntax("memory.init expects operands")
  }
  let data_atom = expect_atom_at(items, start)
  guard is_name(data_atom) || is_uint_atom(data_atom) else {
    raise WatError::InvalidSyntax("memory.init expects data index")
  }
  let data_ref = parse_index_ref(data_atom)
  if start + 1 < items.length() {
    match items[start + 1] {
      Atom(atom) =>
        if is_name(atom) || is_uint_atom(atom) {
          return (data_ref, parse_index_ref(atom), start + 2)
        }
      _ => ()
    }
  }
  (data_ref, IndexRef::Index(0U), start + 1)
}

///|
fn parse_memory_init_from_list(
  list_items : Array[SExpr],
) -> (IndexRef, IndexRef) raise WatError {
  if list_items.length() == 2 {
    return (parse_index_ref(expect_atom(list_items[1])), IndexRef::Index(0U))
  }
  guard list_items.length() == 3 else {
    raise WatError::InvalidSyntax("memory.init expects one or two operands")
  }
  let data_ref = parse_index_ref(expect_atom(list_items[1]))
  let mem_ref = parse_index_ref(expect_atom(list_items[2]))
  (data_ref, mem_ref)
}

///|
fn parse_memory_copy_from_items(
  items : Array[SExpr],
  start : Int,
) -> (IndexRef, IndexRef, Int) raise WatError {
  guard start <= items.length() else {
    raise WatError::InvalidSyntax("memory.copy expects operands")
  }
  if start == items.length() {
    return (IndexRef::Index(0U), IndexRef::Index(0U), start)
  }
  if start + 1 < items.length() {
    match items[start] {
      Atom(first) =>
        if is_name(first) || is_uint_atom(first) {
          match items[start + 1] {
            Atom(second) =>
              if is_name(second) || is_uint_atom(second) {
                let dst = parse_index_ref(first)
                let src = parse_index_ref(second)
                return (dst, src, start + 2)
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  (IndexRef::Index(0U), IndexRef::Index(0U), start)
}

///|
fn parse_memory_copy_from_list(
  list_items : Array[SExpr],
) -> (IndexRef, IndexRef) raise WatError {
  if list_items.length() == 1 {
    return (IndexRef::Index(0U), IndexRef::Index(0U))
  }
  guard list_items.length() == 3 else {
    raise WatError::InvalidSyntax("memory.copy expects zero or two operands")
  }
  let dst = parse_index_ref(expect_atom(list_items[1]))
  let src = parse_index_ref(expect_atom(list_items[2]))
  (dst, src)
}

///|
fn parse_simple_op(op : Bytes) -> @core.Instr? {
  match op {
    b"unreachable" => Some(@core.Instr::Unreachable)
    b"nop" => Some(@core.Instr::Nop)
    b"drop" => Some(@core.Instr::Drop)
    b"select" => Some(@core.Instr::Select)
    b"return" => Some(@core.Instr::Return)
    b"ref.is_null" => Some(@core.Instr::RefIsNull)
    b"ref.eq" => Some(@core.Instr::RefEq)
    b"ref.as_non_null" => Some(@core.Instr::RefAsNonNull)
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
  let table_map = Map::new()
  let global_map = Map::new()
  let tag_map = Map::new()
  let elem_map = Map::new()
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
  let mut table_index = 0U
  for imp in wat.table_imports {
    if imp.table_name is Some(name) {
      ensure_unique_name(table_map, name, "table")
      table_map[name] = table_index
    }
    table_index = table_index + 1U
  }
  for mem in wat.mems {
    if mem.name is Some(name) {
      ensure_unique_name(mem_map, name, "memory")
      mem_map[name] = mem_index
    }
    mem_index = mem_index + 1U
  }
  for table in wat.tables {
    if table.name is Some(name) {
      ensure_unique_name(table_map, name, "table")
      table_map[name] = table_index
    }
    table_index = table_index + 1U
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
  let mut tag_index = 0U
  for imp in wat.tag_imports {
    if imp.tag_name is Some(name) {
      ensure_unique_name(tag_map, name, "tag")
      tag_map[name] = tag_index
    }
    tag_index = tag_index + 1U
  }
  for tag in wat.tags {
    if tag.name is Some(name) {
      ensure_unique_name(tag_map, name, "tag")
      tag_map[name] = tag_index
    }
    tag_index = tag_index + 1U
  }
  let mut elem_index = 0U
  for elem in wat.elems {
    if elem.name is Some(name) {
      ensure_unique_name(elem_map, name, "elem")
      elem_map[name] = elem_index
    }
    elem_index = elem_index + 1U
  }
  let data_map = Map::new()
  let mut data_index = 0U
  for data in wat.datas {
    if data.name is Some(name) {
      ensure_unique_name(data_map, name, "data")
      data_map[name] = data_index
    }
    data_index = data_index + 1U
  }
  let types : Array[@core.FuncType] = []
  for type_def in wat.type_defs {
    types.push({ params: type_def.params, results: type_def.results })
  }
  let type_map = Map::new()
  for i in 0..<wat.type_defs.length() {
    let type_def = wat.type_defs[i]
    if type_def.name is Some(name) {
      type_map[name] = i.reinterpret_as_uint()
    }
  }
  let imports : Array[@core.Import] = []
  for imp in wat.func_imports {
    let type_idx = match imp.type_idx {
      Some(idx) => idx
      None => type_index(types, imp.params, imp.results)
    }
    imports.push({
      module_: imp.module_,
      name: imp.name,
      desc: @core.ImportDesc::Func(type_idx),
    })
  }
  for imp in wat.table_imports {
    imports.push({
      module_: imp.module_,
      name: imp.name,
      desc: @core.ImportDesc::Table(imp.table_type),
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
  for imp in wat.tag_imports {
    let type_idx = match imp.type_idx {
      Some(idx) => idx
      None => type_index(types, imp.params, imp.results)
    }
    imports.push({
      module_: imp.module_,
      name: imp.name,
      desc: @core.ImportDesc::Tag(type_idx),
    })
  }
  let funcs : Array[UInt] = []
  let codes : Array[@core.Code] = []
  for func in wat.funcs {
    let type_idx = match func.type_idx {
      Some(idx) => idx
      None => type_index(types, func.params, func.results)
    }
    funcs.push(type_idx)
    let instrs = resolve_instrs(
      func.body,
      func_map,
      table_map,
      elem_map,
      mem_map,
      data_map,
      global_map,
      tag_map,
      wat.type_defs,
      type_map,
      types,
    )
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
  let tags : Array[@core.Tag] = []
  for tag in wat.tags {
    let type_idx = match tag.type_idx {
      Some(idx) => idx
      None => type_index(types, tag.params, tag.results)
    }
    tags.push(@core.Tag::{ type_idx, })
  }
  let mems : Array[@core.MemType] = []
  for mem in wat.mems {
    mems.push({ limits: mem.limits })
  }
  let tables : Array[@core.TableType] = []
  for table in wat.tables {
    tables.push(table.table_type)
  }
  let elems : Array[@core.Elem] = []
  for elem in wat.elems {
    let table_idx = resolve_index_ref(elem.table_ref, table_map, "table")
    let offset_instrs = if elem.is_active {
      resolve_offset_instrs(elem.offset, global_map, wat.global_imports)
    } else {
      []
    }
    let init_indices : Array[UInt] = []
    for func_ref in elem.init {
      init_indices.push(resolve_func_ref(func_ref, func_map))
    }
    elems.push({
      table_idx,
      offset: @core.Expr::{ instrs: offset_instrs },
      init: init_indices,
      is_active: elem.is_active,
      elem_type: elem.elem_type,
    })
  }
  let exports : Array[@core.Export] = []
  for export_ in wat.exports {
    exports.push(
      resolve_export(export_, func_map, mem_map, table_map, global_map, tag_map),
    )
  }
  let datas : Array[@core.Data] = []
  for data in wat.datas {
    let mem_idx = resolve_index_ref(data.mem_ref, mem_map, "memory")
    let offset_instrs = if data.is_active {
      resolve_offset_instrs(data.offset, global_map, wat.global_imports)
    } else {
      []
    }
    datas.push({
      mem_idx,
      offset: @core.Expr::{ instrs: offset_instrs },
      init: data.init.sub(),
      is_active: data.is_active,
    })
  }
  let start = match wat.start {
    Some(func_ref) => Some(resolve_func_ref(func_ref, func_map))
    None => None
  }
  @core.Module::{
    types,
    funcs,
    tables,
    mems,
    globals,
    tags,
    elems,
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
  table_map : Map[Bytes, UInt],
  elem_map : Map[Bytes, UInt],
  mem_map : Map[Bytes, UInt],
  data_map : Map[Bytes, UInt],
  global_map : Map[Bytes, UInt],
  tag_map : Map[Bytes, UInt],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
  types : Array[@core.FuncType],
) -> Array[@core.Instr] raise WatError {
  let out : Array[@core.Instr] = []
  for instr in instrs {
    out.push(
      resolve_instr(
        instr, func_map, table_map, elem_map, mem_map, data_map, global_map, tag_map,
        type_defs, type_map, types,
      ),
    )
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
  table_map : Map[Bytes, UInt],
  elem_map : Map[Bytes, UInt],
  mem_map : Map[Bytes, UInt],
  data_map : Map[Bytes, UInt],
  global_map : Map[Bytes, UInt],
  tag_map : Map[Bytes, UInt],
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
  types : Array[@core.FuncType],
) -> @core.Instr raise WatError {
  match instr {
    WatInstr::Core(core_instr) => core_instr
    WatInstr::GlobalGet(global_ref) =>
      @core.Instr::GlobalGet(resolve_global_ref(global_ref, global_map))
    WatInstr::GlobalSet(global_ref) =>
      @core.Instr::GlobalSet(resolve_global_ref(global_ref, global_map))
    WatInstr::Call(func_ref) =>
      @core.Instr::Call(resolve_func_ref(func_ref, func_map))
    WatInstr::ReturnCall(func_ref) =>
      @core.Instr::ReturnCall(resolve_func_ref(func_ref, func_map))
    WatInstr::CallIndirect(call_indirect) => {
      let table_idx = resolve_index_ref(
        call_indirect.table_ref,
        table_map,
        "table",
      )
      let type_idx = resolve_type_use_index(
        call_indirect.type_ref,
        call_indirect.params,
        call_indirect.results,
        type_defs,
        type_map,
        types,
      )
      @core.Instr::CallIndirect(type_idx, table_idx)
    }
    WatInstr::ReturnCallIndirect(call_indirect) => {
      let table_idx = resolve_index_ref(
        call_indirect.table_ref,
        table_map,
        "table",
      )
      let type_idx = resolve_type_use_index(
        call_indirect.type_ref,
        call_indirect.params,
        call_indirect.results,
        type_defs,
        type_map,
        types,
      )
      @core.Instr::ReturnCallIndirect(type_idx, table_idx)
    }
    WatInstr::CallRef(typeuse) => {
      let type_idx = resolve_type_use_index(
        typeuse.type_ref,
        typeuse.params,
        typeuse.results,
        type_defs,
        type_map,
        types,
      )
      @core.Instr::CallRef(type_idx)
    }
    WatInstr::ReturnCallRef(typeuse) => {
      let type_idx = resolve_type_use_index(
        typeuse.type_ref,
        typeuse.params,
        typeuse.results,
        type_defs,
        type_map,
        types,
      )
      @core.Instr::ReturnCallRef(type_idx)
    }
    WatInstr::RefFunc(func_ref) =>
      @core.Instr::RefFunc(resolve_func_ref(func_ref, func_map))
    WatInstr::TableGet(table_ref) =>
      @core.Instr::TableGet(resolve_index_ref(table_ref, table_map, "table"))
    WatInstr::TableSet(table_ref) =>
      @core.Instr::TableSet(resolve_index_ref(table_ref, table_map, "table"))
    WatInstr::TableSize(table_ref) =>
      @core.Instr::TableSize(resolve_index_ref(table_ref, table_map, "table"))
    WatInstr::TableGrow(table_ref) =>
      @core.Instr::TableGrow(resolve_index_ref(table_ref, table_map, "table"))
    WatInstr::TableInit(table_ref, elem_ref) =>
      @core.Instr::TableInit(
        resolve_index_ref(table_ref, table_map, "table"),
        resolve_index_ref(elem_ref, elem_map, "elem"),
      )
    WatInstr::TableCopy(dst_ref, src_ref) =>
      @core.Instr::TableCopy(
        resolve_index_ref(dst_ref, table_map, "table"),
        resolve_index_ref(src_ref, table_map, "table"),
      )
    WatInstr::TableFill(table_ref) =>
      @core.Instr::TableFill(resolve_index_ref(table_ref, table_map, "table"))
    WatInstr::ElemDrop(elem_ref) =>
      @core.Instr::ElemDrop(resolve_index_ref(elem_ref, elem_map, "elem"))
    WatInstr::MemorySize(mem_ref) =>
      @core.Instr::MemorySize(resolve_index_ref(mem_ref, mem_map, "memory"))
    WatInstr::MemoryGrow(mem_ref) =>
      @core.Instr::MemoryGrow(resolve_index_ref(mem_ref, mem_map, "memory"))
    WatInstr::MemoryInit(data_ref, mem_ref) => {
      let data_idx = resolve_index_ref(data_ref, data_map, "data")
      let mem_idx = resolve_index_ref(mem_ref, mem_map, "memory")
      guard mem_idx == 0U else {
        raise WatError::Unsupported("memory.init only supports memory 0")
      }
      @core.Instr::MemoryInit(data_idx)
    }
    WatInstr::DataDrop(data_ref) =>
      @core.Instr::DataDrop(resolve_index_ref(data_ref, data_map, "data"))
    WatInstr::MemoryCopy(dst_ref, src_ref) => {
      let dst_idx = resolve_index_ref(dst_ref, mem_map, "memory")
      let src_idx = resolve_index_ref(src_ref, mem_map, "memory")
      guard dst_idx == 0U && src_idx == 0U else {
        raise WatError::Unsupported("memory.copy only supports memory 0")
      }
      @core.Instr::MemoryCopy
    }
    WatInstr::MemoryFill(mem_ref) => {
      let mem_idx = resolve_index_ref(mem_ref, mem_map, "memory")
      guard mem_idx == 0U else {
        raise WatError::Unsupported("memory.fill only supports memory 0")
      }
      @core.Instr::MemoryFill
    }
    WatInstr::Throw(tag_ref) =>
      @core.Instr::Throw(resolve_index_ref(tag_ref, tag_map, "tag"))
    WatInstr::Rethrow(label_idx) => @core.Instr::Rethrow(label_idx)
    WatInstr::Block(block_type, body) =>
      @core.Instr::Block(
        resolve_block_type(block_type, type_defs, type_map, types),
        resolve_instrs(
          body, func_map, table_map, elem_map, mem_map, data_map, global_map, tag_map,
          type_defs, type_map, types,
        ),
      )
    WatInstr::Loop(block_type, body) =>
      @core.Instr::Loop(
        resolve_block_type(block_type, type_defs, type_map, types),
        resolve_instrs(
          body, func_map, table_map, elem_map, mem_map, data_map, global_map, tag_map,
          type_defs, type_map, types,
        ),
      )
    WatInstr::If(block_type, then_body, else_body) =>
      @core.Instr::If(
        resolve_block_type(block_type, type_defs, type_map, types),
        resolve_instrs(
          then_body, func_map, table_map, elem_map, mem_map, data_map, global_map,
          tag_map, type_defs, type_map, types,
        ),
        resolve_instrs(
          else_body, func_map, table_map, elem_map, mem_map, data_map, global_map,
          tag_map, type_defs, type_map, types,
        ),
      )
    WatInstr::TryTable(block_type, catches, body) => {
      let resolved_catches : Array[@core.CatchClause] = []
      for clause in catches {
        match clause {
          WatCatchClause::Catch(tag_ref, label_idx) =>
            resolved_catches.push(
              @core.CatchClause::Catch(
                resolve_index_ref(tag_ref, tag_map, "tag"),
                label_idx,
              ),
            )
          WatCatchClause::CatchRef(tag_ref, label_idx) =>
            resolved_catches.push(
              @core.CatchClause::CatchRef(
                resolve_index_ref(tag_ref, tag_map, "tag"),
                label_idx,
              ),
            )
          WatCatchClause::CatchAll(label_idx) =>
            resolved_catches.push(@core.CatchClause::CatchAll(label_idx))
          WatCatchClause::CatchAllRef(label_idx) =>
            resolved_catches.push(@core.CatchClause::CatchAllRef(label_idx))
        }
      }
      @core.Instr::TryTable(
        resolve_block_type(block_type, type_defs, type_map, types),
        resolved_catches,
        resolve_instrs(
          body, func_map, table_map, elem_map, mem_map, data_map, global_map, tag_map,
          type_defs, type_map, types,
        ),
      )
    }
  }
}

///|
fn resolve_block_type(
  block_type : WatBlockType,
  type_defs : Array[WatTypeDef],
  type_map : Map[Bytes, UInt],
  types : Array[@core.FuncType],
) -> @core.BlockType raise WatError {
  match block_type {
    Empty => @core.BlockType::Empty
    Results(results) =>
      if results.length() == 0 {
        @core.BlockType::Empty
      } else if results.length() == 1 {
        @core.BlockType::Value(results[0])
      } else {
        @core.BlockType::TypeIndex(
          type_index(types, [], results).reinterpret_as_int(),
        )
      }
    TypeUse(typeuse) => {
      let idx = resolve_type_use_index(
        typeuse.type_ref,
        typeuse.params,
        typeuse.results,
        type_defs,
        type_map,
        types,
      )
      @core.BlockType::TypeIndex(idx.reinterpret_as_int())
    }
  }
}

///|
fn resolve_export(
  export_ : WatExport,
  func_map : Map[Bytes, UInt],
  mem_map : Map[Bytes, UInt],
  table_map : Map[Bytes, UInt],
  global_map : Map[Bytes, UInt],
  tag_map : Map[Bytes, UInt],
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
    Table(table_ref) => {
      let idx = resolve_index_ref(table_ref, table_map, "table")
      { name: export_.name, desc: @core.ExportDesc::Table(idx) }
    }
    Global(global_ref) => {
      let idx = resolve_index_ref(global_ref, global_map, "global")
      { name: export_.name, desc: @core.ExportDesc::Global(idx) }
    }
    Tag(tag_ref) => {
      let idx = resolve_index_ref(tag_ref, tag_map, "tag")
      { name: export_.name, desc: @core.ExportDesc::Tag(idx) }
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
fn same_sig_arrays(
  params : Array[@core.ValType],
  results : Array[@core.ValType],
  other_params : Array[@core.ValType],
  other_results : Array[@core.ValType],
) -> Bool {
  if params.length() != other_params.length() {
    return false
  }
  if results.length() != other_results.length() {
    return false
  }
  for i in 0..<params.length() {
    if params[i] != other_params[i] {
      return false
    }
  }
  for i in 0..<results.length() {
    if results[i] != other_results[i] {
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
fn parse_valtype_expr(
  expr : SExpr,
  type_map : Map[Bytes, UInt],
) -> @core.ValType raise WatError {
  match expr {
    Atom(atom) => parse_valtype_atom(atom, type_map)
    List(list_items) => {
      guard list_items.length() > 0 && list_items[0] is Atom(tag) else {
        raise WatError::InvalidSyntax("valtype list invalid")
      }
      match tag {
        b"ref" => parse_ref_valtype(list_items, type_map)
        _ => raise WatError::Unsupported("valtype \{tag}")
      }
    }
    _ => raise WatError::InvalidSyntax("expected type")
  }
}

///|
fn parse_valtype_atom(
  atom : Bytes,
  _type_map : Map[Bytes, UInt],
) -> @core.ValType raise WatError {
  match atom {
    b"i32" => I32
    b"i64" => I64
    b"f32" => F32
    b"f64" => F64
    b"v128" => V128
    b"funcref" => FuncRef
    b"externref" => ExternRef
    b"anyref" => AnyRef
    b"eqref" => EqRef
    b"i31ref" => I31Ref
    b"structref" => StructRef
    b"arrayref" => ArrayRef
    b"exnref" => ExnRef
    b"nullref" => NullRef
    b"nullfuncref" => NullFuncRef
    b"nullexternref" => NullExternRef
    b"nullexnref" => NullExnRef
    _ => raise WatError::Unsupported("valtype \{atom}")
  }
}

///|
fn parse_ref_valtype(
  items : Array[SExpr],
  type_map : Map[Bytes, UInt],
) -> @core.ValType raise WatError {
  guard items.length() == 2 || items.length() == 3 else {
    raise WatError::InvalidSyntax("ref type expects heap type")
  }
  let mut nullable = false
  let mut heap_idx = 1
  if items.length() == 3 {
    guard items[1] is Atom(tag) && tag == b"null" else {
      raise WatError::InvalidSyntax("ref type expects null")
    }
    nullable = true
    heap_idx = 2
  }
  let heap_type = parse_heaptype_atom(expect_atom(items[heap_idx]), type_map)
  valtype_from_ref(heap_type, nullable)
}

///|
fn valtype_from_ref(ref_type : @core.RefType, nullable : Bool) -> @core.ValType {
  if nullable {
    match ref_type {
      Func => FuncRef
      Extern => ExternRef
      Any => AnyRef
      Eq => EqRef
      I31 => I31Ref
      Struct => StructRef
      Array => ArrayRef
      Exn => ExnRef
      None => NullRef
      NoFunc => NullFuncRef
      NoExtern => NullExternRef
      NoExn => NullExnRef
      TypeIndex(_) => Ref(ref_type, true)
    }
  } else {
    Ref(ref_type, false)
  }
}

///|
fn valtype_to_reftype(
  val_type : @core.ValType,
) -> (@core.RefType, Bool) raise WatError {
  match val_type {
    FuncRef => (Func, true)
    ExternRef => (Extern, true)
    AnyRef => (Any, true)
    EqRef => (Eq, true)
    I31Ref => (I31, true)
    StructRef => (Struct, true)
    ArrayRef => (Array, true)
    ExnRef => (Exn, true)
    NullRef => (None, true)
    NullFuncRef => (NoFunc, true)
    NullExternRef => (NoExtern, true)
    NullExnRef => (NoExn, true)
    Ref(ref_type, nullable) => (ref_type, nullable)
    _ => raise WatError::InvalidSyntax("expected reference type")
  }
}

///|
fn parse_reftype_expr(
  expr : SExpr,
  type_map : Map[Bytes, UInt],
) -> (@core.RefType, Bool) raise WatError {
  let val_type = parse_valtype_expr(expr, type_map)
  valtype_to_reftype(val_type)
}

///|
fn parse_heaptype_atom(
  atom : Bytes,
  type_map : Map[Bytes, UInt],
) -> @core.RefType raise WatError {
  match atom {
    b"func" => @core.RefType::Func
    b"extern" => @core.RefType::Extern
    b"any" => @core.RefType::Any
    b"eq" => @core.RefType::Eq
    b"i31" => @core.RefType::I31
    b"struct" => @core.RefType::Struct
    b"array" => @core.RefType::Array
    b"exn" => @core.RefType::Exn
    b"none" => @core.RefType::None
    b"nofunc" => @core.RefType::NoFunc
    b"noextern" => @core.RefType::NoExtern
    b"noexn" => @core.RefType::NoExn
    _ =>
      if is_name(atom) {
        match type_map.get(atom) {
          Some(idx) => @core.RefType::TypeIndex(idx.reinterpret_as_int())
          None => raise WatError::UnknownIdentifier("type \{atom}")
        }
      } else {
        @core.RefType::TypeIndex(parse_uint(atom).reinterpret_as_int())
      }
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
