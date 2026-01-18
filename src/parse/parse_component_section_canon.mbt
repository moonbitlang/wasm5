// Canonical section parser (section 8)

///|
/// Parse canonical function (section 8)
/// Binary format:
/// - 0x00 0x00 f opts* ft => (canon lift f opts* (type ft))   // sync lift
/// - 0x00 0x01 f opts* ft => (canon lift async f opts* (type ft)) // async lift
/// - 0x01 0x00 f opts*    => (canon lower f opts*)            // sync lower
/// - 0x01 0x01 f opts*    => (canon lower async f opts*)      // async lower
/// - 0x02 rt              => (canon resource.new rt)
/// - 0x03 rt              => (canon resource.drop rt)
/// - 0x04 rt              => (canon resource.rep rt)
fn parse_canon(parser : Parser) -> @core.Canon raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      // Lift
      // Read async flag (0x00 for sync, 0x01 for async)
      let _async_flag = parser.read_byte().to_uint()
      let core_func_idx = parser.read_u32_leb128()
      let opts = parse_canon_opts(parser)
      let func_type_idx = parser.read_u32_leb128()
      @core.Canon::Lift(core_func_idx, opts, func_type_idx)
    }
    0x01 => {
      // Lower
      // Read async flag (0x00 for sync, 0x01 for async)
      let _async_flag = parser.read_byte().to_uint()
      let func_idx = parser.read_u32_leb128()
      let opts = parse_canon_opts(parser)
      @core.Canon::Lower(func_idx, opts)
    }
    0x02 => {
      // Resource.new
      let resource_idx = parser.read_u32_leb128()
      @core.Canon::ResourceNew(resource_idx)
    }
    0x03 => {
      // Resource.drop
      let resource_idx = parser.read_u32_leb128()
      @core.Canon::ResourceDrop(resource_idx)
    }
    0x04 => {
      // Resource.rep
      let resource_idx = parser.read_u32_leb128()
      @core.Canon::ResourceRep(resource_idx)
    }
    _ => raise ParseError::InvalidFormat("invalid canon kind")
  }
}

///|
fn parse_canon_opts(parser : Parser) -> Array[@core.CanonOpt] raise ParseError {
  let count = parser.read_u32_leb128()
  let opts : Array[@core.CanonOpt] = []
  for i = 0; i.reinterpret_as_uint() < count; i = i + 1 {
    let opt_kind = parser.read_byte().to_uint()
    let opt = match opt_kind {
      0x00 => @core.CanonOpt::Utf8
      0x01 => @core.CanonOpt::Utf16
      0x02 => @core.CanonOpt::Latin1Utf16
      0x03 => @core.CanonOpt::Memory(parser.read_u32_leb128())
      0x04 => @core.CanonOpt::Realloc(parser.read_u32_leb128())
      0x05 => @core.CanonOpt::PostReturn(parser.read_u32_leb128())
      _ => raise ParseError::InvalidFormat("invalid canon opt kind")
    }
    opts.push(opt)
  }
  opts
}
