%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013-2014 Basho Technologies, Inc.
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

-module(cuttlefish_test_logging).

-behavior(gen_event).

%% API
-export([start_link/0, add_handler/0]).
-export([set_up/0, log/2, reset/0, get_logs/0, bounce/0, bounce/1]).

%% gen_event callbacks
-export([init/1,
         handle_call/2,
         handle_event/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include_lib("kernel/include/logger.hrl").

-define(SERVER, ?MODULE).

%% holds the log messages for retrieval
-record(state, {
    logs :: list(string() | binary())
}).

%%
%% API
%%

set_up() ->
    Pid = case start_link() of
        {ok, Pid0}                       -> Pid0;
        {error, {already_started, Pid1}} -> Pid1
    end,
    case lists:member(?MODULE, gen_event:which_handlers(Pid)) of
        true -> ok;
        false ->
            gen_event:add_handler(Pid, ?MODULE, [])
    end,
    ok.

-spec get_logs() -> [iolist()] | {error, term()}.
get_logs() ->
    gen_event:call(?SERVER, ?MODULE, get_logs, infinity).

bounce() ->
    bounce(error).

bounce(Level) ->
    gen_event:call(?SERVER, ?MODULE, reset),
    logger:remove_handler(?MODULE),
    logger:add_handler(?SERVER, ?MODULE, #{
        level => Level
    }),
    ok.

start_link() ->
    gen_event:start_link({local, ?SERVER}).

log(LogEvent, Config) ->
    gen_event:call(?SERVER, ?MODULE, {log, LogEvent, Config}).

reset() ->
    gen_event:call(?SERVER, ?MODULE, reset).


add_handler() ->
    gen_event:add_handler(?SERVER, ?MODULE, []).

%%
%% Callbacks
%%

-spec(init(integer()|atom()|[term()]) -> {ok, #state{}} | {error, atom()}).
%% @private
%% @doc Initializes the event handler
init([]) ->
    {ok, #state{
        logs = []
    }}.

-spec(handle_event(tuple(), #state{}) -> {ok, #state{}}).
%% @private
%% @doc handles the event, adding the log message to the gen_event's state.
handle_event(Event, #state{logs = Logs} = State) ->
    {ok, State#state{logs = [Event | Logs]}};
handle_event(_Event, State) ->
    {ok, State}.

-spec(handle_call(any(), #state{}) -> {ok, any(), #state{}}).
%% @private
%% @doc Adds and retrieves logs.
handle_call({log, LogEvent, LogConfig}, #state{logs = Logs0} = State) ->
    #{formatter := {FModule, FConfig}} = LogConfig,
    %% [Time, " ", LevelStr, Message]
    Log = FModule:format(LogEvent, FConfig),
    Logs = [Log | Logs0],
    {ok, ok, State#state{logs = Logs}};
handle_call(get_logs, #state{logs = Logs} = State) ->
    {ok, lists:reverse(Logs), State};
handle_call(reset, State) ->
    {ok, ok, State#state{logs = []}};
handle_call(_, State) ->
    {ok, ok, State}.

-spec(handle_info(any(), #state{}) -> {ok, #state{}}).
%% @private
%% @doc gen_event callback, does nothing.
handle_info(_, State) ->
    {ok, State}.

-spec(code_change(any(), #state{}, any()) -> {ok, #state{}}).
%% @private
%% @doc gen_event callback, does nothing.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec(terminate(any(), #state{}) -> ok).
%% @doc gen_event callback, does nothing.
terminate(_Reason, #state{}) ->
    ok.
