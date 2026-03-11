/// Parallel map for embarrassingly parallel workloads.
/// On Erlang, spawns one BEAM process per item and collects results in order.
/// On JavaScript, falls back to sequential list.map.

import gleam/list

/// Maps a function over a list, potentially in parallel on the BEAM.
@external(erlang, "caffeine_lang_ffi", "parallel_map")
pub fn parallel_map(over items: List(a), with fun: fn(a) -> b) -> List(b) {
  list.map(items, fun)
}
