// Section parsers: element section

///|
fn parse_element_section(parser : Parser) -> Array[@core.Elem] raise ParseError {
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
    let is_declarative = flags == 3 || flags == 7
    let table_idx : UInt = match flags {
      0 | 4 => 0U // implicit table 0
      2 | 6 => parser.read_u32_leb128() // explicit table index
      _ => 0U // passive/declarative segments have no table
    }
    let explicit_table = flags == 2 || flags == 6
    let offset : @core.Expr = match flags {
      0 | 2 | 4 | 6 => parse_expr(parser) // active segments have offset
      _ => @core.Expr::{ instrs: [I32Const(0U)] } // dummy offset for passive/declarative
    }
    // Read elemkind or reftype for certain flags
    // For funcidx form (flags 0-3), elem type is non-nullable because ref.func produces non-null
    // For expr form with explicit type (flags 5-7), use the declared type
    // For expr form without explicit type (flag 4), default to nullable funcref for compatibility
    let (elem_type, elem_nullable) = match flags {
      0 =>
        // funcidx form, no type byte - type is (ref func) non-nullable
        (@core.RefType::Func, false)
      1 | 3 => {
        let _elemkind = parser.read_byte()
        // elemkind (0x00 = funcref), but funcidx form is non-nullable
        (@core.RefType::Func, false)
      }
      2 => {
        let _elemkind = parser.read_byte()
        // elemkind, funcidx form is non-nullable
        (@core.RefType::Func, false)
      }
      5 | 7 => parser.read_reftype_with_nullability()
      6 => parser.read_reftype_with_nullability()
      _ => (@core.RefType::Func, true) // flag 4: expr form, default to nullable funcref
    }
    // Read init vector
    let init_count = parser.read_u32_leb128()
    let init : Array[@core.Expr] = []
    let uses_exprs = flags >= 4
    for j in 0U..<init_count {
      if uses_exprs {
        // Parse expression (ref.func/ref.null/global.get)
        let expr = parse_expr(parser)
        init.push(expr)
      } else {
        let idx = parser.read_u32_leb128()
        init.push(@core.Expr::{ instrs: [RefFunc(idx)] })
      }
    }
    elems.push(@core.Elem::{
      table_idx,
      offset,
      init,
      is_active,
      is_declarative,
      elem_type,
      elem_nullable,
      explicit_table,
    })
  }
  elems
}
