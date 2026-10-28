%% Copyright 2015 Mariano Guerra
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% compile time function execution: `#ct <expr>` is evaluated while compiling
%% and replaced by the literal value it returns.
%%
%% The #ct extension (fn_ext_val_atom_ct) leaves a holder in the erlang ast,
%% once the whole module is translated eval/3 compiles a temporary copy of the
%% module (so #ct expressions can call functions defined anywhere in it),
%% compiles and loads the efene modules the module uses that are found in the
%% import roots, evaluates each holder and replaces it with the result.
-module(fn_ct).
-export([holder/2, has_holders/1, strip/1, eval/3]).

-define(HOLDER(Line, Expr), {efene_ct, Line, Expr}).
% a holder in a pattern or guard, Kind is pattern or guard
-define(RESTRICTED(Line, Kind, Expr), {efene_ct_restricted, Line, Kind, Expr}).

holder(Line, Expr) -> ?HOLDER(Line, Expr).

has_holders(?HOLDER(_, _)) -> true;
has_holders(T) when is_tuple(T) -> has_holders(tuple_to_list(T));
has_holders([H|T]) -> has_holders(H) orelse has_holders(T);
has_holders(_) -> false.

% replace holders with the expression they hold, evaluating it at runtime
strip(?HOLDER(_Line, Expr)) -> strip(Expr);
strip(T) when is_tuple(T) -> list_to_tuple(strip(tuple_to_list(T)));
strip(L) when is_list(L) -> [strip(I) || I <- L];
strip(Other) -> Other.

% Opts: roots (import roots to look for efene modules), ct_loading (modules
% being loaded for compile time evaluation, to avoid loading cycles)
%
% Evaluation happens in two stages because a function call can't be placed in
% a pattern or a guard: first the #ct expressions in patterns and guards are
% evaluated with a temporary module where they are replaced by `_` (and `true`
% in guards), then the rest with a temporary module with the first ones
% already replaced by their values.
eval(Module, Forms, Opts) ->
    case has_holders(Forms) of
        false -> {ok, Forms};
        true ->
            Roots = maps:get(roots, Opts, []),
            Loading = maps:get(ct_loading, Opts, [Module]),
            case load_deps(strip(Forms), Roots, Loading) of
                ok ->
                    case eval_stage(Module, mark(Forms), restricted) of
                        {ok, Forms1} -> eval_stage(Module, Forms1, body);
                        Error -> Error
                    end;
                Error -> Error
            end
    end.

eval_stage(Module, Forms, Stage) ->
    case has_holders(Forms, Stage) of
        false -> {ok, Forms};
        true ->
            with_temp_module(Module, Forms,
                             fun (LocalFn) ->
                                     case replace(Forms, Stage, LocalFn, []) of
                                         {Forms1, []} -> {ok, Forms1};
                                         {_, Errors} ->
                                             errors(Module, lists:reverse(Errors))
                                     end
                             end)
    end.

has_holders(?HOLDER(_, _), body) -> true;
has_holders(?RESTRICTED(_, _, _), restricted) -> true;
has_holders(T, Stage) when is_tuple(T) -> has_holders(tuple_to_list(T), Stage);
has_holders([H|T], Stage) -> has_holders(H, Stage) orelse has_holders(T, Stage);
has_holders(_, _Stage) -> false.

% mark holders in patterns and guards as restricted
mark({clause, Line, Patterns, Guards, Body}) ->
    {clause, Line, restrict(Patterns, pattern), restrict(Guards, guard), mark(Body)};
mark({match, Line, Pattern, Expr}) ->
    {match, Line, restrict(Pattern, pattern), mark(Expr)};
mark({Gen, Line, Pattern, Expr}) when Gen == generate; Gen == b_generate ->
    {Gen, Line, restrict(Pattern, pattern), mark(Expr)};
mark(T) when is_tuple(T) -> list_to_tuple(mark(tuple_to_list(T)));
mark(L) when is_list(L) -> [mark(I) || I <- L];
mark(Other) -> Other.

restrict(?HOLDER(Line, Expr), Kind) -> ?RESTRICTED(Line, Kind, Expr);
restrict(T, Kind) when is_tuple(T) -> list_to_tuple(restrict(tuple_to_list(T), Kind));
restrict(L, Kind) when is_list(L) -> [restrict(I, Kind) || I <- L];
restrict(Other, _Kind) -> Other.

% the module with #ct expressions evaluated at runtime (or replaced by a
% placeholder in patterns and guards) and everything exported
with_temp_module(Module, Forms, Fun) ->
    TmpModule = list_to_atom("efene_ct$" ++ atom_to_list(Module)),
    case compile:forms(temp_module_forms(TmpModule, Forms), [binary, return_errors]) of
        {ok, TmpModule, Bin} ->
            {module, TmpModule} = code:load_binary(TmpModule, "efene_ct", Bin),
            try
                Fun(fun (Name, Args) -> apply(TmpModule, Name, Args) end)
            after
                code:purge(TmpModule),
                code:delete(TmpModule),
                code:purge(TmpModule)
            end;
        {error, Errors, _Warnings} ->
            {error, Errors, []}
    end.

temp_module_forms(TmpModule, Forms) ->
    Forms1 = [F || F <- for_temp(Forms), not is_skipped_in_temp(F)],
    Header = [{attribute, 1, module, TmpModule},
              {attribute, 1, compile, [export_all, nowarn_export_all]}],
    case Forms1 of
        [{attribute, _, file, _}=File|Rest] -> [File|Header ++ Rest];
        _ -> Header ++ Forms1
    end.

for_temp(?HOLDER(_Line, Expr)) -> strip(Expr);
for_temp(?RESTRICTED(Line, pattern, _Expr)) -> {var, Line, '_'};
for_temp(?RESTRICTED(Line, guard, _Expr)) -> {atom, Line, true};
for_temp(T) when is_tuple(T) -> list_to_tuple(for_temp(tuple_to_list(T)));
for_temp(L) when is_list(L) -> [for_temp(I) || I <- L];
for_temp(Other) -> Other.

is_skipped_in_temp({attribute, _, module, _}) -> true;
is_skipped_in_temp({attribute, _, export, _}) -> true;
is_skipped_in_temp({attribute, _, on_load, _}) -> true;
is_skipped_in_temp(_) -> false.

replace(?HOLDER(Line, Expr), body, LocalFn, Errors) ->
    replace_holder(Line, Expr, LocalFn, Errors);
replace(?RESTRICTED(Line, _Kind, Expr), restricted, LocalFn, Errors) ->
    replace_holder(Line, Expr, LocalFn, Errors);
replace(T, Stage, LocalFn, Errors) when is_tuple(T) ->
    {L, Errors1} = replace(tuple_to_list(T), Stage, LocalFn, Errors),
    {list_to_tuple(L), Errors1};
replace(L, Stage, LocalFn, Errors) when is_list(L) ->
    lists:mapfoldl(fun (I, Errs) -> replace(I, Stage, LocalFn, Errs) end, Errors, L);
replace(Other, _Stage, _LocalFn, Errors) ->
    {Other, Errors}.

replace_holder(Line, Expr, LocalFn, Errors) ->
    case eval_expr(strip(Expr), LocalFn) of
        {ok, Value} ->
            try erl_parse:abstract(Value, [{line, anno_line(Line)}]) of
                Ast -> {Ast, Errors}
            catch _:_ ->
                Msg = io_lib:format("#ct result can't be inserted in code: ~p", [Value]),
                {{atom, Line, error}, [{ct_error, Line, {message, Msg}}|Errors]}
            end;
        {error, Msg} ->
            {{atom, Line, error}, [{ct_error, Line, {message, Msg}}|Errors]}
    end.

eval_expr(Expr, LocalFn) ->
    try erl_eval:expr(Expr, erl_eval:new_bindings(), {value, LocalFn}) of
        {value, Value, _Bindings} -> {ok, Value}
    catch
        error:{Unbound, Var} when Unbound == unbound; Unbound == unbound_var ->
            {error, io_lib:format("#ct expression can't use variable ~s, "
                                  "it's only known at runtime", [Var])};
        error:undef:Stack ->
            undef_error(Stack);
        Class:Reason ->
            {error, io_lib:format("#ct evaluation failed: ~p:~p", [Class, Reason])}
    end.

undef_error([{Mod, Fun, Args, _}|_]) when is_atom(Mod) ->
    case code:is_loaded(Mod) of
        false ->
            {error, io_lib:format("#ct can't call ~s:~s/~p, module ~s isn't "
                                  "available at compile time (not found in the "
                                  "import roots or a circular #ct dependency)",
                                  [Mod, Fun, arity(Args), Mod])};
        _ ->
            {error, io_lib:format("#ct evaluation failed: undefined function ~s:~s/~p",
                                  [Mod, Fun, arity(Args)])}
    end;
undef_error(_Stack) ->
    {error, "#ct evaluation failed: error:undef"}.

arity(Args) when is_list(Args) -> length(Args);
arity(Arity) -> Arity.

anno_line(Line) when is_integer(Line) -> Line;
anno_line(Anno) -> erl_anno:line(Anno).

errors(Module, Errors) ->
    {error, {efene, Module, fn_error:to_string(Module, Errors)}}.

% compile and load the efene modules used by Forms that are found in the
% import roots (and the ones they use) so #ct expressions can call them.
% Sticky modules (kernel, stdlib...) are never replaced.
load_deps(Forms, Roots, Loading) ->
    Deps = [Dep || {Module, _Path}=Dep <- efene:find_imports(Forms, Roots),
                   not lists:member(Module, Loading),
                   not code:is_sticky(Module)],
    load_modules(Deps, Roots, Loading).

load_modules([], _Roots, _Loading) -> ok;
load_modules([{Module, Path}|T], Roots, Loading) ->
    case lists:member(Module, Loading) of
        true -> load_modules(T, Roots, Loading);
        false -> load_module(Module, Path, T, Roots, [Module|Loading])
    end.

load_module(Module, Path, T, Roots, Loading) ->
    case efene:to_mod(Path, #{module => Module, roots => Roots, ct_loading => Loading}) of
        {ok, Forms} ->
            case compile:forms(Forms, [binary, return_errors]) of
                {ok, Module, Bin} ->
                    {module, Module} = code:load_binary(Module, Path, Bin),
                    case load_deps(Forms, Roots, Loading) of
                        ok -> load_modules(T, Roots, Loading);
                        Error -> Error
                    end;
                {error, Errors, _Warnings} ->
                    {error, Errors, []}
            end;
        Other -> Other
    end.
