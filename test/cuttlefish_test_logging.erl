%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013-2014 Basho Technologies, Inc.
%% Copyright (c) 2023-2024 Workday, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%%
-module(cuttlefish_test_logging).
-behavior(gen_server).
-if(OTP_RELEASE >= 27).
-behavior(logger_handler).
-endif.

%% API
-export([
    get_logs/0,
    get_level/0, set_level/1,
    reset/0, reset/1,
    start/0, start/1, stop/0,
    start_link/0, start_link/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    terminate/2
]).

%% logger_handler callbacks
-export([
    log/2
]).

-ifdef(TEST).
-export([
    logger_test_/0
]).
-endif.


-include_lib("kernel/include/logger.hrl").
-ifdef(TEST).
-include_lib("stdlib/include/assert.hrl").
-endif.

-define(SERVER, ?MODULE).
-define(HANDLER_ID, ?MODULE).
-define(FILTER_ID, ?MODULE).
-define(DEFAULT_LEVEL, error).
-define(VALID_LEVELS, [
    emergency, alert, critical, error,
    warning, notice, info, debug,
    all, none
]).
-define(HANDLER_CONFIG(Level), #{
    level => Level,
    filters => [{?FILTER_ID, {fun module_filter/2, ?MODULE}}]
}).

-type level() :: logger:level() | all | none.
-type log() :: unicode:chardata().
-type logs() :: list(log()).
-type state() :: logs().

-if(OTP_RELEASE < 27).
% Deprecated types
-type handler_config() :: logger:handler_config().
-else.
% Have logger_handler behavior module
-type handler_config() :: logger_handler:config().
-endif.

%% ===================================================================
%% API
%% ===================================================================

-spec start() -> ok | {error, term()}.
%% @doc Ensure that the service is running.
%%
%% If not already running, it is started at the default logging level.
%% If already running, the log history is cleared.
start() ->
    case start_link() of
        {ok, _} ->
            gen_server:call(?SERVER, ?FUNCTION_NAME);
        {error, {already_started, _}} ->
            reset();
        Error ->
            Error
    end.

-spec start(Level :: logger:level()) -> ok | {error, term()}.
%% @doc Ensure that the service is running at the specified logging Level.
%% If already running, the log history is cleared.
start(Level) ->
    case start_link(Level) of
        {ok, _} ->
            gen_server:call(?SERVER, ?FUNCTION_NAME);
        {error, {already_started, _}} ->
            reset(Level);
        Error ->
            Error
    end.

-spec stop() -> ok.
%% @doc Ensure that the service is not running.
stop() ->
    case erlang:whereis(?SERVER) of
        undefined ->
            set_level(none);
        Pid ->
            gen_server:stop(Pid)
    end.

-spec get_level() -> level().
%% @doc Retrieves the handler's current log level.
get_level() ->
    gen_server:call(?SERVER, ?FUNCTION_NAME).

-spec set_level(Level :: level()) -> level().
%% @doc Sets the handler's current log level.
%%
%% Does NOT clear logs; to change level AND clear logs, use {@link reset/1}.
set_level(Level) ->
    gen_server:call(?SERVER, {?FUNCTION_NAME, check_level(Level)}).

-spec get_logs() -> logs() | {error, term()}.
%% @doc Retrieves the recorded logs.
get_logs() ->
    gen_server:call(?SERVER, ?FUNCTION_NAME).

-spec start_link() -> {ok, pid()} | {error, term()}.
%% @doc Starts the service at the default logging level.
start_link() ->
    start_link(?DEFAULT_LEVEL).

-spec start_link(Level :: level()) -> {ok, pid()} | {error, term()}.
%% @doc Starts the service at the specified logging level.
start_link(Level) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, check_level(Level), []).

-spec reset() -> ok | {error, term()}.
%% @doc Clears all recorded logs.
reset() ->
    gen_server:call(?SERVER, ?FUNCTION_NAME).

-spec reset(Level :: level()) -> ok | {error, term()}.
%% @doc Clears all recorded logs and sets the logging level to Level.
%%
%% To change the logging level without clearing logs use {@link set_level/1}.
reset(Level) ->
    gen_server:call(?SERVER, {?FUNCTION_NAME, check_level(Level)}).

%% ===================================================================
%% Callbacks
%% ===================================================================

-spec log(
    LogEvent :: logger:log_event(), HConfig :: handler_config()) -> ok.
%% @private
%% @doc logger_handler callback; records LogEvent.
%%
%% LogEvent is formatted in the calling process then stored in the service.
%%
%% The returned term is ignored.
log(LogEvent, #{formatter := {FModule, FConfig}}) ->
    gen_server:cast(?SERVER,
        {?FUNCTION_NAME, FModule:format(LogEvent, FConfig)}).

-spec init(Level :: level()) -> {ok, state()}.
%% @private
%% @doc gen_server callback; initializes the handler.
init(Level) ->
    set_handler_level(Level),
    {ok, []}.

-spec handle_call(
    Msg :: term(), From :: gen_server:from(), State :: state())
        -> {reply, term(), state()}.
%% @private
%% @doc gen_server callback; retrieves or resets logs.
handle_call(get_level, _From, Logs) ->
    Result = case logger:get_handler_config(?HANDLER_ID) of
        {ok, #{level := Level}} ->
            Level;
        {error, Reason} = Error ->
            Reason == {not_found, ?HANDLER_ID} orelse
                ?LOG_ERROR("Unexpected error reason: ~0tp", [Error]),
            none
    end,
    {reply, Result, Logs};
handle_call(get_logs, _From, Logs) ->
    {reply, lists:reverse(Logs), Logs};
handle_call(reset, _From, _Logs) ->
    {reply, ok, []};
handle_call({reset, Level}, _From, _Logs) ->
    {reply, set_handler_level(Level), []};
handle_call({set_level, Level}, _From, Logs) ->
    {reply, set_handler_level(Level), Logs};
handle_call(start, _From, State) ->
    % Internal, ensures that init/1 has completed
    {reply, ok, State};
handle_call(Msg, _From, State) ->
    ?LOG_WARNING("Unhandled: ~0tp", [Msg]),
    {reply, {ignored, Msg}, State}.

-spec handle_cast(Msg :: term(), State :: state()) -> {noreply, state()}.
%% @private
%% @doc gen_server callback; adds a log message.
handle_cast({log, Log}, Logs) ->
    {noreply, [Log | Logs]};
handle_cast(Msg, State) ->
    ?LOG_WARNING("Unhandled: ~0tp", [Msg]),
    {noreply, State}.

-spec terminate(Reason :: term(), State :: state()) -> term().
%% @private
%% @doc gen_server callback; disconnects the handler.
%%
%% The returned term is ignored.
terminate(_Reason, _State) ->
    set_handler_level(none).

%% ===================================================================
%% Internal
%% ===================================================================

-spec check_level(Level :: level()) -> level().
%% @hidden
%% @doc Confirms Level validity.
check_level(Level) ->
    case lists:member(Level, ?VALID_LEVELS) of
        true ->
            Level;
        _ ->
            erlang:error(badarg, [Level])
    end.

-spec set_handler_level(Level :: level()) -> ok.
%% @hidden
%% @doc Ensures the handler is active at the specified level.
set_handler_level(none) ->
    _ = logger:remove_handler(?HANDLER_ID),
    ok;
set_handler_level(Level) ->
    case logger:get_handler_config(?HANDLER_ID) of
        {ok, #{level := Level}} ->
            ok;
        {ok, _Config} ->
            ok = logger:set_handler_config(?HANDLER_ID, level, Level);
        {error, Reason} = Error ->
            Reason == {not_found, ?HANDLER_ID} orelse
                ?LOG_ERROR("Unexpected error reason: ~0tp", [Error]),
            ok = logger:add_handler(
                ?HANDLER_ID, ?MODULE, ?HANDLER_CONFIG(Level))
    end.

-spec module_filter(
    LogEvent :: logger:log_event(), ?MODULE) -> logger:filter_return().
%% @hidden
%% @doc Filters out log events from this module.
module_filter(#{meta := #{mfa := {?MODULE, _, _}}}, ?MODULE) ->
    stop;
module_filter(_LogEvent, _Module) ->
    ignore.

%% ===================================================================
%% EUnit Tests
%% ===================================================================
-ifdef(TEST).

logger_test_() ->
    #{level := PLevel} = logger:get_primary_config(),
    {ok, #{level := DLevel}} = logger:get_handler_config(default),
    Setup = fun() ->
        ok = logger:set_primary_config(level, all),
        ok = logger:set_handler_config(default, level, notice)
    end,
    Cleanup = fun(_) ->
        ok = logger:set_primary_config(level, PLevel),
        ok = logger:set_handler_config(default, level, DLevel),
        _ = case erlang:whereis(?SERVER) of
            undefined = R ->
                R;
            Pid ->
                gen_server:stop(Pid)
        end,
        _ = logger:remove_handler(?HANDLER_ID),
        ok
    end,
    {foreach, Setup, Cleanup, [
        fun test_start_stop/0,
        fun test_filter/0,
        fun test_level/0,
        fun test_reset/0
    ]}.

test_start_stop() ->
    ?assertMatch({ok, P} when erlang:is_pid(P), ?MODULE:start_link()),
    ?assertMatch(?DEFAULT_LEVEL, ?MODULE:get_level()),
    ?assertMatch(ok, ?MODULE:stop()),
    ?assertMatch(undefined, erlang:whereis(?SERVER)),
    ?assertMatch(
        {error, {not_found, ?HANDLER_ID}},
        logger:remove_handler(?HANDLER_ID) ),
    ?assertMatch(ok, ?MODULE:start()),
    Pid = erlang:whereis(?SERVER),
    ?assertMatch(true, erlang:is_pid(Pid)),
    ?assertMatch(?DEFAULT_LEVEL, ?MODULE:get_level()),
    ?assertMatch(ok, ?MODULE:start(alert)),
    ?assertMatch(Pid, erlang:whereis(?SERVER)),
    ?assertMatch(alert, ?MODULE:get_level()),
    ?assertMatch(ok, ?MODULE:stop()).

test_filter() ->
    % Ensure logs from this module don't get recorded, but others do
    mute_default_log(),
    ?assertMatch(ok, ?MODULE:start()),
    ?assertMatch([], ?MODULE:get_logs()),
    ?assertMatch(ok, logger:log(?DEFAULT_LEVEL, "No metadata ~b", [?LINE])),
    Res1 = ?MODULE:get_logs(),
    ?assertMatch([ [_|_] ], Res1),
    [Log1] = Res1,
    ?assertNotMatch(nomatch, string:find(Log1, "No metadata")),
    ?LOG_ALERT("From this module"),
    Meta2 = #{mfa => {other_module, ?FUNCTION_NAME, ?FUNCTION_ARITY}},
    ?LOG_ALERT("Other metadata ~b", [?LINE], Meta2),
    Res2 = ?MODULE:get_logs(),
    ?assertMatch([Log1, [_|_] ], Res2),
    [_, Log2] = Res2,
    ?assertNotMatch(nomatch, string:find(Log2, "Other metadata")).

test_level() ->
    ?assertError(badarg, ?MODULE:set_level(bogus)),

    ?assertMatch(ok, ?MODULE:start()),
    ?assertMatch(?DEFAULT_LEVEL, ?MODULE:get_level()),
    ?assertMatch(
        {ok, #{level := ?DEFAULT_LEVEL}},
        logger:get_handler_config(?HANDLER_ID)),
    ?assertMatch(ok, ?MODULE:set_level(none)),
    ?assertMatch(none, ?MODULE:get_level()),
    ?assertMatch(
        {error, {not_found, ?HANDLER_ID}},
        logger:get_handler_config(?HANDLER_ID)),
    ?assertMatch(ok, ?MODULE:start(notice)),
    ?assertMatch(notice, ?MODULE:get_level()),
    ?assertMatch(
        {ok, #{level := notice}},
        logger:get_handler_config(?HANDLER_ID)),

    mute_default_log(),
    Meta = #{mfa => {other_module, ?FUNCTION_NAME, ?FUNCTION_ARITY}},
    ?LOG_ERROR("Error message ~b", [?LINE], Meta),
    Logs1 = ?MODULE:get_logs(),
    ?assertMatch([ [_|_] ], Logs1),
    [Log1] = Logs1,
    ?assertNotMatch(nomatch, string:find(Log1, "Error message")),
    ?LOG_INFO("Info message ~b", [?LINE], Meta),
    ?assertMatch(Logs1, ?MODULE:get_logs()).

test_reset() ->
    ?assertMatch(ok, ?MODULE:start(debug)),
    mute_default_log(),
    Meta = #{mfa => {other_module, ?FUNCTION_NAME, ?FUNCTION_ARITY}},
    timer:sleep(100),
    ?LOG_INFO("Info message ~b", [?LINE], Meta),
    ?LOG_WARNING("Warning message ~b", [?LINE], Meta),
    ?LOG_ERROR("Error message ~b", [?LINE], Meta),
    timer:sleep(100),
    ?assertMatch([ [_|_], [_|_], [_|_] ], ?MODULE:get_logs()),
    ?assertMatch(ok, ?MODULE:reset()),
    ?assertMatch(debug, ?MODULE:get_level()),
    ?assertMatch([], ?MODULE:get_logs()),
    ?LOG_INFO("Info message ~b", [?LINE], Meta),
    ?LOG_WARNING("Warning message ~b", [?LINE], Meta),
    ?LOG_ERROR("Error message ~b", [?LINE], Meta),
    ?assertMatch([ [_|_], [_|_], [_|_] ], ?MODULE:get_logs()),
    ?assertMatch(ok, ?MODULE:reset(error)),
    ?assertMatch(error, ?MODULE:get_level()),
    ?assertMatch([], ?MODULE:get_logs()),
    ?LOG_INFO("Info message ~b", [?LINE], Meta),
    ?LOG_WARNING("Warning message ~b", [?LINE], Meta),
    ?LOG_ERROR("Error message ~b", [?LINE], Meta),
    ?assertMatch([ [_|_] ], ?MODULE:get_logs()).

mute_default_log() ->
    ?assertMatch(ok, logger:set_handler_config(default, level, none)).

-endif. % TEST
