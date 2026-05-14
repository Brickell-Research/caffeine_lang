// Fast tokenizer primitives. gleam_stdlib's string.pop_grapheme constructs
// a fresh Intl.Segmenter().segment(s)[Symbol.iterator]() on every call and
// walks it from index 0, turning the tokenizer's per-char loop into O(N^2).
// We split by codepoint instead — which only differs from grapheme for
// combining-mark / ZWJ sequences inside string-literal or comment bodies,
// neither of which the tokenizer needs to slice grapheme-correctly (it just
// scans for ASCII terminators).

// Returns [first_codepoint_as_string, rest]. Returns ["", ""] when source is
// empty — the Gleam wrapper turns that back into Error(Nil).
export function pop_codepoint(s) {
  if (s.length === 0) return ["", ""];
  const cp = s.codePointAt(0);
  const charLen = cp > 0xffff ? 2 : 1;
  return [String.fromCodePoint(cp), s.substring(charLen)];
}

// Returns the UTF-16 code unit at index i, or -1 if i is out of bounds.
// Used by is_digit / is_letter on single-codepoint strings.
export function code_unit_at(s, i) {
  if (i < 0 || i >= s.length) return -1;
  return s.charCodeAt(i);
}

// Codeunit length — used to advance the column counter without re-walking
// the just-read token via Intl.Segmenter.
export function code_unit_length(s) {
  return s.length;
}
