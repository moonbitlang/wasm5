// Core Instance and Core Type section parsers

///|
/// Parse core instance (section 1)
fn parse_core_instance(parser : Parser) -> @core.CoreInstance raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      // Instantiate
      let module_idx = parser.read_u32_leb128()
      let arg_count = parser.read_u32_leb128()
      let args : Array[@core.CoreInstantiateArg] = []
      for i = 0; i.reinterpret_as_uint() < arg_count; i = i + 1 {
        let name = parser.read_name()
        let _ = parser.read_byte() // kind (always 0x12 = instance for core)
        let idx = parser.read_u32_leb128()
        args.push(@core.CoreInstantiateArg::Instance(name, idx))
      }
      @core.CoreInstance::Instantiate(module_idx, args)
    }
    0x01 => {
      // From exports
      let export_count = parser.read_u32_leb128()
      let exports : Array[@core.CoreExport] = []
      for i = 0; i.reinterpret_as_uint() < export_count; i = i + 1 {
        let name = parser.read_name()
        let kind_byte = parser.read_byte().to_uint()
        let idx = parser.read_u32_leb128()
        let kind = match kind_byte {
          0x00 => @core.CoreExportKind::Func(idx)
          0x01 => @core.CoreExportKind::Table(idx)
          0x02 => @core.CoreExportKind::Memory(idx)
          0x03 => @core.CoreExportKind::Global(idx)
          0x04 => @core.CoreExportKind::Tag(idx)
          _ => raise ParseError::InvalidFormat("invalid core export kind")
        }
        exports.push(@core.CoreExport::{ name, kind })
      }
      @core.CoreInstance::FromExports(exports)
    }
    _ => raise ParseError::InvalidFormat("invalid core instance kind")
  }
}

///|
/// Parse core type (section 2)
fn parse_core_type(parser : Parser) -> @core.CoreType raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x60 => {
      // Function type
      let param_count = parser.read_u32_leb128()
      let params : Array[@core.ValType] = []
      for i = 0; i.reinterpret_as_uint() < param_count; i = i + 1 {
        params.push(parse_valtype(parser))
      }
      let result_count = parser.read_u32_leb128()
      let results : Array[@core.ValType] = []
      for i = 0; i.reinterpret_as_uint() < result_count; i = i + 1 {
        results.push(parse_valtype(parser))
      }
      @core.CoreType::Func(@core.FuncType::{ params, results })
    }
    0x50 => {
      // Module type
      let decl_count = parser.read_u32_leb128()
      let decls : Array[@core.ModuleTypeDecl] = []
      for i = 0; i.reinterpret_as_uint() < decl_count; i = i + 1 {
        let decl = parse_module_type_decl(parser)
        decls.push(decl)
      }
      @core.CoreType::Module(@core.ModuleType::{ decls, })
    }
    _ => raise ParseError::InvalidFormat("invalid core type kind")
  }
}

///|
fn parse_valtype(parser : Parser) -> @core.ValType raise ParseError {
  let byte = parser.read_byte().to_int()
  match byte {
    0x7F => @core.ValType::I32
    0x7E => @core.ValType::I64
    0x7D => @core.ValType::F32
    0x7C => @core.ValType::F64
    0x7B => @core.ValType::V128
    0x70 => @core.ValType::FuncRef
    0x6F => @core.ValType::ExternRef
    0x6E => @core.ValType::AnyRef
    0x69 => @core.ValType::ExnRef
    _ => raise ParseError::InvalidFormat("invalid value type")
  }
}

///|
fn parse_module_type_decl(
  parser : Parser,
) -> @core.ModuleTypeDecl raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      // Import
      let module_ = parser.read_name()
      let name = parser.read_name()
      let desc = parse_import_desc(parser)
      @core.ModuleTypeDecl::Import(@core.Import::{ module_, name, desc })
    }
    0x01 => {
      // Type
      let type_def = parse_typedef(parser)
      @core.ModuleTypeDecl::Type(type_def)
    }
    0x02 => {
      // Alias
      let alias_val = parse_core_alias(parser)
      @core.ModuleTypeDecl::Alias(alias_val)
    }
    0x03 => {
      // Export (in module type, exports contain inline types, not indices)
      let name = parser.read_name()
      let desc = parse_import_desc(parser)
      @core.ModuleTypeDecl::Export(name, desc)
    }
    _ => raise ParseError::InvalidFormat("invalid module type decl kind")
  }
}

///|
fn parse_import_desc(parser : Parser) -> @core.ImportDesc raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => @core.ImportDesc::Func(parser.read_u32_leb128())
    0x01 => @core.ImportDesc::Table(parse_table_type(parser))
    0x02 => @core.ImportDesc::Mem(parse_mem_type(parser))
    0x03 => @core.ImportDesc::Global(parse_global_type(parser))
    0x04 => @core.ImportDesc::Tag(parser.read_u32_leb128())
    _ => raise ParseError::InvalidFormat("invalid import desc kind")
  }
}

///|
fn parse_table_type(parser : Parser) -> @core.TableType raise ParseError {
  let elem_type = parse_reftype(parser)
  let limits = parse_limits(parser)
  @core.TableType::{
    elem_type,
    limits,
    init: None,
    nullable: true,
    table64: false,
  }
}

///|
fn parse_mem_type(parser : Parser) -> @core.MemType raise ParseError {
  let flags = parser.read_byte().to_uint()
  let shared = (flags & 0x02) != 0
  let memory64 = (flags & 0x04) != 0
  let has_max = (flags & 0x01) != 0
  let min = if memory64 {
    parser.read_u64_leb128()
  } else {
    parser.read_u32_leb128().to_uint64()
  }
  let max = if has_max {
    Some(
      if memory64 {
        parser.read_u64_leb128()
      } else {
        parser.read_u32_leb128().to_uint64()
      },
    )
  } else {
    None
  }
  @core.MemType::{ limits: @core.Limits::{ min, max }, shared, memory64 }
}

///|
fn parse_global_type(parser : Parser) -> @core.GlobalType raise ParseError {
  let val_type = parse_valtype(parser)
  let mutable = parser.read_byte().to_uint() == 1
  @core.GlobalType::{ val_type, mutable }
}

///|
fn parse_reftype(parser : Parser) -> @core.RefType raise ParseError {
  let byte = parser.read_byte().to_int()
  match byte {
    0x70 => @core.RefType::Func
    0x6F => @core.RefType::Extern
    0x6E => @core.RefType::Any
    0x6D => @core.RefType::Eq
    0x6C => @core.RefType::I31
    0x6B => @core.RefType::Struct
    0x6A => @core.RefType::Array
    0x69 => @core.RefType::Exn
    _ => raise ParseError::InvalidFormat("invalid ref type")
  }
}

///|
fn parse_limits(parser : Parser) -> @core.Limits raise ParseError {
  let flags = parser.read_byte().to_uint()
  let has_max = (flags & 0x01) != 0
  let min = parser.read_u32_leb128().to_uint64()
  let max = if has_max {
    Some(parser.read_u32_leb128().to_uint64())
  } else {
    None
  }
  @core.Limits::{ min, max }
}

///|
fn parse_typedef(parser : Parser) -> @core.TypeDef raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x60 => {
      // Function type
      let param_count = parser.read_u32_leb128()
      let params : Array[@core.ValType] = []
      for i = 0; i.reinterpret_as_uint() < param_count; i = i + 1 {
        params.push(parse_valtype(parser))
      }
      let result_count = parser.read_u32_leb128()
      let results : Array[@core.ValType] = []
      for i = 0; i.reinterpret_as_uint() < result_count; i = i + 1 {
        results.push(parse_valtype(parser))
      }
      @core.TypeDef::Func(@core.FuncType::{ params, results })
    }
    _ =>
      raise ParseError::InvalidFormat(
        "invalid type def kind: 0x\{kind.to_string()}",
      )
  }
}

///|
/// Parse core alias in module type context
/// core-sort encoding: 0x00=func, 0x01=table, 0x02=memory, 0x03=global, 0x10=type, 0x11=module
fn parse_core_alias(parser : Parser) -> @core.CoreAlias raise ParseError {
  let sort = parser.read_byte().to_uint()
  let target_kind = parser.read_byte().to_uint()
  let kind = match sort {
    0x00 => @core.AliasKind::CoreFunc
    0x01 => @core.AliasKind::CoreTable
    0x02 => @core.AliasKind::CoreMemory
    0x03 => @core.AliasKind::CoreGlobal
    0x04 => @core.AliasKind::CoreTag
    0x10 => @core.AliasKind::CoreType
    0x11 => @core.AliasKind::CoreModule
    _ =>
      raise ParseError::InvalidFormat(
        "invalid core alias sort: 0x\{sort.to_string()}",
      )
  }
  let target = match target_kind {
    0x00 => {
      // Export
      let instance_idx = parser.read_u32_leb128()
      let name = parser.read_name()
      @core.AliasTarget::CoreExport(instance_idx, name)
    }
    0x01 => {
      // Outer
      let count = parser.read_u32_leb128()
      let idx = parser.read_u32_leb128()
      @core.AliasTarget::Outer(count, idx)
    }
    _ => raise ParseError::InvalidFormat("invalid core alias target")
  }
  @core.CoreAlias::{ kind, target }
}
