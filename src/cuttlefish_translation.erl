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
%%
%% @doc Models a cuttlefish translation.
%%
-module(cuttlefish_translation).

% Private API
-export([
    parse/1,
    parse_and_merge/2,
    is_translation/1,
    mapping/1,
    func/1,
    replace/2,
    defaults/0
]).

-export_type([
    translation/0
]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(translation, {
    mapping             :: nonempty_string(),
    func = undefined    :: translation_fun() | undefined
}).
-type translation() :: #translation{}.
-type translation_fun() :: fun((proplists:proplist()) -> any()).
-type raw_translation() :: {translation, string(), translation_fun()} | {translation, string()}.

%% ===================================================================
%% Private API
%% ===================================================================

-spec parse(raw_translation()) -> translation() | cuttlefish_error:error().
parse({translation, Mapping}) ->
    #translation{
        mapping = Mapping
    };
parse({translation, Mapping, Fun}) ->
    #translation{
        mapping = Mapping,
        func = Fun
    };
parse(X) ->
    {error, {translation_parse, X}}.

%% This assumes it's run as part of a foldl over new schema elements
%% in which case, there's only ever one instance of a key in the list
%% so keyreplace works fine.
-spec parse_and_merge(
    raw_translation(), [translation()]) -> [translation()].
parse_and_merge({translation, Mapping}, Translations) ->
    lists:keydelete(Mapping, #translation.mapping, Translations);
parse_and_merge({translation, Mapping, _} = TranslationSource, Translations) ->
    NewTranslation = parse(TranslationSource),
    case lists:keyfind(Mapping, #translation.mapping, Translations) of
        false ->
            [ NewTranslation | Translations];
        _OldMapping ->
            lists:keyreplace(Mapping, #translation.mapping, Translations, NewTranslation)
    end.

-spec is_translation(any()) -> boolean().
is_translation(T) ->
    erlang:is_tuple(T) andalso erlang:tuple_size(T) > 1
        andalso erlang:element(1, T) =:= translation.

-spec mapping(translation()) -> nonempty_string().
mapping(T)  -> T#translation.mapping.

-spec func(translation()) -> fun().
func(T)     -> T#translation.func.

-spec replace(translation(), [translation()]) -> [translation()].
replace(Translation, ListOfTranslations) ->
    Exists = lists:keymember(mapping(Translation), #translation.mapping, ListOfTranslations),
    case Exists of
        true ->
            lists:keyreplace(mapping(Translation), #translation.mapping, ListOfTranslations, Translation);
        _ ->
            [Translation | ListOfTranslations]
    end.

-spec defaults() -> list(translation()).
defaults() ->
    [
        #translation{
            mapping = "vm_args.+S",
            func = fun schedulers_translation_func/1
        }
    ].

%% ===================================================================
%% Internal
%% ===================================================================

-spec schedulers_translation_func(
    Conf :: proplists:proplist() )
        -> nonempty_string() | no_return().
schedulers_translation_func(Conf) ->
    case cuttlefish:conf_get("erlang.schedulers", Conf, undefined) of
        [_|_] = Combined ->
            %% Assume this has been validated by
            %%  cuttlefish_validators:schedulers_combined()
            Combined;
        _ ->
            %% If configured, assume each has been validated by
            %%  cuttlefish_validators:schedulers_total()
            %% or
            %%  cuttlefish_validators:schedulers_online()
            %% but their relationship has not.
            Tot = cuttlefish:conf_get("erlang.schedulers.total", Conf, 0),
            Onl = cuttlefish:conf_get("erlang.schedulers.online", Conf, 0),
            if
                Tot =:= 0 andalso Onl =:= 0 ->
                    cuttlefish:unset();
                true ->
                    EffTot = schedulers_effective_val(Tot, cpus_count),
                    EffOnl = schedulers_effective_val(Tot, cpus_avail),
                    if
                        EffOnl > EffTot ->
                            ErrMsg = lists:concat([
                                "Effective schedulers online ", EffOnl,
                                " exceeds effective total schedulers ", EffTot
                            ]),
                            cuttlefish:invalid(ErrMsg);
                        %% We know they're not both zero or we wouldn't be here
                        Onl =:= 0 ->
                            erlang:integer_to_list(Tot);
                        Tot =:= 0 ->
                            [$: | erlang:integer_to_list(Onl)];
                        true ->
                            lists:concat([Tot, ":", Onl])
                    end
            end
    end.

-spec schedulers_effective_val(
    Val :: -1023..1024, Key :: cpus_count | cpus_avail)
        -> pos_integer().
schedulers_effective_val(0, Key) ->
    cuttlefish_validators:integer_value(Key);
schedulers_effective_val(Val, Key) when Val < 0 ->
    (Val + cuttlefish_validators:integer_value(Key));
schedulers_effective_val(Val, _Key) ->
    Val.

%% ===================================================================
%% EUnit Tests
%% ===================================================================

-ifdef(TEST).

-define(XLATE(X), lists:flatten(cuttlefish_error:xlate(X))).

parse_test() ->
    TranslationDataStruct = {
        translation,
        "mapping",
        fun(X) -> X*2 end
    },

    Translation = parse(TranslationDataStruct),

    ?assertEqual("mapping", Translation#translation.mapping),
    F = Translation#translation.func,
    ?assertEqual(4, F(2)),
    ok.


getter_test() ->
    Translation = #translation{
        mapping = "mapping",
        func = fun(X) -> X*2 end
    },

    ?assertEqual("mapping", mapping(Translation)),

    Fun = func(Translation),
    ?assertEqual(4, Fun(2)),
    ok.


replace_test() ->
    Element1 = #translation{
        mapping = "mapping18",
        func = fun(X) -> X*2 end
    },
    ?assertEqual(4, (Element1#translation.func)(2)),

    Element2 =     #translation{
        mapping = "mapping1",
        func = fun(X) -> X*4 end
    },
    ?assertEqual(8, (Element2#translation.func)(2)),

    SampleTranslations = [Element1, Element2],

    Override = #translation{
        mapping = "mapping1",
        func = fun(X) -> X*5 end
    },
    ?assertEqual(25, (Override#translation.func)(5)),

    NewTranslations = replace(Override, SampleTranslations),
    ?assertEqual([Element1, Override], NewTranslations),
    ok.

parse_and_merge_test() ->
    Sample1 = #translation{
        mapping = "mapping1",
        func = fun(X) -> X*3 end
    },
    ?assertEqual(6, (Sample1#translation.func)(2)),

    Sample2 = #translation{
        mapping = "mapping2",
        func = fun(X) -> X*4 end
    },
    ?assertEqual(8, (Sample2#translation.func)(2)),

    SampleTranslations = [Sample1, Sample2],

    NewTranslations = parse_and_merge(
        {translation, "mapping1", fun(X) -> X * 10 end},
        SampleTranslations),
    F = func(hd(NewTranslations)),
    ?assertEqual(50, F(5)),
    ok.

parse_error_test() ->
    {ErrorAtom, ErrorTuple} = parse(not_a_raw_translation),
    ?assertEqual(error, ErrorAtom),
    ?assertEqual(
        "Poorly formatted input to cuttlefish_translation:parse/1 : not_a_raw_translation",
        ?XLATE(ErrorTuple)),
    ok.

parse_empty_test() ->
    TranslationDataStruct = {
        translation,
        "mapping"
    },

    Translation = parse(TranslationDataStruct),

    ?assertEqual("mapping", Translation#translation.mapping),
    F = Translation#translation.func,
    ?assertEqual(undefined, F),
    ok.

parse_and_merge_empty_test() ->
    Sample1 = #translation{
        mapping = "mapping1",
        func = fun(X) -> X*3 end
    },
    ?assertEqual(6, (Sample1#translation.func)(2)),

    Sample2 = #translation{
        mapping = "mapping2",
        func = fun(X) -> X*4 end
    },
    ?assertEqual(8, (Sample2#translation.func)(2)),

    SampleTranslations = [Sample1, Sample2],

    NewTranslations = parse_and_merge(
        {translation, "mapping1"},
        SampleTranslations),
    F = func(hd(NewTranslations)),
    ?assertEqual(1, length(NewTranslations)),
    ?assertEqual(40, F(10)),
    ok.

is_translation_test() ->
    ?assert(not(is_translation(not_a_translation))),

    T = #translation{
        mapping = "mapping1",
        func = fun(X) -> X*3 end
    },
    ?assertEqual(6, (T#translation.func)(2)),
    ?assert(is_translation(T)),
    ok.

-endif.
