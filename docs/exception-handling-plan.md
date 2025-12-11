# Exception Handling Implementation Plan

A design for WebAssembly exception handling that works with the current fetch-execute loop architecture while preparing for future migration to wasm3-style tail-call threading.

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Architecture Overview](#2-architecture-overview)
3. [Compile-Time Design](#3-compile-time-design)
4. [Runtime Design](#4-runtime-design)
5. [Instruction Specifications](#5-instruction-specifications)
6. [Implementation Phases](#6-implementation-phases)
7. [Future Migration Path](#7-future-migration-path)
8. [Testing Strategy](#8-testing-strategy)

---

## 1. Design Philosophy

### Core Principle: Compile-Time Knowledge, Runtime Simplicity

Following wasm3's philosophy: **"Move complexity to compile time, make runtime trivial."**

Exception handling information is fully resolved during compilation:
- Handler targets are concrete PCs (not symbolic labels)
- Stack heights are pre-computed
- Type checking is complete before execution

At runtime, operations simply follow pre-computed paths.

### Preparing for Tail-Call Threading

When MoonBit supports tail-call optimization, we want to migrate to wasm3-style execution:

```
Current (fetch-execute loop):
┌─────────────────────────────────────┐
│  while true {                       │
│    match f(self) {                  │
│      Next => self.pc += 1           │
│      Jump(target) => self.pc = target│
│      ...                            │
│    }                                │
│  }                                  │
└─────────────────────────────────────┘

Future (tail-call threading):
┌─────────────────────────────────────┐
│  Each operation tail-calls next:    │
│                                     │
│  fn op_i32_add(rt, pc) {            │
│    // do work                       │
│    return nextOp(rt, pc + 1)  // TCO│
│  }                                  │
└─────────────────────────────────────┘
```

**Design Goal**: Structure compile-time artifacts identically to wasm3 so migration only affects runtime dispatch, not the compiled representation.

---

## 2. Architecture Overview

### System Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     WASM Binary                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      PARSING                                 │
│  • Parse tag section (exception signatures)                  │
│  • Parse try_table blocks with catch clauses                 │
│  • Build AST with TryTable, Throw, ThrowRef instructions    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    VALIDATION                                │
│  • Validate tag indices and types                           │
│  • Validate exception payload matches tag signature          │
│  • Validate catch clause targets and stack polymorphism      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    COMPILATION                               │
│  • Track exception scopes in CompileCtx                      │
│  • Compute handler PCs and stack restoration info            │
│  • Emit handler metadata inline with instructions            │
│  • Patch catch targets like branch targets                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     RUNTIME                                  │
│  Current: Explicit handler stack + direct manipulation       │
│  Future:  Implicit handlers via tail-call return values      │
└─────────────────────────────────────────────────────────────┘
```

### Key Insight: Handler Information Flow

```
Compile Time                          Runtime
────────────                          ───────

try_table with catch clauses          op_try_table_enter
         │                                   │
         ▼                                   ▼
┌─────────────────┐                  ┌─────────────────┐
│ Compute:        │                  │ Register:       │
│ • handler PCs   │  ───emit───▶     │ • handler PC    │
│ • stack heights │                  │ • stack height  │
│ • catch tags    │                  │ • call depth    │
└─────────────────┘                  └─────────────────┘
         │                                   │
         ▼                                   ▼
   (body instrs)                       (execute body)
         │                                   │
         ▼                                   ▼
┌─────────────────┐                  ┌─────────────────┐
│ Patch targets   │                  │ If throw:       │
│ like br targets │                  │ • find handler  │
└─────────────────┘                  │ • unwind stack  │
                                     │ • jump to PC    │
                                     └─────────────────┘
```

---

## 3. Compile-Time Design

### 3.1 Extended CompileBlock for Exception Scopes

Extend the existing `CompileBlock` structure to track exception handlers, mirroring wasm3's `M3CompilationScope`:

```moonbit
// src/compile.mbt

/// Catch clause compiled representation
struct CompiledCatchClause {
  kind : CatchKind           // catch, catch_ref, catch_all, catch_all_ref
  tag_idx : Int              // Tag index (-1 for catch_all variants)
  target_pc_slot : Int       // Slot in ops[] to patch with handler PC
  target_label : Int         // Original label index for patching
  pushes_exnref : Bool       // Whether to push exnref (for _ref variants)
}

enum CatchKind {
  Catch          // catch tag label - extracts payload
  CatchRef       // catch_ref tag label - extracts payload + exnref
  CatchAll       // catch_all label - no payload
  CatchAllRef    // catch_all_ref label - pushes exnref only
}

/// Extended block kind
enum CompileBlockKind {
  BlockKind      // br jumps to end, uses results
  LoopKind       // br jumps to start, uses params
  IfKind         // br jumps to end, uses results
  TryTableKind   // Like block, but with exception handlers
}

/// Extended compile block with exception support
struct CompileBlock {
  kind : CompileBlockKind
  params : Array[ValType]
  results : Array[ValType]
  stack_height_at_entry : Int
  target_pc : Int
  pending_br_patches : Array[Int]

  // NEW: Exception handling (only for TryTableKind)
  catch_clauses : Array[CompiledCatchClause]  // Handler metadata
  handler_base_slot : Int                      // Where handler info starts in ops[]
}
```

### 3.2 Compile Context Exception Tracking

```moonbit
// src/compile.mbt

struct CompileCtx {
  type_stack : Array[ValType]
  control_stack : Array[CompileBlock]

  // For validation during compilation
  module_tags : Array[TagType]  // Reference to module's tag section
}

/// Get the exception scope depth for a label
/// Used to determine how many exception scopes to exit on branch
fn CompileCtx::get_exception_scope_depth(self : CompileCtx, label : Int) -> Int {
  let target_idx = self.control_stack.length() - 1 - label
  let mut depth = 0
  for i = self.control_stack.length() - 1; i > target_idx; i = i - 1 {
    if self.control_stack[i].kind == TryTableKind {
      depth += 1
    }
  }
  depth
}
```

### 3.3 TryTable Compilation

The key compilation pattern - emit handler metadata inline, then patch targets:

```moonbit
// src/compile.mbt

TryTable(block_type, catch_clauses, instrs) => {
  let (params, results) = get_compile_block_type(self.module_, block_type)

  // Record where handler info will be emitted
  let handler_base = self.ops.length()

  // Emit: op_try_table_enter <num_handlers>
  self.emit(WasmInstr(op_try_table_enter))
  self.emit(ImmediateIdx(catch_clauses.length()))

  // Pre-compute compiled catch clauses
  let compiled_clauses : Array[CompiledCatchClause] = []

  for clause in catch_clauses {
    // Emit handler metadata inline (will be read by op_try_table_enter)
    // Format: <kind> <tag_idx> <handler_pc> <stack_restore_height>

    let kind = match clause {
      Catch(_, _) => CatchKind::Catch
      CatchRef(_, _) => CatchKind::CatchRef
      CatchAll(_) => CatchKind::CatchAll
      CatchAllRef(_) => CatchKind::CatchAllRef
    }

    let tag_idx = match clause {
      Catch(tag, _) | CatchRef(tag, _) => tag.reinterpret_as_int()
      CatchAll(_) | CatchAllRef(_) => -1
    }

    let target_label = match clause {
      Catch(_, label) | CatchRef(_, label) |
      CatchAll(label) | CatchAllRef(label) => label.reinterpret_as_int()
    }

    self.emit(ImmediateIdx(kind.to_int()))
    self.emit(ImmediateIdx(tag_idx))

    // Handler PC - placeholder, will be patched
    let target_pc_slot = self.ops.length()
    self.emit(ImmediateIdx(0))

    // Stack height to restore (computed from target block's entry height)
    // Will be filled during patching based on target block's stack_height_at_entry
    self.emit(ImmediateIdx(0))  // Placeholder for stack height

    compiled_clauses.push({
      kind,
      tag_idx,
      target_pc_slot,
      target_label,
      pushes_exnref: kind == CatchRef || kind == CatchAllRef,
    })
  }

  // Push control frame with exception info
  ctx.push_control_try_table(
    params,
    results,
    compiled_clauses,
    handler_base,
  )

  // Compile try body
  for instr in instrs {
    self.compile_wasm_instr(ctx, instr)
  }

  // Emit cleanup instruction
  self.emit(WasmInstr(op_try_table_exit))

  // End of try_table block
  let end_pc = self.ops.length()

  // Pop control frame and patch branches (same as regular block)
  let block = ctx.pop_control()
  for slot in block.pending_br_patches {
    self.ops[slot] = ImmediateIdx(end_pc)
  }

  // Patch catch clause targets
  for clause in block.catch_clauses {
    // Find target block and get its entry stack height
    let target_block = ctx.get_block_at_label(clause.target_label)
    let target_pc = if target_block.kind == LoopKind {
      target_block.target_pc  // Loop: jump to start
    } else {
      // Block/if: need to register for patching at target's end
      ctx.add_catch_patch(clause.target_label, clause.target_pc_slot)
      0  // Will be patched when target block ends
    }

    if target_pc != 0 {
      self.ops[clause.target_pc_slot] = ImmediateIdx(target_pc)
    }

    // Patch stack height (slot after target_pc_slot)
    self.ops[clause.target_pc_slot + 1] = ImmediateIdx(
      target_block.stack_height_at_entry
    )
  }

  // Reset type stack
  ctx.truncate_stack(block.stack_height_at_entry)
  ctx.push_types(block.results)
}
```

### 3.4 Throw Compilation

```moonbit
// src/compile.mbt

Throw(tag_idx) => {
  let tag = self.module_.tags[tag_idx.reinterpret_as_int()]
  let tag_type = self.module_.types[tag.type_idx]

  // Pop payload values from type stack
  for i = tag_type.params.length() - 1; i >= 0; i = i - 1 {
    ctx.pop_type()
  }

  // Emit throw instruction with tag index
  self.emit(WasmInstr(op_throw))
  self.emit(ImmediateIdx(tag_idx.reinterpret_as_int()))

  // Throw is a terminator - code after is unreachable
  // (handled by validation setting is_unreachable)
}

ThrowRef => {
  ctx.pop_type()  // Pop exnref
  self.emit(WasmInstr(op_throw_ref))
  // Also a terminator
}
```

### 3.5 Compiled Code Layout

The compiled instruction stream for a try_table:

```
Offset  Instruction/Data
──────  ────────────────
N+0     op_try_table_enter
N+1     <num_handlers>
N+2     <catch_kind_0>
N+3     <tag_idx_0>
N+4     <handler_pc_0>        ← Patched to actual PC
N+5     <stack_height_0>      ← Stack height to restore
N+6     <catch_kind_1>
N+7     <tag_idx_1>
N+8     <handler_pc_1>
N+9     <stack_height_1>
...
N+M     (first instruction of try body)
...
N+K     op_try_table_exit
N+K+1   (instructions after try_table)
```

This layout allows `op_try_table_enter` to read all handler metadata in a single forward scan, then register handlers before executing the body.

---

## 4. Runtime Design

### 4.1 Current Architecture (Fetch-Execute Loop)

For the current VM, we use explicit handler tracking:

```moonbit
// src/runtime.mbt

/// Exception handler registered at runtime
struct ExceptionHandler {
  tag_idx : Int           // -1 for catch_all
  handler_pc : Int        // Where to jump
  stack_height : Int      // Value stack height to restore
  call_depth : Int        // call_stack.length() when registered
  pushes_exnref : Bool    // Whether handler expects exnref on stack
}

/// Active exception being propagated
struct ActiveException {
  tag_idx : Int
  payload : Array[Value]
  exnref : Value          // The exception reference itself
}

/// Extended Runtime
struct Runtime {
  // ... existing fields ...

  // Exception handling state
  exception_handlers : Array[ExceptionHandler]
  active_exception : ActiveException?
}
```

### 4.2 Operation Implementations (Current)

```moonbit
// src/compile.mbt (operation functions)

///|
/// Enter a try_table block - register handlers
fn op_try_table_enter(rt : Runtime) -> ControlFlow {
  let num_handlers = rt.read_imm_idx()
  let current_call_depth = rt.call_stack.length()

  // Read and register each handler
  for _ in 0..<num_handlers {
    let kind = rt.read_imm_idx()
    let tag_idx = rt.read_imm_idx()
    let handler_pc = rt.read_imm_idx()
    let stack_height = rt.read_imm_idx()

    rt.exception_handlers.push({
      tag_idx,
      handler_pc,
      stack_height,
      call_depth: current_call_depth,
      pushes_exnref: kind == 1 || kind == 3,  // CatchRef or CatchAllRef
    })
  }

  Next
}

///|
/// Exit a try_table block normally - pop handlers
fn op_try_table_exit(rt : Runtime) -> ControlFlow {
  // Pop all handlers registered by this try_table
  // We need to track how many were registered - simplest: store count
  // Or: scan backwards to find handlers at current call_depth

  let current_depth = rt.call_stack.length()
  while rt.exception_handlers.length() > 0 {
    let handler = rt.exception_handlers[rt.exception_handlers.length() - 1]
    if handler.call_depth == current_depth {
      let _ = rt.exception_handlers.unsafe_pop()
    } else {
      break
    }
  }

  Next
}

///|
/// Throw an exception
fn op_throw(rt : Runtime) -> ControlFlow {
  let tag_idx = rt.read_imm_idx()

  // Get tag signature to know payload size
  let tag = rt.module_.tags[tag_idx]
  let tag_type = rt.module_.types[tag.type_idx]
  let num_payload = tag_type.params.length()

  // Collect payload from stack (in reverse order)
  let payload : Array[Value] = []
  for _ in 0..<num_payload {
    payload.push(rt.stack.unsafe_pop())
  }
  payload.reverse()

  // Create exception reference
  let exnref = Value::Exception({ tag_idx, payload: payload.copy() })

  // Find matching handler (search from most recent)
  for i = rt.exception_handlers.length() - 1; i >= 0; i = i - 1 {
    let handler = rt.exception_handlers[i]

    // Check if handler matches
    let matches = handler.tag_idx == -1 ||  // catch_all
                  handler.tag_idx == tag_idx

    if matches {
      // Unwind call stack to handler's depth
      while rt.call_stack.length() > handler.call_depth {
        let frame = rt.call_stack.unsafe_pop()
        rt.locals = frame.locals
      }

      // Restore value stack height
      while rt.stack.length() > handler.stack_height {
        let _ = rt.stack.unsafe_pop()
      }

      // Push payload values for catch block (if not catch_all)
      if handler.tag_idx != -1 {
        for val in payload {
          rt.stack.push(val)
        }
      }

      // Push exnref if handler expects it
      if handler.pushes_exnref {
        rt.stack.push(exnref)
      }

      // Remove this handler and all inner ones
      rt.exception_handlers.truncate(i)

      // Jump to handler
      return Jump(handler.handler_pc)
    }
  }

  // No handler found - uncaught exception
  Trap(RuntimeError::UncaughtException(tag_idx, payload))
}

///|
/// Throw from exception reference
fn op_throw_ref(rt : Runtime) -> ControlFlow {
  let exnref = rt.stack.unsafe_pop()

  guard exnref is Value::Exception(exc) else {
    return Trap(RuntimeError::InvalidExceptionRef)
  }

  // Re-throw using the stored tag and payload
  // (Similar to op_throw but uses exc.tag_idx and exc.payload)

  for i = rt.exception_handlers.length() - 1; i >= 0; i = i - 1 {
    let handler = rt.exception_handlers[i]

    if handler.tag_idx == -1 || handler.tag_idx == exc.tag_idx {
      // Same unwinding logic as op_throw...
      while rt.call_stack.length() > handler.call_depth {
        let frame = rt.call_stack.unsafe_pop()
        rt.locals = frame.locals
      }

      while rt.stack.length() > handler.stack_height {
        let _ = rt.stack.unsafe_pop()
      }

      if handler.tag_idx != -1 {
        for val in exc.payload {
          rt.stack.push(val)
        }
      }

      if handler.pushes_exnref {
        rt.stack.push(exnref)
      }

      rt.exception_handlers.truncate(i)
      return Jump(handler.handler_pc)
    }
  }

  Trap(RuntimeError::UncaughtException(exc.tag_idx, exc.payload))
}
```

### 4.3 Exception Value Representation

```moonbit
// src/types.mbt

/// Exception data stored in exception reference
struct ExceptionData {
  tag_idx : Int
  payload : Array[Value]
}

/// Extended Value enum
enum Value {
  I32(UInt)
  I64(UInt64)
  F32(Double)
  F64(Double)
  Ref(Int?)              // funcref/externref
  Exception(ExceptionData)  // NEW: exception reference
}
```

---

## 5. Instruction Specifications

### 5.1 New Instructions

| Instruction | Opcode | Operands | Stack Effect | Description |
|------------|--------|----------|--------------|-------------|
| `try_table` | 0x1F | blocktype, catch*, instr* | [t1*] → [t2*] | Try block with catch handlers |
| `throw` | 0x08 | tagidx | [t*] → [] | Throw exception with payload |
| `throw_ref` | 0x0A | - | [exnref] → [] | Re-throw from exception ref |

### 5.2 Catch Clause Kinds

| Kind | Code | Operands | Stack on Handler Entry |
|------|------|----------|----------------------|
| `catch` | 0x00 | tagidx, labelidx | [payload*] |
| `catch_ref` | 0x01 | tagidx, labelidx | [payload*, exnref] |
| `catch_all` | 0x02 | labelidx | [] |
| `catch_all_ref` | 0x03 | labelidx | [exnref] |

### 5.3 Tag Section

```
tagsec  ::= section_13(tag*)
tag     ::= 0x00 typeidx    // Exception tag with signature
```

Tags define exception signatures. The type must have empty results (exceptions don't return values, only carry payload).

---

## 6. Implementation Phases

### Phase 1: Data Structures (2-3 hours)

**Files**: `src/types.mbt`

- [ ] Add `TagType` struct
- [ ] Add `tags` field to `Module`
- [ ] Add `ExceptionData` struct
- [ ] Extend `Value` enum with `Exception` variant
- [ ] Add `TryTable`, `Throw`, `ThrowRef` to `Instr` enum
- [ ] Add `CatchClause` enum for parsed catch clauses

```moonbit
// src/types.mbt additions

struct TagType {
  type_idx : Int  // Index into types array
}

enum CatchClause {
  Catch(UInt, UInt)      // tag_idx, label_idx
  CatchRef(UInt, UInt)   // tag_idx, label_idx
  CatchAll(UInt)         // label_idx
  CatchAllRef(UInt)      // label_idx
}

enum Instr {
  // ... existing variants ...
  TryTable(BlockType, Array[CatchClause], Array[Instr])
  Throw(UInt)      // tag_idx
  ThrowRef
}
```

### Phase 2: Parsing (3-4 hours)

**Files**: `src/parse.mbt`

- [ ] Parse tag section (section ID 13)
- [ ] Update `try_table` (0x1F) parsing to build proper AST
- [ ] Update `throw` (0x08) parsing
- [ ] Add `throw_ref` (0x0A) parsing
- [ ] Handle tag imports/exports

```moonbit
// src/parse.mbt additions

fn parse_tag_section(parser : Parser) -> Array[TagType] {
  let count = parser.read_u32_leb128()
  let tags = []
  for _ in 0U..<count {
    let kind = parser.read_byte()  // Must be 0x00
    guard kind == 0x00 else { abort("invalid tag kind") }
    let type_idx = parser.read_u32_leb128()
    tags.push({ type_idx: type_idx.reinterpret_as_int() })
  }
  tags
}

// Update opcode 0x1F
0x1F => {
  let blocktype = parse_blocktype(parser)
  let catch_count = parser.read_u32_leb128()
  let catches = []
  for _ in 0U..<catch_count {
    let kind = parser.read_byte()
    let clause = match kind {
      0x00 => {
        let tag = parser.read_u32_leb128()
        let label = parser.read_u32_leb128()
        CatchClause::Catch(tag, label)
      }
      0x01 => {
        let tag = parser.read_u32_leb128()
        let label = parser.read_u32_leb128()
        CatchClause::CatchRef(tag, label)
      }
      0x02 => CatchClause::CatchAll(parser.read_u32_leb128())
      0x03 => CatchClause::CatchAllRef(parser.read_u32_leb128())
      _ => abort("invalid catch kind")
    }
    catches.push(clause)
  }
  let instrs = parse_instrs(parser)
  TryTable(blocktype, catches, instrs)
}
```

### Phase 3: Validation (4-5 hours)

**Files**: `src/validate.mbt`

- [ ] Validate tag section (type must have empty results)
- [ ] Validate `try_table` catch clauses
- [ ] Validate catch label targets exist and have compatible types
- [ ] Validate `throw` tag index and payload types
- [ ] Validate `throw_ref` operand is exnref
- [ ] Handle stack polymorphism after throw

```moonbit
// src/validate.mbt additions

TryTable(block_type, catches, instrs) => {
  let (params, results) = get_block_type(module_, block_type)

  // Validate each catch clause
  for clause in catches {
    match clause {
      Catch(tag_idx, label) | CatchRef(tag_idx, label) => {
        // Validate tag exists
        guard tag_idx.reinterpret_as_int() < module_.tags.length() else {
          raise ValidationError::InvalidTagIndex(tag_idx)
        }

        // Validate label exists
        let label_int = label.reinterpret_as_int()
        guard label_int < ctx.control_stack.length() else {
          raise ValidationError::InvalidLabel(label)
        }

        // Get tag signature
        let tag = module_.tags[tag_idx.reinterpret_as_int()]
        let tag_type = module_.types[tag.type_idx]

        // Validate target block can receive payload + optional exnref
        let target_types = ctx.get_label_types(label_int)
        // ... type compatibility check ...
      }
      CatchAll(label) | CatchAllRef(label) => {
        // Validate label exists
        // For CatchAllRef, target must accept exnref
      }
    }
  }

  // Create block context and validate body
  let try_ctx = ValidationCtx::new()
  // ... copy control stack, push try_table frame ...

  for instr in instrs {
    validate_instruction(module_, func_type, code, try_ctx, instr)
  }

  // Push results to parent stack
  for r in results {
    ctx.stack.push(r)
  }
}

Throw(tag_idx) => {
  // Validate tag exists
  guard tag_idx.reinterpret_as_int() < module_.tags.length() else {
    raise ValidationError::InvalidTagIndex(tag_idx)
  }

  // Get tag signature and pop payload
  let tag = module_.tags[tag_idx.reinterpret_as_int()]
  let tag_type = module_.types[tag.type_idx]

  for i = tag_type.params.length() - 1; i >= 0; i = i - 1 {
    ctx.poly_pop_expect(tag_type.params[i], "throw payload")
  }

  // After throw, stack is polymorphic (unreachable)
  ctx.set_unreachable()
}

ThrowRef => {
  ctx.poly_pop_expect(ExnRef, "throw_ref operand")
  ctx.set_unreachable()
}
```

### Phase 4: Compilation (4-5 hours)

**Files**: `src/compile.mbt`

- [ ] Add `CompiledCatchClause` and extend `CompileBlock`
- [ ] Implement `TryTable` compilation with handler metadata emission
- [ ] Implement catch target patching
- [ ] Implement `Throw` compilation
- [ ] Implement `ThrowRef` compilation

### Phase 5: Runtime (5-6 hours)

**Files**: `src/compile.mbt` (operation functions), `src/runtime.mbt`

- [ ] Add `ExceptionHandler` struct
- [ ] Add `exception_handlers` to `Runtime`
- [ ] Implement `op_try_table_enter`
- [ ] Implement `op_try_table_exit`
- [ ] Implement `op_throw`
- [ ] Implement `op_throw_ref`
- [ ] Handle cross-function exception propagation

### Phase 6: Integration & Testing (4-6 hours)

- [ ] Add exception handling spec tests
- [ ] Test nested try_table blocks
- [ ] Test cross-function throws
- [ ] Test throw_ref re-throwing
- [ ] Test catch_all handlers
- [ ] Performance benchmarking

---

## 7. Future Migration Path

### 7.1 When MoonBit Supports Tail-Call Optimization

The key change is in the execution model:

```moonbit
// CURRENT: Fetch-execute loop
fn Runtime::execute(self : Runtime) -> Unit raise RuntimeError {
  while true {
    match f(self) {
      Next => self.pc += 1
      Jump(target) => self.pc = target
      End => return
      Trap(err) => raise err
    }
  }
}

// FUTURE: Tail-call threaded
fn execute_threaded(rt : Runtime, pc : Int) -> Result[Unit, RuntimeError] {
  let op = rt.ops[pc]
  match op(rt) {
    (Next, _) => execute_threaded(rt, pc + 1)  // TCO!
    (Jump, target) => execute_threaded(rt, target)  // TCO!
    (End, _) => Ok(())
    (Trap, err) => Err(err)
  }
}
```

### 7.2 Exception Handler Stack on "Call Stack"

With tail-call, handlers can live on the implicit call stack:

```moonbit
// FUTURE: Handler as stack frame
fn op_try_table_enter_threaded(rt : Runtime, pc : Int) -> ... {
  // Register handler BY CALLING INTO THE BODY
  // Handler cleanup happens when this function returns

  let result = execute_body(rt, body_start_pc)

  match result {
    Ok(()) => {
      // Normal exit - just return
      execute_threaded(rt, after_try_pc)
    }
    Err(ExceptionSignal(exc)) => {
      // Exception! Check if we catch it
      if matches_our_handlers(exc) {
        // Handle it
        setup_catch_state(rt, exc)
        execute_threaded(rt, handler_pc)
      } else {
        // Propagate up
        Err(ExceptionSignal(exc))
      }
    }
  }
}
```

### 7.3 What Changes, What Stays

| Component | Current | Future (TCO) | Change Required |
|-----------|---------|--------------|-----------------|
| Compiled handler metadata | Inline in ops[] | Same | None |
| Handler PC computation | Compile-time | Same | None |
| Stack height tracking | Compile-time | Same | None |
| Handler registration | Explicit array push | Implicit in call | Runtime only |
| Exception propagation | Array traversal | Return value | Runtime only |
| Unwinding | Direct manipulation | Return chain | Runtime only |

**Key insight**: All compile-time work remains identical. Only runtime dispatch changes.

### 7.4 Abstraction Layer

To ease migration, we can introduce an abstraction:

```moonbit
// Abstract exception handler operations
trait ExceptionRuntime {
  fn push_handler(self, handler : HandlerInfo) -> Unit
  fn pop_handlers_to_depth(self, depth : Int) -> Unit
  fn find_handler(self, tag_idx : Int) -> ExceptionHandler?
  fn unwind_to(self, handler : ExceptionHandler) -> Unit
}

// Current implementation
impl ExceptionRuntime for Runtime { ... }

// Future implementation can swap this out
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

```moonbit
// Basic throw/catch
test "simple_throw_catch" {
  let wat = "
    (module
      (tag $e (param i32))
      (func (export \"test\") (result i32)
        (block $handler (result i32)
          (try_table (result i32) (catch $e $handler)
            (throw $e (i32.const 42))
            (i32.const 0)  ;; Never reached
          )
        )
      )
    )
  "
  let result = run_wat(wat, "test", [])
  assert_eq!(result, [I32(42)])
}

// Nested try_table
test "nested_try_table" {
  // Inner throw caught by outer handler
}

// Cross-function throw
test "cross_function_throw" {
  // Function A calls B, B throws, A catches
}

// throw_ref
test "throw_ref_rethrow" {
  // Catch with catch_ref, then throw_ref
}
```

### 8.2 Spec Test Integration

WebAssembly exception handling proposal has a test suite:
- `exception-handling/throw.wast`
- `exception-handling/try_table.wast`
- `exception-handling/rethrow.wast`

Convert these to the test harness format and add to `test/reference_tests/`.

### 8.3 Edge Cases

- [ ] Empty payload exceptions
- [ ] Multiple catch clauses (first match wins)
- [ ] catch_all after specific catches
- [ ] Exception during exception handling
- [ ] Stack restoration correctness
- [ ] Handler at different call depths

---

## Appendix A: WebAssembly Exception Handling Spec Reference

- [Exception Handling Proposal](https://github.com/WebAssembly/exception-handling)
- [Binary Format](https://webassembly.github.io/exception-handling/core/binary/modules.html#tag-section)
- [Validation Rules](https://webassembly.github.io/exception-handling/core/valid/instructions.html)
- [Execution Semantics](https://webassembly.github.io/exception-handling/core/exec/instructions.html)

## Appendix B: File Change Summary

| File | Changes |
|------|---------|
| `src/types.mbt` | Add TagType, CatchClause, ExceptionData; extend Value, Instr |
| `src/parse.mbt` | Parse tag section, try_table, throw, throw_ref |
| `src/validate.mbt` | Validate exception instructions and catch clauses |
| `src/compile.mbt` | Compile exception blocks, emit handler metadata |
| `src/runtime.mbt` | Add ExceptionHandler, exception_handlers field |
| `test/main.mbt` | Update test harness for exception assertions |
