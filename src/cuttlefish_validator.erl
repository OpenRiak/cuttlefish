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
%% @doc models a cuttlefish validator
%%
-module(cuttlefish_validator).

-export([
    parse/1,
    parse_and_merge/2,
    is_validator/1,
    name/1,
    description/1,
    func/1,
    replace/2
]).

-export_type([validator/0]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(validator, {
    name :: validator_name(),
    description :: validator_desc(),
    func :: validator_fun()
}).
-type validator() :: #validator{}.
-type validator_desc() :: nonempty_string().
-type validator_fun() :: fun((any()) -> boolean()).
-type validator_name() :: nonempty_string().

-type validator_tag() :: validator.
-type fun_args() :: list().
-type fun_name() :: atom().
-type raw_validator() ::
    {validator_tag(), string(), string(), validator_fun()} |
    {validator_tag(), fun_name(), fun_args()} | {validator_tag(), fun_name()}.

-spec parse(raw_validator()) -> validator() | cuttlefish_error:error().
parse({validator, [_|_] = Name, [_|_] = Description, Fun})
        when erlang:is_function(Fun, 1) ->
    #validator{
        name = Name,
        description = Description,
        func = Fun
    };
parse({validator, FunName}) when erlang:is_atom(FunName) ->
    parse({validator, FunName, []});
parse({validator, FunName, FunArgs}) when
        erlang:is_atom(FunName) andalso erlang:is_list(FunArgs) ->
    try
        parse(erlang:apply(cuttlefish_validators, FunName, FunArgs))
    catch
        error:undef ->
            {error, {validator_parse,
                {undefined, {cuttlefish_validators, FunName, FunArgs}}}}
    end;
parse(X) ->
    {error, {validator_parse, X}}.

%% This assumes it's run as part of a foldl over new schema elements
%% in which case, there's only ever one instance of a key in the list
%% so keyreplace works fine.
-spec parse_and_merge(
    raw_validator(), [validator()]) -> [validator()|cuttlefish_error:error()].
parse_and_merge(ValidatorSource, Validators) ->
    case parse(ValidatorSource) of
        #validator{name = ValidatorName} = NewValidator ->
            case lists:keyfind(ValidatorName, #validator.name, Validators) of
                false ->
                    [NewValidator | Validators];
                _OldMapping ->
                    lists:keyreplace(ValidatorName, #validator.name, Validators, NewValidator)
            end;
        Error ->
            [Error | Validators]
    end.

-spec is_validator(any()) -> boolean().
is_validator(V) ->
    erlang:is_tuple(V) andalso erlang:tuple_size(V) > 1
        andalso erlang:element(1, V) =:= validator.

-spec name(validator()) -> validator_name().
name(#validator{name = N}) -> N.

-spec description(validator()) -> validator_desc().
description(#validator{description = D}) -> D.

-spec func(validator()) -> validator_fun().
func(#validator{func = F}) -> F.

-spec replace(validator(), [validator()]) -> [validator()].
replace(Validator, ListOfValidators) ->
    Exists = lists:keymember(name(Validator), #validator.name, ListOfValidators),
    case Exists of
        true ->
            lists:keyreplace(name(Validator), #validator.name, ListOfValidators, Validator);
        _ ->
            [Validator | ListOfValidators]
    end.

-ifdef(TEST).

-define(XLATE(X), lists:flatten(cuttlefish_error:xlate(X))).

parse_test() ->
    ValidatorDataStruct = {
        validator,
        "name",
        "description",
        fun(X) -> X*2 end
    },

    Validator = parse(ValidatorDataStruct),

    ?assertEqual("name", Validator#validator.name),
    ?assertEqual("description", Validator#validator.description),
    F = Validator#validator.func,
    ?assertEqual(4, F(2)),
    ok.


getter_test() ->
    Validator = #validator{
        name = "name",
        description = "description",
        func = fun(X) -> X*2 end
    },

    ?assertEqual("name", name(Validator)),
    ?assertEqual("description", description(Validator)),

    Fun = func(Validator),
    ?assertEqual(4, Fun(2)),
    ok.


replace_test() ->
    Element1 = #validator{
        name = "name18",
        description = "description18",
        func = fun(X) -> X*2 end
    },
    ?assertEqual(4, (Element1#validator.func)(2)),

    Element2 = #validator{
        name = "name1",
        description = "description1",
        func = fun(X) -> X*4 end
    },
    ?assertEqual(8, (Element2#validator.func)(2)),

    SampleValidators = [Element1, Element2],

    Override = #validator{
        name = "name1",
        description = "description1",
        func = fun(X) -> X*5 end
    },
    ?assertEqual(25, (Override#validator.func)(5)),

    NewValidators = replace(Override, SampleValidators),
    ?assertEqual([Element1, Override], NewValidators),
    ok.

remove_duplicates_test() ->
    Sample1 = #validator{
        name = "name1",
        description = "description1",
        func = fun(X) -> X*3 end
    },
    ?assertEqual(6, (Sample1#validator.func)(2)),

    Sample2 = #validator{
        name = "name1",
        description = "description1",
        func = fun(X) -> X*4 end
    },
    ?assertEqual(8, (Sample2#validator.func)(2)),

    SampleValidators = [Sample1, Sample2],

    [NewValidator|_] = parse_and_merge(
        {validator, "name1", "description2", fun(X) -> X*10 end},
        SampleValidators),
    F = func(NewValidator),
    ?assertEqual(50, F(5)),
    ?assertEqual("description2", description(NewValidator)),
    ?assertEqual("name1", name(NewValidator)),
    ok.

parse_error_test() ->
    {ErrorAtom, ErrorTerm} = parse(not_a_raw_validator),
    ?assertEqual(error, ErrorAtom),
    ?assertEqual(
        "Poorly formatted input to cuttlefish_validator:parse/1 : not_a_raw_validator",
        ?XLATE(ErrorTerm)),
    ok.

is_validator_test() ->
    ?assert(not(is_validator(not_a_validator))),

    V = #validator{
        name = "name1",
        description = "description1",
        func = fun(X) -> X*4 end
    },
    ?assertEqual(8, (V#validator.func)(2)),
    ?assert(is_validator(V)),
    ok.

-endif.
