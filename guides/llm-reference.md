# Efene Reference for LLMs

Compact and exact guide to write correct efene (`.fn`) code. Efene is a syntax for Erlang/BEAM:
it compiles to Erlang abstract forms, so every Erlang/OTP library works (`lists.map(...)`,
`ets.new(...)`, `maps.get(...)`). Prefer this page over general knowledge of other languages:
several things look familiar and are different.

Everything below was checked against the compiler (`rebar3 ct`, suite `fn_sugar_SUITE`).

## 1. Quick rules (read first)

- Blocks end with `end`. `:` starts a body. Newline ends a statement, `;` is not a statement separator.
- Variables start with an uppercase letter or `_` and are **single assignment**. Atoms are lowercase: `ok`, `error`. Wrap odd atoms in backticks: `` `hello world` ``.
- **Tuples use parentheses** `(ok, 1)`, one element `(1,)`, empty `()`. **Maps use braces** `{a: 1}`, empty `{}`. Lists use brackets.
- Cons is `H :: T`. **`|` is bitwise or**, so `[H|T]` is wrong, write `H :: T`.
- `"text"` is a list string (charlist), `'text'` is a **binary** (the usual one). Atoms: lowercase word or `` `...` ``.
- Comments: `## to end of line`. There is no block comment.
- Modules are files: `shapes/geo/point.fn` is module `'shapes.geo.point'`, called `shapes.geo.point.new(1, 2)`. A module not found as a file is an Erlang module (`lists.reverse(L)`).
- **All functions are public**. `@private` and `@public` were removed and are compile errors.
- There is no `return`, no loops with mutation, no `if`/`else if`. Use `match`, `when`, function clauses.
- Reserved words (write as `` `word` `` to use as atoms): `after begin case catch do else end fn for in match receive try when with guard defer loop`.
- `#{}` (Erlang syntax) is not valid, write `{}`. `%` is remainder, `//` integer division, `!=` not equal, `is`/`isnt` exact equality (`=:=`, `=/=`), `and`/`or` short circuit, `andd`/`orr` non short circuit.

## 2. Functions

    fn double(X) = X * 2                 ## one expression shorthand
    fn clock = erlang.monotonic_time(second)
    fn area                              ## general form
      @doc("area of a rect")             ## attributes go after the name
      @spec(number(), number()) -> number()
      case W, H: W * H
    end

- Every `case` clause of the same arity is one function. Different arities in one `fn` block become separate functions (`area/1`, `area/2`), clauses keep their order.
- Shorthand `fn name(params) = expr` is one expression on one line (no multi-line body). Use the `case` form for several statements.
- Zero arguments: `case:` (colon right after case).
- Guards: `case N when N > 0, N < 10: ...`. `,` is and, `;` is or. Only guard BIFs are allowed (`is_integer`, `map_get`, `X in [a,b]`, ...).
- `else:` is the catch all clause: `case 0: zero  else: other`.
- Default arguments with `:=` (only trailing): `case Name, Greeting := 'hello':` defines `/1` and `/2`.
- `@guard` marks a one clause one expression function that is inlined in guards: `fn is_session @guard case S: is_binary(S) and S != '' end`, use it as `when is_session(S)`.
- Anonymous: `fn case X: X + 1 end`, short `fn(X) = X + 1`, named for recursion `fn Fact case 0: 1  case N: N * Fact(N - 1) end`. References: `fn lists.reverse:1`, `fn helper:2`.
- Constants: `@const(TTL) -> 12 * 3600` then `#m TTL` (works in guards and patterns). Names are variables (uppercase).
- Compile time: `#ct expr` runs at compile time and inlines the literal. `@assert_ct(#m TTL > 0)` fails the build if false.

## 3. Control flow

    match Result:                         ## like case/switch, patterns + guards
      case ok, Value when Value > 0: Value
      case error, Reason: fail(Reason)
      else: default                       ## optional catch all
    end

- In `match`/`receive`, several comma separated patterns after `case` are a **tuple** pattern: `case ok, V:` matches `(ok, V)`. `ok(V)` and `err(R)` are sugar for `(ok, V)` and `(error, R)`, also in patterns (unless the module defines functions with that name).
- `when` is the if/else-if chain (guards only):

      when X < 10: small
      else X < 20: medium
      else: large
      end

- Comprehension: `for X in L; Y in M; when X != Y: (X, Y) end`. A pattern can be the generator variable and filters the non matching items: `for (ok, V) in Results: V end`. Generators are `Pattern in List` (or `Pattern <- Binary`), not `Pattern = Expr`.
- Ranges and `in`: `1..10` is `lists:seq(1, 10)`; `X in [a, b]` and `X in 1..9` work in guards when X is a variable. Range patterns (`case 1..5:`) do not exist, use `when X in 1..5`.
- `begin ... end` groups statements. `try ... catch case error, badarg: ... after ... end`, `catch` clauses are `case Class, Reason:` with Class one of `throw error exit` (one pattern means throw).
- `receive case Pat: ... after 1000: timeout end`.
- `try! Expr else Default` returns Default if Expr raises an error (only class `error`).
- `loop (I = 0, Acc = []): when I == 3: Acc  else: recur(I + 1, I :: Acc)  end end`; `recur(...)` should be in tail position; the loop is an expression.

## 4. Early exit without return

In a block of statements (function body, `case` body):

    fn price
      case Id:
        guard Id > 0 else err(bad_id)                       ## boolean guard
        guard ok(Product) = db.find(Id) else err(missing)   ## pattern guard
        Rate = rates.get(Product.currency)?                  ## unwrap (ok, V) or leave the block with the other value
        defer metrics.done(Id)                               ## runs when the block ends (try/after)
        ok(Product.cents * Rate)
    end

- `X = f()?` / `f()?`: `(ok, V)` continues with `X = V`, anything else becomes the value of the **enclosing block**, bare `ok` also continues for `f()?` alone. `?` is only valid as a statement or right of `=`, not inside arguments.
- `guard P = E else V` continues if the pattern matches, otherwise the block's value is `V`.
- "Block" means the nearest body: inside a `match` clause the exit leaves only that clause.
- `with` chains matches inside an expression:

      with ok(Base) = config(url); ok(Key) = config(key) when Key != '':
        post(Base, Key)
      else: err(unavailable)          ## or: else case ... end  (cases see the value that failed)
      end

  Without `else` the failing value is the result. Variables bound in the `with` clauses are not visible in `else`.

## 5. Data and access

    M = {name: 'bob', age: 3}
    {name = N} = M                  ## pattern: key = Pattern
    M#{age: 4}                      ## update existing or add (also P.user#{name: 'x'})
    M.name                          ## atom key, raises {badkey, name} if missing (works in guards)
    M['name']  M[Key]  M[Key, Default]   ## any key; with default it never raises
    P?.user?.name                   ## nil when the receiver is nil/undefined or the key is missing
    {id:, user_name:}               ## shorthand for {id: Id, user_name: UserName} (CamelCase of the key)
    {id=, user_name=} = M           ## pattern shorthand, binds Id and UserName

- `X.key` works only when X is a variable (else it is a module call). A var followed by `.atom` is map access; `lists.seq(...)` is a module call.
- Records: `@record(person) -> (name, age = 0)`, `#r.person {name: "a"}`, `P#r.person ...`.
- Binaries: `#b {A: 8, Rest: binary}`. Chars: `#c "a"`.
- Strings: `'hi #{Name}, #{N + 1}'` interpolation (binary strings and list strings; values can be binaries, atoms, numbers, strings). `\#{` is a literal. Triple quotes `""" ... """` / `''' ... '''` keep newlines and quotes, drop the first and last line if empty and remove common indentation:

      Sql = '''
        SELECT *
          FROM users
        '''

## 6. Pipelines

- `X -> f(1) -> g()` puts the value as the **first** argument; `X ->> f(1)` as the last. A `_` argument is replaced instead: `Id -> lists.seq(1, _)`.
- `Result => f() => g(1)` passes the value of `(ok, V)` as first argument, stops at the first non ok result (it is the result of the whole pipe). Can be mixed with `->`.
- Trailing lambda (do-block style): `lists.map(L) <<- case X: X + 1 end` puts the lambda as the **first** argument (`lists:map(Fun, L)`, the usual order in `lists`/`maps`), `lists.foldl(0, L) <<- case X, Acc: Acc + X end` too. `<-` puts it as the **last** argument for functions that take the fun last.
- `match Value -> f(): case ...: ... end` allows a pipeline as the scrutinee.

## 7. Types and specs

    @type(principal) -> {id: binary(), roles: [binary()], name: binary() or nil}
    @export_type(principal/0)
    fn login
      @spec(binary(), binary()) -> (ok, binary()) or err(invalid or forbidden)
      case ...
    end

- `@spec` goes **inside** the fn block. Zero arguments: `@spec -> integer()`. Specs on functions with defaults go on the longest arity.
- Unions use `or`. Maps `{key: type}` mean required keys, `map()` any map. `ok(T)`, `err(T)` are `(ok, T)`, `(error, T)`. Ranges `range(1, 10)`, lists `[T]`, functions `fun([a, b], r)`.
- Module attributes: `@export(f/1)` (not needed), `@import(lists, [map/2])`, `@include("x.hrl")`, `@behaviour(gen_server)`, `@vsn("1")`, `@on_load(f/0)`.

## 8. Tooling

    efene beam file.fn outdir [--root dir]     ## compile (also compiles imported .fn modules)
    efene fmt file.fn                          ## format (prints from Erlang forms: sugar comes out expanded)
    rebar3 ct                                  ## project tests
    rebar3 escriptize                          ## build _build/default/bin/efene

Errors print as `error:LINE:type: ...`. In Erlang tests call `efene:compile(File, OutDir, Opts)` or `efene:to_mod(File)`.

## 9. Common mistakes (checked while building the compiler)

| Wrong | Right |
|---|---|
| `[H\|T]`, `L \| M` | `H :: T` (`\|` is bor) |
| `#{a => 1}`, `{a, b}` as tuple | `{a: 1}`, `(a, b)` |
| `fn f(X)` followed by `case` | `fn f case X: ... end` or `fn f(X) = expr` |
| multi line body in `fn f(X) = ...` | use the `case` form |
| `if C then A else B` | `when C: A else: B end` |
| line starting with `or`/`and` to continue | end the previous line with the operator (`->`, `=>` may start a line) |
| `@private fn ...` | removed, everything is public |
| `case [H :: _]:` for a cons pattern | `case H :: _:` (the first matches a one element list) |
| `X? ` inside arguments | statement or `X = f()?` only |
| `fn f case A: .. case A, B: ..` expecting one function | two functions, `f/1` and `f/2` |
| `case X when f(X):` calling a local function in a guard | mark `f` with `@guard`, or compute before |
| `guard`, `defer`, `loop` as atoms | `` `guard` `` |
| `@spec` outside the fn | inside the fn block |
| `"#{1.5}"` expecting a warning | folded at compile time, fine |

## 10. Complete example

See `examples/staff/staff_sugar.fn` (same module as the plain version `examples/staff/staff.fn` and the Elixir original, uses `@const`, `@guard`, `guard`, `with`, `try!`, defaults, interpolation, heredoc docs, `@type`/`@spec`, map access and punning).

A small module:

    @const(LIMIT) -> 10
    @type(item) -> {id: integer(), name: binary()}

    fn is_small @guard case N: N < #m LIMIT end

    fn parse
      @spec(binary()) -> ok(item()) or err(atom())
      case Text:
        guard Text != '' else err(empty)
        Id = try! binary_to_integer(Text) else -1
        guard Id > 0 else err(bad_id)
        ok({id: Id, name: 'item #{Id}'})
    end

    fn names
      case Texts:
        Parsed = for T in Texts: parse(T) end
        for (ok, I) in Parsed; when is_small(I.id): I.name end
    end

    fn sum_to(N) = loop (I = 1, Acc = 0):
      when I > N: Acc
      else: recur(I + 1, Acc + I)
      end
    end
