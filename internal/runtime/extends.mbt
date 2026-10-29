///|
pub extend RuntimeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RuntimeError with Show::{to_string, output}

///|
pub extend RuntimeStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RuntimeStatus with Eq::{not_equal, equal}
