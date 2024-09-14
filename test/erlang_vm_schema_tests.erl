%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013-2017 Basho Technologies, Inc.
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

-module(erlang_vm_schema_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHOWVAR(V), io:format(user,
    "~n= = = = = ~ts:~b  ~ts:~n  ~tp.~n= = = = =~n", [?MODULE, ?LINE, ??V, V])).

%% basic schema test will check to make sure that all defaults from the schema
%% make it into the generated app.config
basic_schema_test() ->
    %% The defaults are defined in priv/erlang_vm.schema, the file under test.
    Config = cuttlefish_unit:generate_templated_config(
        [cuttlefish_test_util:priv_file("erlang_vm.schema")], [], context()),

    %% The only defaults set in the schema file
    cuttlefish_unit:assert_config(Config, "vm_args.-name", 'node@host'),
    cuttlefish_unit:assert_config(Config, "vm_args.-env ERL_CRASH_DUMP", "dump"),

    %% Following are listed in the schema file but don't have defaults that are
    %% written to app.config
    cuttlefish_unit:assert_not_configured(Config, "vm_args.-setcookie"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.-env ERL_FULLSWEEP_AFTER"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+a"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+A"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+B"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+c"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+C"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+e"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+pc"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+P"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+Q"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+S"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+SP"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+scl"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+sub"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+t"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+W"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+zdbbl"),
    cuttlefish_unit:assert_not_configured(Config, "kernel.inet_dist_listen_min"),
    cuttlefish_unit:assert_not_configured(Config, "kernel.inet_dist_listen_max"),
    cuttlefish_unit:assert_not_configured(Config, "kernel.inet_dist_use_interface"),
    cuttlefish_unit:assert_not_configured(Config, "kernel.net_ticktime"),

    %% Deprecated
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+sfwi"),

    %% Obsolete
    cuttlefish_unit:assert_not_configured(Config, "vm_args.-smp"),
    cuttlefish_unit:assert_not_configured(Config, "vm_args.+K"),
    ok.

override_schema_test() ->
    %% Conf represents the riak.conf file that would be read in by cuttlefish.
    %% This proplists is what would be output by the conf_parse module.
    Conf = [
        {["erlang", "warning_map"], "i"},
        {["erlang", "schedulers", "total"], 4},
        {["erlang", "schedulers", "online"], 4},
        {["nodename"], "mynode@myhost"},
        {["distributed_cookie"], "riak"},
        {["erlang", "async_threads"], 22},
        {["erlang", "async_threads", "stack_size"], 163840},
        {["erlang", "max_ports"], 32000},
        {["erlang", "fullsweep_after"], 1},
        {["erlang", "crash_dump"], "place"},
        {["erlang", "max_ets_tables"], 128000},
        {["erlang", "process_limit"], 128001},
        {["erlang", "distribution_buffer_size"], 1024},
        {["erlang", "schedulers", "force_wakeup_interval"], 500},
        {["erlang", "schedulers", "compaction_of_load"], true},
        {["erlang", "schedulers", "utilization_balancing"], false},
        {["erlang", "distribution", "port_range", "minimum"], 6000},
        {["erlang", "distribution", "port_range", "maximum"], 7999},
        {["erlang", "distribution", "net_ticktime"], 43}
    ],

    Config = cuttlefish_unit:generate_templated_config(
        [cuttlefish_test_util:priv_file("erlang_vm.schema")], Conf, context()),

    cuttlefish_unit:assert_config(Config, "vm_args.+W", 'i'),
    cuttlefish_unit:assert_config(Config, "vm_args.+S", "4:4"),
    cuttlefish_unit:assert_config(Config, "vm_args.-name", 'mynode@myhost'),
    cuttlefish_unit:assert_config(Config, "vm_args.-setcookie", 'riak'),
    cuttlefish_unit:assert_config(Config, "vm_args.+a", 163840),
    cuttlefish_unit:assert_config(Config, "vm_args.+A", 22),
    cuttlefish_unit:assert_config(Config, "vm_args.-env ERL_FULLSWEEP_AFTER", 1),
    cuttlefish_unit:assert_config(Config, "vm_args.-env ERL_CRASH_DUMP", "place"),
    cuttlefish_unit:assert_config(Config, "vm_args.+P", 128001),
    cuttlefish_unit:assert_config(Config, "vm_args.+zdbbl", 1),
    cuttlefish_unit:assert_config(Config, "vm_args.+sfwi", 500),
    cuttlefish_unit:assert_config(Config, "vm_args.+scl", 'true'),
    cuttlefish_unit:assert_config(Config, "vm_args.+sub", 'false'),
    cuttlefish_unit:assert_config(Config, "kernel.inet_dist_listen_min", 6000),
    cuttlefish_unit:assert_config(Config, "kernel.inet_dist_listen_max", 7999),
    cuttlefish_unit:assert_config(Config, "kernel.net_ticktime", 43),
    cuttlefish_unit:assert_config(Config, "vm_args.+Q", 32000),
    cuttlefish_unit:assert_config(Config, "vm_args.+e", 128000),
    ok.

erlang_scheduler_test() ->
    ErlVmSchema = cuttlefish_test_util:priv_file("erlang_vm.schema"),
    Conf1 = [
        {["erlang", "schedulers", "total"], 4},
        {["erlang", "schedulers", "online"], 1}
    ],
    Config1 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf1, context()),
    cuttlefish_unit:assert_config(Config1, "vm_args.+S", "4:1"),

    Conf2 = [
        {["erlang", "schedulers", "total"], 4}
    ],
    Config2 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf2, context()),
    cuttlefish_unit:assert_config(Config2, "vm_args.+S", "4"),

    Conf3 = [
        {["erlang", "schedulers", "online"], 4}
    ],
    Config3 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf3, context()),
    cuttlefish_unit:assert_config(Config3, "vm_args.+S", ":4"),

    Config4 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], [], context()),
    cuttlefish_unit:assert_not_configured(Config4, "vm_args.+S"),

    ok.

async_threads_stack_size_test() ->
    WordSize = erlang:system_info({wordsize, external}),
    TooSmall    = cuttlefish_bytesize:to_string(WordSize * 1024 * 10),
    TooLarge    = cuttlefish_bytesize:to_string(WordSize * 1024 * 9000),
    Indivisible = cuttlefish_bytesize:to_string(WordSize * 1024 * 16 - 2),
    Correct     = cuttlefish_bytesize:to_string(WordSize * 1024 * 32),
    MinSize     = cuttlefish_bytesize:to_string(WordSize * 1024 * 16),
    MaxSize     = cuttlefish_bytesize:to_string(WordSize * 1024 * 8192),
    CorrectRaw  = 32,
    ErlVmSchema = cuttlefish_test_util:priv_file("erlang_vm.schema"),

    Conf0 = [],
    Config0 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf0, context()),
    cuttlefish_unit:assert_not_configured(Config0, "vm_args.+a"),

    Conf1 = [{["erlang", "async_threads", "stack_size"], Correct}],
    Config1 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf1, context()),
    cuttlefish_unit:assert_config(Config1, "vm_args.+a", CorrectRaw),

    Conf2 = [{["erlang", "async_threads", "stack_size"], TooSmall}],
    Config2 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf2, context()),
    cuttlefish_unit:assert_error_message(Config2,
        "erlang.async_threads.stack_size invalid, must be in the range of "
        ++ MinSize ++ " to " ++ MaxSize),

    Conf3 = [{["erlang", "async_threads", "stack_size"], TooLarge}],
    Config3 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf3, context()),
    cuttlefish_unit:assert_error_message(Config3,
        "erlang.async_threads.stack_size invalid, must be in the range of "
        ++ MinSize ++ " to " ++ MaxSize),

    Conf4 = [{["erlang", "async_threads", "stack_size"], Indivisible}],
    Config4 = cuttlefish_unit:generate_templated_config(
        [ErlVmSchema], Conf4, context()),
    cuttlefish_unit:assert_error_message(Config4,
        "erlang.async_threads.stack_size invalid, must be divisible by "
        ++ integer_to_list(WordSize)),

    ok.

%% this context() represents the substitution variables that rebar
%% will use during the build process.  riak_core's schema file is
%% written with some {{mustache_vars}} for substitution during
%% packaging cuttlefish doesn't have a great time parsing those, so we
%% perform the substitutions first, because that's how it would work
%% in real life.
context() ->
    [
        {node, "node@host"},
        {crash_dump, "dump"}
    ].

inet_dist_use_interface_test() ->
    InputConfig = "erlang.distribution.interface",
    GeneratedConfig = "kernel.inet_dist_use_interface",
    InputConfigPoint = string:tokens(InputConfig, "."),
    ErlVmSchema = cuttlefish_test_util:priv_file("erlang_vm.schema"),

    Pass =[
        {"127.0.0.1",{127,0,0,1}},
        {"0.0.0.0",{0,0,0,0}},
        {"fe80:1200::1",{65152,4608,0,0,0,0,0,1}}
    ],
    Fail = [
        "127.0.0.1:8080",
        "127.1",
        "fe80:1200::g",
        "Not an IP"
    ],

    lists:foreach(fun({Input, Expected}) ->
                Config = cuttlefish_unit:generate_templated_config(
                    [ErlVmSchema], [{InputConfigPoint, Input}], context()),
                cuttlefish_unit:assert_config(Config, GeneratedConfig, Expected)
        end, Pass),
    lists:foreach(fun(Input) ->
                Config = cuttlefish_unit:generate_templated_config(
                    [ErlVmSchema], [{InputConfigPoint, Input}], context()),
                cuttlefish_unit:assert_error_message(Config,
                    InputConfig ++ " invalid, must be a valid IPv4 or IPv6 address")
        end, Fail).
