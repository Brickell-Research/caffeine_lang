-module(yaml_ffi).
-export([parse_file/1, parse_string/1, document_root/1, int_parse/1]).

%% Delegate to glaml for Erlang target
parse_file(Path) ->
    glaml:parse_file(Path).

parse_string(Content) ->
    glaml:parse_string(Content).

document_root(Doc) ->
    glaml:document_root(Doc).

int_parse(S) ->
    try
        {ok, binary_to_integer(S)}
    catch
        _:_ -> {error, nil}
    end.
