-module(fn_ext_val_atom_ct).
-export([handle/3]).

-behaviour(fn_exts).

-include("efene.hrl").

% #ct <expr>, evaluated at compile time, see fn_ct
handle(_Path, Ast, #{level := Level}=State) when is_tuple(Ast), Level > 0 ->
    {EAst, State1} = fn_to_erl:ast_to_ast(Ast, State),
    {fn_ct:holder(element(2, Ast), EAst), State1};
handle(_Path, Ast, #{level := 0}=State) when is_tuple(Ast) ->
    Line = element(2, Ast),
    State1 = fn_to_erl:add_error(State, ct_error, Line,
                                 {message, "#ct can only be used inside functions"}),
    {{atom, Line, error}, State1};
handle(_Path, _Ast, _State) ->
    next.
