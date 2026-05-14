%% Fast byte-level helpers paralleling parser_ffi.mjs. Erlang strings are UTF-8
%% binaries; for ASCII tokens (operators, parens, keyword bytes) byte position
%% equals UTF-8 codepoint position, so binary:at / binary:part are correct.
-module(parser_ffi).
-export([code_unit_at/2, substring_equals_at/3, code_unit_length/1, slice_codeunits/3]).

code_unit_at(S, I) when is_binary(S), is_integer(I), I >= 0 ->
    case byte_size(S) > I of
        true -> binary:at(S, I);
        false -> -1
    end;
code_unit_at(_, _) -> -1.

substring_equals_at(Haystack, Pos, Needle) when is_binary(Haystack), is_binary(Needle), is_integer(Pos), Pos >= 0 ->
    NeedleSize = byte_size(Needle),
    case byte_size(Haystack) >= Pos + NeedleSize of
        true -> binary:part(Haystack, Pos, NeedleSize) =:= Needle;
        false -> false
    end;
substring_equals_at(_, _, _) -> false.

code_unit_length(S) when is_binary(S) -> byte_size(S);
code_unit_length(_) -> 0.

slice_codeunits(S, Start, Len) when is_binary(S), is_integer(Start), is_integer(Len), Start >= 0, Len > 0 ->
    Total = byte_size(S),
    case Start >= Total of
        true -> <<>>;
        false ->
            ClampedLen = min(Len, Total - Start),
            binary:part(S, Start, ClampedLen)
    end;
slice_codeunits(_, _, _) -> <<>>.
