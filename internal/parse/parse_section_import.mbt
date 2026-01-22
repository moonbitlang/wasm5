// Section parsers: import section

///|
fn parse_import_section(
  parser : Parser,
) -> Array[@core.Import] raise ParseError {
  let count = parser.read_u32_leb128()
  let imports = []
  for i in 0U..<count {
    let module_ = parser.read_name()
    let name = parser.read_name()
    let desc_tag = parser.read_byte()
    let desc : @core.ImportDesc = match desc_tag {
      0x00 => Func(parser.read_u32_leb128())
      0x01 => {
        let (elem_type, nullable) = parser.read_reftype_with_nullability()
        let (limits, table64) = parser.read_limits()
        Table(@core.TableType::{
          elem_type,
          limits,
          init: None,
          nullable,
          table64,
        })
      }
      0x02 => Mem(parser.read_memtype())
      0x03 => {
        let val_type = parser.read_valtype()
        let mutable = parser.read_byte() == 0x01
        Global(@core.GlobalType::{ val_type, mutable })
      }
      // Exception handling: tag import
      0x04 => {
        let attr = parser.read_byte()
        if attr != 0x00U.to_byte() {
          raise ParseError::InvalidFormat(
            "invalid tag attribute: 0x\{attr.to_string()}",
          )
        }
        let type_idx = parser.read_u32_leb128()
        Tag(type_idx)
      }
      _ =>
        raise ParseError::InvalidFormat(
          "invalid import descriptor tag: 0x\{desc_tag.to_string()}",
        )
    }
    imports.push(@core.Import::{ module_, name, desc })
  }
  imports
}
