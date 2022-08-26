%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 Basho Technologies, Inc.
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

-module(cuttlefish_nested_schema_test).

-include_lib("eunit/include/eunit.hrl").

nested_schema_test() ->
    Conf = [
        {["thing", "a"], foo},
        {["nested", "thing1", "type"], "thing"},
        {["nested", "thing1", "thing", "a"], 0},
        {["nested", "thing2", "type"], "thing"}
    ],
    Config = cuttlefish_generator:map(schema(), Conf),
    ?assertEqual(
        [{thing, [{a, foo}]},
         {nested_things, [{thing, [{a, 0}]}, {thing, [{a, 5}]}]}],
         Config
        ),
    ok.

schema() ->
    Mappings = [
        {mapping, "thing.a", "thing.a", [
            {datatype, [{atom, foo}, integer]},
            {default, 5}
        ]},
        {mapping, "nested.$name.type", "nested_things", [
            {datatype, {enum, [thing]}}
        ]},
        {mapping, "nested.$name.thing.a", "nested_things", [
            {datatype, [{atom, foo}, integer]},
            {default, 5}
        ]}
    ],
    Translations = [
        {translation, "nested_things",
        fun(Conf, Schema) ->
            NestedNames = cuttlefish_variable:fuzzy_matches(["nested","$name","type"], Conf),
            Things = [ begin
                ConfigName = ["nested", Name],
                Prefix = ConfigName ++ ["thing"],
                SubConf = [ begin
                    {Key -- ConfigName, Value}
                end || {Key, Value} <- cuttlefish_variable:filter_by_prefix(Prefix, Conf)],

                Proplist = cuttlefish_generator:map(Schema, SubConf),
                case cuttlefish_error:is_error(Proplist) of
                    true -> cuttlefish:invalid("gtfo");
                    _ -> {thing, proplists:get_value(thing, Proplist)}
                end
            end|| {"$name", Name} <- NestedNames],
            case Things of
                [] -> cuttlefish:unset();
                _ -> Things
            end
        end}
    ],
    {
        [ cuttlefish_translation:parse(T) || T <- Translations],
        [ cuttlefish_mapping:parse(M) || M <- Mappings],
        []}.
