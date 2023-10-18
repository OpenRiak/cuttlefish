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
%%
%% @doc Handles vm.args file values
%%
-module(cuttlefish_vmargs).

-export([stringify/1]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% @doc turns a proplist into a list of strings suitable for vm.args files
-spec stringify([{any(), string()}]) -> [string()].
stringify(VMArgsProplist) ->
    [ stringify_line(K, V) || {K, V} <- VMArgsProplist ].


stringify_line(K, V) when is_list(V) ->
  lists:flatten(io_lib:format("~ts ~ts", [K, V]));
stringify_line(K, V) ->
  lists:flatten(io_lib:format("~ts ~w", [K, V])).

-ifdef(TEST).

stringify_test() ->
    VMArgsProplist = [
      {'-name', "dev1@127.0.0.1"},
      {'-setcookie', 'riak'},
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
        "-setcookie riak",
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
    [ ?assertEqual(E, V) || {E, V} <- lists:zip(Expected, VMArgs)],
    ok.

-endif.
