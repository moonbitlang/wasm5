///|
/// Run the start function if present.
pub fn Runtime::run_start(self : Runtime) -> Unit raise RuntimeError {
  // Execute the start function if present
  match self.ctx.module_.start {
    Some(start_idx) => {
      // Call the start function
      // Start function must have type [] -> []
      let func_idx = start_idx.reinterpret_as_int()
      let num_imported_funcs = count_imported_funcs(self.ctx.module_)

      // Only execute if it's a local function (not imported)
      // Imported start functions would require host environment support
      if func_idx >= num_imported_funcs {
        let local_idx = func_idx - num_imported_funcs
        if local_idx < 0 || local_idx >= self.ctx.compiled.func_entries.length() {
          raise RuntimeError::FunctionNotCompiled("Start function not compiled")
        }
        let start_pc = self.ctx.compiled.func_entries[local_idx]
        let code = self.ctx.module_.codes[local_idx]

        // Clear stack before setting up locals
        let rt = self
        rt.sp = 0

        // Initialize entry locals (start function has no parameters)
        let rt = initialize_entry_locals(rt, [], code)
        rt.pc = start_pc

        // Execute start function, ignoring runtime errors
        // (e.g., calls to unimplemented imported functions)
        let _ = execute(rt) catch { _ => rt }

      }
    }
    None => ()
  }
}

///|
fn execute(rt : Runtime) -> Runtime raise RuntimeError {
  let rt = rt
  let mut code = Running
  while code is Running {
    code = dispatch(rt)
  }
  if code is Trap {
    raise RuntimeError::from_detail(rt.ctx.error_detail)
  }
  // Returned and Terminated both exit normally
  rt
}

///|
fn dispatch(rt : Runtime) -> ReturnCode {
  let opcode = rt.ops.unsafe_get(rt.pc).reinterpret_as_int64()
  match opcode {
    // Control flow (0-18)
    0L => op_unreachable(rt)
    1L => op_nop(rt)
    2L => op_return(rt)
    3L => op_end(rt)
    4L => op_func_exit(rt)
    5L => op_copy_slot(rt)
    6L => op_set_sp(rt)
    7L => op_br(rt)
    8L => op_br_if(rt)
    9L => op_if(rt)
    10L => op_br_table(rt)
    11L => op_call(rt)
    12L => op_call_import(rt)
    13L => op_call_external(rt)
    14L => op_entry(rt)
    15L => op_call_indirect(rt)
    16L => op_call_ref(rt)
    17L => op_br_on_null(rt)
    18L => op_br_on_non_null(rt)

    // Constants (20-23)
    20L => op_i32_const(rt)
    21L => op_i64_const(rt)
    22L => op_f32_const(rt)
    23L => op_f64_const(rt)

    // Variables (24-28)
    24L => op_local_get(rt)
    25L => op_local_set(rt)
    26L => op_local_tee(rt)
    27L => op_global_get(rt)
    28L => op_global_set(rt)

    // Stack operations (29-30)
    29L => op_drop(rt)
    30L => op_select(rt)

    // i32 arithmetic (31-45)
    31L => op_i32_add(rt)
    32L => op_i32_sub(rt)
    33L => op_i32_mul(rt)
    34L => op_i32_div_s(rt)
    35L => op_i32_div_u(rt)
    36L => op_i32_rem_s(rt)
    37L => op_i32_rem_u(rt)
    38L => op_i32_and(rt)
    39L => op_i32_or(rt)
    40L => op_i32_xor(rt)
    41L => op_i32_shl(rt)
    42L => op_i32_shr_s(rt)
    43L => op_i32_shr_u(rt)
    44L => op_i32_rotl(rt)
    45L => op_i32_rotr(rt)

    // i32 comparison (46-56)
    46L => op_i32_eqz(rt)
    47L => op_i32_eq(rt)
    48L => op_i32_ne(rt)
    49L => op_i32_lt_s(rt)
    50L => op_i32_lt_u(rt)
    51L => op_i32_gt_s(rt)
    52L => op_i32_gt_u(rt)
    53L => op_i32_le_s(rt)
    54L => op_i32_le_u(rt)
    55L => op_i32_ge_s(rt)
    56L => op_i32_ge_u(rt)

    // i32 unary (57-59)
    57L => op_i32_clz(rt)
    58L => op_i32_ctz(rt)
    59L => op_i32_popcnt(rt)

    // i64 arithmetic (60-74)
    60L => op_i64_add(rt)
    61L => op_i64_sub(rt)
    62L => op_i64_mul(rt)
    63L => op_i64_div_s(rt)
    64L => op_i64_div_u(rt)
    65L => op_i64_rem_s(rt)
    66L => op_i64_rem_u(rt)
    67L => op_i64_and(rt)
    68L => op_i64_or(rt)
    69L => op_i64_xor(rt)
    70L => op_i64_shl(rt)
    71L => op_i64_shr_s(rt)
    72L => op_i64_shr_u(rt)
    73L => op_i64_rotl(rt)
    74L => op_i64_rotr(rt)

    // i64 comparison (75-85)
    75L => op_i64_eqz(rt)
    76L => op_i64_eq(rt)
    77L => op_i64_ne(rt)
    78L => op_i64_lt_s(rt)
    79L => op_i64_lt_u(rt)
    80L => op_i64_gt_s(rt)
    81L => op_i64_gt_u(rt)
    82L => op_i64_le_s(rt)
    83L => op_i64_le_u(rt)
    84L => op_i64_ge_s(rt)
    85L => op_i64_ge_u(rt)

    // i64 unary (86-88)
    86L => op_i64_clz(rt)
    87L => op_i64_ctz(rt)
    88L => op_i64_popcnt(rt)

    // f32 arithmetic (89-95)
    89L => op_f32_add(rt)
    90L => op_f32_sub(rt)
    91L => op_f32_mul(rt)
    92L => op_f32_div(rt)
    93L => op_f32_min(rt)
    94L => op_f32_max(rt)
    95L => op_f32_copysign(rt)

    // f32 comparison (96-101)
    96L => op_f32_eq(rt)
    97L => op_f32_ne(rt)
    98L => op_f32_lt(rt)
    99L => op_f32_gt(rt)
    100L => op_f32_le(rt)
    101L => op_f32_ge(rt)

    // f32 unary (102-108)
    102L => op_f32_abs(rt)
    103L => op_f32_neg(rt)
    104L => op_f32_ceil(rt)
    105L => op_f32_floor(rt)
    106L => op_f32_trunc(rt)
    107L => op_f32_nearest(rt)
    108L => op_f32_sqrt(rt)

    // f64 arithmetic (109-115)
    109L => op_f64_add(rt)
    110L => op_f64_sub(rt)
    111L => op_f64_mul(rt)
    112L => op_f64_div(rt)
    113L => op_f64_min(rt)
    114L => op_f64_max(rt)
    115L => op_f64_copysign(rt)

    // f64 comparison (116-121)
    116L => op_f64_eq(rt)
    117L => op_f64_ne(rt)
    118L => op_f64_lt(rt)
    119L => op_f64_gt(rt)
    120L => op_f64_le(rt)
    121L => op_f64_ge(rt)

    // f64 unary (122-128)
    122L => op_f64_abs(rt)
    123L => op_f64_neg(rt)
    124L => op_f64_ceil(rt)
    125L => op_f64_floor(rt)
    126L => op_f64_trunc(rt)
    127L => op_f64_nearest(rt)
    128L => op_f64_sqrt(rt)

    // Conversions (129-161)
    129L => op_i32_wrap_i64(rt)
    130L => op_i32_trunc_f32_s(rt)
    131L => op_i32_trunc_f32_u(rt)
    132L => op_i32_trunc_f64_s(rt)
    133L => op_i32_trunc_f64_u(rt)
    134L => op_i64_extend_i32_s(rt)
    135L => op_i64_extend_i32_u(rt)
    136L => op_i64_trunc_f32_s(rt)
    137L => op_i64_trunc_f32_u(rt)
    138L => op_i64_trunc_f64_s(rt)
    139L => op_i64_trunc_f64_u(rt)
    140L => op_i32_trunc_sat_f32_s(rt)
    141L => op_i32_trunc_sat_f32_u(rt)
    142L => op_i32_trunc_sat_f64_s(rt)
    143L => op_i32_trunc_sat_f64_u(rt)
    144L => op_i64_trunc_sat_f32_s(rt)
    145L => op_i64_trunc_sat_f32_u(rt)
    146L => op_i64_trunc_sat_f64_s(rt)
    147L => op_i64_trunc_sat_f64_u(rt)
    148L => op_f32_convert_i32_s(rt)
    149L => op_f32_convert_i32_u(rt)
    150L => op_f32_convert_i64_s(rt)
    151L => op_f32_convert_i64_u(rt)
    152L => op_f32_demote_f64(rt)
    153L => op_f64_convert_i32_s(rt)
    154L => op_f64_convert_i32_u(rt)
    155L => op_f64_convert_i64_s(rt)
    156L => op_f64_convert_i64_u(rt)
    157L => op_f64_promote_f32(rt)
    158L => op_i32_reinterpret_f32(rt)
    159L => op_i64_reinterpret_f64(rt)
    160L => op_f32_reinterpret_i32(rt)
    161L => op_f64_reinterpret_i64(rt)

    // Sign extension (162-166)
    162L => op_i32_extend8_s(rt)
    163L => op_i32_extend16_s(rt)
    164L => op_i64_extend8_s(rt)
    165L => op_i64_extend16_s(rt)
    166L => op_i64_extend32_s(rt)

    // Memory operations (167-195)
    167L => op_memory_grow(rt)
    168L => op_memory_size(rt)
    169L => op_i32_load(rt)
    170L => op_i32_store(rt)
    171L => op_i32_load8_s(rt)
    172L => op_i32_load8_u(rt)
    173L => op_i32_load16_s(rt)
    174L => op_i32_load16_u(rt)
    175L => op_i32_store8(rt)
    176L => op_i32_store16(rt)
    177L => op_i64_load(rt)
    178L => op_i64_load8_s(rt)
    179L => op_i64_load8_u(rt)
    180L => op_i64_load16_s(rt)
    181L => op_i64_load16_u(rt)
    182L => op_i64_load32_s(rt)
    183L => op_i64_load32_u(rt)
    184L => op_i64_store(rt)
    185L => op_i64_store8(rt)
    186L => op_i64_store16(rt)
    187L => op_i64_store32(rt)
    188L => op_f32_load(rt)
    189L => op_f32_store(rt)
    190L => op_f64_load(rt)
    191L => op_f64_store(rt)
    192L => op_memory_copy(rt)
    193L => op_memory_fill(rt)
    194L => op_memory_init(rt)
    195L => op_data_drop(rt)

    // Table operations (196-203)
    196L => op_table_copy(rt)
    197L => op_table_fill(rt)
    198L => op_table_init(rt)
    199L => op_elem_drop(rt)
    200L => op_table_get(rt)
    201L => op_table_set(rt)
    202L => op_table_size(rt)
    203L => op_table_grow(rt)

    // Reference types (204-208)
    204L => op_ref_null(rt)
    205L => op_ref_func(rt)
    206L => op_ref_is_null(rt)
    207L => op_ref_eq(rt)
    208L => op_ref_as_non_null(rt)

    // GC operations (209-237)
    209L => op_struct_new(rt)
    210L => op_struct_new_default(rt)
    211L => op_struct_get(rt)
    212L => op_struct_get_s(rt)
    213L => op_struct_get_u(rt)
    214L => op_struct_set(rt)
    215L => op_array_new(rt)
    216L => op_array_new_default(rt)
    217L => op_array_new_fixed(rt)
    218L => op_array_new_data(rt)
    219L => op_array_new_elem(rt)
    220L => op_array_get(rt)
    221L => op_array_get_s(rt)
    222L => op_array_get_u(rt)
    223L => op_array_set(rt)
    224L => op_array_len(rt)
    225L => op_array_fill(rt)
    226L => op_array_copy(rt)
    227L => op_array_init_data(rt)
    228L => op_array_init_elem(rt)
    229L => op_ref_i31(rt)
    230L => op_i31_get_s(rt)
    231L => op_i31_get_u(rt)
    232L => op_any_convert_extern(rt)
    233L => op_extern_convert_any(rt)
    234L => op_ref_test(rt)
    235L => op_ref_cast(rt)
    236L => op_br_on_cast(rt)
    237L => op_br_on_cast_fail(rt)
    238L => op_return_call_local(rt)
    239L => op_return_call_import(rt)
    240L => op_return_call_indirect(rt)
    241L => op_return_call_ref(rt)
    _ => {
      rt.ctx.error_detail = "invalid opcode \{opcode}"
      Trap
    }
  }
}

///|
/// Execute a local function call using native stack.
/// Caller state is preserved on the MoonBit stack frame.
/// Returns the runtime with results on the stack after callee returns.
fn execute_call(
  rt : Runtime,
  callee_pc : Int,
  caller_bp : Int,
  caller_num_locals : Int,
  caller_sp : Int,
  return_pc : Int,
) -> Runtime raise RuntimeError {
  // Execute callee
  let rt = rt
  rt.pc = callee_pc
  let rt = execute(rt)

  // Callee has returned - results are at stack[rt.bp .. rt.sp)
  // Return values are already copied to bp by op_return
  // Restore caller's state
  rt.bp = caller_bp
  rt.num_locals = caller_num_locals
  rt.sp = caller_sp
  rt.pc = return_pc
  rt
}

///|
/// Call a compiled function by name with the given arguments.
pub fn Runtime::call_compiled(
  self : Runtime,
  func_name : Bytes,
  args : Array[Value],
) -> Array[Value] raise RuntimeError {
  let mut func_idx : Int? = None
  for exp in self.ctx.module_.exports {
    if exp.name == func_name {
      match exp.desc {
        Func(idx) => {
          func_idx = Some(idx.reinterpret_as_int())
          break
        }
        _ => continue
      }
    }
  }
  guard func_idx is Some(idx) else {
    raise RuntimeError::FunctionNotFound("Function not found: \{func_name}")
  }
  let num_imported_funcs = count_imported_funcs(self.ctx.module_)

  // Check if it's an imported function - call it directly via import resolver
  if idx < num_imported_funcs {
    let imported_func = self.ctx.imported_funcs[idx]
    return (imported_func.func)(args)
  }

  // Adjust to local function index
  let local_idx = idx - num_imported_funcs
  let type_idx = self.ctx.module_.funcs[local_idx].reinterpret_as_int()
  let func_type = require_func_type(self.ctx.module_, type_idx, "call_compiled")
  if local_idx < 0 || local_idx >= self.ctx.compiled.func_entries.length() {
    raise RuntimeError::FunctionNotCompiled(
      "Function not compiled: \{func_name}",
    )
  }
  let start_pc = self.ctx.compiled.func_entries[local_idx]
  let code = self.ctx.module_.codes[local_idx]

  // Clear stack before setting up entry frame
  let rt = self
  rt.sp = 0

  // Initialize entry locals (pushes args and locals onto stack, sets sp/num_locals)
  let rt = initialize_entry_locals(rt, args, code)
  rt.pc = start_pc
  let rt = execute(rt)

  // Extract results from unified stack
  // After function returns, results are at stack[0..num_results)
  let results : Array[Value] = []
  let result_types = func_type.results
  for i in 0..<result_types.length() {
    if i < rt.sp {
      results.push(stack_to_value(rt.stack.unsafe_get(i), result_types[i]))
    }
  }
  results
}

///|
/// Call a function by its index (used for funcref handling).
/// This allows calling functions that may not be exported by name.
pub fn Runtime::call_by_index(
  self : Runtime,
  func_idx : Int,
  args : Array[Value],
) -> Array[Value] raise RuntimeError {
  let num_imported_funcs = count_imported_funcs(self.ctx.module_)

  // Check if it's an imported function - call it directly via import resolver
  if func_idx < num_imported_funcs {
    if func_idx < 0 || func_idx >= self.ctx.imported_funcs.length() {
      raise RuntimeError::FunctionNotFound(
        "Invalid imported function index: \{func_idx}",
      )
    }
    let imported_func = self.ctx.imported_funcs[func_idx]
    return (imported_func.func)(args)
  }

  // Adjust to local function index
  let local_idx = func_idx - num_imported_funcs
  if local_idx < 0 || local_idx >= self.ctx.module_.codes.length() {
    raise RuntimeError::FunctionNotFound(
      "Invalid local function index: \{func_idx}",
    )
  }
  let type_idx = self.ctx.module_.funcs[local_idx].reinterpret_as_int()
  let func_type = require_func_type(self.ctx.module_, type_idx, "call_by_index")
  if local_idx < 0 || local_idx >= self.ctx.compiled.func_entries.length() {
    raise RuntimeError::FunctionNotCompiled(
      "Function not compiled: index \{func_idx}",
    )
  }
  let start_pc = self.ctx.compiled.func_entries[local_idx]
  let code = self.ctx.module_.codes[local_idx]

  // Clear stack before setting up entry frame
  let rt = self
  rt.sp = 0

  // Initialize entry locals (pushes args and locals onto stack, sets sp/num_locals)
  let rt = initialize_entry_locals(rt, args, code)
  rt.pc = start_pc
  let rt = execute(rt)

  // Extract results from unified stack
  let results : Array[Value] = []
  let result_types = func_type.results
  for i in 0..<result_types.length() {
    if i < rt.sp {
      results.push(stack_to_value(rt.stack.unsafe_get(i), result_types[i]))
    }
  }
  results
}
