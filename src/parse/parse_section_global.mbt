// Section parsers: global section

///|
fn parse_global_section(parser : Parser) -> Array[@core.Global] raise {
  let count = parser.read_u32_leb128()
  let globals = []
  for i in 0U..<count {
    let val_type = parser.read_valtype()
    let mutable = match parser.view() {
      [byte, .. rest] => {
        parser.update_view(rest)
        byte == 0x01
      }
      _ => raise ParseError::UnexpectedEof
    }
    let init = parse_expr(parser)
    globals.push(@core.Global::{
      type_: @core.GlobalType::{ val_type, mutable },
      init,
    })
  }
  globals
}
