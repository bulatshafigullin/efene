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

Nonterminals
    program tl_exprs tl_expr literal raw_literal e_fn_tl
    l_atom l_var l_integer l_float l_boolean l_string l_bstring l_fn l_fn_ref
    guard_seq seq_items l_tuple l_list l_cons
    kv_items kv_item
    kv_key kv_val l_map l_map_update
    e_bool
    e_case e_cases e_case_cond e_case_else e_else_only_case
    e_switch e_receive e_try e_with with_items fn_params
    e_when e_when_cond e_when_else e_when_final_else e_when_elses
    e_begin
    e_for for_items for_item
    raw_expr expr body
    attrs attr
    e_call e_call_do e_call_thread e_call_thread_funs
    e_assign e_send
    e_bool_and e_comp e_concat e_add e_mul e_unary
    path path_item e_access range_item
    e_loop.

Terminals
    fn atom var integer float boolean string bstring colon end nl case else match when
    begin receive after try catch for in with coloneq
    question qdot dotdot fatarrow guard defer loop
    hash open close sep semicolon open_list close_list
    open_map close_map cons_op at arrow arrowend dot larrow larrowend
    assign send_op
    bool_or bool_orr bool_xor bool_and bool_andd comp_op concat_op add_op mul_op
    bin_or bin_and bin_shift bin_not bool_not.

Rootsymbol program.

%% the body of an anonymous fn(X) = expr extends as far right as possible (the
%% conflicts are resolved by shifting, which is that)
Expect 45.

program -> tl_exprs : '$1'.
program -> nl tl_exprs : '$2'.

tl_exprs -> tl_expr : ['$1'].
tl_exprs -> tl_expr nl tl_exprs : ['$1'|'$3'].

tl_expr -> e_fn_tl: '$1'.
tl_expr -> attr: '$1'.
tl_expr -> expr: '$1'.

e_fn_tl -> fn l_atom e_case end:
    Name = '$2',
    Cases = '$3',
    {expr, line('$1'), fn, {Name, [], Cases}}.

e_fn_tl -> fn l_atom attrs e_case end:
    Name = '$2',
    Attrs = '$3',
    Cases = '$4',
    {expr, line('$1'), fn, {Name, Attrs, Cases}}.

% fn name = expr, fn name(params) = expr, attributes go before the =
e_fn_tl -> fn l_atom assign expr:
    fn_shorthand('$1', '$2', [], [], '$4').
e_fn_tl -> fn l_atom attrs assign expr:
    fn_shorthand('$1', '$2', [], '$3', '$5').
e_fn_tl -> fn l_atom fn_params assign expr:
    fn_shorthand('$1', '$2', '$3', [], '$5').
e_fn_tl -> fn l_atom fn_params attrs assign expr:
    fn_shorthand('$1', '$2', '$3', '$4', '$6').

fn_params -> open close : [].
fn_params -> open seq_items close : '$2'.

e_else_only_case -> e_case_else : {expr, line('$1'), 'case', ['$1']}.
e_else_only_case -> e_case : '$1'.

e_case -> e_cases : {expr, line('$1'), 'case', '$1'}.

e_case_cond -> case colon body : {cmatch, line('$1'), {[], nowhen, '$3'}}.
e_case_cond -> case seq_items colon body : {cmatch, line('$1'), {'$2', nowhen, '$4'}}.
e_case_cond -> case seq_items when guard_seq colon body : {cmatch, line('$1'), {'$2', '$4', '$6'}}.
e_case_cond -> case seq_items nl when guard_seq colon body : {cmatch, line('$1'), {'$2', '$5', '$7'}}.

e_case_else -> else colon body : {celse, line('$1'), '$3'}.

e_cases -> e_case_cond : ['$1'].
e_cases -> e_case_cond e_case_else : ['$1', '$2'].
e_cases -> e_case_cond e_cases : ['$1'|'$2'].

e_switch -> match e_call_thread colon e_case end:
    {expr, line('$1'), switch, {'$2', '$4'}}.

e_switch -> match seq_items colon e_case end:
    case '$2' of
        [Item] ->
            {expr, line('$1'), switch, {Item, '$4'}};
        Items ->
            {expr, line('$1'), switch, {seq_value(Items, line('$1'), tuple), '$4'}}
    end.

e_receive -> receive e_case end:
    {expr, line('$1'), 'receive', {'$2', noafter}}.

e_receive -> receive e_case after literal colon body end:
    {expr, line('$1'), 'receive', {'$2', {'$4', '$6'}}}.

e_receive -> receive after literal colon body end:
    {expr, line('$1'), 'receive', {[], {'$3', '$5'}}}.

e_try -> try body after body end:
    {expr, line('$1'), 'try', {'$2', nocatch, '$4'}}.

e_try -> try body catch e_else_only_case end:
    {expr, line('$1'), 'try', {'$2', '$4', noafter}}.

e_try -> try body catch e_else_only_case after body end:
    {expr, line('$1'), 'try', {'$2', '$4', '$6'}}.

% try! expr else default: the default replaces any error raised by expr
e_try -> try send_op expr else expr:
    Line = line('$1'),
    Default = '$5',
    Catch = {expr, Line, 'case', [{cmatch, Line, {[{val, Line, atom, error}, {val, Line, var, '_'}], nowhen, [Default]}}]},
    {expr, Line, 'try', {['$3'], Catch, noafter}}.

% with Pattern = Expr; ...: body [else: body | else case ...] end
with_items -> e_assign when e_bool : [{with_when, line('$2'), '$1', '$3'}].
with_items -> e_assign when e_bool semicolon with_items : [{with_when, line('$2'), '$1', '$3'}|'$5'].
with_items -> e_assign : ['$1'].
with_items -> e_assign semicolon with_items : ['$1'|'$3'].

e_with -> with with_items colon body end:
    {expr, line('$1'), with, {'$2', '$4', noelse}}.
e_with -> with with_items colon body else colon body end:
    {expr, line('$1'), with, {'$2', '$4', {expr, line('$5'), 'case', [{cmatch, line('$5'), {[{val, line('$5'), var, '_'}], nowhen, '$7'}}]}}}.
e_with -> with with_items colon body else e_case end:
    {expr, line('$1'), with, {'$2', '$4', '$6'}}.

% loop (I = 0, Acc = []): ... recur(I + 1, [I|Acc]) ... end
e_loop -> loop colon body end : {expr, line('$1'), loop, {[], '$3'}}.
e_loop -> loop open seq_items close colon body end : {expr, line('$1'), loop, {'$3', '$6'}}.

e_when -> e_when_cond end : {expr, line('$1'), 'when', ['$1']}.
e_when -> e_when_cond e_when_elses end : {expr, line('$1'), 'when', ['$1'|'$2']}.

e_when_cond -> when guard_seq colon body : {wcond, line('$1'), '$2', '$4'}.
e_when_else -> else guard_seq colon body : {wcond, line('$1'), '$2', '$4'}.
e_when_final_else -> else colon body  : {welse, line('$1'), '$3'}.

e_when_elses -> e_when_else : ['$1'].
e_when_elses -> e_when_final_else : ['$1'].
e_when_elses -> e_when_else e_when_elses : ['$1'|'$2'].

e_begin -> begin body end: {expr, line('$1'), 'begin', '$2'}.

e_for -> for for_items colon body end : {expr, line('$1'), 'for', {'$2', '$4'}}.

for_item -> when e_bool : {filter, '$2'}.
for_item -> literal in literal : {generate, line('$2'), '$1', '$3'}.
for_item -> literal larrow literal : {b_generate, line('$2'), '$1', '$3'}.

for_items -> for_item : ['$1'].
for_items -> for_item semicolon for_items : ['$1'|'$3'].

e_bool -> e_bool_and bool_or e_bool: op('$2', '$1', '$3').
e_bool -> e_bool_and: '$1'.

e_bool_and -> e_comp bool_and e_bool_and: op('$2', '$1', '$3').
e_bool_and -> e_comp: '$1'.

e_comp -> e_concat comp_op e_comp : op('$2', '$1', '$3').
e_comp -> e_concat in e_concat : {op, line('$2'), 'in', '$1', '$3'}.
e_comp -> e_concat : '$1'.

e_concat -> e_add concat_op e_concat : op('$2', '$1', '$3').
e_concat -> e_add : '$1'.

e_add -> e_add add_op e_mul : op('$2', '$1', '$3').
e_add -> e_add bool_orr e_mul : op('$2', '$1', '$3').
e_add -> e_add bool_xor e_mul : op('$2', '$1', '$3').
e_add -> e_add bin_shift e_mul : op('$2', '$1', '$3').
e_add -> e_add bin_or e_mul : op('$2', '$1', '$3').
e_add -> e_mul : '$1'.

e_mul -> e_mul mul_op e_unary : op('$2', '$1', '$3').
e_mul -> e_mul bool_andd e_unary : op('$2', '$1', '$3').
e_mul -> e_mul bin_and e_unary : op('$2', '$1', '$3').
e_mul -> l_cons : '$1'.

e_unary -> bin_not literal: unary_op('$1', '$2').
e_unary -> bool_not literal: unary_op('$1', '$2').
e_unary -> add_op literal: unary_op('$1', '$2').
e_unary -> literal : '$1'.

expr -> bin_or path raw_expr: {tag, line('$1'), '$2', '$3'}.
expr -> guard e_assign else expr : {expr, line('$1'), guard, {'$2', '$4'}}.
expr -> defer expr : {expr, line('$1'), defer, '$2'}.
expr -> raw_expr : '$1'.

raw_expr -> e_switch : '$1'.
raw_expr -> e_when: '$1'.
raw_expr -> e_with: '$1'.
raw_expr -> e_loop: '$1'.
raw_expr -> e_for: '$1'.
raw_expr -> e_receive: '$1'.
raw_expr -> e_try: '$1'.
raw_expr -> e_send : '$1'.
raw_expr -> e_call_do : '$1'.
raw_expr -> e_call_thread : '$1'.

body -> expr: [stmt('$1')].
body -> expr nl: [stmt('$1')].
body -> expr nl body : [stmt('$1')|'$3'].

literal -> hash path raw_literal : {ltag, line('$1'), '$2', '$3'}.
literal -> raw_literal : '$1'.

path -> path_item : ['$1'].
path -> path_item dot path : ['$1'|'$3'].

path_item -> l_atom : '$1'.
path_item -> l_var : '$1'.

raw_literal -> l_atom : '$1'.
% a dotted atom like lib.math (not followed by arguments) is the atom 'lib.math',
% the name of a nested module (see efene:compile/3)
raw_literal -> path_item dot path : dotted_atom(['$1'|'$3']).
% Map['key'], Map['key', Default], Map.key.other['key']
raw_literal -> e_access : '$1'.
raw_literal -> l_var : '$1'.
raw_literal -> range_item dotdot range_item : {expr, line('$2'), range, {'$1', '$3'}}.
raw_literal -> l_integer : '$1'.
raw_literal -> l_float : '$1'.
raw_literal -> l_boolean : '$1'.
raw_literal -> l_string : '$1'.
raw_literal -> l_bstring : '$1'.
raw_literal -> l_tuple : '$1'.
raw_literal -> l_list : '$1'.
raw_literal -> l_map : '$1'.
raw_literal -> l_map_update : '$1'.
raw_literal -> l_fn : '$1'.
raw_literal -> l_fn_ref : '$1'.
raw_literal -> e_begin: '$1'.

raw_literal -> e_call : '$1'.
raw_literal -> open expr close : '$2'.

e_access -> l_var open_list seq_items close_list : access('$1', '$3').
e_access -> e_access open_list seq_items close_list : access('$1', '$3').
e_access -> e_access dot l_atom : access('$1', ['$3']).

range_item -> l_integer : '$1'.
range_item -> l_var : '$1'.
range_item -> e_call : '$1'.
range_item -> e_access : '$1'.
range_item -> open expr close : '$2'.

% Value?, unwraps (ok, Value) or leaves the block with the other value
raw_literal -> e_call question : {expr, line('$2'), try_op, '$1'}.
raw_literal -> e_access question : {expr, line('$2'), try_op, '$1'}.
raw_literal -> l_var question : {expr, line('$2'), try_op, '$1'}.

e_access -> l_var qdot l_atom : access_nil('$1', '$3').
e_access -> e_access qdot l_atom : access_nil('$1', '$3').

l_atom -> atom : value('$1', atom).
l_var -> var : value('$1', var).
l_integer -> integer : value('$1', integer).
l_float -> float : value('$1', float).
l_boolean -> boolean : value('$1', boolean).
l_string -> string : string_value('$1', string).
l_bstring -> bstring : string_value('$1', bstring).
l_fn -> fn e_case end: expr_raw('$2', fn).
l_fn -> fn fn_params assign expr:
    Line = line('$1'),
    {expr, Line, fn, {expr, Line, 'case', [{cmatch, Line, {'$2', nowhen, ['$4']}}]}}.
l_fn -> fn l_var e_case end: {expr, line('$1'), fn, {'$2', '$3'}}.
l_fn_ref -> fn path colon l_integer : {val, line('$1'), fn_ref, {'$2', '$4'}}.

l_tuple -> open close : seq_value([], line('$1'), tuple).
l_tuple -> open e_assign sep close : seq_value(['$2'], line('$1'), tuple).
l_tuple -> open e_assign sep seq_items close: seq_value(['$2'|'$4'], line('$1'), tuple).

l_list -> open_list close_list : seq_value([], line('$1'), list).
l_list -> open_list seq_items close_list : seq_value('$2', line('$1'), list).

l_cons -> e_unary cons_op l_cons : seq_value({'$1', '$3'}, line('$1'), cons).
l_cons -> e_unary : '$1'.

guard_seq -> seq_items : ['$1'].
guard_seq -> seq_items semicolon guard_seq :
    Tail = '$3',
    [TailHead|_] = Tail,
    if is_tuple(TailHead) -> ['$1',Tail];
        true -> ['$1'|Tail]
    end.

seq_items -> e_assign: ['$1'].
seq_items -> e_assign sep: ['$1'].
seq_items -> e_assign sep seq_items : ['$1'|'$3'].

l_map -> open_map close_map: seq_value([], line('$1'), map).
l_map -> open_map kv_items close_map: seq_value('$2', line('$1'), map).

l_map_update -> l_var hash l_map : map_update('$1', '$3').
l_map_update -> e_access hash l_map : map_update('$1', '$3').
l_map_update -> path_item dot path hash l_map : map_update(dotted_atom(['$1'|'$3']), '$5').


kv_key -> literal : '$1'.
kv_val -> e_bool : '$1'.

kv_item -> kv_key colon kv_val: {kv, line('$1'), '$1', '$3'}.
kv_item -> kv_key assign kv_val: {kvmatch, line('$1'), '$1', '$3'}.
kv_item -> kv_key colon: {kv, line('$1'), '$1', pun_var('$1')}.
kv_item -> kv_key assign: {kvmatch, line('$1'), '$1', pun_var('$1')}.

kv_items -> kv_item: ['$1'].
kv_items -> kv_item sep: ['$1'].
kv_items -> kv_item sep kv_items: ['$1'|'$3'].


attrs -> attr : ['$1'].
attrs -> attr attrs : ['$1'|'$2'].
attrs -> attr nl attrs : ['$1'|'$3'].

attr -> at guard : make_attr(line('$1'), [{val, line('$2'), atom, guard}], noparams, noresult).
attr -> at path : make_attr(line('$1'), '$2', noparams, noresult).
attr -> at path arrow e_bool : make_attr(line('$1'), '$2', noparams, '$4').
attr -> at path open seq_items close : make_attr(line('$1'), '$2', '$4', noresult).
attr -> at path open seq_items close arrow e_bool : make_attr(line('$1'), '$2', '$4', '$7').

e_call -> path open close : {expr, line('$2'), call, {'$1', []}}.
e_call -> path open seq_items close : {expr, line('$2'), call, {'$1', '$3'}}.

e_call_do -> e_call larrow e_case end:
    {expr, line('$2'), call_do, {last, '$1', expr_raw('$3', fn)}}.
e_call_do -> e_call larrowend e_case end:
    {expr, line('$2'), call_do, {first, '$1', expr_raw('$3', fn)}}.

e_call_thread -> literal e_call_thread_funs : {expr, line('$1'), call_thread, {'$1', '$2'}}.

e_call_thread_funs -> arrow e_call : [{first, '$2'}].
e_call_thread_funs -> arrowend e_call : [{last, '$2'}].
% Result => f() => g(1): stops at the first error, the stages get the ok value
e_call_thread_funs -> fatarrow e_call : [{result, '$2'}].
e_call_thread_funs -> fatarrow e_call e_call_thread_funs : [{result, '$2'}|'$3'].
e_call_thread_funs -> arrow e_call e_call_thread_funs : [{first, '$2'}|'$3'].
e_call_thread_funs -> arrowend e_call e_call_thread_funs : [{last, '$2'}|'$3'].

e_send -> literal send_op expr : op('$2', '$1', '$3').
e_send -> e_assign : '$1'.

% can't chain assignments a = b = c, this is to simplify the parser and why
% woud you make that is that or you have to wrap the right side in parenthesis
% if it's an expression, which is much more common
e_assign -> e_bool assign expr : op('$2', '$1', '$3').
e_assign -> e_bool coloneq e_bool : {default, line('$2'), '$1', '$3'}.
e_assign -> e_bool : '$1'.

Erlang code.

unwrap({_,V})   -> V;
unwrap({_,_,V}) -> V;
unwrap(V) -> ct:print("WAT ~p", [V]).

line(T) when is_tuple(T) -> element(2, T);
line([H|_T]) -> element(2, H);
line(T) -> ct:print("WAT ~p", [T]).

value(Val, Type) -> {val, line(Val), Type, unwrap(Val)}.

string_value(Tok, Type) ->
    Line = line(Tok),
    case unwrap(Tok) of
        {interp, Parts} ->
            {expr, Line, interp, {Type, [interp_part(Part, Line) || Part <- Parts]}};
        String ->
            {val, Line, Type, String}
    end.

interp_part({lit, String}, _Line) -> {lit, String};
interp_part({expr, Source}, Line) ->
    case fn_lexer:string(Source) of
        {ok, Tokens, _} ->
            Tokens1 = [setelement(2, T, Line) || T <- Tokens, element(1, T) =/= nl],
            try fn_parser:parse(Tokens1) of
                {ok, [Expr]} -> Expr;
                _ -> return_error(Line, "invalid expression in string interpolation: " ++ Source)
            catch
                _:_ -> return_error(Line, "invalid expression in string interpolation: " ++ Source)
            end;
        _ ->
            return_error(Line, "invalid expression in string interpolation: " ++ Source)
    end.

fn_shorthand(Fn, Name, Params, Attrs, Expr) ->
    Line = line(Fn),
    Cases = {expr, Line, 'case', [{cmatch, Line, {Params, nowhen, [Expr]}}]},
    {expr, Line, fn, {Name, Attrs, Cases}}.

expr_raw(Val, Type) -> {expr, line(Val), Type, Val}.

seq_value(Val, Line, Type) -> {seq, Line, Type, Val}.

make_attr(Line, Path, Params, Result) ->
    {attr, Line, Path, Params, Result}.

% Map.key.other is Map['key']['other']
dotted_atom([{val, _, var, _}=Var|Keys]) ->
    case lists:all(fun ({val, _, atom, _}) -> true; (_) -> false end, Keys) of
        true -> lists:foldl(fun (Key, Acc) -> access(Acc, [Key]) end, Var, Keys);
        false -> return_error(line(Var), "only atoms can be joined with dots")
    end;
dotted_atom([{val, Line, atom, _}|_]=Items) ->
    case lists:all(fun ({val, _, atom, _}) -> true; (_) -> false end, Items) of
        true ->
            Name = string:join([atom_to_list(V) || {val, _, atom, V} <- Items], "."),
            {val, Line, atom, list_to_atom(Name)};
        false ->
            return_error(Line, "only atoms can be joined with dots")
    end;
dotted_atom([First|_]) ->
    return_error(line(First), "only atoms can be joined with dots").

map_update({val, _, var, _}=Base, {seq, Line, map, Items}) -> {seq, Line, map, {Base, Items}};
map_update({expr, _, access, _}=Base, {seq, Line, map, Items}) -> {seq, Line, map, {Base, Items}};
map_update(Base, _) -> return_error(line(Base), "only a variable or a map access can be updated with #{}").

% Value? and X = Value? are statements only in a body, see fn_to_erl:rewrite_stmts/1
stmt({expr, Line, try_op, Expr}) -> {expr, Line, try_stmt, Expr};
stmt({op, Line, '=', Pattern, {expr, _, try_op, Expr}}) -> {op, Line, '=', Pattern, {expr, Line, try_stmt, Expr}};
stmt(Other) -> Other.

access_nil(Map, Key) -> {expr, line(Map), access, {Map, Key, nilsafe}}.

% {id:, user_name:} is {id: Id, user_name: UserName}
pun_var({val, Line, atom, Name}) ->
    Parts = string:split(atom_to_list(Name), "_", all),
    Camel = lists:append([capitalize(P) || P <- Parts]),
    {val, Line, var, list_to_atom(Camel)};
pun_var(Other) ->
    return_error(line(Other), "only atom keys can be written without a value").

capitalize([]) -> [];
capitalize([C|Rest]) -> [string:to_upper(C)|Rest].

access(Map, [Key]) -> {expr, line(Map), access, {Map, Key, nodefault}};
access(Map, [Key, Default]) -> {expr, line(Map), access, {Map, Key, Default}};
access(Map, _) -> return_error(line(Map), "map access takes a key and an optional default").

op(Op, Left, Right) ->
    {op, line(Op), unwrap(Op), Left, Right}.

unary_op(Op, Val) ->
    {unary_op, line(Op), unwrap(Op), Val}.

