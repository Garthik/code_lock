-module(code_lock_tests).
-include_lib("eunit/include/eunit.hrl").

-define(TIMEOUT, 15000).

unique_name() ->
    list_to_atom(atom_to_list(?MODULE) ++ "_" ++ integer_to_list(erlang:unique_integer([positive]))).

%% Test 1: Correct code opens lock
correct_code_test_() ->
    fun() ->
        Name = unique_name(),
        {ok, Pid} = gen_statem:start_link({local, Name}, code_lock, "1234", []),
        try
            ?assertEqual(locked, gen_statem:call(Name, get_state)),
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "1234"),
            timer:sleep(100),
            ?assertEqual(open, gen_statem:call(Name, get_state))
        after
            catch gen_statem:stop(Pid)
        end
    end.

%% Test 2: Incorrect code keeps lock closed
incorrect_code_test_() ->
    fun() ->
        Name = unique_name(),
        {ok, Pid} = gen_statem:start_link({local, Name}, code_lock, "1234", []),
        try
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "0000"),
            timer:sleep(100),
            ?assertEqual(locked, gen_statem:call(Name, get_state))
        after
            catch gen_statem:stop(Pid)
        end
    end.

%% Test 3: Three failed attempts trigger suspended state
suspended_after_three_failures_test_() ->
    fun() ->
        Name = unique_name(),
        {ok, Pid} = gen_statem:start_link({local, Name}, code_lock, "1234", []),
        try
            % First failed
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "0000"),
            timer:sleep(50),
            ?assertEqual(locked, gen_statem:call(Name, get_state)),
            % Second failed
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "1111"),
            timer:sleep(50),
            ?assertEqual(locked, gen_statem:call(Name, get_state)),
            % Third failed → suspended
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "2222"),
            timer:sleep(50),
            ?assertEqual(suspended, gen_statem:call(Name, get_state))
        after
            catch gen_statem:stop(Pid)
        end
    end.

%% Test 4: Button presses ignored in suspended state
suspended_ignores_buttons_test_() ->
    fun() ->
        Name = unique_name(),
        {ok, Pid} = gen_statem:start_link({local, Name}, code_lock, "1234", []),
        try
            % Trigger suspension
            lists:foreach(fun(_) -> 
                lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "0000"),
                timer:sleep(50)
            end, lists:seq(1, 3)),
            ?assertEqual(suspended, gen_statem:call(Name, get_state)),
            % Try correct code - should be ignored
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "1234"),
            timer:sleep(50),
            ?assertEqual(suspended, gen_statem:call(Name, get_state))
        after
            catch gen_statem:stop(Pid)
        end
    end.

%% Test 5: Change code in open state
change_code_test_() ->
    {timeout, ?TIMEOUT,
     fun() ->
        Name = unique_name(),
        {ok, Pid} = gen_statem:start_link({local, Name}, code_lock, "1234", []),
        try
            % Open with old code
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "1234"),
            timer:sleep(100),
            ?assertEqual(open, gen_statem:call(Name, get_state)),
            % Change code
            ?assertEqual(ok, gen_statem:call(Name, {change_code, "5678"})),
            % Auto-lock (wait 11 seconds)
            timer:sleep(11000),
            ?assertEqual(locked, gen_statem:call(Name, get_state)),
            % Old code fails
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "1234"),
            timer:sleep(50),
            ?assertEqual(locked, gen_statem:call(Name, get_state)),
            % New code works
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "5678"),
            timer:sleep(50),
            ?assertEqual(open, gen_statem:call(Name, get_state))
        after
            catch gen_statem:stop(Pid)
        end
     end}.

%% Test 6: Reset from suspended state
reset_from_suspended_test_() ->
    fun() ->
        Name = unique_name(),
        {ok, Pid} = gen_statem:start_link({local, Name}, code_lock, "1234", []),
        try
            % Trigger suspension
            lists:foreach(fun(_) -> 
                lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "0000"),
                timer:sleep(50)
            end, lists:seq(1, 3)),
            ?assertEqual(suspended, gen_statem:call(Name, get_state)),
            % Reset
            ?assertEqual(ok, gen_statem:call(Name, reset)),
            ?assertEqual(locked, gen_statem:call(Name, get_state)),
            % Correct code now works
            lists:foreach(fun(D) -> gen_statem:cast(Name, {button, D}) end, "1234"),
            timer:sleep(50),
            ?assertEqual(open, gen_statem:call(Name, get_state))
        after
            catch gen_statem:stop(Pid)
        end
    end.