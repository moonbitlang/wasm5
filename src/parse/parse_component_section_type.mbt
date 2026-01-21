// Component Type section parser (section 6)

///|
/// Parse component type definition (section 7)
/// Binary format from Component Model spec:
/// typedef ::= 0x40 ft:compfunctype           // function type
///          |  0x41 cd*:vec(componentdecl)    // component type
///          |  0x42 id*:vec(instancedecl)     // instance type
///          |  0x3f rt:resourcetype           // resource type
///          |  dv:defvaltype                  // defined value type (0x72, 0x71, etc.)
fn parse_component_type_def(
  parser : Parser,
  boundary : Int?,
) -> @core.ComponentTypeDef raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x40 => {
      // Function type (0x40)
      let func_type = parse_component_func_type(parser)
      @core.ComponentTypeDef::Func(func_type)
    }
    0x41 => {
      // Component type: 0x41 cd*:vec(componentdecl)
      // Reuse existing parse_component_type which reads decl_count and decls
      let comp_type = parse_component_type(parser)
      @core.ComponentTypeDef::Component(comp_type)
    }
    0x42 => {
      // Instance type: 0x42 id*:vec(instancedecl)
      // Reuse existing parse_instance_type which reads decl_count and decls
      let inst_type = parse_instance_type(parser)
      @core.ComponentTypeDef::Instance(inst_type)
    }
    0x3F => {
      // Resource type
      let res_type = parse_resource_type(parser)
      @core.ComponentTypeDef::Resource(res_type)
    }
    _ => {
      // Value type (primitive or defined)
      // Back up and re-parse as component valtype (handles both primitives and defvaltypes)
      parser.set_pos(parser.get_pos() - 1)
      let val_type = parse_component_valtype(parser)
      ignore(boundary)
      @core.ComponentTypeDef::Defined(val_type)
    }
  }
}

///|
/// Parse import declaration within type
fn parse_import_decl_in_type(
  parser : Parser,
) -> @core.ComponentImportDecl raise ParseError {
  let (name, url) = parse_externname(parser)
  let desc = parse_extern_desc_in_type(parser)
  @core.ComponentImportDecl::{ name, url, desc }
}

///|
/// Parse export declaration within type
/// exportdecl ::= externname externdesc
fn parse_export_decl_in_type(
  parser : Parser,
) -> @core.ComponentExportDecl raise ParseError {
  let (name, url) = parse_externname(parser)
  let desc = parse_extern_desc_in_type(parser)
  @core.ComponentExportDecl::{ name, url, desc }
}

///|
/// Parse externdesc (external descriptor) within type context
/// externdesc ::= 0x00 0x11 i:<core:typeidx>  => (core module (type i))
///              | 0x01 i:<typeidx>             => (func (type i))
///              | 0x02 b:<valuebound>          => (value b)
///              | 0x03 b:<typebound>           => (type b)
///              | 0x04 i:<typeidx>             => (component (type i))
///              | 0x05 i:<typeidx>             => (instance (type i))
fn parse_extern_desc_in_type(
  parser : Parser,
) -> @core.ComponentExternDesc raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      // Core module - read 0x11 discriminant then typeidx
      let sub_kind = parser.read_byte().to_uint()
      if sub_kind != 0x11 {
        raise ParseError::InvalidFormat(
          "expected 0x11 for core module externdesc, got 0x\{sub_kind.to_string()}",
        )
      }
      let idx = parser.read_u32_leb128()
      @core.ComponentExternDesc::Module(idx)
    }
    0x01 => {
      // Func
      let idx = parser.read_u32_leb128()
      @core.ComponentExternDesc::Func(idx)
    }
    0x02 => {
      // Value bound
      let bound_kind = parser.read_byte().to_uint()
      match bound_kind {
        0x00 => {
          let idx = parser.read_u32_leb128()
          @core.ComponentExternDesc::Value(
            @core.ComponentValType::TypeIndex(idx),
          )
        }
        0x01 => {
          let val_type = parse_component_valtype(parser)
          @core.ComponentExternDesc::Value(val_type)
        }
        _ =>
          raise ParseError::InvalidFormat(
            "invalid valuebound kind: 0x\{bound_kind.to_string()}",
          )
      }
    }
    0x03 => {
      // Type bound
      let bound_kind = parser.read_byte().to_uint()
      match bound_kind {
        0x00 => {
          let idx = parser.read_u32_leb128()
          @core.ComponentExternDesc::Type(@core.TypeBounds::Eq(idx))
        }
        0x01 => @core.ComponentExternDesc::Type(@core.TypeBounds::SubResource)
        _ =>
          raise ParseError::InvalidFormat(
            "invalid typebound kind: 0x\{bound_kind.to_string()}",
          )
      }
    }
    0x04 => {
      // Component
      let idx = parser.read_u32_leb128()
      @core.ComponentExternDesc::Component(idx)
    }
    0x05 => {
      // Instance
      let idx = parser.read_u32_leb128()
      @core.ComponentExternDesc::Instance(idx)
    }
    _ =>
      raise ParseError::InvalidFormat(
        "invalid externdesc kind: 0x\{kind.to_string()}",
      )
  }
}

///|
/// Parse component function type (after 0x40 tag)
/// compfunctype ::= ps:vec(param) rs:result
/// param ::= name:name t:valtype
/// result ::= 0x00 rs:vec(result-named) | 0x01 t:valtype
fn parse_component_func_type(
  parser : Parser,
) -> @core.ComponentFuncType raise ParseError {
  let params : Array[@core.ComponentParam] = []
  let results : Array[@core.ComponentResult] = []

  // Parse params
  let param_count = parser.read_u32_leb128()
  for i = 0; i.reinterpret_as_uint() < param_count; i = i + 1 {
    let name = parser.read_name()
    let type_ = parse_component_valtype(parser)
    params.push(@core.ComponentParam::{ name, type_ })
  }

  // Parse results
  // Result encoding (wasm-tools binary format):
  // 0x00 = single anonymous result (followed by valtype)
  // 0x01 = named results (followed by vec of (name, type) pairs)
  let result_tag = parser.read_byte().to_uint()
  match result_tag {
    0x00 => {
      // Single anonymous result
      let type_ = parse_component_valtype(parser)
      results.push(@core.ComponentResult::{ name: None, type_ })
    }
    0x01 => {
      // Named results
      let result_count = parser.read_u32_leb128()
      for i = 0; i.reinterpret_as_uint() < result_count; i = i + 1 {
        let name = parser.read_name()
        let type_ = parse_component_valtype(parser)
        results.push(@core.ComponentResult::{ name: Some(name), type_ })
      }
    }
    _ => raise ParseError::InvalidFormat("invalid component func result tag")
  }
  @core.ComponentFuncType::{ params, results }
}

///|
/// Parse defined value type (after 0x41 tag)
/// defvaltype ::= 0x72 record | 0x71 variant | 0x70 list | 0x6f tuple
///             |  0x6e flags | 0x6d enum | 0x6c option | 0x6b result
///             |  0x69 own | 0x68 borrow
fn parse_defvaltype(parser : Parser) -> @core.ComponentValType raise ParseError {
  let byte = parser.read_byte()
  let kind = byte.to_int()
  match kind {
    0x72 => {
      // Record
      let field_count = parser.read_u32_leb128()
      let fields : Array[@core.RecordField] = []
      for i = 0; i.reinterpret_as_uint() < field_count; i = i + 1 {
        let name = parser.read_name()
        let type_ = parse_component_valtype(parser)
        fields.push(@core.RecordField::{ name, type_ })
      }
      @core.ComponentValType::Record(fields)
    }
    0x71 => {
      // Variant
      let case_count = parser.read_u32_leb128()
      let cases : Array[@core.VariantCase] = []
      for i = 0; i.reinterpret_as_uint() < case_count; i = i + 1 {
        let name = parser.read_name()
        let has_type = parser.read_byte().to_uint()
        let type_ = if has_type == 0x01 {
          Some(parse_component_valtype(parser))
        } else {
          None
        }
        let has_refines = parser.read_byte().to_uint()
        let refines = if has_refines == 0x01 {
          Some(parser.read_u32_leb128())
        } else {
          None
        }
        cases.push(@core.VariantCase::{ name, type_, refines })
      }
      @core.ComponentValType::Variant(cases)
    }
    0x70 => {
      // List
      let elem_type = parse_component_valtype(parser)
      @core.ComponentValType::List(elem_type)
    }
    0x6F => {
      // Tuple
      let count = parser.read_u32_leb128()
      let types : Array[@core.ComponentValType] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        types.push(parse_component_valtype(parser))
      }
      @core.ComponentValType::Tuple(types)
    }
    0x6E => {
      // Flags
      let count = parser.read_u32_leb128()
      let names : Array[Bytes] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        names.push(parser.read_name())
      }
      @core.ComponentValType::Flags(names)
    }
    0x6D => {
      // Enum
      let count = parser.read_u32_leb128()
      let names : Array[Bytes] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        names.push(parser.read_name())
      }
      @core.ComponentValType::Enum(names)
    }
    0x6B => {
      // Option (0x6B in wasm-tools encoding)
      let inner = parse_component_valtype(parser)
      @core.ComponentValType::Option(inner)
    }
    0x6A => {
      // Result (0x6A in wasm-tools encoding)
      let ok_tag = parser.read_byte().to_uint()
      let ok = if ok_tag == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      let err_tag = parser.read_byte().to_uint()
      let err = if err_tag == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      @core.ComponentValType::Result(ok, err)
    }
    0x69 => {
      // Own
      let idx = parser.read_u32_leb128()
      @core.ComponentValType::Own(idx)
    }
    0x68 => {
      // Borrow
      let idx = parser.read_u32_leb128()
      @core.ComponentValType::Borrow(idx)
    }
    0x67 => {
      // Fixed-size list: 0x67 t:<valtype> len:<u32>
      let elem_type = parse_component_valtype(parser)
      let length = parser.read_u32_leb128()
      @core.ComponentValType::FixedSizeList(elem_type, length)
    }
    0x66 => {
      // Stream: 0x66 t?:<valtype>?
      let has_type = parser.read_byte().to_uint()
      let elem_type = if has_type == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      @core.ComponentValType::Stream(elem_type)
    }
    0x65 => {
      // Future: 0x65 t?:<valtype>?
      let has_type = parser.read_byte().to_uint()
      let elem_type = if has_type == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      @core.ComponentValType::Future(elem_type)
    }
    0x64 =>
      // Error-context: 0x64
      @core.ComponentValType::ErrorContext
    _ =>
      raise ParseError::InvalidFormat(
        "invalid defvaltype kind: 0x\{kind.to_string()}",
      )
  }
}

///|
/// Parse component type (nested, with decl_count)
/// componenttypedecl encoding (within component type):
/// - 0x00: core type
/// - 0x03: import
/// - 0x04: export
/// - 0x06: outer alias (type)
/// - 0x07 and above for export alias with sort
/// - 0x40: inline func type definition
/// - 0x41: inline instance type definition
/// - 0x42: inline component type definition (nested)
/// - 0x72, 0x71, etc.: inline defvaltype definitions
/// - 0x3F: inline resource type
fn parse_component_type(
  parser : Parser,
) -> @core.ComponentType raise ParseError {
  let decl_count = parser.read_u32_leb128()
  let decls : Array[@core.ComponentTypeDecl] = []
  for i = 0; i.reinterpret_as_uint() < decl_count; i = i + 1 {
    let decl_kind = parser.read_byte().to_uint()
    let decl = match decl_kind {
      0x00 => {
        // Core type
        let core_type = parse_core_type(parser)
        @core.ComponentTypeDecl::CoreType(core_type)
      }
      0x01 => {
        // Inline type definition with prefix
        // After 0x01 prefix, 0x41=component, 0x42=instance (both with decl_count)
        let inner_kind = parser.read_byte().to_uint()
        match inner_kind {
          0x3F => {
            let res_type = parse_resource_type(parser)
            @core.ComponentTypeDecl::Type(
              @core.ComponentTypeDef::Resource(res_type),
            )
          }
          0x40 => {
            let func_type = parse_component_func_type(parser)
            @core.ComponentTypeDecl::Type(
              @core.ComponentTypeDef::Func(func_type),
            )
          }
          0x41 => {
            // Component type (0x41 with decl_count)
            let comp_type = parse_component_type(parser)
            @core.ComponentTypeDecl::Type(
              @core.ComponentTypeDef::Component(comp_type),
            )
          }
          0x42 => {
            // Instance type (0x42 with decl_count)
            let inst_type = parse_instance_type(parser)
            @core.ComponentTypeDecl::Type(
              @core.ComponentTypeDef::Instance(inst_type),
            )
          }
          _ => {
            // valtype (includes both primitives and defvaltypes)
            parser.set_pos(parser.get_pos() - 1)
            let val_type = parse_component_valtype(parser)
            @core.ComponentTypeDecl::Type(
              @core.ComponentTypeDef::Defined(val_type),
            )
          }
        }
      }
      0x02 => {
        // Alias: 0x02 s:<sort'> t:<aliastarget>
        // sort' encoding: 0x00 + core:sort OR component sort (0x01-0x05)
        let sort_byte = parser.read_byte().to_uint()
        let kind = if sort_byte == 0x00 {
          // Core sort: read another byte
          let core_sort = parser.read_byte().to_uint()
          match core_sort {
            0x00 => @core.AliasKind::CoreFunc
            0x01 => @core.AliasKind::CoreTable
            0x02 => @core.AliasKind::CoreMemory
            0x03 => @core.AliasKind::CoreGlobal
            0x10 => @core.AliasKind::CoreType
            0x11 => @core.AliasKind::CoreModule
            _ =>
              raise ParseError::InvalidFormat(
                "invalid core sort in alias: 0x\{core_sort.to_string()}",
              )
          }
        } else {
          // Component sort: direct
          match sort_byte {
            0x01 => @core.AliasKind::Func
            0x02 => @core.AliasKind::Value
            0x03 => @core.AliasKind::Type
            0x04 => @core.AliasKind::Component
            0x05 => @core.AliasKind::Instance
            _ =>
              raise ParseError::InvalidFormat(
                "invalid component sort in alias: 0x\{sort_byte.to_string()}",
              )
          }
        }
        // aliastarget: 0x00 = export (u32, name), 0x01 = outer (u32, u32)
        let target_kind = parser.read_byte().to_uint()
        let target = match target_kind {
          0x00 => {
            // Export alias
            let instance_idx = parser.read_u32_leb128()
            let name = parser.read_name()
            @core.AliasTarget::Export(instance_idx, name)
          }
          0x01 | 0x02 => {
            // Outer alias (both 0x01 and 0x02 encode outer alias in type context)
            let ct = parser.read_u32_leb128()
            let idx = parser.read_u32_leb128()
            @core.AliasTarget::Outer(ct, idx)
          }
          _ =>
            raise ParseError::InvalidFormat(
              "invalid aliastarget kind: 0x\{target_kind.to_string()}",
            )
        }
        let alias_val = @core.Alias::{ kind, target }
        @core.ComponentTypeDecl::Alias(alias_val)
      }
      0x03 => {
        // Import (in component type context, uses different externdesc encoding)
        let import_decl = parse_import_decl_in_type(parser)
        @core.ComponentTypeDecl::Import(import_decl)
      }
      0x04 => {
        // Export (in component type context, uses different externdesc encoding)
        let export_decl = parse_export_decl_in_type(parser)
        @core.ComponentTypeDecl::Export(export_decl)
      }
      0x06 => {
        // Outer alias (alternative encoding)
        let ct = parser.read_u32_leb128()
        let idx = parser.read_u32_leb128()
        let alias_val = @core.Alias::{
          kind: @core.AliasKind::Type,
          target: @core.AliasTarget::Outer(ct, idx),
        }
        @core.ComponentTypeDecl::Alias(alias_val)
      }
      0x3F => {
        // Inline resource type (direct, no prefix)
        let res_type = parse_resource_type(parser)
        @core.ComponentTypeDecl::Type(
          @core.ComponentTypeDef::Resource(res_type),
        )
      }
      0x40 => {
        // Inline func type (direct, no prefix)
        let func_type = parse_component_func_type(parser)
        @core.ComponentTypeDecl::Type(@core.ComponentTypeDef::Func(func_type))
      }
      0x41 => {
        // Inline component type (direct, no 0x01 prefix)
        let comp_type = parse_component_type(parser)
        @core.ComponentTypeDecl::Type(
          @core.ComponentTypeDef::Component(comp_type),
        )
      }
      0x42 => {
        // Inline instance type (direct, no 0x01 prefix)
        let inst_type = parse_instance_type(parser)
        @core.ComponentTypeDecl::Type(
          @core.ComponentTypeDef::Instance(inst_type),
        )
      }
      _ =>
        // Check for export alias (sort byte >= 0x07)
        if decl_kind >= 0x07 && decl_kind <= 0x0F {
          // Export alias: sort i:u32 name:name
          let kind = parse_alias_kind(decl_kind)
          let instance_idx = parser.read_u32_leb128()
          let name = parser.read_name()
          let alias_val = @core.Alias::{
            kind,
            target: @core.AliasTarget::Export(instance_idx, name),
          }
          @core.ComponentTypeDecl::Alias(alias_val)
        } else if decl_kind >= 0x68 && decl_kind <= 0x72 {
          // Inline defvaltype (record, variant, list, etc.) - direct, no prefix
          parser.set_pos(parser.get_pos() - 1)
          let val_type = parse_defvaltype(parser)
          @core.ComponentTypeDecl::Type(
            @core.ComponentTypeDef::Defined(val_type),
          )
        } else {
          raise ParseError::InvalidFormat(
            "invalid component type decl kind: 0x\{decl_kind.to_string()}",
          )
        }
    }
    decls.push(decl)
  }
  @core.ComponentType::{ decls, }
}

///|
/// Parse instance type (after 0x41 0x01 tags at top level, or 0x41 within componenttypedecl)
/// instancetypedecl encoding:
/// - 0x00: core type
/// - 0x04: export decl
/// - 0x06: outer alias (type)
/// - 0x07 and above for export alias with sort
/// - 0x3F: inline resource type
/// - 0x40: inline func type definition
/// - 0x41: inline instance type definition (nested)
/// - 0x42: inline component type definition
/// - 0x72, 0x71, etc.: inline defvaltype definitions
fn parse_instance_type(parser : Parser) -> @core.InstanceType raise ParseError {
  let decl_count = parser.read_u32_leb128()
  let decls : Array[@core.InstanceTypeDecl] = []
  for i = 0; i.reinterpret_as_uint() < decl_count; i = i + 1 {
    let decl_kind = parser.read_byte().to_uint()
    let decl = match decl_kind {
      0x00 => {
        // Core type
        let core_type = parse_core_type(parser)
        @core.InstanceTypeDecl::CoreType(core_type)
      }
      0x01 => {
        // Inline type definition with prefix
        // After 0x01 prefix, 0x41=component, 0x42=instance (both with decl_count)
        let inner_kind = parser.read_byte().to_uint()
        match inner_kind {
          0x3F => {
            let res_type = parse_resource_type(parser)
            @core.InstanceTypeDecl::Type(
              @core.ComponentTypeDef::Resource(res_type),
            )
          }
          0x40 => {
            let func_type = parse_component_func_type(parser)
            @core.InstanceTypeDecl::Type(
              @core.ComponentTypeDef::Func(func_type),
            )
          }
          0x41 => {
            // Component type (0x41 with decl_count)
            let comp_type = parse_component_type(parser)
            @core.InstanceTypeDecl::Type(
              @core.ComponentTypeDef::Component(comp_type),
            )
          }
          0x42 => {
            // Instance type (0x42 with decl_count)
            let inst_type = parse_instance_type(parser)
            @core.InstanceTypeDecl::Type(
              @core.ComponentTypeDef::Instance(inst_type),
            )
          }
          _ => {
            // valtype (includes both primitives and defvaltypes)
            parser.set_pos(parser.get_pos() - 1)
            let val_type = parse_component_valtype(parser)
            @core.InstanceTypeDecl::Type(
              @core.ComponentTypeDef::Defined(val_type),
            )
          }
        }
      }
      0x02 => {
        // Alias: 0x02 s:<sort'> t:<aliastarget>
        // sort' encoding: 0x00 + core:sort OR component sort (0x01-0x05)
        let sort_byte = parser.read_byte().to_uint()
        let kind = if sort_byte == 0x00 {
          // Core sort: read another byte
          let core_sort = parser.read_byte().to_uint()
          match core_sort {
            0x00 => @core.AliasKind::CoreFunc
            0x01 => @core.AliasKind::CoreTable
            0x02 => @core.AliasKind::CoreMemory
            0x03 => @core.AliasKind::CoreGlobal
            0x10 => @core.AliasKind::CoreType
            0x11 => @core.AliasKind::CoreModule
            _ =>
              raise ParseError::InvalidFormat(
                "invalid core sort in alias: 0x\{core_sort.to_string()}",
              )
          }
        } else {
          // Component sort: direct
          match sort_byte {
            0x01 => @core.AliasKind::Func
            0x02 => @core.AliasKind::Value
            0x03 => @core.AliasKind::Type
            0x04 => @core.AliasKind::Component
            0x05 => @core.AliasKind::Instance
            _ =>
              raise ParseError::InvalidFormat(
                "invalid component sort in alias: 0x\{sort_byte.to_string()}",
              )
          }
        }
        // aliastarget: 0x00 = export (u32, name), 0x01/0x02 = outer (u32, u32)
        let target_kind = parser.read_byte().to_uint()
        let target = match target_kind {
          0x00 => {
            // Export alias
            let instance_idx = parser.read_u32_leb128()
            let name = parser.read_name()
            @core.AliasTarget::Export(instance_idx, name)
          }
          0x01 | 0x02 => {
            // Outer alias (both 0x01 and 0x02 encode outer alias in type context)
            let ct = parser.read_u32_leb128()
            let idx = parser.read_u32_leb128()
            @core.AliasTarget::Outer(ct, idx)
          }
          _ =>
            raise ParseError::InvalidFormat(
              "invalid aliastarget kind: 0x\{target_kind.to_string()}",
            )
        }
        let alias_val = @core.Alias::{ kind, target }
        @core.InstanceTypeDecl::Alias(alias_val)
      }
      0x03 => {
        // Import (valid in instance types within component types)
        let import_decl = parse_import_decl_in_type(parser)
        @core.InstanceTypeDecl::Import(import_decl)
      }
      0x04 => {
        // Export
        let export_decl = parse_export_decl_in_type(parser)
        @core.InstanceTypeDecl::Export(export_decl)
      }
      0x06 => {
        // Outer alias (alternative encoding)
        let ct = parser.read_u32_leb128()
        let idx = parser.read_u32_leb128()
        let alias_val = @core.Alias::{
          kind: @core.AliasKind::Type,
          target: @core.AliasTarget::Outer(ct, idx),
        }
        @core.InstanceTypeDecl::Alias(alias_val)
      }
      0x3F => {
        // Inline resource type (direct, no prefix)
        let res_type = parse_resource_type(parser)
        @core.InstanceTypeDecl::Type(@core.ComponentTypeDef::Resource(res_type))
      }
      0x40 => {
        // Inline func type (direct, no prefix)
        let func_type = parse_component_func_type(parser)
        @core.InstanceTypeDecl::Type(@core.ComponentTypeDef::Func(func_type))
      }
      0x41 => {
        // Inline component type (direct, no 0x01 prefix)
        let comp_type = parse_component_type(parser)
        @core.InstanceTypeDecl::Type(
          @core.ComponentTypeDef::Component(comp_type),
        )
      }
      0x42 => {
        // Inline instance type (direct, no 0x01 prefix)
        let inst_type = parse_instance_type(parser)
        @core.InstanceTypeDecl::Type(
          @core.ComponentTypeDef::Instance(inst_type),
        )
      }
      _ =>
        // Check for export alias (sort byte >= 0x07)
        if decl_kind >= 0x07 && decl_kind <= 0x0F {
          // Export alias: sort i:u32 name:name
          let kind = parse_alias_kind(decl_kind)
          let instance_idx = parser.read_u32_leb128()
          let name = parser.read_name()
          let alias_val = @core.Alias::{
            kind,
            target: @core.AliasTarget::Export(instance_idx, name),
          }
          @core.InstanceTypeDecl::Alias(alias_val)
        } else if decl_kind >= 0x68 && decl_kind <= 0x72 {
          // Inline defvaltype (record, variant, list, etc.) - direct, no prefix
          parser.set_pos(parser.get_pos() - 1)
          let val_type = parse_defvaltype(parser)
          @core.InstanceTypeDecl::Type(
            @core.ComponentTypeDef::Defined(val_type),
          )
        } else {
          raise ParseError::InvalidFormat(
            "invalid instance type decl kind: 0x\{decl_kind.to_string()}",
          )
        }
    }
    decls.push(decl)
  }
  @core.InstanceType::{ decls, }
}

///|
fn parse_resource_type(parser : Parser) -> @core.ResourceType raise ParseError {
  let rep = parse_valtype(parser)
  let dtor_flag = parser.read_byte().to_uint()
  let dtor = if dtor_flag == 0x01 {
    Some(parser.read_u32_leb128())
  } else {
    None
  }
  @core.ResourceType::{ rep, dtor }
}

///|
/// Parse externdesc for section 10/11 imports and exports
/// externdesc ::= 0x00 0x11 i:<core:typeidx>  => (core module (type i))
///              | 0x01 i:<typeidx>             => (func (type i))
///              | 0x02 t:<valtype>             => (value t)
///              | 0x03 b:<typebound>           => (type b)
///              | 0x04 i:<typeidx>             => (component (type i))
///              | 0x05 i:<typeidx>             => (instance (type i))
fn parse_extern_desc(
  parser : Parser,
) -> @core.ComponentExternDesc raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      // Core module - read 0x11 discriminant then typeidx
      let sub_kind = parser.read_byte().to_uint()
      if sub_kind != 0x11 {
        raise ParseError::InvalidFormat(
          "expected 0x11 for core module externdesc, got 0x\{sub_kind.to_string()}",
        )
      }
      let idx = parser.read_u32_leb128()
      @core.ComponentExternDesc::Module(idx)
    }
    0x01 => @core.ComponentExternDesc::Func(parser.read_u32_leb128())
    0x02 => {
      let val_type = parse_component_valtype(parser)
      @core.ComponentExternDesc::Value(val_type)
    }
    0x03 => {
      let bounds = parse_type_bounds(parser)
      @core.ComponentExternDesc::Type(bounds)
    }
    0x04 => @core.ComponentExternDesc::Component(parser.read_u32_leb128())
    0x05 => @core.ComponentExternDesc::Instance(parser.read_u32_leb128())
    _ => raise ParseError::InvalidFormat("invalid extern desc kind")
  }
}

///|
fn parse_type_bounds(parser : Parser) -> @core.TypeBounds raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => @core.TypeBounds::Eq(parser.read_u32_leb128())
    0x01 => @core.TypeBounds::SubResource
    _ => raise ParseError::InvalidFormat("invalid type bounds kind")
  }
}

///|
fn parse_component_valtype(
  parser : Parser,
) -> @core.ComponentValType raise ParseError {
  let byte = parser.read_byte()
  let kind = byte.to_int()

  // Primitive types are encoded with specific bytes
  match kind {
    0x7F => @core.ComponentValType::Primitive(@core.PrimitiveType::Bool)
    0x7E => @core.ComponentValType::Primitive(@core.PrimitiveType::S8)
    0x7D => @core.ComponentValType::Primitive(@core.PrimitiveType::U8)
    0x7C => @core.ComponentValType::Primitive(@core.PrimitiveType::S16)
    0x7B => @core.ComponentValType::Primitive(@core.PrimitiveType::U16)
    0x7A => @core.ComponentValType::Primitive(@core.PrimitiveType::S32)
    0x79 => @core.ComponentValType::Primitive(@core.PrimitiveType::U32)
    0x78 => @core.ComponentValType::Primitive(@core.PrimitiveType::S64)
    0x77 => @core.ComponentValType::Primitive(@core.PrimitiveType::U64)
    0x76 => @core.ComponentValType::Primitive(@core.PrimitiveType::F32)
    0x75 => @core.ComponentValType::Primitive(@core.PrimitiveType::F64)
    0x74 => @core.ComponentValType::Primitive(@core.PrimitiveType::Char)
    0x73 => @core.ComponentValType::Primitive(@core.PrimitiveType::String)
    0x72 => {
      // Record
      let field_count = parser.read_u32_leb128()
      let fields : Array[@core.RecordField] = []
      for i = 0; i.reinterpret_as_uint() < field_count; i = i + 1 {
        let name = parser.read_name()
        let type_ = parse_component_valtype(parser)
        fields.push(@core.RecordField::{ name, type_ })
      }
      @core.ComponentValType::Record(fields)
    }
    0x71 => {
      // Variant
      let case_count = parser.read_u32_leb128()
      let cases : Array[@core.VariantCase] = []
      for i = 0; i.reinterpret_as_uint() < case_count; i = i + 1 {
        let name = parser.read_name()
        let has_type = parser.read_byte().to_uint()
        let type_ = if has_type == 0x01 {
          Some(parse_component_valtype(parser))
        } else {
          None
        }
        let has_refines = parser.read_byte().to_uint()
        let refines = if has_refines == 0x01 {
          Some(parser.read_u32_leb128())
        } else {
          None
        }
        cases.push(@core.VariantCase::{ name, type_, refines })
      }
      @core.ComponentValType::Variant(cases)
    }
    0x70 => {
      // List
      let elem_type = parse_component_valtype(parser)
      @core.ComponentValType::List(elem_type)
    }
    0x6F => {
      // Tuple
      let count = parser.read_u32_leb128()
      let types : Array[@core.ComponentValType] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        types.push(parse_component_valtype(parser))
      }
      @core.ComponentValType::Tuple(types)
    }
    0x6E => {
      // Flags
      let count = parser.read_u32_leb128()
      let names : Array[Bytes] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        names.push(parser.read_name())
      }
      @core.ComponentValType::Flags(names)
    }
    0x6D => {
      // Enum
      let count = parser.read_u32_leb128()
      let names : Array[Bytes] = []
      for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
        names.push(parser.read_name())
      }
      @core.ComponentValType::Enum(names)
    }
    0x6B => {
      // Option (0x6B in wasm-tools encoding)
      let inner = parse_component_valtype(parser)
      @core.ComponentValType::Option(inner)
    }
    0x6A => {
      // Result (0x6A in wasm-tools encoding)
      let ok_tag = parser.read_byte().to_uint()
      let ok = if ok_tag == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      let err_tag = parser.read_byte().to_uint()
      let err = if err_tag == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      @core.ComponentValType::Result(ok, err)
    }
    0x69 => {
      // Own
      let idx = parser.read_u32_leb128()
      @core.ComponentValType::Own(idx)
    }
    0x68 => {
      // Borrow
      let idx = parser.read_u32_leb128()
      @core.ComponentValType::Borrow(idx)
    }
    0x67 => {
      // Fixed-size list: 0x67 t:<valtype> len:<u32>
      let elem_type = parse_component_valtype(parser)
      let length = parser.read_u32_leb128()
      @core.ComponentValType::FixedSizeList(elem_type, length)
    }
    0x66 => {
      // Stream: 0x66 t?:<valtype>?
      let has_type = parser.read_byte().to_uint()
      let elem_type = if has_type == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      @core.ComponentValType::Stream(elem_type)
    }
    0x65 => {
      // Future: 0x65 t?:<valtype>?
      let has_type = parser.read_byte().to_uint()
      let elem_type = if has_type == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      @core.ComponentValType::Future(elem_type)
    }
    0x64 =>
      // Error-context: 0x64
      @core.ComponentValType::ErrorContext
    _ => {
      // Type index (negative LEB128)
      parser.set_pos(parser.get_pos() - 1)
      let idx = parser.read_i32_leb128()
      if idx < 0 {
        raise ParseError::InvalidFormat("invalid component val type")
      }
      @core.ComponentValType::TypeIndex(idx.reinterpret_as_uint())
    }
  }
}
