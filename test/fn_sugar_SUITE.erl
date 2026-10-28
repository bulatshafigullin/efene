-module(fn_sugar_SUITE).
-compile(export_all).

all() -> [comments, consts, guard_fns, fn_shorthand, default_arguments,
          interpolation, ok_err, with, with_else, try_bang, piped_match,
          map_access, multiple_arities, heredoc, map_update, with_guard, literal_interpolation,
          spec_sugar, map_types_and_empty_specs, reserved_words,
          try_operator, guard_stmt, defer_stmt, punning, lambda_shorthand, ranges_and_in,
          loop_recur, result_pipe, optional_chaining, pipe_placeholder, llm_guide_example, error_paths, formatter_keeps_meaning].

init_per_suite(Config) ->
    OutDir = filename:join(proplists:get_value(priv_dir, Config), "sugar"),
    ok = filelib:ensure_path(OutDir),
    true = code:add_patha(OutDir),
    Src = filename:join(proplists:get_value(data_dir, Config), "sugar.fn"),
    {ok, _} = efene:compile(Src, OutDir, []),
    [{src, Src} | Config].

end_per_suite(_Config) ->
    code:purge(sugar),
    code:delete(sugar),
    ok.

comments(_Config) ->
    "not ## a comment" = sugar:comment_in_string(),
    no = sugar:big(50 - 40 - 10).

consts(_Config) ->
    43200 = sugar:ttl().

guard_fns(_Config) ->
    yes = sugar:big(11),
    no = sugar:big(10).

fn_shorthand(_Config) ->
    8 = sugar:double(4),
    true = lists:member({clock, 0}, sugar:module_info(exports)),
    true = is_integer(sugar:clock_for_test()).

default_arguments(_Config) ->
    <<"hello, bob!">> = sugar:greet(<<"bob">>),
    <<"hi, bob!">> = sugar:greet(<<"bob">>, <<"hi">>),
    <<"hi, bob?">> = sugar:greet(<<"bob">>, <<"hi">>, <<"?">>).

interpolation(_Config) ->
    "n=3 f=1.5 a=abc" = sugar:greet_list(3),
    <<"literal #{x}">> = sugar:escaped().

ok_err(_Config) ->
    {ok, 1} = sugar:cfg(a),
    {error, nope} = sugar:cfg(b),
    {mine, 1} = sugar:own_ok(1).

with(_Config) ->
    2 = sugar:check(a, a),
    {error, nope} = sugar:check(a, b).

with_else(_Config) ->
    failed = sugar:check2(a, b),
    nope_found = sugar:check3(a, b),
    2 = sugar:check3(a, a).

try_bang(_Config) ->
    12 = sugar:safe(<<"12">>),
    -1 = sugar:safe(<<"x">>).

piped_match(_Config) ->
    3 = sugar:piped([1, 2, 3]),
    none = sugar:piped([]).

map_access(_Config) ->
    1 = sugar:get_id(#{id => 1}),
    <<"bob">> = sugar:get_deep(#{user => #{name => <<"bob">>}}),
    2 = sugar:get_key(#{<<"k">> => 2}, <<"k">>),
    nil = sugar:get_default(#{}),
    <<"x">> = sugar:get_default(#{<<"name">> => <<"x">>}),
    <<"bob">> = sugar:mixed(#{<<"user">> => #{name => <<"bob">>}}),
    {'EXIT', {{badkey, id}, _}} = (catch sugar:get_id(#{})),
    big = sugar:has_id(#{id => 2}),
    small = sugar:has_id(#{id => 1}).

multiple_arities(_Config) ->
    zero = sugar:arities(),
    {one, 1} = sugar:arities(1),
    {two, 1, 2} = sugar:arities(1, 2),
    {two_zero, 1} = sugar:arities(1, 0).

heredoc(_Config) ->
    "Hello bob,\n  indented \"quoted\"\nbye" = sugar:heredoc("bob"),
    <<"raw 'q'">> = sugar:heredoc_bin().

map_update(_Config) ->
    P = #{user => #{name => <<"x">>, id => 1}},
    #{name := <<"new">>, id := 1} = sugar:update_deep(P),
    #{a := 1} = sugar:update_var(P).

with_guard(_Config) ->
    big = sugar:with_guard({ok, 11}),
    small = sugar:with_guard({ok, 1}).

literal_interpolation(_Config) ->
    <<"1-2.5-abc">> = sugar:lits().

spec_sugar(_Config) ->
    {ok, 1} = sugar:spec_sugar(1).

map_types_and_empty_specs(Config) ->
    {ok, Forms} = efene:to_mod(proplists:get_value(src, Config)),
    [{type, _, map, [{type, _, map_field_exact, _}, _, _]}] =
        [T || {attribute, _, type, {user, T, []}} <- Forms],
    [_] = [S || {attribute, _, spec, {{no_args_spec, 0}, S}} <- Forms].

try_operator(_Config) ->
    6 = sugar:q1(3),
    {error, zero} = sugar:q1(0),
    done = sugar:q_bare(1),
    {error, zero} = sugar:q_bare(0).

guard_stmt(_Config) ->
    9 = sugar:g1(9),
    {error, nope} = sugar:g1(0),
    {error, small} = sugar:g1(2).

defer_stmt(_Config) ->
    T = ets:new(t, [public]),
    [{a, 1}] = sugar:d1(T),
    undefined = ets:info(T).

punning(_Config) ->
    #{id := 1, user_name := <<"bob">>} = sugar:pun(1, <<"bob">>),
    {1, 2} = sugar:pun_match(#{id => 1, user_name => 2}).

lambda_shorthand(_Config) ->
    [1, 4, 9, 16] = sugar:sq().

ranges_and_in(_Config) ->
    {true, false} = {sugar:in_test(2), sugar:in_test(9)},
    {true, false} = {sugar:in_range(5), sugar:in_range(11)},
    {yes, mid, no} = {sugar:in_guard(a), sugar:in_guard(7), sugar:in_guard(z)}.

loop_recur(_Config) ->
    [0, 1, 2] = sugar:lp().

result_pipe(_Config) ->
    {ok, 15} = sugar:rt(3),
    {error, zero} = sugar:rt(0),
    {error, boom} = sugar:rt2(3).

optional_chaining(_Config) ->
    {nil, nil, x, nil} = {sugar:opt_chain(nil), sugar:opt_chain(#{user => nil}),
                          sugar:opt_chain(#{user => #{name => x}}), sugar:opt_chain(#{})}.

pipe_placeholder(_Config) ->
    [1, 2, 3] = sugar:place(3).

llm_guide_example(Config) ->
    Out = filename:join(proplists:get_value(priv_dir, Config), "llm"),
    ok = filelib:ensure_path(Out),
    true = code:add_patha(Out),
    Src = filename:join(proplists:get_value(data_dir, Config), "llm_example.fn"),
    {ok, _} = efene:compile(Src, Out, []),
    {ok, #{id := 5}} = llm_example:parse(<<"5">>),
    {error, empty} = llm_example:parse(<<>>),
    {error, bad_id} = llm_example:parse(<<"x">>),
    [<<"item 3">>] = llm_example:names([<<"3">>, <<"20">>, <<"x">>]),
    10 = llm_example:sum_to(4).

reserved_words(_Config) ->
    {'def', 'cond', 'let', 'of', 'if'} = sugar:reserved_words().

error_paths(Config) ->
    Dir = filename:join(proplists:get_value(data_dir, Config), "bad"),
    lists:foreach(
      fun (File) ->
              Path = filename:join(Dir, File),
              case catch efene:to_mod(Path) of
                  {error, _} -> ok;
                  {error, _, _} -> ok;
                  Other -> ct:fail({File, expected_error, Other})
              end
      end, ["default_not_trailing.fn", "unterminated_interp.fn", "bad_interp_expr.fn",
            "bad_access.fn", "bad_access_args.fn", "undefined_const.fn",
            "question_in_args.fn", "bad_loop.fn", "assert_ct_fails.fn"]).

formatter_keeps_meaning(Config) ->
    Out = efene:to_efene(proplists:get_value(src, Config)),
    {match, _} = re:run(Out, "fn greet"),
    nomatch = re:run(Out, "with ").
