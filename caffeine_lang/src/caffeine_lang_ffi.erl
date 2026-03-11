-module(caffeine_lang_ffi).
-export([parallel_map/2]).

%% Maps a function over a list using one BEAM process per element.
%% Results are collected in the original list order.
%% On the JavaScript target, the Gleam function body falls back to list.map.
parallel_map(List, Fun) ->
    Parent = self(),
    Refs = lists:map(fun(Item) ->
        Ref = erlang:make_ref(),
        erlang:spawn_link(fun() ->
            Result = Fun(Item),
            Parent ! {Ref, Result}
        end),
        Ref
    end, List),
    lists:map(fun(Ref) ->
        receive
            {Ref, Result} -> Result
        end
    end, Refs).
