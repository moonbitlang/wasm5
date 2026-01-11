///|
/// C Runtime Function Signature:
///
/// ```c
/// typedef struct {
///     uint64_t* pc;      // Program counter into code array
///     uint64_t* sp;      // Stack pointer (points to next push slot)
///     uint8_t* mem;      // Linear memory
/// } CRuntime;
///
/// typedef void (*OpFn)(CRuntime* rt);
///
/// // Each handler tail-calls next op: ((OpFn)*rt->pc++)(rt)
/// ```

// Control
extern "C" fn wasm_unreachable() -> UInt64 = "wasm_unreachable"

///|
extern "C" fn nop() -> UInt64 = "nop"

///|
extern "C" fn wasm_return() -> UInt64 = "wasm_return"

///|
extern "C" fn end() -> UInt64 = "end"

// Constants

///|
extern "C" fn i32_const() -> UInt64 = "i32_const"

///|
extern "C" fn i64_const() -> UInt64 = "i64_const"

///|
extern "C" fn f32_const() -> UInt64 = "f32_const"

///|
extern "C" fn f64_const() -> UInt64 = "f64_const"

// Local/Global access

///|
extern "C" fn local_get() -> UInt64 = "local_get"

///|
extern "C" fn local_set() -> UInt64 = "local_set"

///|
extern "C" fn local_tee() -> UInt64 = "local_tee"

///|
extern "C" fn global_get() -> UInt64 = "global_get"

///|
extern "C" fn global_set() -> UInt64 = "global_set"

// i32 arithmetic

///|
extern "C" fn i32_add() -> UInt64 = "i32_add"

///|
extern "C" fn i32_sub() -> UInt64 = "i32_sub"

///|
extern "C" fn i32_mul() -> UInt64 = "i32_mul"

///|
extern "C" fn i32_div_s() -> UInt64 = "i32_div_s"

///|
extern "C" fn i32_div_u() -> UInt64 = "i32_div_u"

///|
extern "C" fn i32_rem_s() -> UInt64 = "i32_rem_s"

///|
extern "C" fn i32_rem_u() -> UInt64 = "i32_rem_u"

///|
extern "C" fn i32_and() -> UInt64 = "i32_and"

///|
extern "C" fn i32_or() -> UInt64 = "i32_or"

///|
extern "C" fn i32_xor() -> UInt64 = "i32_xor"

///|
extern "C" fn i32_shl() -> UInt64 = "i32_shl"

///|
extern "C" fn i32_shr_s() -> UInt64 = "i32_shr_s"

///|
extern "C" fn i32_shr_u() -> UInt64 = "i32_shr_u"

///|
extern "C" fn i32_rotl() -> UInt64 = "i32_rotl"

///|
extern "C" fn i32_rotr() -> UInt64 = "i32_rotr"

// i32 comparison

///|
extern "C" fn i32_eqz() -> UInt64 = "i32_eqz"

///|
extern "C" fn i32_eq() -> UInt64 = "i32_eq"

///|
extern "C" fn i32_ne() -> UInt64 = "i32_ne"

///|
extern "C" fn i32_lt_s() -> UInt64 = "i32_lt_s"

///|
extern "C" fn i32_lt_u() -> UInt64 = "i32_lt_u"

///|
extern "C" fn i32_gt_s() -> UInt64 = "i32_gt_s"

///|
extern "C" fn i32_gt_u() -> UInt64 = "i32_gt_u"

///|
extern "C" fn i32_le_s() -> UInt64 = "i32_le_s"

///|
extern "C" fn i32_le_u() -> UInt64 = "i32_le_u"

///|
extern "C" fn i32_ge_s() -> UInt64 = "i32_ge_s"

///|
extern "C" fn i32_ge_u() -> UInt64 = "i32_ge_u"

// i32 unary

///|
extern "C" fn i32_clz() -> UInt64 = "i32_clz"

///|
extern "C" fn i32_ctz() -> UInt64 = "i32_ctz"

///|
extern "C" fn i32_popcnt() -> UInt64 = "i32_popcnt"
