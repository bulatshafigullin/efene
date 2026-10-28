-module(fn_pp_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1,
         values/1, cons/1, tuple/1, map/1, ops/1, exprs/1,
         e_case/1,

         guards/1
        ]).

-define(CmpExprs(FnVar, ErlVar, FnName), begin
                                             {FnVar, ErlVar} = format_ast_node_cmp_expr(Config, FnName),
                                             FnVar= ErlVar
                                         end).
-define(AstNode(FnName), format_ast_node(Config, FnName)).

all() -> [values, cons, tuple, map, ops, exprs, guards, e_case].

init_per_suite(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    Path = filename:join(DataDir, "ppi.erl"),
    {ok, Ast0} = epp:parse_file(Path, [], []),
    Ast = erl_syntax:form_list(Ast0),
    [{ast, Ast} | Config].

end_per_suite(Config) ->
    Config.

get_ast(Config) -> 
    proplists:get_value(ast, Config).

get_ast_node(Config, FnName) ->
    {_,_, _, RootList} = get_ast(Config),
    % something like: {function,3,v_n_1,0,[{clause,3,[],[],[{integer,3,42}]}]}
    [{_, _, _, _, [{_, _, _, _, Body}]}] = [Node || Node <- RootList, element(1, Node) == function, element(3, Node) == FnName],
    Body.

format_ast_node(Config, FnName) ->
    [AstNode] = get_ast_node(Config, FnName),
    Layout = fn_pp:layout(AstNode),
    ct:pal("~p", [AstNode]),
    ct:pal("~p", [Layout]),
    Code = prettypr:format(Layout),
    ct:pal("~s", [Code]),
    Code.

format_ast_node_cmp_expr(Config, FnName) ->
    [AstNode] = get_ast_node(Config, FnName),
    FnCode = fn_pp:format(AstNode),
    ErlCode = lists:flatten(erl_pp:expr(AstNode)),
    ct:pal("~s | ~s", [FnCode, ErlCode]),
    {FnCode, ErlCode}.

values(Config) ->
    "42" = ?AstNode(v_int),

    "Asd" = ?AstNode(v_var),

    "#c \"A\"" = ?AstNode(v_char),

    "#c \"\\\"\"" = ?AstNode(v_char_quote),

    "true" = ?AstNode(v_true),
    "false" = ?AstNode(v_false),

    "an_atom" = ?AstNode(v_atom),

    "`an atom`" = ?AstNode(v_atom_space),
    "`an \\`atom\\``" = ?AstNode(v_atom_quote),

    "`after`" = ?AstNode(v_atom_after),
    "`begin`" = ?AstNode(v_atom_begin),
    "`case`" = ?AstNode(v_atom_case),
    "`catch`" = ?AstNode(v_atom_catch),
    "`do`" = ?AstNode(v_atom_do),
    "`else`" = ?AstNode(v_atom_else),
    "`end`" = ?AstNode(v_atom_end),
    "`fn`" = ?AstNode(v_atom_fn),
    "`for`" = ?AstNode(v_atom_for),
    "`if`" = ?AstNode(v_atom_if),
    "`in`" = ?AstNode(v_atom_in),
    "`match`" = ?AstNode(v_atom_match),
    "`receive`" = ?AstNode(v_atom_receive),
    "`try`" = ?AstNode(v_atom_try),
    "`when`" = ?AstNode(v_atom_when),
    "def" = ?AstNode(v_atom_def),
    "`cond`" = ?AstNode(v_atom_cond),
    "`let`" = ?AstNode(v_atom_let),
    "`of`" = ?AstNode(v_atom_of),

    "\"\"" = ?AstNode(v_string_empty),
    "\"hello world!\"" = ?AstNode(v_string_simple),
    "\"hello \\\"world\\\"!\"" = ?AstNode(v_string_quote),
    "\"\\thello world!\\n\"" = ?AstNode(v_string_escapes),

    "''" = ?AstNode(v_bstring_empty),
    "'hello world!'" = ?AstNode(v_bstring_simple),
    "'hello \\'world\\'!'" = ?AstNode(v_bstring_quote),
    "'\\thello world!\\n'" = ?AstNode(v_bstring_escapes),

    "42.5" = ?AstNode(v_float).

cons(Config) ->
    "[]" = ?AstNode(l_empty),
    "[1]" = ?AstNode(l_one),
    "[1, 2]" = ?AstNode(l_two),
    "[1, 2, 3]" = ?AstNode(l_three),
    "1 :: 2" = ?AstNode(l_improper),
    "[1, 2] :: 3" = ?AstNode(l_improper_two),
    "[[]]" = ?AstNode(l_nested),
    "[[1]]" = ?AstNode(l_nested_one),
    "[[1], 2]" = ?AstNode(l_nested_two),
    "[1, [2], 3]" = ?AstNode(l_nested_three),
    "[1] :: 2" = ?AstNode(l_nested_improper),

    ok.

tuple(Config) ->
    "()" = ?AstNode(t_empty),
    "(1,)" = ?AstNode(t_one),
    "(1, 2)" = ?AstNode(t_two),
    "(1, 2, 3)" = ?AstNode(t_three),
    
    ok.

map(Config) ->
    "{}" = ?AstNode(m_empty),
    "{a: 1}" = ?AstNode(m_one),
    "{a: 1, 'b': false}" = ?AstNode(m_two),
    "{a: 1, 'b': false, \"c\": []}" = ?AstNode(m_three),
    
    ok.

ops(Config) ->
    ?CmpExprs(FnAdd, ErlAdd, o_add),
    ?CmpExprs(FnAdd2, ErlAdd2, o_add_2),

    ?CmpExprs(FnSub, ErlSub, o_sub),
    ?CmpExprs(FnSub2, ErlSub2, o_sub_2),

    ?CmpExprs(FnMul, ErlMul, o_mul),
    ?CmpExprs(FnMul2, ErlMul2, o_mul_2),

    ?CmpExprs(FnDiv, ErlDiv, o_div),
    ?CmpExprs(FnDiv2, ErlDiv2, o_div_2),

    ?CmpExprs(FnPrec, ErlPrec, o_prec),

    "true and false or true" = ?AstNode(o_bool),
    "true and (false or true)" = ?AstNode(o_bool_prec),

    ok.

exprs(Config) ->
    "begin true end" = ?AstNode(e_begin),
    "begin\n  true\n  false\nend" = ?AstNode(e_begin_2),

    "begin begin true end end" = ?AstNode(e_begin_nested),
    "begin\n  begin\n    true\n    false\n  end\nend" = ?AstNode(e_begin_nested_2),

    "when true:\n  ok\nend" = ?AstNode(e_if),
    "when A:\n  ok\nelse:\n  error\nend" = ?AstNode(e_if_elif),
    "when a, b:\n  ok\nelse a; b:\n  ok\nelse a, b; c:\n  ok\nelse a; b, c:\n  ok\nelse a, b; c, d:\n  ok\nend" = ?AstNode(e_if_guards),
    "when a, b:\n  ok\nelse a; b:\n  ok\nelse a, b; c:\n  ok\nelse a; b, c:\n  ok\nelse a, b; c, d:\n  ok\nelse:\n  ok\nend" = ?AstNode(e_if_guards_else),

    ok.

guards(_Config) ->
    PP = fun(Ast) -> prettypr:format(fn_pp:pp_guards(Ast, fn_pp:default_ctx())) end,
    "a, b" = PP([[{atom,97,a},{atom,97,b}]]),
    "a; b" = PP([[{atom,98,a}],[{atom,98,b}]]),
    "a, b; c" = PP([[{atom,99,a},{atom,99,b}],[{atom,99,c}]]),
    "a; b, c" = PP([[{atom,100,a}],[{atom,100,b},{atom,100,c}]]),
    "a, b; c, d" = PP([[{atom,101,a},{atom,101,b}],[{atom,101,c},{atom,101,d}]]),

    ok.

e_case(Config) ->
    "match A:\ncase true:\n  ok\ncase false:\n  error\nend" = ?AstNode(e_case),
    "match A:\ncase true when A > 5; A < 2:\n  ok\ncase false when A > 10:\n  error\nend" = ?AstNode(e_case_guards),

    ok.
