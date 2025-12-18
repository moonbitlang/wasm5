// Value types

///|
enum ValType {
  I32
  I64
  F32
  F64
  V128
  FuncRef
  ExternRef
  AnyRef
  ExnRef
  NullRef
  NullFuncRef
  NullExnRef
  NullExternRef
  EqRef
  I31Ref
  StructRef
  ArrayRef
  // Typed reference with explicit nullability: Ref(heap_type, nullable)
  // Used for (ref $t) when nullable=false, (ref null $t) when nullable=true
  Ref(RefType, Bool)
} derive(Show, Eq)

// Reference types (heap types)

///|
enum RefType {
  Func // 0x70
  Extern // 0x6F
  Any // 0x6E
  Eq // 0x6D
  I31 // 0x6C
  Struct // 0x6B
  Array // 0x6A
  Exn // 0x69
  None // 0x71 - bottom type
  NoFunc // 0x73 - bottom type for func
  NoExtern // 0x72 - bottom type for extern
  NoExn // 0x74 - bottom type for exn
  TypeIndex(Int) // typed reference (ref null $t)
} derive(Show, Eq)

///|
/// Check if a value type has a default value (is defaultable)
/// - Numeric types (i32, i64, f32, f64, v128): defaultable (default: 0)
/// - Nullable reference types: defaultable (default: null)
/// - Non-nullable reference types: NOT defaultable (must be initialized)
fn ValType::is_defaultable(self : ValType) -> Bool {
  match self {
    // Numeric types are always defaultable
    I32 | I64 | F32 | F64 | V128 => true
    // Nullable reference types are defaultable (have null as default)
    FuncRef
    | ExternRef
    | AnyRef
    | ExnRef
    | EqRef
    | I31Ref
    | StructRef
    | ArrayRef => true
    // Bottom types (null types) are defaultable
    NullRef | NullFuncRef | NullExnRef | NullExternRef => true
    // Typed references: defaultable only if nullable
    Ref(_, nullable) => nullable
  }
}

// Function type (signature)

///|
pub struct FuncType {
  params : Array[ValType]
  results : Array[ValType]
}

// Block type (can be empty, single value, or type index to function type)

///|
enum BlockType {
  Empty // no params, no results
  Value(ValType) // no params, single result
  TypeIndex(Int) // index into types section (can have params and/or multiple results)
} derive(Show)

// Limits for tables and memories

///|
priv struct Limits {
  min : UInt
  max : UInt?
}

// Memory type

///|
struct MemType {
  limits : Limits
}

// Table type

///|
struct TableType {
  elem_type : RefType
  limits : Limits
  init : Expr? // Optional initializer expression (GC proposal)
  nullable : Bool // Whether the element type is nullable (default true for backward compat)
}

// Global type

///|
struct GlobalType {
  val_type : ValType
  mutable : Bool // mutable or not
}

// Import descriptor

///|
pub enum ImportDesc {
  Func(UInt) // type index
  Table(TableType)
  Mem(MemType)
  Global(GlobalType)
  Tag(UInt) // type index for exception handling tags
}

// Import

///|
pub struct Import {
  module_ : Bytes
  name : Bytes
  desc : ImportDesc
}

// Export descriptor

///|
pub enum ExportDesc {
  Func(UInt) // function index
  Table(UInt) // table index
  Mem(UInt) // memory index
  Global(UInt) // global index
  Tag(UInt) // tag index for exception handling
}

// Export

///|
pub struct Export {
  name : Bytes
  desc : ExportDesc
}

// Global definition

///|
struct Global {
  type_ : GlobalType
  init : Expr
}

// Element segment (for table initialization)

///|
struct Elem {
  table_idx : UInt
  offset : Expr
  init : Array[UInt] // function indices
  is_active : Bool // True for active segments (flags 0,2,4,6), false for passive/declarative
  elem_type : RefType // Element type (funcref, externref, or typed reference)
}

// Data segment (for memory initialization)

///|
struct Data {
  mem_idx : UInt
  offset : Expr
  init : BytesView
  is_active : Bool // Only active segments reference memory
}

// Instructions

///|
pub enum Instr {
  // Control instructions
  Unreachable
  Nop
  Block(BlockType, Array[Instr])
  Loop(BlockType, Array[Instr])
  If(BlockType, Array[Instr], Array[Instr])
  Br(UInt)
  BrIf(UInt)
  BrTable(Array[UInt], UInt)
  BrOnNull(UInt) // GC proposal: branch if null
  BrOnNonNull(UInt) // GC proposal: branch if not null
  Return
  Call(UInt)
  CallIndirect(UInt, UInt)
  ReturnCall(UInt) // tail call proposal
  ReturnCallIndirect(UInt, UInt) // tail call proposal
  CallRef(UInt) // typed function references
  ReturnCallRef(UInt) // typed function references

  // Parametric instructions
  Drop
  Select // 0x1B - untyped select (numeric types only)
  SelectTyped(Array[ValType]) // 0x1C - typed select (any type)

  // Variable instructions
  LocalGet(UInt)
  LocalSet(UInt)
  LocalTee(UInt)
  GlobalGet(UInt)
  GlobalSet(UInt)

  // Memory instructions
  I32Load(UInt, UInt) // align, offset
  I64Load(UInt, UInt)
  F32Load(UInt, UInt)
  F64Load(UInt, UInt)
  I32Load8S(UInt, UInt)
  I32Load8U(UInt, UInt)
  I32Load16S(UInt, UInt)
  I32Load16U(UInt, UInt)
  I64Load8S(UInt, UInt)
  I64Load8U(UInt, UInt)
  I64Load16S(UInt, UInt)
  I64Load16U(UInt, UInt)
  I64Load32S(UInt, UInt)
  I64Load32U(UInt, UInt)
  I32Store(UInt, UInt)
  I64Store(UInt, UInt)
  F32Store(UInt, UInt)
  F64Store(UInt, UInt)
  I32Store8(UInt, UInt)
  I32Store16(UInt, UInt)
  I64Store8(UInt, UInt)
  I64Store16(UInt, UInt)
  I64Store32(UInt, UInt)
  MemorySize(UInt) // memory index (usually 0)
  MemoryGrow(UInt) // memory index (usually 0)

  // Table instructions
  TableGet(UInt) // table index
  TableSet(UInt) // table index
  TableSize(UInt) // table index
  TableGrow(UInt) // table index
  TableInit(UInt, UInt) // table index, elem segment index
  TableCopy(UInt, UInt) // dest table index, src table index
  ElemDrop(UInt) // elem segment index

  // Bulk memory instructions
  MemoryInit(UInt) // data segment index (memory index always 0)
  DataDrop(UInt) // data segment index
  MemoryCopy // memory.copy (src and dest memory indices always 0)
  MemoryFill // memory.fill (memory index always 0)

  // Reference instructions
  RefNull(RefType) // ref.null with heap type
  RefFunc(UInt) // ref.func with function index
  RefIsNull // ref.is_null - check if reference is null

  // Numeric instructions - constants
  I32Const(UInt)
  I64Const(UInt64)
  F32Const(Float)
  F64Const(Double)

  // Numeric instructions - i32 operations
  I32Eqz
  I32Eq
  I32Ne
  I32LtS
  I32LtU
  I32GtS
  I32GtU
  I32LeS
  I32LeU
  I32GeS
  I32GeU
  I32Clz
  I32Ctz
  I32Popcnt
  I32Add
  I32Sub
  I32Mul
  I32DivS
  I32DivU
  I32RemS
  I32RemU
  I32And
  I32Or
  I32Xor
  I32Shl
  I32ShrS
  I32ShrU
  I32Rotl
  I32Rotr

  // Numeric instructions - i64 operations
  I64Eqz
  I64Eq
  I64Ne
  I64LtS
  I64LtU
  I64GtS
  I64GtU
  I64LeS
  I64LeU
  I64GeS
  I64GeU
  I64Clz
  I64Ctz
  I64Popcnt
  I64Add
  I64Sub
  I64Mul
  I64DivS
  I64DivU
  I64RemS
  I64RemU
  I64And
  I64Or
  I64Xor
  I64Shl
  I64ShrS
  I64ShrU
  I64Rotl
  I64Rotr

  // Numeric instructions - f32 operations
  F32Eq
  F32Ne
  F32Lt
  F32Gt
  F32Le
  F32Ge
  F32Abs
  F32Neg
  F32Ceil
  F32Floor
  F32Trunc
  F32Nearest
  F32Sqrt
  F32Add
  F32Sub
  F32Mul
  F32Div
  F32Min
  F32Max
  F32Copysign

  // Numeric instructions - f64 operations
  F64Eq
  F64Ne
  F64Lt
  F64Gt
  F64Le
  F64Ge
  F64Abs
  F64Neg
  F64Ceil
  F64Floor
  F64Trunc
  F64Nearest
  F64Sqrt
  F64Add
  F64Sub
  F64Mul
  F64Div
  F64Min
  F64Max
  F64Copysign

  // Conversion instructions
  I32WrapI64
  I32TruncF32S
  I32TruncF32U
  I32TruncF64S
  I32TruncF64U
  I64ExtendI32S
  I64ExtendI32U
  I64TruncF32S
  I64TruncF32U
  I64TruncF64S
  I64TruncF64U
  F32ConvertI32S
  F32ConvertI32U
  F32ConvertI64S
  F32ConvertI64U
  F32DemoteF64
  F64ConvertI32S
  F64ConvertI32U
  F64ConvertI64S
  F64ConvertI64U
  F64PromoteF32
  I32ReinterpretF32
  I64ReinterpretF64
  F32ReinterpretI32
  F64ReinterpretI64

  // Sign extension instructions
  I32Extend8S
  I32Extend16S
  I64Extend8S
  I64Extend16S
  I64Extend32S

  // Saturating truncation instructions
  I32TruncSatF32S
  I32TruncSatF32U
  I32TruncSatF64S
  I32TruncSatF64U
  I64TruncSatF32S
  I64TruncSatF32U
  I64TruncSatF64S
  I64TruncSatF64U
} derive(Show)

// Expression (sequence of instructions)

///|
pub struct Expr {
  instrs : Array[Instr]
}

// Function code

///|
struct Code {
  locals : Array[ValType]
  body : Expr
  mut compiled : Int?
}

// Function (combines type index with code)

///|
/// Module structure according to WASM specification
pub struct Module {
  types : Array[FuncType] // type section
  funcs : Array[UInt] // function section (type indices)
  tables : Array[TableType] // table section
  mems : Array[MemType] // memory section
  globals : Array[Global] // global section
  elems : Array[Elem] // element section
  datas : Array[Data] // data section
  start : UInt? // start section (optional function index)
  imports : Array[Import] // import section
  exports : Array[Export] // export section
  codes : Array[Code] // code section (function bodies)
}
