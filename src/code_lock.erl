-module(code_lock).
-behaviour(gen_statem).

%% API
-export([start_link/1, stop/0]).
-export([button/1, change_code/1, get_state/0, reset/0]).

%% gen_statem callbacks
-export([init/1, callback_mode/0, terminate/3]).
-export([handle_event/4]).

-define(SERVER, ?MODULE).
-define(DEFAULT_CODE, "1234").
-define(MAX_ATTEMPTS, 3).
-define(SUSPEND_TIMEOUT, 10000).  % 10 seconds
-define(BUTTON_TIMEOUT, 30000).    % 30 seconds

-record(data, {
    code :: string(),
    length :: non_neg_integer(),
    buttons = [] :: list(),
    failed_attempts = 0 :: non_neg_integer()
}).

%% ============================================================================
%% API functions
%% ============================================================================

-spec start_link(string()) -> {ok, pid()} | {error, term()}.
start_link(Code) ->
    gen_statem:start_link({local, ?SERVER}, ?MODULE, Code, []).

-spec stop() -> ok.
stop() ->
    gen_statem:stop(?SERVER).

-spec button(char()) -> ok.
button(Button) ->
    gen_statem:cast(?SERVER, {button, Button}).

-spec change_code(string()) -> ok | {error, not_open}.
change_code(NewCode) ->
    gen_statem:call(?SERVER, {change_code, NewCode}).

-spec get_state() -> locked | open | suspended.
get_state() ->
    gen_statem:call(?SERVER, get_state).

-spec reset() -> ok.
reset() ->
    gen_statem:call(?SERVER, reset).

%% ============================================================================
%% gen_statem callbacks
%% ============================================================================

-spec init(string()) -> {ok, {locked | open | suspended, term()}, #data{}}.
init(Code) ->
    process_flag(trap_exit, true),
    Data = #data{
        code = Code,
        length = length(Code),
        buttons = [],
        failed_attempts = 0
    },
    {ok, {locked, undefined}, Data}.

-spec callback_mode() -> [handle_event_function | state_enter].
callback_mode() ->
    [handle_event_function, state_enter].

%% ============================================================================
%% State: locked
%% ============================================================================

handle_event(enter, _OldState, {locked, _}, Data) ->
    do_lock(),
    {keep_state, Data#data{buttons = []}};

handle_event(state_timeout, button, {locked, _}, Data) ->
    {keep_state, Data#data{buttons = []}};

handle_event(cast, {button, Button}, {locked, _}, 
             #data{code = Code, length = Len, buttons = Buttons, failed_attempts = Failed} = Data) ->
    NewButtons = case length(Buttons) < Len of
        true -> Buttons ++ [Button];
        false -> tl(Buttons) ++ [Button]
    end,
    
    case NewButtons of
        Code when length(NewButtons) =:= Len ->
            % Correct code
            {next_state, {open, undefined}, Data#data{buttons = [], failed_attempts = 0}};
        _ when length(NewButtons) < Len ->
            % Incomplete code
            {keep_state, Data#data{buttons = NewButtons}, 
             [{state_timeout, ?BUTTON_TIMEOUT, button}]};
        _ ->
            % Incorrect code
            NewFailed = Failed + 1,
            io:format("Incorrect code. Attempts: ~p/~p~n", [NewFailed, ?MAX_ATTEMPTS]),
            if
                NewFailed >= ?MAX_ATTEMPTS ->
                    % Suspend the lock
                    io:format("Too many failed attempts! Lock suspended for 10 seconds.~n", []),
                    {next_state, {suspended, undefined}, Data#data{buttons = [], failed_attempts = 0},
                     [{state_timeout, ?SUSPEND_TIMEOUT, resume}]};
                true ->
                    % Still locked, but count failed attempt
                    {keep_state, Data#data{buttons = [], failed_attempts = NewFailed}}
            end
    end;

%% ============================================================================
%% State: open
%% ============================================================================

handle_event(enter, _OldState, {open, _}, _Data) ->
    do_unlock(),
    {keep_state_and_data, [{state_timeout, 10000, lock}]};

handle_event(state_timeout, lock, {open, _}, Data) ->
    {next_state, {locked, undefined}, Data#data{failed_attempts = 0}};

handle_event({call, From}, {change_code, NewCode}, {open, _}, Data) ->
    io:format("Code changed from '~s' to '~s'~n", [Data#data.code, NewCode]),
    {keep_state, Data#data{code = NewCode}, [{reply, From, ok}]};

handle_event({call, From}, get_state, {open, _}, _Data) ->
    {keep_state_and_data, [{reply, From, open}]};

handle_event({call, From}, reset, {open, _}, Data) ->
    {next_state, {locked, undefined}, Data#data{buttons = [], failed_attempts = 0}, 
     [{reply, From, ok}]};

handle_event(cast, {button, _}, {open, _}, _Data) ->
    % Ignore button presses in open state (or could auto-lock)
    {keep_state_and_data, [postpone]};

%% ============================================================================
%% State: suspended
%% ============================================================================

handle_event(enter, _OldState, {suspended, _}, _Data) ->
    io:format("LOCK SUSPENDED - All attempts blocked for 10 seconds~n", []),
    {keep_state_and_data, []};

handle_event(state_timeout, resume, {suspended, _}, Data) ->
    io:format("Lock resumed. You can try again.~n", []),
    {next_state, {locked, undefined}, Data#data{failed_attempts = 0}};

handle_event(cast, {button, _Button}, {suspended, _}, _Data) ->
    io:format("Error: Lock is suspended. Wait for timeout.~n", []),
    {keep_state_and_data, []};

handle_event({call, From}, get_state, {suspended, _}, _Data) ->
    {keep_state_and_data, [{reply, From, suspended}]};

handle_event({call, From}, reset, {suspended, _}, _Data) ->
    {next_state, {locked, undefined}, _Data, [{reply, From, ok}]};

%% ============================================================================
%% Common events
%% ============================================================================

handle_event({call, From}, get_state, {StateName, _}, _Data) ->
    {keep_state_and_data, [{reply, From, StateName}]};

handle_event({call, From}, reset, {StateName, _}, Data) ->
    {next_state, {locked, undefined}, Data#data{buttons = [], failed_attempts = 0},
     [{reply, From, ok}]};

handle_event(EventType, EventContent, StateName, Data) ->
    io:format("Unhandled event: ~p ~p in state ~p~n", [EventType, EventContent, StateName]),
    {keep_state_and_data, []}.

%% ============================================================================
%% Helper functions
%% ============================================================================

do_lock() ->
    io:format("Locked~n", []).

do_unlock() ->
    io:format("Open~n", []).

-spec terminate(term(), {locked | open | suspended, term()}, #data{}) -> ok.
terminate(_Reason, State, _Data) ->
    case State of
        {open, _} -> do_lock();
        {suspended, _} -> io:format("Lock terminated while suspended~n", []);
        _ -> ok
    end,
    ok.