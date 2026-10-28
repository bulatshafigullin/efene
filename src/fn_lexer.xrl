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

Definitions.

% binary operators
BinOr       = (\||\^)
BinAnd      = \&
Shift       = (<<|>>)
BinNot      = ~

% bool operators
BoolAnd     = and
BoolOr      = or
BoolAndd    = andd
BoolOrr     = orr
BoolXor     = xor
BoolNot     = not
Bool        = (true|false)

% arithmetic operators
Add         = (\+|-)
Mul         = (\*|//|/|%)
Comp        = (<|<=|==|is|>=|>|!=|isnt)
Assign      = =
ColonEq     = :=

% list operators
Concat      = (\+\+|--)

% numbers
Number      = [0-9]
Float       = [0-9]+\.[0-9]+([eE][-+]?[0-9]+)?

% delimiters and operators
Open        = \(
Close       = \)
OpenList    = \[
CloseList   = \]
OpenMap     = \{
CloseMap    = \}
Sep         = ,
SemiColon   = ;
Endls       = (\s|\t)*(\r?\n)
Whites      = \s+
Tabs        = \t+
ConsOp      = ::
Colon       = :
Dot         = \.
Arrow       = ->
ArrowEnd    = ->>
LArrow      = <-
LArrowEnd   = <<-
FatArrow    = =>
Send        = !
Hash        = #
Comment     = ##[^\n]*
At          = @

% string stuff
HString     = \"\"\"([^\"]|\"[^\"]|\"\"[^\"])*\"\"\"
HBString    = '''([^']|'[^']|''[^'])*'''
String      = "(\\\^.|\\.|[^\"])*"
BString     = '(\\\^.|\\.|[^\'])*'
AtomString  = `(\\\^.|\\.|[^\`])*`

% identifiers and atoms
Identifier  = [A-Z\_][a-zA-Z0-9\_]*
Atom        = [a-z][a-zA-Z0-9\_@]*

Rules.

% binary operators
{Shift}                  : make_token(bin_shift, TokenLine, TokenChars).
{BinNot}                 : make_token(bin_not,  TokenLine, TokenChars).
{BinAnd}                 : make_token(bin_and,   TokenLine, TokenChars).
{BinOr}                  : make_token(bin_or,    TokenLine, TokenChars).

% bool operators
{BoolNot}                : make_token(bool_not,     TokenLine, TokenChars).
{Bool}                   : make_token(boolean,      TokenLine, TokenChars).
{BoolAnd}                : make_token(bool_and, TokenLine, TokenChars).
{BoolOr}                 : make_token(bool_or,  TokenLine, TokenChars).
{BoolAndd}               : make_token(bool_andd, TokenLine, TokenChars).
{BoolOrr}                : make_token(bool_orr,  TokenLine, TokenChars).
{BoolXor}                : make_token(bool_xor,  TokenLine, TokenChars).

% arithmetic operators
{Add}                    : make_token(add_op,  TokenLine, TokenChars).
{Mul}                    : make_token(mul_op,  TokenLine, TokenChars).
{Assign}                 : make_token(assign,   TokenLine, TokenChars).

{ColonEq}                : make_token(coloneq,   TokenLine, TokenChars).

{Comp}                   : make_token(comp_op, TokenLine, TokenChars).

% list operators
{Concat}                 : make_token(concat_op, TokenLine, TokenChars).

% numbers
{Float}                  : make_token(float,   TokenLine, TokenChars, fun erlang:list_to_float/1).
{Number}+                : make_token(integer, TokenLine, TokenChars, fun erlang:list_to_integer/1).

% delimiters and operators
{Open}                   : make_token(open,        TokenLine, TokenChars).
{Close}                  : make_token(close,       TokenLine, TokenChars).
{OpenList}               : make_token(open_list,   TokenLine, TokenChars).
{CloseList}              : make_token(close_list,  TokenLine, TokenChars).
{OpenMap}                : make_token(open_map,    TokenLine, TokenChars).
{CloseMap}               : make_token(close_map ,  TokenLine, TokenChars).

{Sep}                    : make_token(sep,          TokenLine, TokenChars).
{SemiColon}              : make_token(semicolon,    TokenLine, TokenChars).
{Send}                   : make_token(send_op,      TokenLine, TokenChars).
{Comment}                : skip_token.
{Hash}                   : make_token(hash,         TokenLine, TokenChars).
{At}                     : make_token(at,           TokenLine, TokenChars).
{ConsOp}                 : make_token(cons_op,      TokenLine, TokenChars).
{Colon}                  : make_token(colon,        TokenLine, TokenChars).
{Dot}                    : make_token(dot,          TokenLine, TokenChars).
{Arrow}                  : make_token(arrow,        TokenLine, TokenChars).
{ArrowEnd}               : make_token(arrowend,     TokenLine, TokenChars).
{LArrow}                 : make_token(larrow,       TokenLine, TokenChars).
{LArrowEnd}              : make_token(larrowend,    TokenLine, TokenChars).
{FatArrow}               : make_token(fatarrow,     TokenLine, TokenChars).

% string stuff
{HString}                : build_heredoc(string, TokenChars, TokenLine, TokenLen).
{HBString}               : build_heredoc(bstring, TokenChars, TokenLine, TokenLen).
{String}                 : build_string(string, TokenChars, TokenLine, TokenLen).
{BString}                : build_string(bstring, TokenChars, TokenLine, TokenLen).

% identifiers and atoms
{Identifier}             : make_token(var, TokenLine, TokenChars).
{Atom}                   : {token, atom_or_identifier(TokenChars, TokenLine)}.
{AtomString}             : build_atom_string(TokenChars, TokenLine, TokenLen).

% spaces, tabs and new lines
{Endls}                 : make_token(nl, TokenLine, endls(TokenChars)).
{Whites}                : skip_token.
{Tabs}                  : skip_token.

Erlang code.

-export([is_reserved/1]).

make_token(Name, Line, Chars) when is_list(Chars) ->
    {token, {Name, Line, list_to_atom(Chars)}};
make_token(Name, Line, Chars) ->
    {token, {Name, Line, Chars}}.

make_token(Name, Line, Chars, Fun) ->
    {token, {Name, Line, Fun(Chars)}}.

endls(Chars) ->
    lists:filter(fun (C) -> C == $\n orelse C == $; end, Chars).

atom_or_identifier(String, TokenLine) ->
     case is_reserved(String) of
         true ->
            {list_to_atom(String), TokenLine};
         false ->
            {atom, TokenLine, build_atom(String, TokenLine)}
     end.

is_reserved("after")   -> true;
is_reserved("begin")   -> true;
is_reserved("case")    -> true;
is_reserved("catch")   -> true;
is_reserved("do")      -> true;
is_reserved("else")    -> true;
is_reserved("end")     -> true;
is_reserved("fn")      -> true;
is_reserved("for")     -> true;
is_reserved("in")      -> true;
is_reserved("match")   -> true;
is_reserved("receive") -> true;
is_reserved("try")     -> true;
is_reserved("when")    -> true;
is_reserved("with")    -> true;



is_reserved(_)         -> false.

build_atom_string(Chars, Line, Len) ->
  String = unescape_string(lists:sublist(Chars, 2, Len - 2), Line),
  {token, {atom, Line, list_to_atom(String)}}.

build_heredoc(Type, Chars, Line, Len) ->
  Raw = dedent(lists:sublist(Chars, 4, Len - 6)),
  string_token(Type, Raw, Line).

% triple quoted text: the first line is dropped if it's empty, so is the last
% one (where the closing quotes are), and the common indentation is removed
dedent(Raw) ->
  Lines0 = string:split(Raw, "\n", all),
  Lines1 = case Lines0 of
             [First|Rest] -> case blank(First) of true -> Rest; false -> Lines0 end;
             [] -> []
           end,
  Lines2 = case lists:reverse(Lines1) of
             [Last|RevRest] -> case blank(Last) of true -> lists:reverse(RevRest); false -> Lines1 end;
             [] -> []
           end,
  Indent = lists:min([length(lists:takewhile(fun is_ws/1, L)) || L <- Lines2, not blank(L)] ++ [1000]),
  Stripped = [case blank(L) of true -> ""; false -> lists:nthtail(Indent, L) end || L <- Lines2],
  string:join(Stripped, "\n").

is_ws(C) -> C == $\s orelse C == $\t.
blank(L) -> lists:all(fun is_ws/1, L).

build_string(Type, Chars, Line, Len) ->
  string_token(Type, lists:sublist(Chars, 2, Len - 2), Line).

string_token(Type, Raw, Line) ->
  case split_interpolation(Raw, Line, [], []) of
    [{lit, String}] -> {token, {Type, Line, String}};
    Parts -> {token, {Type, Line, {interp, Parts}}}
  end.

% "a #{expr} b" -> [{lit, "a "}, {expr, "expr"}, {lit, " b"}], the string is
% still escaped here, \#{ is a literal #{
split_interpolation([], Line, Lit, Parts) ->
  lists:reverse([{lit, lit_string(Lit, Line)}|Parts]);
split_interpolation([$\\, C|Rest], Line, Lit, Parts) ->
  split_interpolation(Rest, Line, [C, $\\|Lit], Parts);
split_interpolation([$#, ${|Rest], Line, Lit, Parts) ->
  {Expr, Rest1} = interpolation_expr(Rest, Line, 0, []),
  Parts1 = [{expr, Expr}, {lit, lit_string(Lit, Line)}|Parts],
  split_interpolation(Rest1, Line, [], Parts1);
split_interpolation([C|Rest], Line, Lit, Parts) ->
  split_interpolation(Rest, Line, [C|Lit], Parts).

lit_string(Lit, Line) -> unescape_string(lists:reverse(Lit), Line).

interpolation_expr([], Line, _Depth, _Acc) ->
  throw({error, {Line, fn_lexer, ["unterminated string interpolation"]}});
interpolation_expr([$}|Rest], _Line, 0, Acc) ->
  {lists:reverse(Acc), Rest};
interpolation_expr([$}=C|Rest], Line, Depth, Acc) ->
  interpolation_expr(Rest, Line, Depth - 1, [C|Acc]);
interpolation_expr([${=C|Rest], Line, Depth, Acc) ->
  interpolation_expr(Rest, Line, Depth + 1, [C|Acc]);
interpolation_expr([$\\, C|Rest], Line, Depth, Acc) ->
  interpolation_expr(Rest, Line, Depth, [C, $\\|Acc]);
interpolation_expr([Q|Rest], Line, Depth, Acc) when Q == $"; Q == $'; Q == $` ->
  {Quoted, Rest1} = lists:splitwith(fun (C) -> C =/= Q end, Rest),
  case Rest1 of
    [] -> throw({error, {Line, fn_lexer, ["unterminated string interpolation"]}});
    [_|Rest2] -> interpolation_expr(Rest2, Line, Depth, lists:reverse([Q|Quoted] ++ [Q]) ++ Acc)
  end;
interpolation_expr([C|Rest], Line, Depth, Acc) ->
  interpolation_expr(Rest, Line, Depth, [C|Acc]).

unescape_string(String, Line) -> unescape_string(String, Line, []).

unescape_string([], _Line, Output) ->
  lists:reverse(Output);
unescape_string([$\\, Escaped | Rest], Line, Output) ->
  Char = map_escaped_char(Escaped, Line),
  unescape_string(Rest, Line, [Char|Output]);
unescape_string([Char|Rest], Line, Output) ->
  unescape_string(Rest, Line, [Char|Output]).

map_escaped_char(Escaped, Line) ->
  case Escaped of
    $\\ -> $\\;
    $/ -> $/;
    $\" -> $\";
    $\' -> $\';
    $\( -> $(;
    $# -> $#;
    $b -> $\b;
    $d -> $\d;
    $e -> $\e;
    $f -> $\f;
    $n -> $\n;
    $r -> $\r;
    $s -> $\s;
    $t -> $\t;
    $v -> $\v;
    _ -> throw({error, {Line, fn_lexer, ["unrecognized escape sequence: ", [$\\, Escaped]]}})
  end.

build_atom(Atom, _Line) -> list_to_atom(Atom).
