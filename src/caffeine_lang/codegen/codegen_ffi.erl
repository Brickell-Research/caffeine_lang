-module(codegen_ffi).
-export([drop_end_codeunits/2]).

drop_end_codeunits(S, N) when is_binary(S), is_integer(N), N > 0 ->
    Total = byte_size(S),
    case N >= Total of
        true -> <<>>;
        false -> binary:part(S, 0, Total - N)
    end;
drop_end_codeunits(S, _) -> S.
