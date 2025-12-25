///|
fn test_empty_expr() -> @core.Expr {
  { instrs: [] }
}

///|
fn test_empty_module() -> @core.Module {
  {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
}

///|
fn test_make_code(
  locals : Array[@core.ValType],
  instrs : Array[@core.Instr],
) -> @core.Code {
  { locals, body: { instrs, }, compiled: None }
}
