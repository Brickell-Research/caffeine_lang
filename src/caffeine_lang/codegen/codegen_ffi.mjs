// Codeunit-level helpers for codegen hot paths. Same justification as
// tokenizer_ffi / parser_ffi: gleam_stdlib's string.drop_end walks the whole
// string via Intl.Segmenter to count graphemes from the end. For trailing
// ASCII stripping (e.g. dropping a final "\n") that's pure overhead.

// Drop the last `n` UTF-16 code units. Returns "" if n >= length.
export function drop_end_codeunits(s, n) {
  if (n <= 0) return s;
  if (n >= s.length) return "";
  return s.substring(0, s.length - n);
}
