-module(fn_module_SUITE).
-compile(export_all).

all() -> [compiles_used_modules_from_file_dir, extra_roots,
          compiled_file_is_named_after_file, variable_in_module_path_is_an_error,
          functions_are_public_by_default, imports_nested_modules].

init_per_testcase(_Case, Config) ->
    OutDir = filename:join(proplists:get_value(priv_dir, Config),
                           integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(OutDir),
    true = code:add_patha(OutDir),
    [{out_dir, OutDir} | Config].

end_per_testcase(_Case, Config) ->
    OutDir = proplists:get_value(out_dir, Config),
    [begin code:purge(M), code:delete(M) end
     || M <- [main, imports, shapes, 'shapes.geo.point', 'text.upper']],
    code:del_path(OutDir),
    Config.

data_path(Config, Name) ->
    filename:join(proplists:get_value(data_dir, Config), Name).

compile(Config, Name, Opts) ->
    efene:compile(data_path(Config, Name), proplists:get_value(out_dir, Config), Opts).

compiles_used_modules_from_file_dir(Config) ->
    {ok, Info} = compile(Config, "proj/main.fn", []),
    main = proplists:get_value(module_name, Info),
    % text.upper is not found without extra roots so it's left as an
    % external module
    [main, shapes, 'shapes.geo.point'] = proplists:get_value(modules, Info),
    OutDir = proplists:get_value(out_dir, Config),
    true = filelib:is_regular(filename:join(OutDir, "shapes.geo.point.beam")),
    {4, {point, 1, 2, 1, 'shapes.geo.point'}, [2, 1], main} = main:main().

extra_roots(Config) ->
    Roots = [data_path(Config, "libs")],
    {ok, Info} = compile(Config, "proj/main.fn", [{roots, Roots}]),
    [main, shapes, 'shapes.geo.point', 'text.upper'] = proplists:get_value(modules, Info),
    "HI" = main:upper("hi").

compiled_file_is_named_after_file(Config) ->
    {ok, Info} = compile(Config, "proj/shapes/geo/point.fn", []),
    [point] = proplists:get_value(modules, Info).

variable_in_module_path_is_an_error(Config) ->
    {error, {efene, bad_path, [Msg]}} = efene:to_mod(data_path(Config, "bad_path.fn")),
    {match, _} = re:run(Msg, "invalid_module_path").

functions_are_public_by_default(Config) ->
    {ok, Forms} = efene:to_mod(data_path(Config, "vis.fn")),
    [Exports] = [E || {attribute, _, export, E} <- Forms],
    [{old_style, 0}, {plain, 0}] = lists:sort(Exports),
    Fmt = efene:to_efene(data_path(Config, "vis.fn")),
    {match, _} = re:run(Fmt, "fn helper @private"),
    nomatch = re:run(Fmt, "@public").

imports_nested_modules(Config) ->
    {ok, Info} = compile(Config, "proj/imports.fn", []),
    % only imported (and called through a variable), still compiled
    [imports, 'shapes.geo.point', shapes] = proplists:get_value(modules, Info),
    {{point, 1, 2, 1, 'shapes.geo.point'}, {point, 3, 4, 9, 'shapes.geo.point'},
     'shapes.geo.point'} = imports:main().
