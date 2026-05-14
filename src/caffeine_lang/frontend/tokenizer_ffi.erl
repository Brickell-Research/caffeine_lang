%% Erlang counterparts to tokenizer_ffi.mjs. Erlang strings are UTF-8 binaries,
%% so the UTF-8 pattern match cleanly extracts one codepoint at a time.
-module(tokenizer_ffi).
-export([pop_codepoint/1, code_unit_at/2, code_unit_length/1]).

pop_codepoint(<<>>) -> {<<>>, <<>>};
pop_codepoint(<<Cp/utf8, Rest/binary>>) -> {<<Cp/utf8>>, Rest};
pop_codepoint(_) -> {<<>>, <<>>}.

code_unit_at(S, I) when is_binary(S), is_integer(I), I >= 0 ->
    case byte_size(S) > I of
        true -> binary:at(S, I);
        false -> -1
    end;
code_unit_at(_, _) -> -1.

code_unit_length(S) when is_binary(S) -> byte_size(S);
code_unit_length(_) -> 0.
