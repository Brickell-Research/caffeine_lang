-module(yaml_ffi).
-export([parse_file/1, parse_string/1, document_root/1, int_parse/1]).

-include_lib("yamerl/include/yamerl_errors.hrl").

%% Ensure yamerl is started (cached after first call)
-define(ENSURE_YAMERL,
    case whereis(yamerl_app) of
        undefined -> application:ensure_all_started(yamerl);
        _ -> ok
    end).

%% Parse YAML file
parse_file(Path) ->
    ?ENSURE_YAMERL,
    try
        Docs = map_yamerl_docs(yamerl_constr:file(Path, [{detailed_constr, true}])),
        {ok, Docs}
    catch
        throw:#yamerl_exception{errors = [First | _]} ->
            {error, format_error(First)};
        error:Reason ->
            {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% Parse YAML string
parse_string(Content) ->
    ?ENSURE_YAMERL,
    try
        Docs = map_yamerl_docs(yamerl_constr:string(Content, [{detailed_constr, true}])),
        {ok, Docs}
    catch
        throw:#yamerl_exception{errors = [First | _]} ->
            {error, format_error(First)};
        error:Reason ->
            {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% Get document root
document_root(Doc) ->
    {document, Root} = Doc,
    Root.

int_parse(S) ->
    try
        {ok, binary_to_integer(S)}
    catch
        _:_ -> {error, nil}
    end.

%% Format yamerl error to string
format_error(#yamerl_parsing_error{text = undefined}) ->
    <<"Unexpected parsing error">>;
format_error(#yamerl_parsing_error{text = Message}) ->
    unicode:characters_to_binary(Message);
format_error(_) ->
    <<"Unknown YAML error">>.

%% Convert yamerl documents to our format
map_yamerl_docs(Documents) ->
    lists:map(fun map_yamerl_doc/1, Documents).

map_yamerl_doc({yamerl_doc, RootNode}) ->
    {document, map_yamerl_node(RootNode)}.

%% Convert yamerl nodes to yaml.gleam compatible format
map_yamerl_node({yamerl_null, _, _Tag, _Loc}) ->
    node_null;
map_yamerl_node({yamerl_str, _, _Tag, _Loc, String}) ->
    {node_str, unicode:characters_to_binary(String)};
map_yamerl_node({yamerl_bool, _, _Tag, _Loc, Bool}) ->
    {node_bool, Bool};
map_yamerl_node({yamerl_int, _, _Tag, _Loc, Int}) ->
    {node_int, Int};
map_yamerl_node({yamerl_float, _, _Tag, _Loc, Float}) ->
    {node_float, Float};
map_yamerl_node({yamerl_seq, _, _Tag, _Loc, Nodes, _Count}) ->
    {node_seq, lists:map(fun map_yamerl_node/1, Nodes)};
map_yamerl_node({yamerl_map, _, _Tag, _Loc, Pairs}) ->
    {node_map, [{map_yamerl_node(K), map_yamerl_node(V)} || {K, V} <- Pairs]}.
