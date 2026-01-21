///|
/// Universal opcode tags for the compiled IR.
/// These are stored as Int64 in the code array and can be transformed
/// to function pointers for the C runtime.
pub(all) enum OpTag {
  // ============================================================
  // Control flow (0-19)
  // ============================================================
  Unreachable // 0
  Nop // 1
  Return // 2
  End // 3
  FuncExit // 4
  CopySlot // 5
  SetSp // 6
  Br // 7
  BrIf // 8
  If // 9
  BrTable // 10
  Call // 11
  CallImport // 12
  CallExternal // 13
  Entry // 14
  CallIndirect // 15
  CallRef // 16
  BrOnNull // 17
  BrOnNonNull // 18

  // ============================================================
  // Constants (20-23)
  // ============================================================
  I32Const // 20
  I64Const // 21
  F32Const // 22
  F64Const // 23

  // ============================================================
  // Variables (24-28)
  // ============================================================
  LocalGet // 24
  LocalSet // 25
  LocalTee // 26
  GlobalGet // 27
  GlobalSet // 28

  // ============================================================
  // Stack operations (29-30)
  // ============================================================
  Drop // 29
  Select // 30

  // ============================================================
  // i32 arithmetic (31-45)
  // ============================================================
  I32Add // 31
  I32Sub // 32
  I32Mul // 33
  I32DivS // 34
  I32DivU // 35
  I32RemS // 36
  I32RemU // 37
  I32And // 38
  I32Or // 39
  I32Xor // 40
  I32Shl // 41
  I32ShrS // 42
  I32ShrU // 43
  I32Rotl // 44
  I32Rotr // 45

  // ============================================================
  // i32 comparison (46-56)
  // ============================================================
  I32Eqz // 46
  I32Eq // 47
  I32Ne // 48
  I32LtS // 49
  I32LtU // 50
  I32GtS // 51
  I32GtU // 52
  I32LeS // 53
  I32LeU // 54
  I32GeS // 55
  I32GeU // 56

  // ============================================================
  // i32 unary (57-59)
  // ============================================================
  I32Clz // 57
  I32Ctz // 58
  I32Popcnt // 59

  // ============================================================
  // i64 arithmetic (60-74)
  // ============================================================
  I64Add // 60
  I64Sub // 61
  I64Mul // 62
  I64DivS // 63
  I64DivU // 64
  I64RemS // 65
  I64RemU // 66
  I64And // 67
  I64Or // 68
  I64Xor // 69
  I64Shl // 70
  I64ShrS // 71
  I64ShrU // 72
  I64Rotl // 73
  I64Rotr // 74

  // ============================================================
  // i64 comparison (75-85)
  // ============================================================
  I64Eqz // 75
  I64Eq // 76
  I64Ne // 77
  I64LtS // 78
  I64LtU // 79
  I64GtS // 80
  I64GtU // 81
  I64LeS // 82
  I64LeU // 83
  I64GeS // 84
  I64GeU // 85

  // ============================================================
  // i64 unary (86-88)
  // ============================================================
  I64Clz // 86
  I64Ctz // 87
  I64Popcnt // 88

  // ============================================================
  // f32 arithmetic (89-95)
  // ============================================================
  F32Add // 89
  F32Sub // 90
  F32Mul // 91
  F32Div // 92
  F32Min // 93
  F32Max // 94
  F32Copysign // 95

  // ============================================================
  // f32 comparison (96-101)
  // ============================================================
  F32Eq // 96
  F32Ne // 97
  F32Lt // 98
  F32Gt // 99
  F32Le // 100
  F32Ge // 101

  // ============================================================
  // f32 unary (102-108)
  // ============================================================
  F32Abs // 102
  F32Neg // 103
  F32Ceil // 104
  F32Floor // 105
  F32Trunc // 106
  F32Nearest // 107
  F32Sqrt // 108

  // ============================================================
  // f64 arithmetic (109-115)
  // ============================================================
  F64Add // 109
  F64Sub // 110
  F64Mul // 111
  F64Div // 112
  F64Min // 113
  F64Max // 114
  F64Copysign // 115

  // ============================================================
  // f64 comparison (116-121)
  // ============================================================
  F64Eq // 116
  F64Ne // 117
  F64Lt // 118
  F64Gt // 119
  F64Le // 120
  F64Ge // 121

  // ============================================================
  // f64 unary (122-128)
  // ============================================================
  F64Abs // 122
  F64Neg // 123
  F64Ceil // 124
  F64Floor // 125
  F64Trunc // 126
  F64Nearest // 127
  F64Sqrt // 128

  // ============================================================
  // Conversions (129-162)
  // ============================================================
  I32WrapI64 // 129
  I32TruncF32S // 130
  I32TruncF32U // 131
  I32TruncF64S // 132
  I32TruncF64U // 133
  I64ExtendI32S // 134
  I64ExtendI32U // 135
  I64TruncF32S // 136
  I64TruncF32U // 137
  I64TruncF64S // 138
  I64TruncF64U // 139
  I32TruncSatF32S // 140
  I32TruncSatF32U // 141
  I32TruncSatF64S // 142
  I32TruncSatF64U // 143
  I64TruncSatF32S // 144
  I64TruncSatF32U // 145
  I64TruncSatF64S // 146
  I64TruncSatF64U // 147
  F32ConvertI32S // 148
  F32ConvertI32U // 149
  F32ConvertI64S // 150
  F32ConvertI64U // 151
  F32DemoteF64 // 152
  F64ConvertI32S // 153
  F64ConvertI32U // 154
  F64ConvertI64S // 155
  F64ConvertI64U // 156
  F64PromoteF32 // 157
  I32ReinterpretF32 // 158
  I64ReinterpretF64 // 159
  F32ReinterpretI32 // 160
  F64ReinterpretI64 // 161

  // ============================================================
  // Sign extension (162-166)
  // ============================================================
  I32Extend8S // 162
  I32Extend16S // 163
  I64Extend8S // 164
  I64Extend16S // 165
  I64Extend32S // 166

  // ============================================================
  // Memory operations (167-194)
  // ============================================================
  MemoryGrow // 167
  MemorySize // 168
  I32Load // 169
  I32Store // 170
  I32Load8S // 171
  I32Load8U // 172
  I32Load16S // 173
  I32Load16U // 174
  I32Store8 // 175
  I32Store16 // 176
  I64Load // 177
  I64Load8S // 178
  I64Load8U // 179
  I64Load16S // 180
  I64Load16U // 181
  I64Load32S // 182
  I64Load32U // 183
  I64Store // 184
  I64Store8 // 185
  I64Store16 // 186
  I64Store32 // 187
  F32Load // 188
  F32Store // 189
  F64Load // 190
  F64Store // 191
  MemoryCopy // 192
  MemoryFill // 193
  MemoryInit // 194
  DataDrop // 195

  // ============================================================
  // Table operations (196-203)
  // ============================================================
  TableCopy // 196
  TableFill // 197
  TableInit // 198
  ElemDrop // 199
  TableGet // 200
  TableSet // 201
  TableSize // 202
  TableGrow // 203

  // ============================================================
  // Reference types (204-209)
  // ============================================================
  RefNull // 204
  RefFunc // 205
  RefIsNull // 206
  RefEq // 207
  RefAsNonNull // 208

  // ============================================================
  // GC operations (209-237)
  // ============================================================
  StructNew // 209
  StructNewDefault // 210
  StructGet // 211
  StructGetS // 212
  StructGetU // 213
  StructSet // 214
  ArrayNew // 215
  ArrayNewDefault // 216
  ArrayNewFixed // 217
  ArrayNewData // 218
  ArrayNewElem // 219
  ArrayGet // 220
  ArrayGetS // 221
  ArrayGetU // 222
  ArraySet // 223
  ArrayLen // 224
  ArrayFill // 225
  ArrayCopy // 226
  ArrayInitData // 227
  ArrayInitElem // 228
  RefI31 // 229
  I31GetS // 230
  I31GetU // 231
  AnyConvertExtern // 232
  ExternConvertAny // 233
  RefTest // 234
  RefCast // 235
  BrOnCast // 236
  BrOnCastFail // 237

  // ============================================================
  // Tail calls (238-241)
  // ============================================================
  ReturnCall // 238
  ReturnCallImport // 239
  ReturnCallIndirect // 240
  ReturnCallRef // 241
} derive(Eq, Show)

///|
/// Convert OpTag to Int64 for storage in the code array.
pub fn OpTag::to_int64(self : OpTag) -> Int64 {
  match self {
    // Control flow (0-18)
    Unreachable => 0L
    Nop => 1L
    Return => 2L
    End => 3L
    FuncExit => 4L
    CopySlot => 5L
    SetSp => 6L
    Br => 7L
    BrIf => 8L
    If => 9L
    BrTable => 10L
    Call => 11L
    CallImport => 12L
    CallExternal => 13L
    Entry => 14L
    CallIndirect => 15L
    CallRef => 16L
    BrOnNull => 17L
    BrOnNonNull => 18L
    // Constants (20-23)
    I32Const => 20L
    I64Const => 21L
    F32Const => 22L
    F64Const => 23L
    // Variables (24-28)
    LocalGet => 24L
    LocalSet => 25L
    LocalTee => 26L
    GlobalGet => 27L
    GlobalSet => 28L
    // Stack operations (29-30)
    Drop => 29L
    Select => 30L
    // i32 arithmetic (31-45)
    I32Add => 31L
    I32Sub => 32L
    I32Mul => 33L
    I32DivS => 34L
    I32DivU => 35L
    I32RemS => 36L
    I32RemU => 37L
    I32And => 38L
    I32Or => 39L
    I32Xor => 40L
    I32Shl => 41L
    I32ShrS => 42L
    I32ShrU => 43L
    I32Rotl => 44L
    I32Rotr => 45L
    // i32 comparison (46-56)
    I32Eqz => 46L
    I32Eq => 47L
    I32Ne => 48L
    I32LtS => 49L
    I32LtU => 50L
    I32GtS => 51L
    I32GtU => 52L
    I32LeS => 53L
    I32LeU => 54L
    I32GeS => 55L
    I32GeU => 56L
    // i32 unary (57-59)
    I32Clz => 57L
    I32Ctz => 58L
    I32Popcnt => 59L
    // i64 arithmetic (60-74)
    I64Add => 60L
    I64Sub => 61L
    I64Mul => 62L
    I64DivS => 63L
    I64DivU => 64L
    I64RemS => 65L
    I64RemU => 66L
    I64And => 67L
    I64Or => 68L
    I64Xor => 69L
    I64Shl => 70L
    I64ShrS => 71L
    I64ShrU => 72L
    I64Rotl => 73L
    I64Rotr => 74L
    // i64 comparison (75-85)
    I64Eqz => 75L
    I64Eq => 76L
    I64Ne => 77L
    I64LtS => 78L
    I64LtU => 79L
    I64GtS => 80L
    I64GtU => 81L
    I64LeS => 82L
    I64LeU => 83L
    I64GeS => 84L
    I64GeU => 85L
    // i64 unary (86-88)
    I64Clz => 86L
    I64Ctz => 87L
    I64Popcnt => 88L
    // f32 arithmetic (89-95)
    F32Add => 89L
    F32Sub => 90L
    F32Mul => 91L
    F32Div => 92L
    F32Min => 93L
    F32Max => 94L
    F32Copysign => 95L
    // f32 comparison (96-101)
    F32Eq => 96L
    F32Ne => 97L
    F32Lt => 98L
    F32Gt => 99L
    F32Le => 100L
    F32Ge => 101L
    // f32 unary (102-108)
    F32Abs => 102L
    F32Neg => 103L
    F32Ceil => 104L
    F32Floor => 105L
    F32Trunc => 106L
    F32Nearest => 107L
    F32Sqrt => 108L
    // f64 arithmetic (109-115)
    F64Add => 109L
    F64Sub => 110L
    F64Mul => 111L
    F64Div => 112L
    F64Min => 113L
    F64Max => 114L
    F64Copysign => 115L
    // f64 comparison (116-121)
    F64Eq => 116L
    F64Ne => 117L
    F64Lt => 118L
    F64Gt => 119L
    F64Le => 120L
    F64Ge => 121L
    // f64 unary (122-128)
    F64Abs => 122L
    F64Neg => 123L
    F64Ceil => 124L
    F64Floor => 125L
    F64Trunc => 126L
    F64Nearest => 127L
    F64Sqrt => 128L
    // Conversions (129-161)
    I32WrapI64 => 129L
    I32TruncF32S => 130L
    I32TruncF32U => 131L
    I32TruncF64S => 132L
    I32TruncF64U => 133L
    I64ExtendI32S => 134L
    I64ExtendI32U => 135L
    I64TruncF32S => 136L
    I64TruncF32U => 137L
    I64TruncF64S => 138L
    I64TruncF64U => 139L
    I32TruncSatF32S => 140L
    I32TruncSatF32U => 141L
    I32TruncSatF64S => 142L
    I32TruncSatF64U => 143L
    I64TruncSatF32S => 144L
    I64TruncSatF32U => 145L
    I64TruncSatF64S => 146L
    I64TruncSatF64U => 147L
    F32ConvertI32S => 148L
    F32ConvertI32U => 149L
    F32ConvertI64S => 150L
    F32ConvertI64U => 151L
    F32DemoteF64 => 152L
    F64ConvertI32S => 153L
    F64ConvertI32U => 154L
    F64ConvertI64S => 155L
    F64ConvertI64U => 156L
    F64PromoteF32 => 157L
    I32ReinterpretF32 => 158L
    I64ReinterpretF64 => 159L
    F32ReinterpretI32 => 160L
    F64ReinterpretI64 => 161L
    // Sign extension (162-166)
    I32Extend8S => 162L
    I32Extend16S => 163L
    I64Extend8S => 164L
    I64Extend16S => 165L
    I64Extend32S => 166L
    // Memory operations (167-195)
    MemoryGrow => 167L
    MemorySize => 168L
    I32Load => 169L
    I32Store => 170L
    I32Load8S => 171L
    I32Load8U => 172L
    I32Load16S => 173L
    I32Load16U => 174L
    I32Store8 => 175L
    I32Store16 => 176L
    I64Load => 177L
    I64Load8S => 178L
    I64Load8U => 179L
    I64Load16S => 180L
    I64Load16U => 181L
    I64Load32S => 182L
    I64Load32U => 183L
    I64Store => 184L
    I64Store8 => 185L
    I64Store16 => 186L
    I64Store32 => 187L
    F32Load => 188L
    F32Store => 189L
    F64Load => 190L
    F64Store => 191L
    MemoryCopy => 192L
    MemoryFill => 193L
    MemoryInit => 194L
    DataDrop => 195L
    // Table operations (196-203)
    TableCopy => 196L
    TableFill => 197L
    TableInit => 198L
    ElemDrop => 199L
    TableGet => 200L
    TableSet => 201L
    TableSize => 202L
    TableGrow => 203L
    // Reference types (204-208)
    RefNull => 204L
    RefFunc => 205L
    RefIsNull => 206L
    RefEq => 207L
    RefAsNonNull => 208L
    StructNew => 209L
    StructNewDefault => 210L
    StructGet => 211L
    StructGetS => 212L
    StructGetU => 213L
    StructSet => 214L
    ArrayNew => 215L
    ArrayNewDefault => 216L
    ArrayNewFixed => 217L
    ArrayNewData => 218L
    ArrayNewElem => 219L
    ArrayGet => 220L
    ArrayGetS => 221L
    ArrayGetU => 222L
    ArraySet => 223L
    ArrayLen => 224L
    ArrayFill => 225L
    ArrayCopy => 226L
    ArrayInitData => 227L
    ArrayInitElem => 228L
    RefI31 => 229L
    I31GetS => 230L
    I31GetU => 231L
    AnyConvertExtern => 232L
    ExternConvertAny => 233L
    RefTest => 234L
    RefCast => 235L
    BrOnCast => 236L
    BrOnCastFail => 237L
    ReturnCall => 238L
    ReturnCallImport => 239L
    ReturnCallIndirect => 240L
    ReturnCallRef => 241L
  }
}

///|
/// Convert Int64 back to OpTag (for debugging/error messages).
/// Returns None for invalid opcodes.
pub fn OpTag::from_int64(v : Int64) -> OpTag? {
  match v {
    // Control flow
    0L => Some(Unreachable)
    1L => Some(Nop)
    2L => Some(Return)
    3L => Some(End)
    4L => Some(FuncExit)
    5L => Some(CopySlot)
    6L => Some(SetSp)
    7L => Some(Br)
    8L => Some(BrIf)
    9L => Some(If)
    10L => Some(BrTable)
    11L => Some(Call)
    12L => Some(CallImport)
    13L => Some(CallExternal)
    14L => Some(Entry)
    15L => Some(CallIndirect)
    16L => Some(CallRef)
    17L => Some(BrOnNull)
    18L => Some(BrOnNonNull)
    // Constants
    20L => Some(I32Const)
    21L => Some(I64Const)
    22L => Some(F32Const)
    23L => Some(F64Const)
    // Variables
    24L => Some(LocalGet)
    25L => Some(LocalSet)
    26L => Some(LocalTee)
    27L => Some(GlobalGet)
    28L => Some(GlobalSet)
    // Stack operations
    29L => Some(Drop)
    30L => Some(Select)
    // i32 arithmetic
    31L => Some(I32Add)
    32L => Some(I32Sub)
    33L => Some(I32Mul)
    34L => Some(I32DivS)
    35L => Some(I32DivU)
    36L => Some(I32RemS)
    37L => Some(I32RemU)
    38L => Some(I32And)
    39L => Some(I32Or)
    40L => Some(I32Xor)
    41L => Some(I32Shl)
    42L => Some(I32ShrS)
    43L => Some(I32ShrU)
    44L => Some(I32Rotl)
    45L => Some(I32Rotr)
    // i32 comparison
    46L => Some(I32Eqz)
    47L => Some(I32Eq)
    48L => Some(I32Ne)
    49L => Some(I32LtS)
    50L => Some(I32LtU)
    51L => Some(I32GtS)
    52L => Some(I32GtU)
    53L => Some(I32LeS)
    54L => Some(I32LeU)
    55L => Some(I32GeS)
    56L => Some(I32GeU)
    // i32 unary
    57L => Some(I32Clz)
    58L => Some(I32Ctz)
    59L => Some(I32Popcnt)
    // i64 arithmetic
    60L => Some(I64Add)
    61L => Some(I64Sub)
    62L => Some(I64Mul)
    63L => Some(I64DivS)
    64L => Some(I64DivU)
    65L => Some(I64RemS)
    66L => Some(I64RemU)
    67L => Some(I64And)
    68L => Some(I64Or)
    69L => Some(I64Xor)
    70L => Some(I64Shl)
    71L => Some(I64ShrS)
    72L => Some(I64ShrU)
    73L => Some(I64Rotl)
    74L => Some(I64Rotr)
    // i64 comparison
    75L => Some(I64Eqz)
    76L => Some(I64Eq)
    77L => Some(I64Ne)
    78L => Some(I64LtS)
    79L => Some(I64LtU)
    80L => Some(I64GtS)
    81L => Some(I64GtU)
    82L => Some(I64LeS)
    83L => Some(I64LeU)
    84L => Some(I64GeS)
    85L => Some(I64GeU)
    // i64 unary
    86L => Some(I64Clz)
    87L => Some(I64Ctz)
    88L => Some(I64Popcnt)
    // f32 arithmetic
    89L => Some(F32Add)
    90L => Some(F32Sub)
    91L => Some(F32Mul)
    92L => Some(F32Div)
    93L => Some(F32Min)
    94L => Some(F32Max)
    95L => Some(F32Copysign)
    // f32 comparison
    96L => Some(F32Eq)
    97L => Some(F32Ne)
    98L => Some(F32Lt)
    99L => Some(F32Gt)
    100L => Some(F32Le)
    101L => Some(F32Ge)
    // f32 unary
    102L => Some(F32Abs)
    103L => Some(F32Neg)
    104L => Some(F32Ceil)
    105L => Some(F32Floor)
    106L => Some(F32Trunc)
    107L => Some(F32Nearest)
    108L => Some(F32Sqrt)
    // f64 arithmetic
    109L => Some(F64Add)
    110L => Some(F64Sub)
    111L => Some(F64Mul)
    112L => Some(F64Div)
    113L => Some(F64Min)
    114L => Some(F64Max)
    115L => Some(F64Copysign)
    // f64 comparison
    116L => Some(F64Eq)
    117L => Some(F64Ne)
    118L => Some(F64Lt)
    119L => Some(F64Gt)
    120L => Some(F64Le)
    121L => Some(F64Ge)
    // f64 unary
    122L => Some(F64Abs)
    123L => Some(F64Neg)
    124L => Some(F64Ceil)
    125L => Some(F64Floor)
    126L => Some(F64Trunc)
    127L => Some(F64Nearest)
    128L => Some(F64Sqrt)
    // Conversions
    129L => Some(I32WrapI64)
    130L => Some(I32TruncF32S)
    131L => Some(I32TruncF32U)
    132L => Some(I32TruncF64S)
    133L => Some(I32TruncF64U)
    134L => Some(I64ExtendI32S)
    135L => Some(I64ExtendI32U)
    136L => Some(I64TruncF32S)
    137L => Some(I64TruncF32U)
    138L => Some(I64TruncF64S)
    139L => Some(I64TruncF64U)
    140L => Some(I32TruncSatF32S)
    141L => Some(I32TruncSatF32U)
    142L => Some(I32TruncSatF64S)
    143L => Some(I32TruncSatF64U)
    144L => Some(I64TruncSatF32S)
    145L => Some(I64TruncSatF32U)
    146L => Some(I64TruncSatF64S)
    147L => Some(I64TruncSatF64U)
    148L => Some(F32ConvertI32S)
    149L => Some(F32ConvertI32U)
    150L => Some(F32ConvertI64S)
    151L => Some(F32ConvertI64U)
    152L => Some(F32DemoteF64)
    153L => Some(F64ConvertI32S)
    154L => Some(F64ConvertI32U)
    155L => Some(F64ConvertI64S)
    156L => Some(F64ConvertI64U)
    157L => Some(F64PromoteF32)
    158L => Some(I32ReinterpretF32)
    159L => Some(I64ReinterpretF64)
    160L => Some(F32ReinterpretI32)
    161L => Some(F64ReinterpretI64)
    // Sign extension
    162L => Some(I32Extend8S)
    163L => Some(I32Extend16S)
    164L => Some(I64Extend8S)
    165L => Some(I64Extend16S)
    166L => Some(I64Extend32S)
    // Memory operations
    167L => Some(MemoryGrow)
    168L => Some(MemorySize)
    169L => Some(I32Load)
    170L => Some(I32Store)
    171L => Some(I32Load8S)
    172L => Some(I32Load8U)
    173L => Some(I32Load16S)
    174L => Some(I32Load16U)
    175L => Some(I32Store8)
    176L => Some(I32Store16)
    177L => Some(I64Load)
    178L => Some(I64Load8S)
    179L => Some(I64Load8U)
    180L => Some(I64Load16S)
    181L => Some(I64Load16U)
    182L => Some(I64Load32S)
    183L => Some(I64Load32U)
    184L => Some(I64Store)
    185L => Some(I64Store8)
    186L => Some(I64Store16)
    187L => Some(I64Store32)
    188L => Some(F32Load)
    189L => Some(F32Store)
    190L => Some(F64Load)
    191L => Some(F64Store)
    192L => Some(MemoryCopy)
    193L => Some(MemoryFill)
    194L => Some(MemoryInit)
    195L => Some(DataDrop)
    // Table operations
    196L => Some(TableCopy)
    197L => Some(TableFill)
    198L => Some(TableInit)
    199L => Some(ElemDrop)
    200L => Some(TableGet)
    201L => Some(TableSet)
    202L => Some(TableSize)
    203L => Some(TableGrow)
    // Reference types
    204L => Some(RefNull)
    205L => Some(RefFunc)
    206L => Some(RefIsNull)
    207L => Some(RefEq)
    208L => Some(RefAsNonNull)
    209L => Some(StructNew)
    210L => Some(StructNewDefault)
    211L => Some(StructGet)
    212L => Some(StructGetS)
    213L => Some(StructGetU)
    214L => Some(StructSet)
    215L => Some(ArrayNew)
    216L => Some(ArrayNewDefault)
    217L => Some(ArrayNewFixed)
    218L => Some(ArrayNewData)
    219L => Some(ArrayNewElem)
    220L => Some(ArrayGet)
    221L => Some(ArrayGetS)
    222L => Some(ArrayGetU)
    223L => Some(ArraySet)
    224L => Some(ArrayLen)
    225L => Some(ArrayFill)
    226L => Some(ArrayCopy)
    227L => Some(ArrayInitData)
    228L => Some(ArrayInitElem)
    229L => Some(RefI31)
    230L => Some(I31GetS)
    231L => Some(I31GetU)
    232L => Some(AnyConvertExtern)
    233L => Some(ExternConvertAny)
    234L => Some(RefTest)
    235L => Some(RefCast)
    236L => Some(BrOnCast)
    237L => Some(BrOnCastFail)
    238L => Some(ReturnCall)
    239L => Some(ReturnCallImport)
    240L => Some(ReturnCallIndirect)
    241L => Some(ReturnCallRef)
    _ => None
  }
}

///|
/// Maximum valid opcode value.
pub let max_opcode : Int64 = 241L

///|
/// Returns the number of Int64 immediates that follow this opcode in the code array.
/// Used for iterating through the code array and for C runtime transformation.
pub fn get_immediate_count(opcode : Int64) -> Int {
  match opcode {
    // Control flow with immediates
    0L => 0 // Unreachable
    1L => 0 // Nop
    2L => 1 // Return: num_results
    3L => 1 // End: num_results
    4L => 0 // FuncExit
    5L => 2 // CopySlot: src, dst
    6L => 1 // SetSp: new_sp
    7L => 1 // Br: target_pc
    8L => 2 // BrIf: taken_pc, fallthrough_pc
    9L => 1 // If: else_pc
    10L => 0 // BrTable: variable immediates (handled specially)
    11L => 2 // Call: callee_pc, frame_offset
    12L => 2 // CallImport: import_idx, frame_offset
    13L => 4 // CallExternal: context_ptr, func_idx, num_params, num_results
    14L => 3 // Entry: num_locals, first_local, num_to_zero
    15L => 3 // CallIndirect: type_idx, table_idx, frame_offset
    16L => 2 // CallRef: type_idx, frame_offset
    17L => 2 // BrOnNull: taken_pc, fallthrough_pc
    18L => 2 // BrOnNonNull: taken_pc, fallthrough_pc

    // Constants (1 immediate each)
    20L => 1 // I32Const: value
    21L => 1 // I64Const: value
    22L => 1 // F32Const: value (as Int64)
    23L => 1 // F64Const: value

    // Variables (1 immediate each)
    24L => 1 // LocalGet: slot_idx
    25L => 1 // LocalSet: slot_idx
    26L => 1 // LocalTee: slot_idx
    27L => 1 // GlobalGet: global_idx
    28L => 1 // GlobalSet: global_idx

    // Stack operations (0 immediates)
    29L => 0 // Drop
    30L => 0 // Select

    // All arithmetic/comparison/unary ops (31-128) have 0 immediates
    31L..=128L => 0

    // All conversions (129-166) have 0 immediates
    129L..=166L => 0

    // Memory operations
    167L => 1 // MemoryGrow: mem_idx
    168L => 1 // MemorySize: mem_idx
    169L => 2 // I32Load: offset, mem_idx
    170L => 2 // I32Store: offset, mem_idx
    171L => 2 // I32Load8S: offset, mem_idx
    172L => 2 // I32Load8U: offset, mem_idx
    173L => 2 // I32Load16S: offset, mem_idx
    174L => 2 // I32Load16U: offset, mem_idx
    175L => 2 // I32Store8: offset, mem_idx
    176L => 2 // I32Store16: offset, mem_idx
    177L => 2 // I64Load: offset, mem_idx
    178L => 2 // I64Load8S: offset, mem_idx
    179L => 2 // I64Load8U: offset, mem_idx
    180L => 2 // I64Load16S: offset, mem_idx
    181L => 2 // I64Load16U: offset, mem_idx
    182L => 2 // I64Load32S: offset, mem_idx
    183L => 2 // I64Load32U: offset, mem_idx
    184L => 2 // I64Store: offset, mem_idx
    185L => 2 // I64Store8: offset, mem_idx
    186L => 2 // I64Store16: offset, mem_idx
    187L => 2 // I64Store32: offset, mem_idx
    188L => 2 // F32Load: offset, mem_idx
    189L => 2 // F32Store: offset, mem_idx
    190L => 2 // F64Load: offset, mem_idx
    191L => 2 // F64Store: offset, mem_idx
    192L => 0 // MemoryCopy
    193L => 0 // MemoryFill
    194L => 1 // MemoryInit: data_idx
    195L => 1 // DataDrop: data_idx

    // Table operations
    196L => 2 // TableCopy: dst_table_idx, src_table_idx
    197L => 1 // TableFill: table_idx
    198L => 2 // TableInit: elem_idx, table_idx
    199L => 1 // ElemDrop: elem_idx
    200L => 1 // TableGet: table_idx
    201L => 1 // TableSet: table_idx
    202L => 1 // TableSize: table_idx
    203L => 1 // TableGrow: table_idx

    // Reference types
    204L => 1 // RefNull: type_code
    205L => 1 // RefFunc: func_idx
    206L => 0 // RefIsNull
    207L => 0 // RefEq
    208L => 0 // RefAsNonNull
    // GC operations
    209L => 2 // StructNew: type_idx, num_fields
    210L => 2 // StructNewDefault: type_idx, num_fields
    211L => 1 // StructGet: field_idx
    212L => 2 // StructGetS: field_idx, storage_type
    213L => 2 // StructGetU: field_idx, storage_type
    214L => 1 // StructSet: field_idx
    215L => 1 // ArrayNew: type_idx
    216L => 1 // ArrayNewDefault: type_idx
    217L => 2 // ArrayNewFixed: type_idx, length
    218L => 3 // ArrayNewData: type_idx, data_idx, elem_size
    219L => 2 // ArrayNewElem: type_idx, elem_idx
    220L => 0 // ArrayGet
    221L => 1 // ArrayGetS: storage_type
    222L => 1 // ArrayGetU: storage_type
    223L => 0 // ArraySet
    224L => 0 // ArrayLen
    225L => 0 // ArrayFill
    226L => 0 // ArrayCopy
    227L => 3 // ArrayInitData: type_idx, data_idx, elem_size
    228L => 2 // ArrayInitElem: type_idx, elem_idx
    229L => 0 // RefI31
    230L => 0 // I31GetS
    231L => 0 // I31GetU
    232L => 0 // AnyConvertExtern
    233L => 0 // ExternConvertAny
    234L => 2 // RefTest: target_type, target_nullable
    235L => 2 // RefCast: target_type, target_nullable
    236L => 4 // BrOnCast: taken_pc, not_taken_pc, target_type, target_nullable
    237L => 4 // BrOnCastFail: taken_pc, not_taken_pc, target_type, target_nullable
    238L => 3 // ReturnCall: callee_pc, num_params, num_locals
    239L => 1 // ReturnCallImport: import_idx
    240L => 2 // ReturnCallIndirect: type_idx, table_idx
    241L => 1 // ReturnCallRef: type_idx
    _ => 0 // Unknown opcode, assume no immediates
  }
}
