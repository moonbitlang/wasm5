///|
/// Get entry function pointer for testing.
pub fn get_entry_fnptr() -> UInt64 {
  entry()
}

///|
/// Transform universal IR (Array[Int64]) to C runtime format (FixedArray[UInt64]).
/// Replaces opcode tags with function pointers while preserving immediates.
pub fn transform_to_c_runtime(code : Array[Int64]) -> FixedArray[UInt64] {
  let result = FixedArray::make(code.length(), 0UL)
  let mut i = 0
  while i < code.length() {
    let opcode = code[i]
    // Replace opcode with function pointer
    result[i] = get_c_handler(opcode)
    i += 1
    // Handle BrTable specially - variable immediates
    if opcode == 10L {
      // BrTable (10): num_labels, then (num_labels + 1) targets
      if i < code.length() {
        let num_labels = code[i].to_int()
        result[i] = code[i].reinterpret_as_uint64()
        i += 1
        // Copy num_labels + 1 target addresses (including default)
        for _ in 0..<(num_labels + 1) {
          if i < code.length() {
            result[i] = code[i].reinterpret_as_uint64()
            i += 1
          }
        }
      }
    } else {
      // Copy immediates based on opcode's immediate count
      let num_immediates = @core.get_immediate_count(opcode)
      for _ in 0..<num_immediates {
        if i < code.length() {
          result[i] = code[i].reinterpret_as_uint64()
          i += 1
        }
      }
    }
  }
  result
}

///|
/// Get C function pointer for an opcode tag.
fn get_c_handler(opcode : Int64) -> UInt64 {
  match opcode {
    // Control flow (0-18)
    0L => wasm_unreachable()
    1L => nop()
    2L => wasm_return()
    3L => end()
    4L => func_exit()
    5L => copy_slot()
    6L => set_sp()
    7L => br()
    8L => br_if()
    9L => wasm_if()
    10L => br_table()
    11L => call()
    12L => call_import()
    13L => call_external()
    14L => entry()
    15L => call_indirect()
    16L => call_ref()
    17L => br_on_null()
    18L => br_on_non_null()

    // Constants (20-23)
    20L => i32_const()
    21L => i64_const()
    22L => f32_const()
    23L => f64_const()

    // Variables (24-28)
    24L => local_get()
    25L => local_set()
    26L => local_tee()
    27L => global_get()
    28L => global_set()

    // Stack operations (29-30)
    29L => drop()
    30L => select()

    // i32 arithmetic (31-45)
    31L => i32_add()
    32L => i32_sub()
    33L => i32_mul()
    34L => i32_div_s()
    35L => i32_div_u()
    36L => i32_rem_s()
    37L => i32_rem_u()
    38L => i32_and()
    39L => i32_or()
    40L => i32_xor()
    41L => i32_shl()
    42L => i32_shr_s()
    43L => i32_shr_u()
    44L => i32_rotl()
    45L => i32_rotr()

    // i32 comparison (46-56)
    46L => i32_eqz()
    47L => i32_eq()
    48L => i32_ne()
    49L => i32_lt_s()
    50L => i32_lt_u()
    51L => i32_gt_s()
    52L => i32_gt_u()
    53L => i32_le_s()
    54L => i32_le_u()
    55L => i32_ge_s()
    56L => i32_ge_u()

    // i32 unary (57-59)
    57L => i32_clz()
    58L => i32_ctz()
    59L => i32_popcnt()

    // i64 arithmetic (60-74)
    60L => i64_add()
    61L => i64_sub()
    62L => i64_mul()
    63L => i64_div_s()
    64L => i64_div_u()
    65L => i64_rem_s()
    66L => i64_rem_u()
    67L => i64_and()
    68L => i64_or()
    69L => i64_xor()
    70L => i64_shl()
    71L => i64_shr_s()
    72L => i64_shr_u()
    73L => i64_rotl()
    74L => i64_rotr()

    // i64 comparison (75-85)
    75L => i64_eqz()
    76L => i64_eq()
    77L => i64_ne()
    78L => i64_lt_s()
    79L => i64_lt_u()
    80L => i64_gt_s()
    81L => i64_gt_u()
    82L => i64_le_s()
    83L => i64_le_u()
    84L => i64_ge_s()
    85L => i64_ge_u()

    // i64 unary (86-88)
    86L => i64_clz()
    87L => i64_ctz()
    88L => i64_popcnt()

    // f32 arithmetic (89-95)
    89L => f32_add()
    90L => f32_sub()
    91L => f32_mul()
    92L => f32_div()
    93L => f32_min()
    94L => f32_max()
    95L => f32_copysign()

    // f32 comparison (96-101)
    96L => f32_eq()
    97L => f32_ne()
    98L => f32_lt()
    99L => f32_gt()
    100L => f32_le()
    101L => f32_ge()

    // f32 unary (102-108)
    102L => f32_abs()
    103L => f32_neg()
    104L => f32_ceil()
    105L => f32_floor()
    106L => f32_trunc()
    107L => f32_nearest()
    108L => f32_sqrt()

    // f64 arithmetic (109-115)
    109L => f64_add()
    110L => f64_sub()
    111L => f64_mul()
    112L => f64_div()
    113L => f64_min()
    114L => f64_max()
    115L => f64_copysign()

    // f64 comparison (116-121)
    116L => f64_eq()
    117L => f64_ne()
    118L => f64_lt()
    119L => f64_gt()
    120L => f64_le()
    121L => f64_ge()

    // f64 unary (122-128)
    122L => f64_abs()
    123L => f64_neg()
    124L => f64_ceil()
    125L => f64_floor()
    126L => f64_trunc()
    127L => f64_nearest()
    128L => f64_sqrt()

    // Conversions (129-161)
    129L => i32_wrap_i64()
    130L => i32_trunc_f32_s()
    131L => i32_trunc_f32_u()
    132L => i32_trunc_f64_s()
    133L => i32_trunc_f64_u()
    134L => i64_extend_i32_s()
    135L => i64_extend_i32_u()
    136L => i64_trunc_f32_s()
    137L => i64_trunc_f32_u()
    138L => i64_trunc_f64_s()
    139L => i64_trunc_f64_u()
    140L => i32_trunc_sat_f32_s()
    141L => i32_trunc_sat_f32_u()
    142L => i32_trunc_sat_f64_s()
    143L => i32_trunc_sat_f64_u()
    144L => i64_trunc_sat_f32_s()
    145L => i64_trunc_sat_f32_u()
    146L => i64_trunc_sat_f64_s()
    147L => i64_trunc_sat_f64_u()
    148L => f32_convert_i32_s()
    149L => f32_convert_i32_u()
    150L => f32_convert_i64_s()
    151L => f32_convert_i64_u()
    152L => f32_demote_f64()
    153L => f64_convert_i32_s()
    154L => f64_convert_i32_u()
    155L => f64_convert_i64_s()
    156L => f64_convert_i64_u()
    157L => f64_promote_f32()
    158L => i32_reinterpret_f32()
    159L => i64_reinterpret_f64()
    160L => f32_reinterpret_i32()
    161L => f64_reinterpret_i64()

    // Sign extension (162-166)
    162L => i32_extend8_s()
    163L => i32_extend16_s()
    164L => i64_extend8_s()
    165L => i64_extend16_s()
    166L => i64_extend32_s()

    // Memory operations (167-195)
    167L => memory_grow()
    168L => memory_size()
    169L => i32_load()
    170L => i32_store()
    171L => i32_load8_s()
    172L => i32_load8_u()
    173L => i32_load16_s()
    174L => i32_load16_u()
    175L => i32_store8()
    176L => i32_store16()
    177L => i64_load()
    178L => i64_load8_s()
    179L => i64_load8_u()
    180L => i64_load16_s()
    181L => i64_load16_u()
    182L => i64_load32_s()
    183L => i64_load32_u()
    184L => i64_store()
    185L => i64_store8()
    186L => i64_store16()
    187L => i64_store32()
    188L => f32_load()
    189L => f32_store()
    190L => f64_load()
    191L => f64_store()
    192L => memory_copy()
    193L => memory_fill()
    194L => memory_init()
    195L => data_drop()

    // Table operations (196-203)
    196L => table_copy()
    197L => table_fill()
    198L => table_init()
    199L => elem_drop()
    200L => table_get()
    201L => table_set()
    202L => table_size()
    203L => table_grow()

    // Reference types (204-208)
    204L => ref_null()
    205L => ref_func()
    206L => ref_is_null()
    207L => ref_eq()
    208L => ref_as_non_null()

    // Unknown opcode - return nop as fallback
    _ => nop()
  }
}
