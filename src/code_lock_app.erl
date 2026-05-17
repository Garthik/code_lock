%%%-------------------------------------------------------------------
%% @doc code_lock public API
%% @end
%%%-------------------------------------------------------------------

-module(code_lock_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    code_lock_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
