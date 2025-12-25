///|
pub enum SExpr {
  Atom(Bytes)
  StringLit(Bytes)
  List(Array[SExpr])
}

///|
fn parse_sexprs(text : String) -> Array[SExpr] raise WatError {
  let lexer = Lexer::new(text)
  let exprs : Array[SExpr] = []
  while true {
    match lexer.next() {
      None => break
      Some(tok) => exprs.push(parse_expr(lexer, tok))
    }
  }
  exprs
}

///|
fn parse_expr(lexer : Lexer, tok : Token) -> SExpr raise WatError {
  match tok {
    LParen => {
      let items : Array[SExpr] = []
      while true {
        match lexer.next() {
          None => raise WatError::InvalidSyntax("unterminated list")
          Some(RParen) => break
          Some(next_tok) => items.push(parse_expr(lexer, next_tok))
        }
      }
      List(items)
    }
    RParen => raise WatError::InvalidSyntax("unexpected ')'")
    Atom(bytes) => Atom(bytes)
    StringLit(bytes) => StringLit(bytes)
  }
}
