// Fast codeunit-level access used by parser.gleam to avoid the Intl.Segmenter
// machinery in gleam_stdlib's string.slice / pop_grapheme. Those grapheme-safe
// helpers construct a new Segmenter iterator per call and walk it from index 0,
// turning the parser's per-position scans into O(N^2). For pure-ASCII tokens
// (operators, parens, keywords like "per") UTF-16 codeunit access is correct
// and orders of magnitude faster.

// Returns the UTF-16 code unit at index i, or -1 if i is out of bounds.
export function code_unit_at(s, i) {
  if (i < 0 || i >= s.length) return -1;
  return s.charCodeAt(i);
}

// Byte-substring equality: true when s.substring(pos, pos+needle.length) === needle.
// Uses substring (no Segmenter) and short-circuits on length check.
export function substring_equals_at(haystack, pos, needle) {
  const end = pos + needle.length;
  if (pos < 0 || end > haystack.length) return false;
  return haystack.substring(pos, end) === needle;
}

// Codeunit count — matches the indexing space used by code_unit_at /
// substring_equals_at / slice_codeunits. Crucially this is NOT grapheme
// count (which gleam_stdlib's string.length returns).
export function code_unit_length(s) {
  return s.length;
}

// Slice by codeunit range. Returns "" if start is out of bounds; clamps len.
export function slice_codeunits(s, start, len) {
  if (start < 0 || start >= s.length || len <= 0) return "";
  return s.substring(start, start + len);
}
