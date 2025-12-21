// Section parsers: import section

///|
fn parse_import_section(parser : Parser) -> Array[@core.Import] raise {
  let count = parser.read_u32_leb128()
  let imports = []
  for i in 0U..<count {
    let module_ = parser.read_name()
    let name = parser.read_name()
    let desc_tag = parser.next_byte()
    let desc : @core.ImportDesc = match desc_tag {
      0x00 => Func(parser.read_u32_leb128())
      0x01 => {
        let (elem_type, nullable) = parser.read_reftype_with_nullability()
        let limits = parser.read_limits()
        Table(@core.TableType::{ elem_type, limits, init: None, nullable })
      }
      0x02 => Mem(@core.MemType::{ limits: parser.read_limits() })
      0x03 => {
        let val_type = parser.read_valtype()
        let mutable = parser.next_byte() == 0x01
        Global(@core.GlobalType::{ val_type, mutable })
      }
      // Exception handling: tag import
      0x04 => {
        let _ = parser.next_byte() // tag attribute (should be 0x00)
        let type_idx = parser.read_u32_leb128()
        Tag(type_idx)
      }
      _ =>
        raise @validate.ValidationError::TypeMismatch(
          "invalid import descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    imports.push(@core.Import::{ module_, name, desc })
  }
  imports
}
