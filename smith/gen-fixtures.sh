#!/usr/bin/env bash
set -euo pipefail

out_dir="$(cd "$(dirname "$0")" && pwd)"

smith_args=(
  --bulk-memory-enabled true
  --reference-types-enabled true
  --tail-call-enabled true
  --sign-extension-ops-enabled true
  --saturating-float-to-int-enabled true
  --multi-value-enabled true
  --exceptions-enabled false
  --gc-enabled false
  --simd-enabled false
  --relaxed-simd-enabled false
  --threads-enabled false
  --shared-everything-threads-enabled false
  --memory64-enabled false
  --wide-arithmetic-enabled false
  --extended-const-enabled false
)

fixtures=(
  "validate_smith_alpha:alpha:128"
  "validate_smith_bravo:bravo:192"
  "validate_smith_charlie:charlie:256"
  "validate_smith_delta:delta:320"
  "validate_smith_echo:echo:384"
  "validate_smith_foxtrot:foxtrot:448"
  "validate_smith_golf:golf:512"
  "validate_smith_hotel:hotel:640"
  "validate_smith_india:india:768"
  "validate_smith_juliet:juliet:896"
  "validate_smith_kilo:kilo:1024"
  "validate_smith_lima:lima:1152"
)

for entry in "${fixtures[@]}"; do
  IFS=":" read -r name pattern size <<< "$entry"
  awk -v p="$pattern" -v n="$size" 'BEGIN {
    out = ""
    while (length(out) < n) out = out p
    printf "%s", substr(out, 1, n)
  }' | wasm-tools smith "${smith_args[@]}" -o "$out_dir/${name}.wasm"
  echo "wrote ${name}.wasm"
done

cat <<'WAT' | wasm-tools parse -o "$out_dir/simple_add.wasm"
(module
  (func $add (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add)
  (export "add" (func $add)))
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/memory_hello.wasm"
(module
  (memory (export "mem") 1)
  (data (i32.const 0) "hello")
  (func (export "len") (result i32)
    i32.const 5))
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/global_counter.wasm"
(module
  (global $g (export "g") (mut i32) (i32.const 7))
  (func (export "inc") (result i32)
    global.get $g
    i32.const 1
    i32.add
    global.set $g
    global.get $g))
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_numeric.wasm"
(module
  (func $numeric
    i32.const 0
    i32.eqz
    drop
    i32.const 0
    i32.clz
    drop
    i32.const 0
    i32.ctz
    drop
    i32.const 0
    i32.popcnt
    drop
    i32.const 0
    i32.const 1
    i32.eq
    drop
    i32.const 0
    i32.const 1
    i32.ne
    drop
    i32.const 0
    i32.const 1
    i32.lt_s
    drop
    i32.const 0
    i32.const 1
    i32.lt_u
    drop
    i32.const 0
    i32.const 1
    i32.gt_s
    drop
    i32.const 0
    i32.const 1
    i32.gt_u
    drop
    i32.const 0
    i32.const 1
    i32.le_s
    drop
    i32.const 0
    i32.const 1
    i32.le_u
    drop
    i32.const 0
    i32.const 1
    i32.ge_s
    drop
    i32.const 0
    i32.const 1
    i32.ge_u
    drop
    i32.const 0
    i32.const 1
    i32.add
    drop
    i32.const 0
    i32.const 1
    i32.sub
    drop
    i32.const 0
    i32.const 1
    i32.mul
    drop
    i32.const 0
    i32.const 1
    i32.div_s
    drop
    i32.const 0
    i32.const 1
    i32.div_u
    drop
    i32.const 0
    i32.const 1
    i32.rem_s
    drop
    i32.const 0
    i32.const 1
    i32.rem_u
    drop
    i32.const 0
    i32.const 1
    i32.and
    drop
    i32.const 0
    i32.const 1
    i32.or
    drop
    i32.const 0
    i32.const 1
    i32.xor
    drop
    i32.const 0
    i32.const 1
    i32.shl
    drop
    i32.const 0
    i32.const 1
    i32.shr_s
    drop
    i32.const 0
    i32.const 1
    i32.shr_u
    drop
    i32.const 0
    i32.const 1
    i32.rotl
    drop
    i32.const 0
    i32.const 1
    i32.rotr
    drop

    i64.const 0
    i64.eqz
    drop
    i64.const 0
    i64.clz
    drop
    i64.const 0
    i64.ctz
    drop
    i64.const 0
    i64.popcnt
    drop
    i64.const 0
    i64.const 1
    i64.eq
    drop
    i64.const 0
    i64.const 1
    i64.ne
    drop
    i64.const 0
    i64.const 1
    i64.lt_s
    drop
    i64.const 0
    i64.const 1
    i64.lt_u
    drop
    i64.const 0
    i64.const 1
    i64.gt_s
    drop
    i64.const 0
    i64.const 1
    i64.gt_u
    drop
    i64.const 0
    i64.const 1
    i64.le_s
    drop
    i64.const 0
    i64.const 1
    i64.le_u
    drop
    i64.const 0
    i64.const 1
    i64.ge_s
    drop
    i64.const 0
    i64.const 1
    i64.ge_u
    drop
    i64.const 0
    i64.const 1
    i64.add
    drop
    i64.const 0
    i64.const 1
    i64.sub
    drop
    i64.const 0
    i64.const 1
    i64.mul
    drop
    i64.const 0
    i64.const 1
    i64.div_s
    drop
    i64.const 0
    i64.const 1
    i64.div_u
    drop
    i64.const 0
    i64.const 1
    i64.rem_s
    drop
    i64.const 0
    i64.const 1
    i64.rem_u
    drop
    i64.const 0
    i64.const 1
    i64.and
    drop
    i64.const 0
    i64.const 1
    i64.or
    drop
    i64.const 0
    i64.const 1
    i64.xor
    drop
    i64.const 0
    i64.const 1
    i64.shl
    drop
    i64.const 0
    i64.const 1
    i64.shr_s
    drop
    i64.const 0
    i64.const 1
    i64.shr_u
    drop
    i64.const 0
    i64.const 1
    i64.rotl
    drop
    i64.const 0
    i64.const 1
    i64.rotr
    drop

    f32.const 0
    f32.const 1
    f32.eq
    drop
    f32.const 0
    f32.const 1
    f32.ne
    drop
    f32.const 0
    f32.const 1
    f32.lt
    drop
    f32.const 0
    f32.const 1
    f32.gt
    drop
    f32.const 0
    f32.const 1
    f32.le
    drop
    f32.const 0
    f32.const 1
    f32.ge
    drop
    f32.const 0
    f32.abs
    drop
    f32.const 0
    f32.neg
    drop
    f32.const 0
    f32.ceil
    drop
    f32.const 0
    f32.floor
    drop
    f32.const 0
    f32.trunc
    drop
    f32.const 0
    f32.nearest
    drop
    f32.const 0
    f32.sqrt
    drop
    f32.const 0
    f32.const 1
    f32.add
    drop
    f32.const 0
    f32.const 1
    f32.sub
    drop
    f32.const 0
    f32.const 1
    f32.mul
    drop
    f32.const 0
    f32.const 1
    f32.div
    drop
    f32.const 0
    f32.const 1
    f32.min
    drop
    f32.const 0
    f32.const 1
    f32.max
    drop
    f32.const 0
    f32.const 1
    f32.copysign
    drop

    f64.const 0
    f64.const 1
    f64.eq
    drop
    f64.const 0
    f64.const 1
    f64.ne
    drop
    f64.const 0
    f64.const 1
    f64.lt
    drop
    f64.const 0
    f64.const 1
    f64.gt
    drop
    f64.const 0
    f64.const 1
    f64.le
    drop
    f64.const 0
    f64.const 1
    f64.ge
    drop
    f64.const 0
    f64.abs
    drop
    f64.const 0
    f64.neg
    drop
    f64.const 0
    f64.ceil
    drop
    f64.const 0
    f64.floor
    drop
    f64.const 0
    f64.trunc
    drop
    f64.const 0
    f64.nearest
    drop
    f64.const 0
    f64.sqrt
    drop
    f64.const 0
    f64.const 1
    f64.add
    drop
    f64.const 0
    f64.const 1
    f64.sub
    drop
    f64.const 0
    f64.const 1
    f64.mul
    drop
    f64.const 0
    f64.const 1
    f64.div
    drop
    f64.const 0
    f64.const 1
    f64.min
    drop
    f64.const 0
    f64.const 1
    f64.max
    drop
    f64.const 0
    f64.const 1
    f64.copysign
    drop

    i64.const 0
    i32.wrap_i64
    drop
    f32.const 0
    i32.trunc_f32_s
    drop
    f32.const 0
    i32.trunc_f32_u
    drop
    f64.const 0
    i32.trunc_f64_s
    drop
    f64.const 0
    i32.trunc_f64_u
    drop
    i32.const 0
    i64.extend_i32_s
    drop
    i32.const 0
    i64.extend_i32_u
    drop
    f32.const 0
    i64.trunc_f32_s
    drop
    f32.const 0
    i64.trunc_f32_u
    drop
    f64.const 0
    i64.trunc_f64_s
    drop
    f64.const 0
    i64.trunc_f64_u
    drop
    i32.const 0
    f32.convert_i32_s
    drop
    i32.const 0
    f32.convert_i32_u
    drop
    i64.const 0
    f32.convert_i64_s
    drop
    i64.const 0
    f32.convert_i64_u
    drop
    f64.const 0
    f32.demote_f64
    drop
    i32.const 0
    f64.convert_i32_s
    drop
    i32.const 0
    f64.convert_i32_u
    drop
    i64.const 0
    f64.convert_i64_s
    drop
    i64.const 0
    f64.convert_i64_u
    drop
    f32.const 0
    f64.promote_f32
    drop
    f32.const 0
    i32.reinterpret_f32
    drop
    f64.const 0
    i64.reinterpret_f64
    drop
    i32.const 0
    f32.reinterpret_i32
    drop
    i64.const 0
    f64.reinterpret_i64
    drop

    i32.const 0
    i32.extend8_s
    drop
    i32.const 0
    i32.extend16_s
    drop
    i64.const 0
    i64.extend8_s
    drop
    i64.const 0
    i64.extend16_s
    drop
    i64.const 0
    i64.extend32_s
    drop

    f32.const 0
    i32.trunc_sat_f32_s
    drop
    f32.const 0
    i32.trunc_sat_f32_u
    drop
    f64.const 0
    i32.trunc_sat_f64_s
    drop
    f64.const 0
    i32.trunc_sat_f64_u
    drop
    f32.const 0
    i64.trunc_sat_f32_s
    drop
    f32.const 0
    i64.trunc_sat_f32_u
    drop
    f64.const 0
    i64.trunc_sat_f64_s
    drop
    f64.const 0
    i64.trunc_sat_f64_u
    drop

    i32.const 1
    i32.const 2
    i32.const 1
    select
    drop
    i32.const 1
    i32.const 2
    i32.const 1
    select (result i32)
    drop)
)
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_memory.wasm"
(module
  (memory 1)
  (data (i32.const 0) "abcdef")
  (func $mem
    i32.const 0
    i32.load offset=0 align=2
    drop
    i32.const 0
    i64.load offset=0 align=4
    drop
    i32.const 0
    f32.load offset=0 align=2
    drop
    i32.const 0
    f64.load offset=0 align=4
    drop
    i32.const 0
    i32.load8_s
    drop
    i32.const 0
    i32.load8_u
    drop
    i32.const 0
    i32.load16_s
    drop
    i32.const 0
    i32.load16_u
    drop
    i32.const 0
    i64.load8_s
    drop
    i32.const 0
    i64.load8_u
    drop
    i32.const 0
    i64.load16_s
    drop
    i32.const 0
    i64.load16_u
    drop
    i32.const 0
    i64.load32_s
    drop
    i32.const 0
    i64.load32_u
    drop
    i32.const 0
    i32.const 0
    i32.store
    i32.const 0
    i64.const 0
    i64.store
    i32.const 0
    f32.const 0
    f32.store
    i32.const 0
    f64.const 0
    f64.store
    i32.const 0
    i32.const 0
    i32.store8
    i32.const 0
    i32.const 0
    i32.store16
    i32.const 0
    i64.const 0
    i64.store8
    i32.const 0
    i64.const 0
    i64.store16
    i32.const 0
    i64.const 0
    i64.store32
    memory.size
    drop
    i32.const 0
    memory.grow
    drop
    i32.const 0
    i32.const 0
    i32.const 1
    memory.init 0
    data.drop 0
    i32.const 0
    i32.const 0
    i32.const 1
    memory.copy
    i32.const 0
    i32.const 0
    i32.const 1
    memory.fill)
)
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_table.wasm"
(module
  (type $t0 (func))
  (func $f0 (type $t0))
  (func $f1 (type $t0))
  (table 2 funcref (ref.null func))
  (elem (i32.const 0) $f0 $f1)
  (elem (i32.const 0) funcref (ref.func $f1))
  (elem (ref.func $f1))
  (func $table_ops
    i32.const 0
    table.get 0
    drop
    i32.const 0
    ref.null func
    table.set 0
    table.size 0
    drop
    ref.null func
    i32.const 1
    table.grow 0
    drop
    i32.const 0
    i32.const 0
    i32.const 1
    table.copy 0 0
    i32.const 0
    i32.const 0
    i32.const 1
    table.init 0 0
    elem.drop 0)
)
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_control.wasm"
(module
  (type $t0 (func (param i32) (result i32)))
  (type $t1 (func))
  (func $id (type $t0) (param i32) (result i32)
    local.get 0)
  (table 1 funcref)
  (elem (i32.const 0) $id)
  (func $control (type $t1) (local i32 i32)
    nop
    i32.const 7
    local.set 0
    i32.const 8
    local.tee 1
    drop
    block (result i32)
      i32.const 1
    end
    drop
    block
      loop
        br 1
      end
    end
    block
      i32.const 0
      br_if 0
    end
    block
      i32.const 0
      br_table 0 0
    end
    block
      i32.const 0
      if
        nop
      else
        nop
      end
    end
    i32.const 0
    call $id
    drop
    i32.const 0
    i32.const 0
    call_indirect (type $t0)
    drop
    return)
  (func $tail_call (type $t0) (param i32) (result i32)
    local.get 0
    return_call $id)
  (func $tail_call_indirect (type $t0) (param i32) (result i32)
    local.get 0
    i32.const 0
    return_call_indirect (type $t0))
  (func $call_ref (type $t0) (param i32) (result i32)
    local.get 0
    ref.func $id
    call_ref $t0)
  (func $return_call_ref (type $t0) (param i32) (result i32)
    local.get 0
    ref.func $id
    return_call_ref $t0)
  (func $trap
    unreachable))
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_reference.wasm"
(module
  (type $t0 (func))
  (func $ref_ops
    ref.null func
    drop
    ref.null extern
    drop
    ref.null any
    drop
    ref.null eq
    drop
    ref.null i31
    drop
    ref.null struct
    drop
    ref.null array
    drop
    ref.null exn
    drop
    ref.null none
    drop
    ref.null noextern
    drop
    ref.null nofunc
    drop
    ref.null noexn
    drop
    ref.null $t0
    drop
    ref.null func
    ref.is_null
    drop
    ref.null func
    ref.as_non_null
    drop
    ref.null func
    ref.null func
    ref.eq
    drop
    drop
    ref.null func
    br_on_null 0
    drop
    ref.null func
    br_on_non_null 0
    ref.func $ref_ops
    drop))
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_valtypes.wasm"
(module
  (rec (type $arr (array (mut i32))))
  (type $t0 (func))
  (func $valtypes
    (param i32) (param i64) (param f32) (param f64) (param v128)
    (param funcref) (param externref) (param anyref) (param eqref)
    (param i31ref) (param structref) (param arrayref) (param exnref)
    (param nullref) (param nullexternref) (param nullfuncref) (param nullexnref)
    (param (ref null func)) (param (ref func))
    (param (ref null extern)) (param (ref extern))
    (param (ref null $t0)) (param (ref $t0))
    nop))
WAT

cat <<'WAT' | wasm-tools parse -o "$out_dir/coverage_import_export.wasm"
(module
  (type $t0 (func))
  (import "m" "f" (func (type $t0)))
  (import "m" "t" (table 1 funcref))
  (import "m" "m" (memory 1))
  (import "m" "g" (global i32))
  (import "m" "tag" (tag (param i32)))
  (func (type $t0))
  (export "f" (func 0))
  (export "t" (table 0))
  (export "m" (memory 0))
  (export "g" (global 0))
  (export "tag" (tag 0)))
WAT
