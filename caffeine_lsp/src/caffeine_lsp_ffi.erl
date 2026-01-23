-module(caffeine_lsp_ffi).
-export([init_io/0, read_line/0, read_bytes/1, write_stdout/1, write_stderr/1]).

%% Set stdin/stdout to binary mode for correct byte-level reads.
init_io() ->
    io:setopts(standard_io, [binary]),
    nil.

%% Read a single line from stdin (up to newline).
read_line() ->
    case io:get_line(standard_io, "") of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line -> {ok, Line}
    end.

%% Read exactly N bytes from stdin.
read_bytes(N) ->
    case io:get_chars(standard_io, "", N) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Data when is_binary(Data) -> {ok, Data};
        Data when is_list(Data) -> {ok, unicode:characters_to_binary(Data)}
    end.

%% Write raw bytes to stdout.
write_stdout(Data) ->
    io:put_chars(standard_io, Data),
    nil.

%% Write to stderr (for logging).
write_stderr(Data) ->
    io:put_chars(standard_error, [Data, "\n"]),
    nil.
