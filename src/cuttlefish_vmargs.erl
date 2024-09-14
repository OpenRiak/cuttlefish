%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013-2014 Basho Technologies, Inc.
%% Copyright (c) 2024 Workday, Inc.
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
%% @doc Handles vm.args file values
%%
-module(cuttlefish_vmargs).

-export([stringify/1]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% Originally spec'd as {any(), string()} but that seems maybe too loose for
%% keys and too narrow for values. The code as written would accept something
%% like the following, so that's what we're keeping going with.
-type kv_key() :: atom() | unicode:chardata().
-type kv_val() :: term().
-type kv_pair() :: {kv_key(), kv_val()}.

%% Originally spec'd as string(), but there's no need for result lines to be
%% flat lists - they can be any form of unicode:chardata() - but we can narrow
%% down the type a bit from that.
-type line() :: list(char() | string()).

%% @doc turns a proplist into a list of strings suitable for vm.args files
-spec stringify(list(kv_pair())) -> list(line()).
stringify([{K, V} | Props]) ->
    KStr = stringify_key(K),
    VStr = stringify_val(V),
    maybe_warn(KStr, VStr),
    Line = [KStr, $\s, VStr],
    [Line | stringify(Props)];
stringify([]) ->
    [].

%% Ensure atoms containing special characters ARE NOT quoted in keys,
%% but ARE quoted in values.
%% Keys MUST be flat lists for maybe_warn/2, values probably should be too
%% in case we check them at some point.

-spec stringify_key(Key :: kv_key()) -> string().
stringify_key(K) when erlang:is_list(K) ->
    stringify_list(K);
stringify_key(K) when erlang:is_atom(K) ->
    erlang:atom_to_list(K);
stringify_key(K) ->
    stringify_term(K).

-spec stringify_val(Val :: kv_val()) -> string().
stringify_val(V) when erlang:is_list(V) ->
    stringify_list(V);
stringify_val(V) ->
    stringify_term(V).

-spec stringify_list(List :: list(term())) -> string().
stringify_list(L) ->
    case io_lib:char_list(L) of
        true ->
            L;
        _ ->
            case io_lib:deep_char_list(L) of
                true ->
                    lists:flatten(L);
                _ ->
                    stringify_term(L)
            end
    end.

-spec stringify_term(Term :: term()) -> string().
stringify_term(T) ->
    %% lists:flatten/1 always allocates a new list, so only use it if needed.
    S = io_lib:format("~0tp", [T]),
    case io_lib:char_list(S) of
        true ->
            S;
        _ ->
            lists:flatten(S)
    end.

-spec maybe_warn(KeyStr :: string(), ValStr :: string()) -> ok.
maybe_warn("-setcookie", _) ->
    case os:getenv("CUTTLEFISH_NOWARN_COOKIE") of
        false ->
            cuttlefish:warn(
                <<"Inclusion of -setcookie in vm.args is discouraged."
                " Use a read-restricted ~/.erlang.cookie file instead.">>);
        _ ->
            ok
    end;
maybe_warn(_, _) ->
    ok.

-ifdef(TEST).

stringify_test() ->
    VMArgsProplist = [
      {'-name', "dev1@127.0.0.1"},
      {'-setcookie', 'Complex atom'},
      {'-smp', enable},
      {'+W',"w"},
      {'+K',"true"},
      {'+A',"64"},
      {'-env ERL_MAX_PORTS',"64000"},
      {'-env ERL_FULLSWEEP_AFTER',"0"},
      {'-env ERL_CRASH_DUMP',"./log/erl_crash.dump"},
      {'-env ERL_MAX_ETS_TABLES',"256000"},
      {'+P', "256000"},
      {'-kernel net_ticktime', "42"}
    ],

    VMArgs = stringify(VMArgsProplist),

    Expected = [
        "-name dev1@127.0.0.1",
        "-setcookie 'Complex atom'",
        "-smp enable",
        "+W w",
        "+K true",
        "+A 64",
        "-env ERL_MAX_PORTS 64000",
        "-env ERL_FULLSWEEP_AFTER 0",
        "-env ERL_CRASH_DUMP ./log/erl_crash.dump",
        "-env ERL_MAX_ETS_TABLES 256000",
        "+P 256000",
        "-kernel net_ticktime 42"
    ],
    [ ?assertEqual(E, lists:flatten(V)) || {E, V} <- lists:zip(Expected, VMArgs)],
    ok.

-endif.
