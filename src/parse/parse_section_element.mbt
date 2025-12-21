// Section parsers: element section

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
      _ => @core.Expr::{ instrs: [I32Const(0U)] } // dummy offset for passive/declarative
    }
    // Read elemkind or reftype for certain flags
    let elem_type : @core.RefType = match flags {
      1 | 3 => {
        let _elemkind = match parser.view() {
          [byte, .. rest] => {
            parser.update_view(rest)
            byte
          }
          _ => raise ParseError::UnexpectedEof
        }
        // elemkind (0x00 = funcref)
        Func
      }
      2 => {
        let _elemkind = match parser.view() {
          [byte, .. rest] => {
            parser.update_view(rest)
            byte
          }
          _ => raise ParseError::UnexpectedEof
        }
        // elemkind
        Func
      }
      5 | 7 => parser.read_reftype()
      6 => parser.read_reftype()
      _ => Func // flags 0 and 4: default to funcref
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
          Some(RefFunc(idx)) => init.push(idx)
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
