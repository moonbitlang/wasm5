///|
/// Group failures by test type for better reporting
fn group_failures_by_type(
  failures : Array[TestFailure],
) -> Map[String, Array[TestFailure]] {
  let grouped : Map[String, Array[TestFailure]] = {}
  for failure in failures {
    match grouped.get(failure.test_type) {
      Some(arr) => arr.push(failure)
      None => grouped[failure.test_type] = [failure]
    }
  }
  grouped
}

///|
/// Format a single failure with additional context
fn format_failure_detail(failure : TestFailure) -> String {
  let location = if failure.line >= 0 {
    "\{failure.source_file}:\{failure.line}"
  } else {
    failure.source_file
  }
  "  [\{failure.test_type}] \{location}\n    → \{failure.message}"
}

///|
async fn run_test_harness(
  subdir : String,
  filename : String,
  runtime_type? : RuntimeType = MoonBit,
) -> Unit {
  let path = "test/reference_tests/\{subdir}"
  let runtime_suffix = match runtime_type {
    MoonBit => ""
    CRuntime => " (cruntime)"
  }
  let display_name = if subdir.length() > 0 {
    "\{subdir}\{filename}\{runtime_suffix}"
  } else {
    "\{filename}\{runtime_suffix}"
  }
  let (file_failures, file_skipped) = process_wast_file(
    path,
    filename,
    runtime_type~,
  )
  if file_failures.length() > 0 {
    let grouped = group_failures_by_type(file_failures)
    println(
      "\n╔══════════════════════════════════════════════════════════════════╗",
    )
    println("║ TEST FAILURES: \{display_name}")
    println(
      "╚══════════════════════════════════════════════════════════════════╝",
    )
    for test_type, failures in grouped {
      println(
        "\n┌─ \{test_type} (\{failures.length()} failures) ─────────────────────",
      )
      for failure in failures {
        println(format_failure_detail(failure))
      }
      println(
        "└────────────────────────────────────────────────────────────────",
      )
    }
    println(
      "\n╔══════════════════════════════════════════════════════════════════╗",
    )
    println(
      "║ SUMMARY: \{file_failures.length()} failure(s), \{file_skipped} skipped",
    )
    println(
      "╚══════════════════════════════════════════════════════════════════╝\n",
    )
    fail("\{file_failures.length()} failure(s) in \{display_name}")
  }
  if file_skipped > 0 {
    println("Skipped \{file_skipped} tests in \{display_name}")
  }
}

// =============================================================================
// WebAssembly Spec Tests
// =============================================================================

///|
async test "address.wast" {
  run_test_harness("", "address.wast")
}

///|
async test "align.wast" {
  run_test_harness("", "align.wast")
}

// Blacklisted: WAT text format test
// async test "annotations.wast" {
//   run_test_harness("","annotations.wast")
// }

///|
async test "binary-leb128.wast" {
  run_test_harness("", "binary-leb128.wast")
}

///|
async test "binary.wast" {
  run_test_harness("", "binary.wast")
}

///|
async test "block.wast" {
  run_test_harness("", "block.wast")
}

///|
async test "br.wast" {
  run_test_harness("", "br.wast")
}

///|
async test "br_if.wast" {
  run_test_harness("", "br_if.wast")
}

///|
async test "br_on_non_null.wast" {
  run_test_harness("", "br_on_non_null.wast")
}

///|
async test "br_on_null.wast" {
  run_test_harness("", "br_on_null.wast")
}

///|
async test "br_table.wast" {
  run_test_harness("", "br_table.wast")
}

///|
async test "call.wast" {
  run_test_harness("", "call.wast")
}

///|
async test "call_indirect.wast" {
  run_test_harness("", "call_indirect.wast")
}

///|
async test "call_ref.wast" {
  run_test_harness("", "call_ref.wast")
}

// Blacklisted: WAT text format test
// async test "comments.wast" {
//   run_test_harness("","comments.wast")
// }

///|
async test "const.wast" {
  run_test_harness("", "const.wast")
}

///|
async test "conversions.wast" {
  run_test_harness("", "conversions.wast")
}

///|
async test "custom.wast" {
  run_test_harness("", "custom.wast")
}

///|
async test "data.wast" {
  run_test_harness("", "data.wast")
}

///|
async test "elem.wast" {
  run_test_harness("", "elem.wast")
}

///|
async test "endianness.wast" {
  run_test_harness("", "endianness.wast")
}

///|
async test "exports.wast" {
  run_test_harness("", "exports.wast")
}

///|
async test "f32.wast" {
  run_test_harness("", "f32.wast")
}

///|
async test "f32_bitwise.wast" {
  run_test_harness("", "f32_bitwise.wast")
}

///|
async test "f32_cmp.wast" {
  run_test_harness("", "f32_cmp.wast")
}

///|
async test "f64.wast" {
  run_test_harness("", "f64.wast")
}

///|
async test "f64_bitwise.wast" {
  run_test_harness("", "f64_bitwise.wast")
}

///|
async test "f64_cmp.wast" {
  run_test_harness("", "f64_cmp.wast")
}

///|
async test "fac.wast" {
  run_test_harness("", "fac.wast")
}

///|
async test "float_exprs.wast" {
  run_test_harness("", "float_exprs.wast")
}

///|
async test "float_literals.wast" {
  run_test_harness("", "float_literals.wast")
}

///|
async test "float_memory.wast" {
  run_test_harness("", "float_memory.wast")
}

///|
async test "float_misc.wast" {
  run_test_harness("", "float_misc.wast")
}

///|
async test "forward.wast" {
  run_test_harness("", "forward.wast")
}

///|
async test "func.wast" {
  run_test_harness("", "func.wast")
}

///|
async test "func_ptrs.wast" {
  run_test_harness("", "func_ptrs.wast")
}

///|
async test "global.wast" {
  run_test_harness("", "global.wast")
}

///|
async test "i32.wast" {
  run_test_harness("", "i32.wast")
}

///|
async test "i64.wast" {
  run_test_harness("", "i64.wast")
}

///|
async test "id.wast" {
  run_test_harness("", "id.wast")
}

///|
async test "if.wast" {
  run_test_harness("", "if.wast")
}

///|
async test "imports.wast" {
  run_test_harness("", "imports.wast")
}

///|
async test "inline-module.wast" {
  run_test_harness("", "inline-module.wast")
}

// Blacklisted: Requires module instances (linking)
// async test "instance.wast" {
//   run_test_harness("","instance.wast")
// }

///|
async test "int_exprs.wast" {
  run_test_harness("", "int_exprs.wast")
}

///|
async test "int_literals.wast" {
  run_test_harness("", "int_literals.wast")
}

///|
async test "labels.wast" {
  run_test_harness("", "labels.wast")
}

///|
async test "left-to-right.wast" {
  run_test_harness("", "left-to-right.wast")
}

// Blacklisted: Requires cross-module imports/exports
// async test "linking.wast" {
//   run_test_harness("","linking.wast")
// }

///|
async test "load.wast" {
  run_test_harness("", "load.wast")
}

///|
async test "local_get.wast" {
  run_test_harness("", "local_get.wast")
}

///|
async test "local_init.wast" {
  run_test_harness("", "local_init.wast")
}

///|
async test "local_set.wast" {
  run_test_harness("", "local_set.wast")
}

///|
async test "local_tee.wast" {
  run_test_harness("", "local_tee.wast")
}

///|
async test "loop.wast" {
  run_test_harness("", "loop.wast")
}

///|
async test "memory.wast" {
  run_test_harness("", "memory.wast")
}

///|
async test "memory_grow.wast" {
  run_test_harness("", "memory_grow.wast")
}

///|
async test "memory_redundancy.wast" {
  run_test_harness("", "memory_redundancy.wast")
}

///|
async test "memory_size.wast" {
  run_test_harness("", "memory_size.wast")
}

///|
async test "memory_trap.wast" {
  run_test_harness("", "memory_trap.wast")
}

///|
async test "names.wast" {
  run_test_harness("", "names.wast")
}

///|
async test "nop.wast" {
  run_test_harness("", "nop.wast")
}

///|
async test "obsolete-keywords.wast" {
  run_test_harness("", "obsolete-keywords.wast")
}

///|
async test "ref.wast" {
  run_test_harness("", "ref.wast")
}

///|
async test "ref_as_non_null.wast" {
  run_test_harness("", "ref_as_non_null.wast")
}

///|
async test "ref_func.wast" {
  run_test_harness("", "ref_func.wast")
}

///|
async test "ref_is_null.wast" {
  run_test_harness("", "ref_is_null.wast")
}

///|
async test "ref_null.wast" {
  run_test_harness("", "ref_null.wast")
}

///|
async test "return.wast" {
  run_test_harness("", "return.wast")
}

///|
async test "return_call.wast" {
  run_test_harness("", "return_call.wast")
}

///|
async test "return_call_indirect.wast" {
  run_test_harness("", "return_call_indirect.wast")
}

///|
async test "return_call_ref.wast" {
  run_test_harness("", "return_call_ref.wast")
}

///|
async test "select.wast" {
  run_test_harness("", "select.wast")
}

///|
async test "skip-stack-guard-page.wast" {
  run_test_harness("", "skip-stack-guard-page.wast")
}

///|
async test "stack.wast" {
  run_test_harness("", "stack.wast")
}

///|
async test "start.wast" {
  run_test_harness("", "start.wast")
}

///|
async test "store.wast" {
  run_test_harness("", "store.wast")
}

///|
async test "switch.wast" {
  run_test_harness("", "switch.wast")
}

///|
async test "table.wast" {
  run_test_harness("", "table.wast")
}

///|
async test "table_get.wast" {
  run_test_harness("", "table_get.wast")
}

///|
async test "table_grow.wast" {
  run_test_harness("", "table_grow.wast")
}

///|
async test "table_set.wast" {
  run_test_harness("", "table_set.wast")
}

///|
async test "table_size.wast" {
  run_test_harness("", "table_size.wast")
}

///|
async test "token.wast" {
  run_test_harness("", "token.wast")
}

///|
async test "traps.wast" {
  run_test_harness("", "traps.wast")
}

// Blacklisted: Requires exception handling
// async test "try_table.wast" {
//   run_test_harness("","try_table.wast")
// }

///|
async test "type-canon.wast" {
  run_test_harness("", "type-canon.wast")
}

///|
async test "type-equivalence.wast" {
  run_test_harness("", "type-equivalence.wast")
}

///|
async test "type-rec.wast" {
  run_test_harness("", "type-rec.wast")
}

///|
async test "type.wast" {
  run_test_harness("", "type.wast")
}

///|
async test "unreachable.wast" {
  run_test_harness("", "unreachable.wast")
}

///|
async test "unreached-invalid.wast" {
  run_test_harness("", "unreached-invalid.wast")
}

///|
async test "unreached-valid.wast" {
  run_test_harness("", "unreached-valid.wast")
}

///|
async test "unwind.wast" {
  run_test_harness("", "unwind.wast")
}

///|
async test "utf8-custom-section-id.wast" {
  run_test_harness("", "utf8-custom-section-id.wast")
}

///|
async test "utf8-import-field.wast" {
  run_test_harness("", "utf8-import-field.wast")
}

///|
async test "utf8-import-module.wast" {
  run_test_harness("", "utf8-import-module.wast")
}

///|
async test "utf8-invalid-encoding.wast" {
  run_test_harness("", "utf8-invalid-encoding.wast")
}

// =============================================================================
// WebAssembly GC Spec Tests
// =============================================================================

///|
async test "gc/array.wast" {
  run_test_harness("gc/", "array.wast")
}

///|
async test "gc/array_copy.wast" {
  run_test_harness("gc/", "array_copy.wast")
}

///|
async test "gc/array_fill.wast" {
  run_test_harness("gc/", "array_fill.wast")
}

///|
async test "gc/array_init_data.wast" {
  run_test_harness("gc/", "array_init_data.wast")
}

///|
async test "gc/array_init_elem.wast" {
  run_test_harness("gc/", "array_init_elem.wast")
}

///|
async test "gc/array_new_data.wast" {
  run_test_harness("gc/", "array_new_data.wast")
}

///|
async test "gc/array_new_elem.wast" {
  run_test_harness("gc/", "array_new_elem.wast")
}

///|
async test "gc/binary-gc.wast" {
  run_test_harness("gc/", "binary-gc.wast")
}

///|
async test "gc/br_on_cast.wast" {
  run_test_harness("gc/", "br_on_cast.wast")
}

///|
async test "gc/br_on_cast_fail.wast" {
  run_test_harness("gc/", "br_on_cast_fail.wast")
}

///|
async test "gc/extern.wast" {
  run_test_harness("gc/", "extern.wast")
}

///|
async test "gc/i31.wast" {
  run_test_harness("gc/", "i31.wast")
}

///|
async test "gc/ref_cast.wast" {
  run_test_harness("gc/", "ref_cast.wast")
}

///|
async test "gc/ref_eq.wast" {
  run_test_harness("gc/", "ref_eq.wast")
}

///|
async test "gc/ref_test.wast" {
  run_test_harness("gc/", "ref_test.wast")
}

///|
async test "gc/struct.wast" {
  run_test_harness("gc/", "struct.wast")
}

///|
async test "gc/type-subtyping.wast" {
  run_test_harness("gc/", "type-subtyping.wast")
}

// =============================================================================
// WebAssembly Bulk Memory Spec Tests
// =============================================================================

///|
async test "bulk-memory/bulk.wast" {
  run_test_harness("bulk-memory/", "bulk.wast")
}

///|
async test "bulk-memory/memory_copy.wast" {
  run_test_harness("bulk-memory/", "memory_copy.wast")
}

///|
async test "bulk-memory/memory_fill.wast" {
  run_test_harness("bulk-memory/", "memory_fill.wast")
}

///|
async test "bulk-memory/memory_init.wast" {
  run_test_harness("bulk-memory/", "memory_init.wast")
}

///|
async test "bulk-memory/table-sub.wast" {
  run_test_harness("bulk-memory/", "table-sub.wast")
}

///|
async test "bulk-memory/table_copy.wast" {
  run_test_harness("bulk-memory/", "table_copy.wast")
}

///|
async test "bulk-memory/table_fill.wast" {
  run_test_harness("bulk-memory/", "table_fill.wast")
}

///|
async test "bulk-memory/table_init.wast" {
  run_test_harness("bulk-memory/", "table_init.wast")
}

// =============================================================================
// C Runtime Tests
// =============================================================================

///|
async test "i32.wast (cruntime)" {
  run_test_harness("", "i32.wast", runtime_type=CRuntime)
}

// Temporarily disabled - debugging crash

///|
async test "call.wast (cruntime)" {
  run_test_harness("", "call.wast", runtime_type=CRuntime)
}

///|
async test "i64.wast (cruntime)" {
  run_test_harness("", "i64.wast", runtime_type=CRuntime)
}

///|
async test "f32_cmp.wast (cruntime)" {
  run_test_harness("", "f32_cmp.wast", runtime_type=CRuntime)
}

///|
async test "f64_cmp.wast (cruntime)" {
  run_test_harness("", "f64_cmp.wast", runtime_type=CRuntime)
}

///|
async test "f32_bitwise.wast (cruntime)" {
  run_test_harness("", "f32_bitwise.wast", runtime_type=CRuntime)
}

///|
async test "f64_bitwise.wast (cruntime)" {
  run_test_harness("", "f64_bitwise.wast", runtime_type=CRuntime)
}

///|
async test "nop.wast (cruntime)" {
  run_test_harness("", "nop.wast", runtime_type=CRuntime)
}

///|
async test "local_get.wast (cruntime)" {
  run_test_harness("", "local_get.wast", runtime_type=CRuntime)
}

///|
async test "local_set.wast (cruntime)" {
  run_test_harness("", "local_set.wast", runtime_type=CRuntime)
}

///|
async test "local_tee.wast (cruntime)" {
  run_test_harness("", "local_tee.wast", runtime_type=CRuntime)
}

///|
async test "return.wast (cruntime)" {
  run_test_harness("", "return.wast", runtime_type=CRuntime)
}

///|
async test "stack.wast (cruntime)" {
  run_test_harness("", "stack.wast", runtime_type=CRuntime)
}

///|
async test "forward.wast (cruntime)" {
  run_test_harness("", "forward.wast", runtime_type=CRuntime)
}

///|
async test "unreachable.wast (cruntime)" {
  run_test_harness("", "unreachable.wast", runtime_type=CRuntime)
}

///|
async test "type.wast (cruntime)" {
  run_test_harness("", "type.wast", runtime_type=CRuntime)
}

///|
async test "int_exprs.wast (cruntime)" {
  run_test_harness("", "int_exprs.wast", runtime_type=CRuntime)
}

///|
async test "int_literals.wast (cruntime)" {
  run_test_harness("", "int_literals.wast", runtime_type=CRuntime)
}

///|
async test "float_literals.wast (cruntime)" {
  run_test_harness("", "float_literals.wast", runtime_type=CRuntime)
}

///|
async test "float_misc.wast (cruntime)" {
  run_test_harness("", "float_misc.wast", runtime_type=CRuntime)
}

///|
async test "const.wast (cruntime)" {
  run_test_harness("", "const.wast", runtime_type=CRuntime)
}

///|
async test "skip-stack-guard-page.wast (cruntime)" {
  run_test_harness("", "skip-stack-guard-page.wast", runtime_type=CRuntime)
}

///|
async test "loop.wast (cruntime)" {
  run_test_harness("", "loop.wast", runtime_type=CRuntime)
}

///|
async test "select.wast (cruntime)" {
  run_test_harness("", "select.wast", runtime_type=CRuntime)
}

///|
async test "block.wast (cruntime)" {
  run_test_harness("", "block.wast", runtime_type=CRuntime)
}

///|
async test "br.wast (cruntime)" {
  run_test_harness("", "br.wast", runtime_type=CRuntime)
}

///|
async test "br_if.wast (cruntime)" {
  run_test_harness("", "br_if.wast", runtime_type=CRuntime)
}

///|
async test "if.wast (cruntime)" {
  run_test_harness("", "if.wast", runtime_type=CRuntime)
}

///|
async test "br_table.wast (cruntime)" {
  run_test_harness("", "br_table.wast", runtime_type=CRuntime)
}

///|
async test "fac.wast (cruntime)" {
  run_test_harness("", "fac.wast", runtime_type=CRuntime)
}

///|
async test "switch.wast (cruntime)" {
  run_test_harness("", "switch.wast", runtime_type=CRuntime)
}

///|
async test "unwind.wast (cruntime)" {
  run_test_harness("", "unwind.wast", runtime_type=CRuntime)
}

///|
async test "labels.wast (cruntime)" {
  run_test_harness("", "labels.wast", runtime_type=CRuntime)
}

///|
async test "traps.wast (cruntime)" {
  run_test_harness("", "traps.wast", runtime_type=CRuntime)
}

///|
async test "load.wast (cruntime)" {
  run_test_harness("", "load.wast", runtime_type=CRuntime)
}

///|
async test "store.wast (cruntime)" {
  run_test_harness("", "store.wast", runtime_type=CRuntime)
}
