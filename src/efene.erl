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

-module(efene).
-export([main/0, main/1, compile/2, compile/3, to_code/1, to_code/2,
         to_raw_lex/1, to_lex/1, to_ast/1,
         to_erl/1, to_efene/1, erl_to_erl_syntax/1, to_erl_ast/1, to_erl_ast/2,
         to_mod/1, to_mod/2, module_path/2, find_imports/2,
         pprint/1, print_errors/2]).

-export([str_to_ast/1]).

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Content} -> {ok, unicode:characters_to_list(Content, utf8)};
        Other -> Other
    end.

with_file_content(Path, Fn) ->
    case read_file(Path) of
        {ok, Content} -> Fn(Content);
        Other -> Other
    end.

to_raw_lex(Path) -> with_file_content(Path, fun str_to_raw_lex/1).
to_lex(Path)     -> with_file_content(Path, fun str_to_lex/1).
to_ast(Path)     -> with_file_content(Path, fun str_to_ast/1).
to_erl_ast(Path) -> to_erl_ast(Path, #{}).
to_erl_ast(Path, Opts) ->
    with_file_content(Path, fun (Str) -> str_to_erl_ast(Str, Path, Opts) end).

to_mod(Path) ->
    to_mod(Path, #{}).

% Opts can have the module name under the module key, the default is the
% file name without extension, and the import roots under roots, used to find
% modules called by #ct expressions, the default is the directory of Path.
% With ct => keep #ct expressions are not evaluated (used by the formatter)
to_mod(Path, Opts) ->
    case to_mod_forms(Path, Opts) of
        {ok, Forms} ->
            case maps:get(ct, Opts, eval) of
                keep -> {ok, Forms};
                eval ->
                    Module = maps:get(module, Opts, get_module_name(Path)),
                    Roots = maps:get(roots, Opts, [filename:dirname(filename:absname(Path))]),
                    fn_ct:eval(Module, Forms, Opts#{roots => Roots})
            end;
        Other -> Other
    end.

to_mod_forms(Path, Opts) ->
    case to_erl_ast(Path, Opts) of
        {ok, {Ast, State}} ->
            ModAtomName = maps:get(module, Opts, get_module_name(Path)),
            ToMod = fun () ->
                            ExportAttr = fn_util:get_export_attr_ast(State),
                            FnAttrs = fn_util:get_fn_attribute(State),
                            ModAttr = {attribute, 1, module, ModAtomName},
                            FileAttr = {attribute, 1, file, {Path, 1}},
                            FilteredFnAttrs = remove_emptish_fn_attrs(FnAttrs, []),
                            case ExportAttr of
                                {attribute, _ExportLine, export, []} ->
                                    {ok, [FileAttr, ModAttr|(FilteredFnAttrs ++ Ast)]};
                                _ ->
                                    {ok, [FileAttr, ModAttr, ExportAttr|(FilteredFnAttrs ++ Ast)]}
                            end
                    end,
            print_warnings(State),
            format_errors_or(ModAtomName, State, ToMod);
        Other -> Other
    end.

pprint(Path) ->
    case from_erl(Path) of
        {ok, Ast} -> 
            try
                io:format("~s~n", [fn_pp:format(Ast)])
            catch T:E:S ->
                io:format("Error formatting ~p: ~p:~p~n~p~n", [Path, T, E, S])
            end;
        Other -> io:format("Error: ~p~n", [Other])
    end.

to_erl(Path) ->
    case to_mod(Path) of
        {ok, [_|Mod]} -> erl_prettypr:format(erl_syntax:form_list(Mod));
        Other -> Other
    end.

% pretty print efene source <file.fn> back as efene source
to_efene(Path) ->
    case to_mod(Path, #{ct => keep}) of
        {ok, [_|Mod]} -> fn_pp:format(Mod);
        Other -> Other
    end.

erl_to_erl_syntax(Path) ->
    {ok, Forms} = epp_dodger:parse_file(Path, [no_fail]),
    Comments = erl_comment_scan:file(Path),
    Forms1 = erl_recomment:recomment_forms(Forms, Comments),
    {ok, Forms1}.

to_code(Path) ->
    to_code(Path, []).

to_code(Path, Opts) ->
    {_Roots, CompileOpts} = split_efene_opts(Opts),
    case to_mod(Path) of
        {ok, Ast} -> forms_to_code(Ast, CompileOpts);
        Other -> Other
    end.

forms_to_code(Ast, Opts) ->
            case compile:forms(Ast, [return, strong_validation|Opts]) of
                {error, _Errors, _Warnings}=Error -> Error;
                error -> {error, [{error, compile_forms_error}], []};
                {ok, _ModuleName0, ValidationInfo} ->
                    Warnings0 = case ValidationInfo of
                        [] -> [];
                        [{_FileName0, W0}] -> W0
                    end,
                    case compile:forms(Ast, Opts) of
                        {ok, ModuleName, Code} -> {ok, ModuleName, Code, Warnings0};
                        {ok, ModuleName, Code, Warnings} ->
                            {ok, ModuleName, Code, Warnings0 ++ Warnings};
                        error -> {error, [{error, compile_forms_error}], []};
                        {error, _Errors, _Warnings}=Error -> Error
                    end
            end.

compile(Path, DestPath) ->
    compile(Path, DestPath, []).

% Compiles Path and every efene module it uses, like python imports: a call
% to foo.bar.baz() or a reference fn foo.bar.baz:0 looks for foo/bar.fn in
% the import roots and compiles it as the module 'foo.bar'. The first root is
% the directory of Path, more roots can be added with {roots, [Dir]} in Opts.
% Modules not found in any root are left alone (erlang modules like lists).
% Path is always compiled as the module named after its file.
% module_name is the module for Path, modules lists all the compiled modules.
compile(Path, DestPath, Opts) ->
    {ExtraRoots, CompileOpts} = split_efene_opts(Opts),
    Roots = [filename:dirname(filename:absname(Path))
             | [filename:absname(Root) || Root <- ExtraRoots]],
    Queue = [{get_module_name(Path), Path}],
    compile_modules(Queue, Roots, DestPath, CompileOpts, #{}, [], []).

compile_modules([], _Roots, _DestPath, _Opts, _Seen, Names, Warnings) ->
    [ModuleName|_] = AllNames = lists:reverse(Names),
    {ok, [{warnings, Warnings}, {module_name, ModuleName}, {modules, AllNames}]};
compile_modules([{Module, _Path}|T], Roots, DestPath, Opts, Seen, Names, Warnings)
  when is_map_key(Module, Seen) ->
    compile_modules(T, Roots, DestPath, Opts, Seen, Names, Warnings);
compile_modules([{Module, Path}|T], Roots, DestPath, Opts, Seen, Names, Warnings) ->
    case to_mod(Path, #{module => Module, roots => Roots}) of
        {ok, Forms} ->
            case forms_to_code(Forms, Opts) of
                {ok, ModuleName, Code, ModWarnings} ->
                    BeamPath = filename:join(DestPath, atom_to_list(ModuleName) ++ ".beam"),
                    case bin_to_file(Code, BeamPath) of
                        ok ->
                            Deps = find_imports(Forms, Roots),
                            compile_modules(T ++ Deps, Roots, DestPath, Opts,
                                            Seen#{Module => Path}, [ModuleName|Names],
                                            Warnings ++ ModWarnings);
                        _ ->
                            {error, [{file_write_error, BeamPath}], []}
                    end;
                Other -> Other
            end;
        Other -> Other
    end.

% efene specific options are removed before calling compile:forms
split_efene_opts(Opts) ->
    Roots = lists:append([Dirs || {roots, Dirs} <- Opts]),
    {Roots, [Opt || Opt <- Opts, not is_efene_opt(Opt)]}.

is_efene_opt({roots, _}) -> true;
is_efene_opt(_) -> false.

% relative path to the file of Module inside an import root, 'foo.bar' is
% foo/bar.fn
module_path(Root, Module) ->
    Parts = string:split(atom_to_list(Module), ".", all),
    filename:join([Root|Parts]) ++ ".fn".

find_imports(Forms, Roots) ->
    Modules = lists:usort(used_modules(Forms, [])),
    lists:filtermap(fun (Module) ->
                            case find_module(Module, Roots) of
                                {ok, Path} -> {true, {Module, Path}};
                                notfound -> false
                            end
                    end, Modules).

find_module(_Module, []) -> notfound;
find_module(Module, [Root|Roots]) ->
    Path = module_path(Root, Module),
    case filelib:is_regular(Path) of
        true -> {ok, Path};
        false -> find_module(Module, Roots)
    end.

% modules referenced by remote calls (mod:fun()) and function references
% (fun mod:fun/1) with a literal module name
used_modules({remote, _, {atom, _, Module}, Fun}, Accum) ->
    used_modules(Fun, [Module|Accum]);
used_modules({'fun', _, {function, {atom, _, Module}, _, _}}, Accum) ->
    [Module|Accum];
used_modules({attribute, _, import, {Module, _Funs}}, Accum) ->
    [Module|Accum];
used_modules(T, Accum) when is_tuple(T) ->
    used_modules(tuple_to_list(T), Accum);
used_modules([H|T], Accum) ->
    used_modules(T, used_modules(H, Accum));
used_modules(_, Accum) ->
    Accum.

from_erl(Path) -> epp:parse_file(Path, [], []).

str_to_raw_lex(String) -> fn_lexer:string(String).

str_to_lex(String) ->
    try fn_lexer:string(String) of
        {ok, Tokens, Endline} ->
            CleanTokens = clean_tokens(Tokens),
            {ok, CleanTokens, Endline};
        {eof, Endline} -> {error, {Endline, fn_lexer, {eof, Endline}}};
        {error, Error} -> {error, Error};
        {error, Error, _} -> {error, Error}
    catch
        throw:{error, Reason} ->
            {error, Reason}
    end.

str_to_ast(Str) ->
    case str_to_lex(Str) of
        {ok, Tokens, _NewLine} -> fn_parser:parse(Tokens);
        Other -> Other
    end.

% to force escriptize to load the default extension modules
force_extensions_load() ->
    fn_ext_expr_atom_b:handle(nil, nil, nil),
    fn_ext_expr_var__:handle(nil, nil, nil),
    fn_ext_val_atom_atom:handle(nil, nil, nil),
    fn_ext_val_atom_b:handle(nil, nil, nil),
    fn_ext_val_atom_c:handle(nil, nil, nil),
    fn_ext_val_atom_ct:handle(nil, nil, nil),
    fn_ext_val_atom_i:handle(nil, nil, nil),
    fn_ext_val_atom_m:handle(nil, nil, nil),
    fn_ext_val_atom_r:handle(nil, nil, nil),
    fn_ext_val_var__:handle(nil, nil, nil).

str_to_erl_ast(String, Path, Opts) ->
    Module = maps:get(module, Opts, get_module_name(Path)),
    force_extensions_load(),
    case str_to_ast(String) of
        {ok, Ast} -> {ok, fn_to_erl:to_erl(Ast, Module, Path, Opts)};
        Other -> Other
    end.

% cli utilities

print({ok, Data}) ->
    print(Data);
print({error, _}=Error) ->
    Reason = fn_error:normalize(Error),
    io:format("error:~s~n", [Reason]);
print(Data) ->
    try io:format("~s~n", [Data]) catch
        _:_ -> io:format("~p~n", [Data])
    end.

% command line interface

main() ->
    main([]).

main([]) ->
    io:format("Usage:~n"),
    io:format("\tefene rawlex <file>: print raw lex tokens~n"),
    io:format("\tefene lex <file>: print lex tokens after normalization~n"),
    io:format("\tefene ast <file>: print efene abstract syntax tree~n"),
    io:format("\tefene erlast <file>: print erlang abstract syntax tree (absform)~n"),
    io:format("\tefene mod <file>: print erlang absform with module attributes~n"),
    io:format("\tefene erl <file>: print erlang code for <file>~n"),
    io:format("\tefene erl2ast <file.erl>: print erlang absform <file.erl>~n"),
    io:format("\tefene erl2erl <file.erl>: parse and pretty print erlang <file.erl>~n"),
    io:format("\tefene beam [--root <dir>]... <file> [<outdir>]: compile <file> and the efene modules it uses~n"),
    io:format("\t\tto beam bytecode to <outdir>, modules are looked up in the directory of <file>~n"),
    io:format("\t\tand then in each --root <dir> (or -r <dir>), foo.bar.baz() uses <root>/foo/bar.fn~n"),
    io:format("\tefene fmt <file.fn>: pretty print efene source <file.fn> as efene~n"),
    io:format("\tefene fmt-erlang <file.erl>: pretty print erlang <file.erl> as efene~n"),
    ok;
main(["rawlex", File]) ->
    print(to_raw_lex(File));
main(["lex", File]) ->
    print(to_lex(File));
main(["ast", File]) ->
    print(to_ast(File));
main(["mod", File]) ->
    print(to_mod(File));
main(["erlast", File]) ->
    print(to_erl_ast(File));
main(["erl", File]) ->
    print(to_erl(File));
main(["fmt", File]) ->
    print(to_efene(File));
main(["erl2syntax", File]) ->
    print(erl_to_erl_syntax(File));
main(["erl2ast", File]) ->
    print(from_erl(File));
main(["erl2erl", File]) ->
    {ok, Ast} = from_erl(File),
    print(erl_prettypr:format(erl_syntax:form_list(Ast)));
main(["shell"]) ->
    user_drv:start(["tty_sl -c -e", {fn_repl, start, []}]);
main(["beam"|Args]) ->
    case parse_root_flags(Args, [], []) of
        {Roots, [File]} -> compile_cli(File, ".", Roots);
        {Roots, [File, OutputDir]} -> compile_cli(File, OutputDir, Roots);
        _ ->
            io:format("Invalid arguments: \"~p\"~n", [["beam"|Args]]),
            main([])
    end;
main(["fmt-erlang", File]) ->
    pprint(File);
% deprecated alias for fmt-erlang
main(["pprint", File]) ->
    pprint(File);
main(Opts) ->
    io:format("Invalid arguments: \"~p\"~n", [Opts]),
    main([]).

% private

compile_cli(File, OutputDir, Roots) ->
    case compile(File, OutputDir, [debug_info, {roots, Roots}]) of
        {ok, CompileInfo} ->
            print_errors(proplists:get_value(warnings, CompileInfo, []), "warnings");
        {error, Errors, Warnings} ->
            print_errors(Errors, "errors"),
            print_errors(Warnings, "warnings"),
            ok;
        Other ->
            print(Other)
    end.

parse_root_flags([], Roots, Positional) ->
    {lists:reverse(Roots), lists:reverse(Positional)};
parse_root_flags([Flag, Dir|T], Roots, Positional)
  when Flag == "-r" orelse Flag == "--root" ->
    parse_root_flags(T, [Dir|Roots], Positional);
parse_root_flags([H|T], Roots, Positional) ->
    parse_root_flags(T, Roots, [H|Positional]).

clean_tokens(Tokens) -> clean_tokens(Tokens, []).

clean_tokens([], Accum) -> lists:reverse(Accum);
% remove newline after colon, comma and semicolon
clean_tokens([{colon, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{semicolon, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{sep, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline after logical ops
clean_tokens([{bool_or, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bool_orr, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bool_xor, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bool_and, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bool_andd, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline after ops
clean_tokens([{add_op, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{mul_op, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{comp_op, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{concat_op, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{send_op, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bin_shift, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bin_and, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{bin_or, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{assign, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{coloneq, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{cons_op, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline after open [ ( and {
clean_tokens([{open, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{open_list, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{open_map, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline after arrows
clean_tokens([{arrow, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{fatarrow, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {fatarrow, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{arrowend, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{larrow, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{larrowend, _, _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline after try, catch, after, receive, begin, when
clean_tokens([{'try', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'catch', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'after', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'receive', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'begin', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'when', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'fn', _}=H, {nl, _, _}|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{'fn', _}=H1, {var, _, _}=H2, {nl, _, _}|T], Accum) -> clean_tokens([H1, H2|T], Accum);
clean_tokens([{'fn', _}=H1, {atom, _, _}=H2, {nl, _, _}|T], Accum) -> clean_tokens([H1, H2|T], Accum);

clean_tokens([{'def', _}=H1, {atom, _, _}=H2, {nl, _, _}|T], Accum) -> clean_tokens([H1, H2|T], Accum);

% remove newline before end and @
clean_tokens([{nl, _, _}, {'end', _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {'case', _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {'else', _}=H|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline before closing ] ) and }
clean_tokens([{nl, _, _}, {close, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {close_list, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {close_map, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
% remove newline before arrows
clean_tokens([{nl, _, _}, {arrow, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {arrowend, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {larrow, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
clean_tokens([{nl, _, _}, {larrowend, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
% remove duplicated endlines
clean_tokens([{nl, _, _}, {nl, _, _}=H|T], Accum) -> clean_tokens([H|T], Accum);
% remove last endline
clean_tokens([{nl, _, _}], Accum) -> clean_tokens([], Accum);
clean_tokens([H|T], Accum) -> clean_tokens(T, [H|Accum]).

get_module_str_name(Path) ->
    BaseName = filename:basename(Path),
    filename:rootname(BaseName).

get_module_name(Path) ->
    list_to_atom(get_module_str_name(Path)).

bin_to_file(Bin, Path) ->
    to_file(Bin, Path, [binary, write]).

to_file(Data, Path, Mode) ->
    case file:open(Path, Mode) of
        {ok, Device} ->
            file:write(Device, Data),
            file:close(Device),
            ok;
        Error -> Error
    end.

print_warning(Warn) ->
    io:format("warning:~s~n", [fn_error:normalize_warning(Warn)]).

print_warnings(#{warnings := Warns}) ->
    lists:foreach(fun print_warning/1, Warns),
    ok.

format_errors_or(_Module, #{errors:=[]}, Fn) -> Fn();
format_errors_or(Module, #{errors:=Errors}, _Fn) ->
    ErrorsFirstToLast = lists:reverse(Errors),
    {error, {efene, Module, fn_error:to_string(Module, ErrorsFirstToLast)}}.

% remove fn attributes that only contain public, private or no attributes
remove_emptish_fn_attrs([], Accum) ->
    lists:reverse(Accum);
remove_emptish_fn_attrs([{attribute, _ALine, fn_attrs, {_FName, _FArity, []}}|T], Accum) ->
    remove_emptish_fn_attrs(T, Accum);
remove_emptish_fn_attrs([{attribute, _ALine, fn_attrs, {_FName, _FArity, [{[Visibility], {[], []}}]}}|T], Accum)
  when Visibility == public; Visibility == private ->
    remove_emptish_fn_attrs(T, Accum);
remove_emptish_fn_attrs([H|T], Accum) ->
    remove_emptish_fn_attrs(T, [H|Accum]).

print_errors([], _Prefix) -> ok;
print_errors(Errors, Prefix) ->
    lists:foreach(fun (Error) ->
                          Reason = fn_error:normalize(Error),
                          io:format("~s:~n~s~n", [Prefix, Reason])
                  end, Errors).
