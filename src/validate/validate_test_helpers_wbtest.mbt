///|
fn test_empty_expr() -> @core.Expr {
  @core.Expr::{ instrs: [] }
}

///|
fn test_empty_module() -> @core.Module {
  @core.Module::{
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
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
  @core.Code::{ locals, body: @core.Expr::{ instrs, }, compiled: None }
}
