///|
pub using @core {
  type ValType,
  type Value,
  type RefType,
  type FuncType,
  type TypeDef,
  type Module,
  type Limits,
  type MemType,
  type TableType,
  type GlobalType,
  type Export,
  type ExportDesc,
  type Import,
  type ImportDesc,
}

///|
pub using @parse {parse, type ParseError}

///|
pub using @runtime {type Runtime, type RuntimeError}
