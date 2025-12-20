// Section parsers

///|
fn parse_single_type(parser : Parser) -> @core.FuncType raise {
  let tag = parser.read_byte()
  // Handle composite types from GC proposal
  match tag {
    // func type
    0x60 => {
      let param_count = parser.read_u32_leb128()
      let params = []
      for _ in 0U..<param_count {
        params.push(parser.read_valtype())
      }
      let result_count = parser.read_u32_leb128()
      let results = []
      for _ in 0U..<result_count {
        results.push(parser.read_valtype())
      }
      { params, results }
    }
    // struct type (GC proposal) - skip fields, return empty func type
    0x5F => {
      let field_count = parser.read_u32_leb128()
      for _ in 0U..<field_count {
        let _ = parser.read_valtype() // field type
        let _ = parser.read_byte()
        // mutability
      }
      { params: [], results: [] }
    }
    // array type (GC proposal) - skip element, return empty func type
    0x5E => {
      let _ = parser.read_valtype() // element type
      let _ = parser.read_byte() // mutability
      { params: [], results: [] }
    }
    _ =>
      raise @core.ValidationError::TypeMismatch(
        "expected composite type tag, got 0x\{tag.to_string()}",
      )
  }
}

///|
fn parse_type_section(parser : Parser) -> Array[@core.FuncType] raise {
  let count = parser.read_u32_leb128()
  let types = []
  for i in 0U..<count {
    let tag = parser.read_byte()
    // GC proposal: handle recursive type groups and subtypes
    match tag {
      // rec - recursive type group
      0x4E => {
        let rec_count = parser.read_u32_leb128()
        for _ in 0U..<rec_count {
          let func_type = parse_single_type(parser)
          types.push(func_type)
        }
        continue
      }
      // sub - subtype (with supertypes)
      0x4F => {
        let supertype_count = parser.read_u32_leb128()
        for _ in 0U..<supertype_count {
          let _ = parser.read_u32_leb128()
          // supertype index, ignored
        }
        let func_type = parse_single_type(parser)
        types.push(func_type)
        continue
      }
      // sub final - final subtype (with supertypes)
      0x50 => {
        let supertype_count = parser.read_u32_leb128()
        for _ in 0U..<supertype_count {
          let _ = parser.read_u32_leb128()
          // supertype index, ignored
        }
        let func_type = parse_single_type(parser)
        types.push(func_type)
        continue
      }
      // Standard function type
      0x60 => {
        parser.pos = parser.pos - 1 // Put the byte back
        let func_type = parse_single_type(parser)
        types.push(func_type)
      }
      _ =>
        raise @core.ValidationError::TypeMismatch(
          "expected type tag, got 0x\{tag.to_string()}",
        )
    }
  }
  types
}

///|
fn parse_import_section(parser : Parser) -> Array[@core.Import] raise {
  let count = parser.read_u32_leb128()
  let imports = []
  for i in 0U..<count {
    let module_ = parser.read_name()
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc = match desc_tag {
      0x00 => @core.ImportDesc::Func(parser.read_u32_leb128())
      0x01 => {
        let (elem_type, nullable) = parser.read_reftype_with_nullability()
        let limits = parser.read_limits()
        @core.ImportDesc::Table(@core.TableType::{
          elem_type,
          limits,
          init: None,
          nullable,
        })
      }
      0x02 =>
        @core.ImportDesc::Mem(@core.MemType::{ limits: parser.read_limits() })
      0x03 => {
        let val_type = parser.read_valtype()
        let mutable = parser.read_byte() == 0x01
        @core.ImportDesc::Global(@core.GlobalType::{ val_type, mutable })
      }
      // Exception handling: tag import
      0x04 => {
        let _ = parser.read_byte() // tag attribute (should be 0x00)
        let type_idx = parser.read_u32_leb128()
        @core.ImportDesc::Tag(type_idx)
      }
      _ =>
        raise @core.ValidationError::TypeMismatch(
          "invalid import descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    imports.push(@core.Import::{ module_, name, desc })
  }
  imports
}

///|
fn parse_function_section(
  parser : Parser,
) -> Array[UInt] raise @core.ParseError {
  let count = parser.read_u32_leb128()
  let funcs = []
  for i in 0U..<count {
    funcs.push(parser.read_u32_leb128())
  }
  funcs
}

///|
fn parse_table_section(parser : Parser) -> Array[@core.TableType] raise {
  let count = parser.read_u32_leb128()
  let tables = []
  for i in 0U..<count {
    // GC proposal: tables can have encoding prefix:
    // - 0x40 0x00: reftype + limits + init_expr (explicit initializer)
    // - otherwise: reftype + limits (old format, implicit null init)
    let first_byte = parser.read_byte()
    if first_byte == 0x40 {
      // New encoding with explicit init expression
      // Skip the reserved byte (always 0x00)
      let _ = parser.read_byte()
      let (elem_type, nullable) = parser.read_reftype_with_nullability()
      let limits = parser.read_limits()
      let init_expr = parse_expr(parser)
      tables.push(@core.TableType::{
        elem_type,
        limits,
        init: Some(init_expr),
        nullable,
      })
    } else {
      // Old encoding: first byte is the reftype (always nullable)
      parser.pos = parser.pos - 1
      let (elem_type, nullable) = parser.read_reftype_with_nullability()
      let limits = parser.read_limits()
      tables.push(@core.TableType::{ elem_type, limits, init: None, nullable })
    }
  }
  tables
}

///|
fn parse_memory_section(
  parser : Parser,
) -> Array[@core.MemType] raise @core.ParseError {
  let count = parser.read_u32_leb128()
  let mems = []
  for i in 0U..<count {
    let limits = parser.read_limits()
    mems.push(@core.MemType::{ limits, })
  }
  mems
}

///|
fn parse_global_section(parser : Parser) -> Array[@core.Global] raise {
  let count = parser.read_u32_leb128()
  let globals = []
  for i in 0U..<count {
    let val_type = parser.read_valtype()
    let mutable = parser.read_byte() == 0x01
    let init = parse_expr(parser)
    globals.push(@core.Global::{
      type_: @core.GlobalType::{ val_type, mutable },
      init,
    })
  }
  globals
}

///|
fn parse_export_section(parser : Parser) -> Array[@core.Export] raise {
  let count = parser.read_u32_leb128()
  let exports = []
  for i in 0U..<count {
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc = match desc_tag {
      0x00 => @core.ExportDesc::Func(parser.read_u32_leb128())
      0x01 => @core.ExportDesc::Table(parser.read_u32_leb128())
      0x02 => @core.ExportDesc::Mem(parser.read_u32_leb128())
      0x03 => @core.ExportDesc::Global(parser.read_u32_leb128())
      // Exception handling: tag export
      0x04 => @core.ExportDesc::Tag(parser.read_u32_leb128())
      _ =>
        raise @core.ValidationError::TypeMismatch(
          "invalid export descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    exports.push(@core.Export::{ name, desc })
  }
  exports
}

///|
fn parse_element_section(parser : Parser) -> Array[@core.Elem] raise {
  let count = parser.read_u32_leb128()
  let elems = []
  for i in 0U..<count {
    let flags = parser.read_u32_leb128()
    // Element segment format depends on flags:
    // flags=0: active, table 0, offset expr, vec of funcidx
    // flags=1: passive, elemkind, vec of funcidx
    // flags=2: active, tableidx, offset expr, elemkind, vec of funcidx
    // flags=3: declarative, elemkind, vec of funcidx
    // flags=4: active, table 0, offset expr, vec of expr
    // flags=5: passive, reftype, vec of expr
    // flags=6: active, tableidx, offset expr, reftype, vec of expr
    // flags=7: declarative, reftype, vec of expr
    // Active segments (flags 0,2,4,6) reference a table
    // Passive/declarative segments (flags 1,3,5,7) don't
    let is_active = flags == 0 || flags == 2 || flags == 4 || flags == 6
    let table_idx : UInt = match flags {
      0 | 4 => 0U // implicit table 0
      2 | 6 => parser.read_u32_leb128() // explicit table index
      _ => 0U // passive/declarative segments have no table
    }
    let offset : @core.Expr = match flags {
      0 | 2 | 4 | 6 => parse_expr(parser) // active segments have offset
      _ => @core.Expr::{ instrs: [@core.Instr::I32Const(0U)] } // dummy offset for passive/declarative
    }
    // Read elemkind or reftype for certain flags
    let elem_type : @core.RefType = match flags {
      1 | 3 => {
        let _elemkind = parser.read_byte()
        // elemkind (0x00 = funcref)
        @core.RefType::Func
      }
      2 => {
        let _elemkind = parser.read_byte()
        // elemkind
        @core.RefType::Func
      }
      5 | 7 => parser.read_reftype()
      6 => parser.read_reftype()
      _ => @core.RefType::Func // flags 0 and 4: default to funcref
    }
    // Read init vector
    let init_count = parser.read_u32_leb128()
    let init = []
    let uses_exprs = flags >= 4
    for j in 0U..<init_count {
      if uses_exprs {
        // Parse expression (ref.func idx or ref.null)
        let expr = parse_expr(parser)
        // Extract function index from expression if it's ref.func
        match expr.instrs.get(0) {
          Some(@core.Instr::RefFunc(idx)) => init.push(idx)
          _ => init.push(0U) // ref.null or other
        }
      } else {
        init.push(parser.read_u32_leb128())
      }
    }
    elems.push(@core.Elem::{ table_idx, offset, init, is_active, elem_type })
  }
  elems
}

///|
fn parse_code_section(parser : Parser) -> Array[@core.Code] raise {
  let count = parser.read_u32_leb128()
  let codes = []
  for i in 0U..<count {
    let _code_size = parser.read_u32_leb128()

    // Parse locals
    let locals_count = parser.read_u32_leb128()
    let locals = []
    for j in 0U..<locals_count {
      let n = parser.read_u32_leb128()
      let val_type = parser.read_valtype()
      for k in 0U..<n {
        locals.push(val_type)
      }
    }

    // Parse body
    let body = parse_expr(parser)
    codes.push(@core.Code::{ locals, body, compiled: None })
  }
  codes
}

///|
fn parse_data_section(parser : Parser) -> Array[@core.Data] raise {
  let count = parser.read_u32_leb128()
  let datas = []
  for i in 0U..<count {
    // Read flags to determine encoding format
    let flags = parser.read_u32_leb128()
    let is_active = flags == 0 || flags == 2
    let (mem_idx, offset) = match flags {
      0 =>
        // Active segment with implicit memory 0
        (0U, parse_expr(parser))
      1 =>
        // Passive segment - no memory index or offset
        (0U, @core.Expr::{ instrs: [@core.Instr::I32Const(0U)] }) // Dummy offset
      2 =>
        // Active segment with explicit memory index
        (parser.read_u32_leb128(), parse_expr(parser))
      _ =>
        // Unknown flag - try old format
        // Treat flags value as mem_idx
        (flags, parse_expr(parser))
    }
    let init_len = parser.read_u32_leb128()
    let init = parser.read_bytes(init_len)
    datas.push(@core.Data::{ mem_idx, offset, init, is_active })
  }
  datas
}
