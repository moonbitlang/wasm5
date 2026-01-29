///|
/// Instance execution return code
enum RuntimeStatus {
  Running
  Terminated
  Trap
  Returned // Used by native stack approach: callee returned, continue in caller
} derive(Eq, Show)

///|
/// Return code from runtime ops (mirrors RuntimeStatus for compatibility).
type ReturnCode = RuntimeStatus
