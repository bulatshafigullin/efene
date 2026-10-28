-module(fn_sugar_SUITE).
-compile(export_all).

all() -> [comments, consts, guard_fns, fn_shorthand, default_arguments,
          interpolation, ok_err, with, with_else, try_bang, piped_match,
          map_access, multiple_arities, error_paths, formatter_keeps_meaning].

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
    false = lists:member({clock, 0}, sugar:module_info(exports)),
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
            "bad_access.fn", "bad_access_args.fn", "undefined_const.fn"]).

formatter_keeps_meaning(Config) ->
    Out = efene:to_efene(proplists:get_value(src, Config)),
    {match, _} = re:run(Out, "fn greet"),
    nomatch = re:run(Out, "with ").
