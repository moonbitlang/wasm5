///|
pub using @core {
  type ValType,
  type Value,
  type RefType,
  type FuncType,
  type TypeDef,
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
pub type Module = @core.Module

///|
pub using @parse {type ParseError}

///|
pub fn parse(bytes : Bytes) -> Module raise ParseError {
  @parse.parse(bytes)
}

///|
pub using @runtime {
  type HostFunc,
  type ImportedMemory,
  type Instance,
  type Imports,
  type RuntimeError,
  type RuntimeTable,
}
