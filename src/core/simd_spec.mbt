///|
pub(all) enum SimdImmKind {
  None
  MemArg
  Lane
  MemArgLane
  Shuffle
  V128Const
} derive(Show, Eq)

///|
pub(all) struct SimdSpec {
  name : Bytes
  opcode : UInt
  imm : SimdImmKind
}

///|
pub(all) enum SimdStackEffect {
  Const
  Load
  Store
  LoadLane
  StoreLane
  Unary
  Binary
  Ternary
  Shift
  ToI32
  Splat(ValType)
  Extract(ValType)
  Replace(ValType)
} derive(Show)

///|
pub let simd_specs : Array[SimdSpec] = [
  { name: b"v128.load", opcode: 0x00U, imm: MemArg },
  { name: b"v128.load8x8_s", opcode: 0x01U, imm: MemArg },
  { name: b"v128.load8x8_u", opcode: 0x02U, imm: MemArg },
  { name: b"v128.load16x4_s", opcode: 0x03U, imm: MemArg },
  { name: b"v128.load16x4_u", opcode: 0x04U, imm: MemArg },
  { name: b"v128.load32x2_s", opcode: 0x05U, imm: MemArg },
  { name: b"v128.load32x2_u", opcode: 0x06U, imm: MemArg },
  { name: b"v128.load8_splat", opcode: 0x07U, imm: MemArg },
  { name: b"v128.load16_splat", opcode: 0x08U, imm: MemArg },
  { name: b"v128.load32_splat", opcode: 0x09U, imm: MemArg },
  { name: b"v128.load64_splat", opcode: 0x0AU, imm: MemArg },
  { name: b"v128.store", opcode: 0x0BU, imm: MemArg },
  { name: b"v128.const", opcode: 0x0CU, imm: V128Const },
  { name: b"i8x16.shuffle", opcode: 0x0DU, imm: Shuffle },
  { name: b"i8x16.swizzle", opcode: 0x0EU, imm: None },
  { name: b"i8x16.splat", opcode: 0x0FU, imm: None },
  { name: b"i16x8.splat", opcode: 0x10U, imm: None },
  { name: b"i32x4.splat", opcode: 0x11U, imm: None },
  { name: b"i64x2.splat", opcode: 0x12U, imm: None },
  { name: b"f32x4.splat", opcode: 0x13U, imm: None },
  { name: b"f64x2.splat", opcode: 0x14U, imm: None },
  { name: b"i8x16.extract_lane_s", opcode: 0x15U, imm: Lane },
  { name: b"i8x16.extract_lane_u", opcode: 0x16U, imm: Lane },
  { name: b"i8x16.replace_lane", opcode: 0x17U, imm: Lane },
  { name: b"i16x8.extract_lane_s", opcode: 0x18U, imm: Lane },
  { name: b"i16x8.extract_lane_u", opcode: 0x19U, imm: Lane },
  { name: b"i16x8.replace_lane", opcode: 0x1AU, imm: Lane },
  { name: b"i32x4.extract_lane", opcode: 0x1BU, imm: Lane },
  { name: b"i32x4.replace_lane", opcode: 0x1CU, imm: Lane },
  { name: b"i64x2.extract_lane", opcode: 0x1DU, imm: Lane },
  { name: b"i64x2.replace_lane", opcode: 0x1EU, imm: Lane },
  { name: b"f32x4.extract_lane", opcode: 0x1FU, imm: Lane },
  { name: b"f32x4.replace_lane", opcode: 0x20U, imm: Lane },
  { name: b"f64x2.extract_lane", opcode: 0x21U, imm: Lane },
  { name: b"f64x2.replace_lane", opcode: 0x22U, imm: Lane },
  { name: b"i8x16.eq", opcode: 0x23U, imm: None },
  { name: b"i8x16.ne", opcode: 0x24U, imm: None },
  { name: b"i8x16.lt_s", opcode: 0x25U, imm: None },
  { name: b"i8x16.lt_u", opcode: 0x26U, imm: None },
  { name: b"i8x16.gt_s", opcode: 0x27U, imm: None },
  { name: b"i8x16.gt_u", opcode: 0x28U, imm: None },
  { name: b"i8x16.le_s", opcode: 0x29U, imm: None },
  { name: b"i8x16.le_u", opcode: 0x2AU, imm: None },
  { name: b"i8x16.ge_s", opcode: 0x2BU, imm: None },
  { name: b"i8x16.ge_u", opcode: 0x2CU, imm: None },
  { name: b"i16x8.eq", opcode: 0x2DU, imm: None },
  { name: b"i16x8.ne", opcode: 0x2EU, imm: None },
  { name: b"i16x8.lt_s", opcode: 0x2FU, imm: None },
  { name: b"i16x8.lt_u", opcode: 0x30U, imm: None },
  { name: b"i16x8.gt_s", opcode: 0x31U, imm: None },
  { name: b"i16x8.gt_u", opcode: 0x32U, imm: None },
  { name: b"i16x8.le_s", opcode: 0x33U, imm: None },
  { name: b"i16x8.le_u", opcode: 0x34U, imm: None },
  { name: b"i16x8.ge_s", opcode: 0x35U, imm: None },
  { name: b"i16x8.ge_u", opcode: 0x36U, imm: None },
  { name: b"i32x4.eq", opcode: 0x37U, imm: None },
  { name: b"i32x4.ne", opcode: 0x38U, imm: None },
  { name: b"i32x4.lt_s", opcode: 0x39U, imm: None },
  { name: b"i32x4.lt_u", opcode: 0x3AU, imm: None },
  { name: b"i32x4.gt_s", opcode: 0x3BU, imm: None },
  { name: b"i32x4.gt_u", opcode: 0x3CU, imm: None },
  { name: b"i32x4.le_s", opcode: 0x3DU, imm: None },
  { name: b"i32x4.le_u", opcode: 0x3EU, imm: None },
  { name: b"i32x4.ge_s", opcode: 0x3FU, imm: None },
  { name: b"i32x4.ge_u", opcode: 0x40U, imm: None },
  { name: b"f32x4.eq", opcode: 0x41U, imm: None },
  { name: b"f32x4.ne", opcode: 0x42U, imm: None },
  { name: b"f32x4.lt", opcode: 0x43U, imm: None },
  { name: b"f32x4.gt", opcode: 0x44U, imm: None },
  { name: b"f32x4.le", opcode: 0x45U, imm: None },
  { name: b"f32x4.ge", opcode: 0x46U, imm: None },
  { name: b"f64x2.eq", opcode: 0x47U, imm: None },
  { name: b"f64x2.ne", opcode: 0x48U, imm: None },
  { name: b"f64x2.lt", opcode: 0x49U, imm: None },
  { name: b"f64x2.gt", opcode: 0x4AU, imm: None },
  { name: b"f64x2.le", opcode: 0x4BU, imm: None },
  { name: b"f64x2.ge", opcode: 0x4CU, imm: None },
  { name: b"v128.not", opcode: 0x4DU, imm: None },
  { name: b"v128.and", opcode: 0x4EU, imm: None },
  { name: b"v128.andnot", opcode: 0x4FU, imm: None },
  { name: b"v128.or", opcode: 0x50U, imm: None },
  { name: b"v128.xor", opcode: 0x51U, imm: None },
  { name: b"v128.bitselect", opcode: 0x52U, imm: None },
  { name: b"v128.any_true", opcode: 0x53U, imm: None },
  { name: b"v128.load8_lane", opcode: 0x54U, imm: MemArgLane },
  { name: b"v128.load16_lane", opcode: 0x55U, imm: MemArgLane },
  { name: b"v128.load32_lane", opcode: 0x56U, imm: MemArgLane },
  { name: b"v128.load64_lane", opcode: 0x57U, imm: MemArgLane },
  { name: b"v128.store8_lane", opcode: 0x58U, imm: MemArgLane },
  { name: b"v128.store16_lane", opcode: 0x59U, imm: MemArgLane },
  { name: b"v128.store32_lane", opcode: 0x5AU, imm: MemArgLane },
  { name: b"v128.store64_lane", opcode: 0x5BU, imm: MemArgLane },
  { name: b"v128.load32_zero", opcode: 0x5CU, imm: MemArg },
  { name: b"v128.load64_zero", opcode: 0x5DU, imm: MemArg },
  { name: b"f32x4.demote_f64x2_zero", opcode: 0x5EU, imm: None },
  { name: b"f64x2.promote_low_f32x4", opcode: 0x5FU, imm: None },
  { name: b"i8x16.abs", opcode: 0x60U, imm: None },
  { name: b"i8x16.neg", opcode: 0x61U, imm: None },
  { name: b"i8x16.popcnt", opcode: 0x62U, imm: None },
  { name: b"i8x16.all_true", opcode: 0x63U, imm: None },
  { name: b"i8x16.bitmask", opcode: 0x64U, imm: None },
  { name: b"i8x16.narrow_i16x8_s", opcode: 0x65U, imm: None },
  { name: b"i8x16.narrow_i16x8_u", opcode: 0x66U, imm: None },
  { name: b"i8x16.shl", opcode: 0x6BU, imm: None },
  { name: b"i8x16.shr_s", opcode: 0x6CU, imm: None },
  { name: b"i8x16.shr_u", opcode: 0x6DU, imm: None },
  { name: b"i8x16.add", opcode: 0x6EU, imm: None },
  { name: b"i8x16.add_sat_s", opcode: 0x6FU, imm: None },
  { name: b"i8x16.add_sat_u", opcode: 0x70U, imm: None },
  { name: b"i8x16.sub", opcode: 0x71U, imm: None },
  { name: b"i8x16.sub_sat_s", opcode: 0x72U, imm: None },
  { name: b"i8x16.sub_sat_u", opcode: 0x73U, imm: None },
  { name: b"i8x16.min_s", opcode: 0x76U, imm: None },
  { name: b"i8x16.min_u", opcode: 0x77U, imm: None },
  { name: b"i8x16.max_s", opcode: 0x78U, imm: None },
  { name: b"i8x16.max_u", opcode: 0x79U, imm: None },
  { name: b"i8x16.avgr_u", opcode: 0x7BU, imm: None },
  { name: b"i16x8.extadd_pairwise_i8x16_s", opcode: 0x7CU, imm: None },
  { name: b"i16x8.extadd_pairwise_i8x16_u", opcode: 0x7DU, imm: None },
  { name: b"i16x8.abs", opcode: 0x80U, imm: None },
  { name: b"i16x8.neg", opcode: 0x81U, imm: None },
  { name: b"i16x8.q15mulr_sat_s", opcode: 0x82U, imm: None },
  { name: b"i16x8.all_true", opcode: 0x83U, imm: None },
  { name: b"i16x8.bitmask", opcode: 0x84U, imm: None },
  { name: b"i16x8.narrow_i32x4_s", opcode: 0x85U, imm: None },
  { name: b"i16x8.narrow_i32x4_u", opcode: 0x86U, imm: None },
  { name: b"i16x8.extend_low_i8x16_s", opcode: 0x87U, imm: None },
  { name: b"i16x8.extend_high_i8x16_s", opcode: 0x88U, imm: None },
  { name: b"i16x8.extend_low_i8x16_u", opcode: 0x89U, imm: None },
  { name: b"i16x8.extend_high_i8x16_u", opcode: 0x8AU, imm: None },
  { name: b"i16x8.shl", opcode: 0x8BU, imm: None },
  { name: b"i16x8.shr_s", opcode: 0x8CU, imm: None },
  { name: b"i16x8.shr_u", opcode: 0x8DU, imm: None },
  { name: b"i16x8.add", opcode: 0x8EU, imm: None },
  { name: b"i16x8.add_sat_s", opcode: 0x8FU, imm: None },
  { name: b"i16x8.add_sat_u", opcode: 0x90U, imm: None },
  { name: b"i16x8.sub", opcode: 0x91U, imm: None },
  { name: b"i16x8.sub_sat_s", opcode: 0x92U, imm: None },
  { name: b"i16x8.sub_sat_u", opcode: 0x93U, imm: None },
  { name: b"i16x8.mul", opcode: 0x95U, imm: None },
  { name: b"i16x8.min_s", opcode: 0x96U, imm: None },
  { name: b"i16x8.min_u", opcode: 0x97U, imm: None },
  { name: b"i16x8.max_s", opcode: 0x98U, imm: None },
  { name: b"i16x8.max_u", opcode: 0x99U, imm: None },
  { name: b"i16x8.avgr_u", opcode: 0x9BU, imm: None },
  { name: b"i16x8.extmul_low_i8x16_s", opcode: 0x9CU, imm: None },
  { name: b"i16x8.extmul_high_i8x16_s", opcode: 0x9DU, imm: None },
  { name: b"i16x8.extmul_low_i8x16_u", opcode: 0x9EU, imm: None },
  { name: b"i16x8.extmul_high_i8x16_u", opcode: 0x9FU, imm: None },
  { name: b"i32x4.abs", opcode: 0xA0U, imm: None },
  { name: b"i32x4.neg", opcode: 0xA1U, imm: None },
  { name: b"i32x4.all_true", opcode: 0xA3U, imm: None },
  { name: b"i32x4.bitmask", opcode: 0xA4U, imm: None },
  { name: b"i32x4.extend_low_i16x8_s", opcode: 0xA7U, imm: None },
  { name: b"i32x4.extend_high_i16x8_s", opcode: 0xA8U, imm: None },
  { name: b"i32x4.extend_low_i16x8_u", opcode: 0xA9U, imm: None },
  { name: b"i32x4.extend_high_i16x8_u", opcode: 0xAAU, imm: None },
  { name: b"i32x4.shl", opcode: 0xABU, imm: None },
  { name: b"i32x4.shr_s", opcode: 0xACU, imm: None },
  { name: b"i32x4.shr_u", opcode: 0xADU, imm: None },
  { name: b"i32x4.add", opcode: 0xAEU, imm: None },
  { name: b"i32x4.sub", opcode: 0xB1U, imm: None },
  { name: b"i32x4.mul", opcode: 0xB5U, imm: None },
  { name: b"i32x4.min_s", opcode: 0xB6U, imm: None },
  { name: b"i32x4.min_u", opcode: 0xB7U, imm: None },
  { name: b"i32x4.max_s", opcode: 0xB8U, imm: None },
  { name: b"i32x4.max_u", opcode: 0xB9U, imm: None },
  { name: b"i32x4.dot_i16x8_s", opcode: 0xBAU, imm: None },
  { name: b"i32x4.extmul_low_i16x8_s", opcode: 0xBCU, imm: None },
  { name: b"i32x4.extmul_high_i16x8_s", opcode: 0xBDU, imm: None },
  { name: b"i32x4.extmul_low_i16x8_u", opcode: 0xBEU, imm: None },
  { name: b"i32x4.extmul_high_i16x8_u", opcode: 0xBFU, imm: None },
  { name: b"i64x2.abs", opcode: 0xC0U, imm: None },
  { name: b"i64x2.neg", opcode: 0xC1U, imm: None },
  { name: b"i64x2.all_true", opcode: 0xC3U, imm: None },
  { name: b"i64x2.bitmask", opcode: 0xC4U, imm: None },
  { name: b"i64x2.extend_low_i32x4_s", opcode: 0xC7U, imm: None },
  { name: b"i64x2.extend_high_i32x4_s", opcode: 0xC8U, imm: None },
  { name: b"i64x2.extend_low_i32x4_u", opcode: 0xC9U, imm: None },
  { name: b"i64x2.extend_high_i32x4_u", opcode: 0xCAU, imm: None },
  { name: b"i64x2.shl", opcode: 0xCBU, imm: None },
  { name: b"i64x2.shr_s", opcode: 0xCCU, imm: None },
  { name: b"i64x2.shr_u", opcode: 0xCDU, imm: None },
  { name: b"i64x2.add", opcode: 0xCEU, imm: None },
  { name: b"i64x2.sub", opcode: 0xD1U, imm: None },
  { name: b"i64x2.mul", opcode: 0xD5U, imm: None },
  { name: b"i64x2.eq", opcode: 0xD6U, imm: None },
  { name: b"i64x2.ne", opcode: 0xD7U, imm: None },
  { name: b"i64x2.lt_s", opcode: 0xD8U, imm: None },
  { name: b"i64x2.gt_s", opcode: 0xD9U, imm: None },
  { name: b"i64x2.le_s", opcode: 0xDAU, imm: None },
  { name: b"i64x2.ge_s", opcode: 0xDBU, imm: None },
  { name: b"f32x4.abs", opcode: 0xE0U, imm: None },
  { name: b"f32x4.neg", opcode: 0xE1U, imm: None },
  { name: b"f32x4.sqrt", opcode: 0xE3U, imm: None },
  { name: b"f32x4.add", opcode: 0xE4U, imm: None },
  { name: b"f32x4.sub", opcode: 0xE5U, imm: None },
  { name: b"f32x4.mul", opcode: 0xE6U, imm: None },
  { name: b"f32x4.div", opcode: 0xE7U, imm: None },
  { name: b"f32x4.min", opcode: 0xE8U, imm: None },
  { name: b"f32x4.max", opcode: 0xE9U, imm: None },
  { name: b"f32x4.pmin", opcode: 0xEAU, imm: None },
  { name: b"f32x4.pmax", opcode: 0xEBU, imm: None },
  { name: b"f64x2.abs", opcode: 0xECU, imm: None },
  { name: b"f64x2.neg", opcode: 0xEDU, imm: None },
  { name: b"f64x2.sqrt", opcode: 0xEFU, imm: None },
  { name: b"f64x2.add", opcode: 0xF0U, imm: None },
  { name: b"f64x2.sub", opcode: 0xF1U, imm: None },
  { name: b"f64x2.mul", opcode: 0xF2U, imm: None },
  { name: b"f64x2.div", opcode: 0xF3U, imm: None },
  { name: b"f64x2.min", opcode: 0xF4U, imm: None },
  { name: b"f64x2.max", opcode: 0xF5U, imm: None },
  { name: b"f64x2.pmin", opcode: 0xF6U, imm: None },
  { name: b"f64x2.pmax", opcode: 0xF7U, imm: None },
  { name: b"i32x4.trunc_sat_f32x4_s", opcode: 0xF8U, imm: None },
  { name: b"i32x4.trunc_sat_f32x4_u", opcode: 0xF9U, imm: None },
  { name: b"f32x4.convert_i32x4_s", opcode: 0xFAU, imm: None },
  { name: b"f32x4.convert_i32x4_u", opcode: 0xFBU, imm: None },
  { name: b"i32x4.trunc_sat_f64x2_s_zero", opcode: 0xFCU, imm: None },
  { name: b"i32x4.trunc_sat_f64x2_u_zero", opcode: 0xFDU, imm: None },
  { name: b"f64x2.convert_low_i32x4_s", opcode: 0xFEU, imm: None },
  { name: b"f64x2.convert_low_i32x4_u", opcode: 0xFFU, imm: None },
]

///|
pub fn simd_spec_by_name(name : Bytes) -> SimdSpec? {
  for spec in simd_specs {
    if spec.name == name {
      return Some(spec)
    }
  }
  None
}

///|
pub fn simd_spec_by_opcode(opcode : UInt) -> SimdSpec? {
  for spec in simd_specs {
    if spec.opcode == opcode {
      return Some(spec)
    }
  }
  None
}

///|
pub fn simd_stack_effect(name : Bytes) -> SimdStackEffect {
  if name == b"v128.const" {
    return SimdStackEffect::Const
  }
  if bytes_starts_with(name, b"v128.load") {
    if bytes_contains(name, b"_lane") {
      return SimdStackEffect::LoadLane
    }
    return SimdStackEffect::Load
  }
  if bytes_starts_with(name, b"v128.store") {
    if bytes_contains(name, b"_lane") {
      return SimdStackEffect::StoreLane
    }
    return SimdStackEffect::Store
  }
  if name == b"i8x16.shuffle" {
    return SimdStackEffect::Binary
  }
  if name == b"v128.bitselect" {
    return SimdStackEffect::Ternary
  }
  if name == b"v128.any_true" ||
    bytes_ends_with(name, b".all_true") ||
    bytes_ends_with(name, b".bitmask") {
    return SimdStackEffect::ToI32
  }
  if bytes_ends_with(name, b".splat") {
    return SimdStackEffect::Splat(simd_scalar_type(name))
  }
  if bytes_contains(name, b"extract_lane") {
    return SimdStackEffect::Extract(simd_scalar_type(name))
  }
  if bytes_contains(name, b"replace_lane") {
    return SimdStackEffect::Replace(simd_scalar_type(name))
  }
  if bytes_ends_with(name, b".shl") ||
    bytes_ends_with(name, b".shr_s") ||
    bytes_ends_with(name, b".shr_u") {
    return SimdStackEffect::Shift
  }
  if bytes_contains(name, b"extadd_pairwise") ||
    bytes_contains(name, b"convert") ||
    bytes_contains(name, b"demote") ||
    bytes_contains(name, b"promote") ||
    bytes_contains(name, b"trunc_sat") ||
    bytes_contains(name, b"extend_low") ||
    bytes_contains(name, b"extend_high") ||
    bytes_contains(name, b"abs") ||
    bytes_contains(name, b"neg") ||
    bytes_contains(name, b"popcnt") ||
    bytes_contains(name, b"sqrt") ||
    name == b"v128.not" {
    return SimdStackEffect::Unary
  }
  if bytes_contains(name, b"swizzle") ||
    bytes_contains(name, b"extmul") ||
    bytes_contains(name, b"narrow_") ||
    bytes_contains(name, b"dot_") ||
    bytes_contains(name, b"q15mulr") ||
    bytes_contains(name, b"avgr") ||
    bytes_contains(name, b".add_sat") ||
    bytes_contains(name, b".sub_sat") ||
    bytes_contains(name, b".add") ||
    bytes_contains(name, b".sub") ||
    bytes_contains(name, b".mul") ||
    bytes_contains(name, b".min") ||
    bytes_contains(name, b".max") ||
    bytes_contains(name, b".pmin") ||
    bytes_contains(name, b".pmax") ||
    bytes_contains(name, b".eq") ||
    bytes_contains(name, b".ne") ||
    bytes_contains(name, b".lt") ||
    bytes_contains(name, b".gt") ||
    bytes_contains(name, b".le") ||
    bytes_contains(name, b".ge") ||
    bytes_contains(name, b".andnot") ||
    bytes_contains(name, b".and") ||
    bytes_contains(name, b".or") ||
    bytes_contains(name, b".xor") {
    return SimdStackEffect::Binary
  }
  SimdStackEffect::Unary
}

///|
fn simd_scalar_type(name : Bytes) -> ValType {
  if bytes_starts_with(name, b"i64x2.") {
    return I64
  }
  if bytes_starts_with(name, b"f32x4.") {
    return F32
  }
  if bytes_starts_with(name, b"f64x2.") {
    return F64
  }
  I32
}

///|
fn bytes_starts_with(bytes : Bytes, prefix : Bytes) -> Bool {
  guard bytes.length() >= prefix.length() else { return false }
  for i in 0..<prefix.length() {
    if bytes[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn bytes_ends_with(bytes : Bytes, suffix : Bytes) -> Bool {
  guard bytes.length() >= suffix.length() else { return false }
  let offset = bytes.length() - suffix.length()
  for i in 0..<suffix.length() {
    if bytes[offset + i] != suffix[i] {
      return false
    }
  }
  true
}

///|
fn bytes_contains(bytes : Bytes, needle : Bytes) -> Bool {
  guard needle.length() > 0 else { return true }
  guard bytes.length() >= needle.length() else { return false }
  let max_idx = bytes.length() - needle.length()
  let mut i = 0
  while i <= max_idx {
    let mut ok = true
    for j in 0..<needle.length() {
      if bytes[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
    i = i + 1
  }
  false
}
