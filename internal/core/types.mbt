// Value types

///|
pub(all) enum ValType {
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
} derive(Debug, Eq)

///|
pub impl Show for ValType with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

// Reference types (heap types)

///|
pub(all) enum RefType {
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
  TypeIndex(Int32) // typed reference (ref null $t)
} derive(Debug, Eq)

///|
pub impl Show for RefType with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Check if a value type has a default value (is defaultable)
/// - Numeric types (i32, i64, f32, f64, v128): defaultable (default: 0)
/// - Nullable reference types: defaultable (default: null)
/// - Non-nullable reference types: NOT defaultable (must be initialized)
pub fn ValType::is_defaultable(self : ValType) -> Bool {
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

///|
/// Check if this is a reference type
pub fn ValType::is_ref_type(self : ValType) -> Bool {
  match self {
    FuncRef
    | ExternRef
    | AnyRef
    | ExnRef
    | EqRef
    | I31Ref
    | StructRef
    | ArrayRef
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef
    | Ref(_, _) => true
    _ => false
  }
}

///|
/// Convert a nullable reference type to its non-nullable version
pub fn ValType::to_non_nullable(self : ValType) -> ValType {
  match self {
    FuncRef => Ref(Func, false)
    ExternRef => Ref(Extern, false)
    AnyRef => Ref(Any, false)
    ExnRef => Ref(Exn, false)
    EqRef => Ref(Eq, false)
    I31Ref => Ref(I31, false)
    StructRef => Ref(Struct, false)
    ArrayRef => Ref(Array, false)
    NullRef => Ref(Any, false)
    NullFuncRef => Ref(Func, false)
    NullExnRef => Ref(Exn, false)
    NullExternRef => Ref(Extern, false)
    Ref(ht, _) => Ref(ht, false)
    // Non-ref types return as-is
    other => other
  }
}

// Function type (signature)

///|
pub(all) struct FuncType {
  params : Array[ValType]
  results : Array[ValType]
} derive(Debug, Eq)

///|
pub(all) enum StorageType {
  Val(ValType)
  I8
  I16
} derive(Debug, Eq)

///|
pub(all) struct FieldType {
  storage : StorageType
  mutable : Bool
} derive(Debug, Eq)

///|
pub(all) struct StructType {
  fields : Array[FieldType]
} derive(Debug, Eq)

///|
pub(all) struct ArrayType {
  element : FieldType
} derive(Debug, Eq)

///|
pub(all) enum TypeDef {
  Func(FuncType)
  Struct(StructType)
  Array(ArrayType)
} derive(Debug, Eq)

///|
pub(all) struct SubTypeDef {
  type_idx : UInt32
  supertypes : Array[UInt32]
  is_final : Bool
} derive(Debug, Eq)

///|
pub(all) struct TypeGroup {
  subtypes : Array[SubTypeDef]
  explicit : Bool
} derive(Debug, Eq)

///|
pub(all) enum SectionId {
  Type
  Import
  Func
  Table
  Memory
  Global
  Tag
  Export
  Start
  Elem
  DataCount
  Code
  Data
} derive(Debug, Eq)

///|
pub(all) enum CustomPlacement {
  Start
  Before(SectionId)
  After(SectionId)
  End
} derive(Debug, Eq)

///|
pub(all) struct CustomSection {
  name : Bytes
  data : Bytes
  placement : CustomPlacement
} derive(Debug, Eq)

// Block type (can be empty, single value, or type index to function type)

///|
pub(all) enum BlockType {
  Empty // no params, no results
  Value(ValType) // no params, single result
  TypeIndex(Int32) // index into types section (can have params and/or multiple results)
} derive(Debug)

// Limits for tables and memories

///|
pub(all) struct Limits {
  min : UInt64
  max : UInt64?
}

// Memory type

///|
pub(all) struct MemType {
  limits : Limits
  shared : Bool
  memory64 : Bool
}

// Table type

///|
pub(all) struct TableType {
  elem_type : RefType
  limits : Limits
  init : Expr? // Optional initializer expression (GC proposal)
  nullable : Bool // Whether the element type is nullable (default true for backward compat)
  table64 : Bool
}

// Global type

///|
pub(all) struct GlobalType {
  val_type : ValType
  mutable : Bool // mutable or not
}

// Import descriptor

///|
pub(all) enum ImportDesc {
  Func(UInt32) // type index
  Table(TableType)
  Mem(MemType)
  Global(GlobalType)
  Tag(UInt32) // type index for exception handling tags
}

// Import

///|
pub(all) struct Import {
  module_ : Bytes
  name : Bytes
  desc : ImportDesc
}

// Export descriptor

///|
pub(all) enum ExportDesc {
  Func(UInt32) // function index
  Table(UInt32) // table index
  Mem(UInt32) // memory index
  Global(UInt32) // global index
  Tag(UInt32) // tag index for exception handling
}

// Export

///|
pub(all) struct Export {
  name : Bytes
  desc : ExportDesc
}

// Global definition

///|
pub(all) struct Global {
  type_ : GlobalType
  init : Expr
}

///|
pub(all) struct Tag {
  type_idx : UInt32
}

// Element segment (for table initialization)

///|
pub(all) struct Elem {
  table_idx : UInt32
  offset : Expr
  init : Array[Expr] // element init expressions
  is_active : Bool // True for active segments (flags 0,2,4,6), false for passive/declarative
  is_declarative : Bool // True for declarative segments (flags 3,7)
  elem_type : RefType // Element heap type
  elem_nullable : Bool // Whether element type is nullable
  explicit_table : Bool // True when table index was explicitly provided in WAT
}

// Data segment (for memory initialization)

///|
pub(all) struct Data {
  mem_idx : UInt32
  offset : Expr
  init : BytesView
  is_active : Bool // Only active segments reference memory
}

// Instructions

///|
pub(all) enum SimdImmediate {
  None
  MemArg(UInt32, UInt32, UInt32) // align, offset, memory index
  Lane(UInt32) // lane index
  MemArgLane(UInt32, UInt32, UInt32, UInt32) // align, offset, memory index, lane
  Shuffle(Array[Byte]) // 16 bytes
  V128Const(Array[Byte]) // 16 bytes
} derive(Debug)

///|
pub(all) struct SimdInstr {
  opcode : UInt32
  imm : SimdImmediate
} derive(Debug)

///|
pub(all) enum AtomicImmediate {
  None
  MemArg(UInt32, UInt32, UInt32) // align, offset, memory index
  Fence(UInt32) // reserved byte (must be 0)
} derive(Debug)

///|
pub(all) struct AtomicInstr {
  opcode : UInt32
  imm : AtomicImmediate
} derive(Debug)

///|
pub(all) enum Instr {
  // Control instructions
  Unreachable
  Nop
  Block(BlockType, Array[Instr])
  Loop(BlockType, Array[Instr])
  If(BlockType, Array[Instr], Array[Instr])
  TryTable(BlockType, Array[CatchClause], Array[Instr]) // Exception handling
  Br(UInt32)
  BrIf(UInt32)
  BrTable(Array[UInt32], UInt32)
  BrOnNull(UInt32) // GC proposal: branch if null
  BrOnNonNull(UInt32) // GC proposal: branch if not null
  Return
  Call(UInt32)
  CallIndirect(UInt32, UInt32)
  ReturnCall(UInt32) // tail call proposal
  ReturnCallIndirect(UInt32, UInt32) // tail call proposal
  CallRef(UInt32) // typed function references
  ReturnCallRef(UInt32) // typed function references
  Throw(UInt32) // exception handling
  Rethrow(UInt32) // exception handling
  Simd(SimdInstr) // SIMD instructions
  Atomic(AtomicInstr) // Atomic instructions (threads)

  // Parametric instructions
  Drop
  Select // 0x1B - untyped select (numeric types only)
  SelectTyped(Array[ValType]) // 0x1C - typed select (any type)

  // Variable instructions
  LocalGet(UInt32)
  LocalSet(UInt32)
  LocalTee(UInt32)
  GlobalGet(UInt32)
  GlobalSet(UInt32)

  // Memory instructions
  I32Load(UInt32, UInt32, UInt32) // align, offset, memory index
  I64Load(UInt32, UInt32, UInt32)
  F32Load(UInt32, UInt32, UInt32)
  F64Load(UInt32, UInt32, UInt32)
  I32Load8S(UInt32, UInt32, UInt32)
  I32Load8U(UInt32, UInt32, UInt32)
  I32Load16S(UInt32, UInt32, UInt32)
  I32Load16U(UInt32, UInt32, UInt32)
  I64Load8S(UInt32, UInt32, UInt32)
  I64Load8U(UInt32, UInt32, UInt32)
  I64Load16S(UInt32, UInt32, UInt32)
  I64Load16U(UInt32, UInt32, UInt32)
  I64Load32S(UInt32, UInt32, UInt32)
  I64Load32U(UInt32, UInt32, UInt32)
  I32Store(UInt32, UInt32, UInt32)
  I64Store(UInt32, UInt32, UInt32)
  F32Store(UInt32, UInt32, UInt32)
  F64Store(UInt32, UInt32, UInt32)
  I32Store8(UInt32, UInt32, UInt32)
  I32Store16(UInt32, UInt32, UInt32)
  I64Store8(UInt32, UInt32, UInt32)
  I64Store16(UInt32, UInt32, UInt32)
  I64Store32(UInt32, UInt32, UInt32)
  MemorySize(UInt32) // memory index (usually 0)
  MemoryGrow(UInt32) // memory index (usually 0)

  // Table instructions
  TableGet(UInt32) // table index
  TableSet(UInt32) // table index
  TableSize(UInt32) // table index
  TableGrow(UInt32) // table index
  TableInit(UInt32, UInt32) // table index, elem segment index
  TableCopy(UInt32, UInt32) // dest table index, src table index
  TableFill(UInt32) // table index
  ElemDrop(UInt32) // elem segment index

  // Bulk memory instructions
  MemoryInit(UInt32, UInt32) // data segment index, memory index
  DataDrop(UInt32) // data segment index
  MemoryCopy(UInt32, UInt32) // memory.copy (dst memory, src memory)
  MemoryFill(UInt32) // memory.fill (memory index)

  // Reference instructions
  RefNull(RefType) // ref.null with heap type
  RefFunc(UInt32) // ref.func with function index
  RefIsNull // ref.is_null - check if reference is null
  RefEq // ref.eq - reference equality
  RefAsNonNull // ref.as_non_null - trap if reference is null
  RefTest(RefType, Bool) // ref.test (heap type, nullable)
  RefCast(RefType, Bool) // ref.cast (heap type, nullable)
  // GC instructions (struct/array, casts, i31)
  StructNew(UInt32)
  StructNewDefault(UInt32)
  StructGet(UInt32, UInt32)
  StructGetS(UInt32, UInt32)
  StructGetU(UInt32, UInt32)
  StructSet(UInt32, UInt32)
  ArrayNew(UInt32)
  ArrayNewDefault(UInt32)
  ArrayNewFixed(UInt32, UInt32)
  ArrayNewData(UInt32, UInt32)
  ArrayNewElem(UInt32, UInt32)
  ArrayGet(UInt32)
  ArrayGetS(UInt32)
  ArrayGetU(UInt32)
  ArraySet(UInt32)
  ArrayLen
  ArrayFill(UInt32)
  ArrayCopy(UInt32, UInt32)
  ArrayInitData(UInt32, UInt32)
  ArrayInitElem(UInt32, UInt32)
  BrOnCast(UInt32, RefType, Bool, RefType, Bool)
  BrOnCastFail(UInt32, RefType, Bool, RefType, Bool)
  AnyConvertExtern
  ExternConvertAny
  RefI31
  I31GetS
  I31GetU

  // Numeric instructions - constants
  I32Const(UInt32)
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
} derive(Debug)

///|
pub impl Show for Instr with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) enum CatchClause {
  Catch(UInt32, UInt32) // tag index, label index
  CatchRef(UInt32, UInt32) // tag index, label index
  CatchAll(UInt32) // label index
  CatchAllRef(UInt32) // label index
} derive(Debug)

// Expression (sequence of instructions)

///|
pub(all) struct Expr {
  instrs : Array[Instr]
}

// Function code

///|
pub(all) struct Code {
  locals : Array[ValType]
  body : Expr
  mut compiled : Int32?
  mut max_stack_height : Int32 // Max stack usage from sp: num_locals + max_operand_depth
}

// Function (combines type index with code)

///|
/// Module structure according to WASM specification
pub(all) struct Module {
  types : Array[TypeDef] // type section
  type_groups : Array[TypeGroup] // recursive type groups
  customs : Array[CustomSection] // custom sections
  funcs : Array[UInt32] // function section (type indices)
  tables : Array[TableType] // table section
  mems : Array[MemType] // memory section
  globals : Array[Global] // global section
  tags : Array[Tag] // tag section (exception handling)
  elems : Array[Elem] // element section
  datas : Array[Data] // data section
  start : UInt32? // start section (optional function index)
  imports : Array[Import] // import section
  exports : Array[Export] // export section
  codes : Array[Code] // code section (function bodies)
}
