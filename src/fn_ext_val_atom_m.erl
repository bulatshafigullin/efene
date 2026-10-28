-module(fn_ext_val_atom_m).
-export([handle/3]).

-behaviour(fn_exts).

-include("efene.hrl").

% #m <var> defined with @const(<var>) -> expr
handle(_Path, ?Var(_Line, MacroName), #{consts := Consts}=State)
  when is_map_key(MacroName, Consts) ->
    fn_to_erl:ast_to_ast(maps:get(MacroName, Consts), State);
% #m <var>
handle(_Path, ?Var(Line, MacroName), State) ->
    expand_macro(Line, State, MacroName, []);
% #m <var>(args..)
handle(_Path, ?E(Line, call, {[?Var(MacroName)], Args}), State) ->
    expand_macro(Line, State, MacroName, Args);
handle(_Path, _Ast, _State) ->
    next.

expand_macro(Line, #{macros := Macros}=State, MacroName, Args) ->
    {EArgs, State1} = fn_to_erl:ast_to_ast(Args, State),
    case fn_erl_macro:call_macro(Macros, MacroName, EArgs) of
        {ok, [Ast]} ->
            {Ast, State1};
        {error, Reason} ->
            State2 = fn_to_erl:add_error(State1, macro_error, Line, Reason),
            {{atom, Line, error}, State2}
    end.

