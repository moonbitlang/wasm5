///|
fn fib(i : Int) -> Int {
  if i <= 1 {
    return i
  }
  return fib(i - 1) + fib(i - 2)
}

///|
fn main {
  ignore(fib(34))
}
