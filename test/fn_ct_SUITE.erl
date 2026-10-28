-module(fn_ct_SUITE).
-compile(export_all).

all() -> [evaluates_at_compile_time, ct_in_patterns, ct_only_modules_are_not_compiled,
          fmt_keeps_ct, reports_errors, only_inside_functions].

init_per_suite(Config) ->
    OutDir = filename:join(proplists:get_value(priv_dir, Config), "ebin"),
    ok = filelib:ensure_path(OutDir),
    {ok, Info} = efene:compile(data_path(Config, "ctmain.fn"), OutDir),
    true = code:add_patha(OutDir),
    [{out_dir, OutDir}, {compile_info, Info} | Config].

end_per_suite(Config) ->
    code:del_path(proplists:get_value(out_dir, Config)),
    Config.

data_path(Config, Name) ->
    filename:join(proplists:get_value(data_dir, Config), Name).

erl_code(Config, Name) ->
    lists:flatten(efene:to_erl(data_path(Config, Name))).

evaluates_at_compile_time(Config) ->
    [1, 4, 9, 16, 25] = ctmain:table(),
    3628800 = ctmain:fact_10(),
    [2, 3, 5, 7, 11, 13, 17, 19, 23, 29] = ctmain:primes(),
    {ctmain, 3, "text"} = ctmain:built(),
    14 = ctmain:nested(),
    % the value is in the code, not a call
    Erl = erl_code(Config, "ctmain.fn"),
    {match, _} = re:run(Erl, "fact_10\\(\\) -> 3628800\\."),
    nomatch = re:run(Erl, "fact_10\\(\\) -> fact").

ct_in_patterns(Config) ->
    true = ctmain:is_answer(6),
    false = ctmain:is_answer(7),
    {match, _} = re:run(erl_code(Config, "ctmain.fn"), "is_answer\\(6\\) -> true").

ct_only_modules_are_not_compiled(Config) ->
    [ctmain] = proplists:get_value(modules, proplists:get_value(compile_info, Config)).

fmt_keeps_ct(Config) ->
    Fmt = efene:to_efene(data_path(Config, "ctmain.fn")),
    {match, _} = re:run(Fmt, "#ct fact\\(10\\)"),
    {match, _} = re:run(Fmt, "#ct lists.sum\\(#ct squares\\(3\\)\\)").

reports_errors(Config) ->
    {error, {efene, errs, [Var, Raise, Fun]}} = efene:to_mod(data_path(Config, "errs.fn")),
    {match, _} = re:run(Var, "can't use variable X"),
    {match, _} = re:run(Raise, "kaboom"),
    {match, _} = re:run(Fun, "can't be inserted").

only_inside_functions(Config) ->
    {error, {efene, toplevel, [Msg]}} = efene:to_mod(data_path(Config, "toplevel.fn")),
    {match, _} = re:run(Msg, "only be used inside functions").
