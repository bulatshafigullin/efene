# efene ORM example

A small Django style ORM written in efene on top of the Elixir
[postgrex](https://hex.pm/packages/postgrex) driver. Queries are values that
you refine step by step, each function returns a new query:

```
Q1 = models.user.objects()
Q2 = orm.query.filter(Q1, {age__gte: 18})
Q3 = orm.query.exclude(Q2, {email__endswith: '@spam.com'})
Q4 = orm.query.order_by(Q3, ["-age"])
Adults = orm.repo.all(Conn, Q4)
```

or chained with efene's `->` (it passes the value as the first argument):

```
Published = models.post.objects() ->
  orm.query.filter({published: true}) ->
  orm.query.filter({author__age__gt: 30}) ->
  orm.query.select_related([author]) ->
  orm.query.order_by([title])
```

## Importing the functions

Import the query builders so they can be called without the module name, the
imported modules are compiled with the module that imports them:

```
@import(orm.query, [filter/2, exclude/2, values/2, order_by/2, limit/2, join/2])
@import(orm.q, [any/1, neg/1, exists/1, ref/1])

fn adults case:
  models.user.objects() ->
    filter({age__gte: 18}) ->
    exclude(any([{active: false}, {email__isnull: true}])) ->
    order_by(["-age"])
end
```

Each function is imported by name and arity (`join/2` and `join/3` are
different functions), an imported name can't also be defined in the importing
module. `src/demo.fn` imports everything from `orm.query` and `orm.q` and keeps
`orm.repo` calls qualified (`orm.repo.all(Conn, Q)`), `orm.q.all/1` and
`orm.repo.all/2` would read alike.

A module name is also a value, so a short variable works too:
`Q = orm.query` then `Q.filter(Users, {age__gte: 18})`.

## Running it

Needs Elixir (for postgrex) and a PostgreSQL server, it uses a database called
`efene_orm_example` (created with `createdb` if missing, override it with
`make run DB=otherdb`) and connects to localhost as the current user.

```
make -C ../.. escript   # build the efene compiler
make deps               # fetch and compile postgrex with mix
make run                # compile src/demo.fn and the modules it uses, run it
```

`make build` runs `efene beam src/demo.fn ebin`, `src` is the import root, so
`orm.query.filter(...)` compiles `src/orm/query.fn` as the module `'orm.query'`
and `models.user.objects()` compiles `src/models/user.fn` as `'models.user'`.

## Layout

| module | file | |
|---|---|---|
| `orm.query` | src/orm/query.fn | build queries: filter, exclude, join, order_by, values... |
| `orm.q` | src/orm/q.fn | combine conditions: `all` (AND), `any` (OR), `neg` (NOT) |
| `orm.repo` | src/orm/repo.fn | run queries: all, first, get, count, exists, update, delete, insert, transaction |
| `orm.sql` | src/orm/sql.fn | compile queries to SQL with `$1` params |
| `orm.schema` | src/orm/schema.fn | read model schemas |
| `orm.filterset` | src/orm/filterset.fn | apply request params to a query with declared filters, see [shop_api](../shop_api) |
| `fn_ext_val_atom_q` | src/fn_ext_val_atom_q.fn | compiler extension for the `#q` operators |
| `models.*` | src/models/*.fn | example models: user, post, comment |
| `demo` | src/demo.fn | creates the tables, inserts rows and runs example queries |

## Models

A model is a module with a `schema/0` function:

```
fn schema
  case:
    {table: 'posts',
     fields: [id, title, body, published, author_id],
     relations: {author: (belongs_to, `models.user`, author_id),
                 comments: (has_many, `models.comment`, post_id)}}
end

fn objects case: orm.query.from(#i module) end

fn create case Conn, Values: orm.repo.insert(Conn, #i module, Values) end
```

`primary_key` defaults to `id`. Relations are `(belongs_to, Model, ForeignKey)`
where the foreign key is in this table, and `(has_many, Model, ForeignKey)` or
`(has_one, Model, ForeignKey)` where the foreign key is in the other table.

## Building queries (`orm.query`)

| function | |
|---|---|
| `from(Model)` | all the rows of Model, what `objects()` returns |
| `filter(Q, Cond)` | keep rows matching Cond, calling it again ANDs the conditions |
| `exclude(Q, Cond)` | remove rows matching Cond |
| `join(Q, Path)` / `left_join(Q, Path)` | join a relation (`posts`, `post__author`) |
| `join(Q, Path, Cond)` / `left_join(Q, Path, Cond)` | join with `Cond` in the `ON` clause |
| `join_as(Q, Name, Rel, Cond)` / `left_join_as(...)` | join `Rel` with `Cond` under another name |
| `cte(Name, Q)` | a named query for `WITH` |
| `join_cte(Q, Cte, On)` / `left_join_cte(...)` | join a CTE, `On` maps this query's fields to CTE columns |
| `order_by(Q, Items)` | `age`, `"-age"`, `(desc, age)`, `author__name` |
| `limit(Q, N)`, `offset(Q, N)` | |
| `distinct(Q)` | `SELECT DISTINCT` |
| `values(Q, Keys)` | only these keys, paths like `author__name` and aggregates `(count, id, posts)` |
| `select_related(Q, Paths)` | include related rows as nested maps (`author: {...}` or `nil`) |
| `to_sql(Q)` | `(Sql, Params)` |

A condition is a map of lookups or a combination built with `orm.q`:

```
orm.query.filter(Q, {age__range: (20, 40), name__in: ['Ann', 'Eve']})
orm.query.filter(Q, orm.q.any([{age__lt: 18}, {email__isnull: true}]))
orm.query.filter(Q, orm.q.neg(orm.q.all([{active: false}, {name: 'Bob'}])))
```

### Operators

Inside the `#q` tag conditions combine with django style operators:

```
filter(Q, #q ({age__lt: 18} | {email__isnull: true}))
filter(Q, #q ({age__gte: 18} & ({active: true} | orm.q.exists(Published))))
filter(Q, #q (~({active: false} | {name: 'Bob'})))
filter(Q, #q ({age__gte: 18} - {email__endswith: '@spam.com'}))
```

| operator | meaning | same as |
|---|---|---|
| `A \| B` | A or B | `orm.q.any([A, B])` |
| `A & B` | A and B | `orm.q.all([A, B])` |
| `~A` | not A | `orm.q.neg(A)` |
| `A - B` | A and not B | `orm.q.all([A, orm.q.neg(B)])` |

`&` binds tighter than `|`, `-` has the same precedence as `|` (left to
right), use parentheses when mixing them. The operands are any expression that
is a condition: lookup maps, variables, `orm.q.exists(...)`, other `orm.q` calls.

Plain `A | B` doesn't work: the BEAM has no operator overloading, in efene `|`
is the integer `bor` and fails at runtime on maps. `#q` is an efene compiler
extension (`src/fn_ext_val_atom_q.fn`) that rewrites the operators to `orm.q`
calls at compile time, so there's no runtime cost. The compiler finds it by its
module name in its code path, the Makefile builds it first and runs the
compiler with `ERL_FLAGS="-pa ebin"`. Lists of conditions built at runtime
still use `orm.q.any(Conds)` and `orm.q.all(Conds)`.

A lookup key is a field, optionally after a path of relations and optionally
followed by a lookup type, separated by `__`: `name`, `age__gte`,
`author__name__istartswith`, `comments__post__title__icontains`. Keys can be
atoms, binaries or strings. Filtering on a relation joins it automatically, with
an inner join, or a left join for `isnull` and inside `orm.q.any`/`neg`/`exclude`
(an inner join there would drop the rows without related rows before the OR or
NOT is checked).

| lookup | SQL |
|---|---|
| `exact` (default) | `= $1`, `IS NULL` for `nil` |
| `ne` | `<> $1`, `IS NOT NULL` for `nil` |
| `iexact` | `LOWER(col) = LOWER($1)` |
| `gt`, `gte`, `lt`, `lte` | `>`, `>=`, `<`, `<=` |
| `contains`, `startswith`, `endswith` | `LIKE` (wildcards in the value are escaped) |
| `icontains`, `istartswith`, `iendswith` | `ILIKE` |
| `in` | `= ANY($1)` |
| `isnull` | `IS NULL` / `IS NOT NULL` |
| `range` | `BETWEEN $1 AND $2`, the value is a tuple `(From, To)` |

A lookup value can also be a query (a subquery, see below), `orm.q.f(Key)` for
another column of the same row (`{updated_at__gt: orm.q.f(created_at)}`, also
in `update` changes) or `orm.q.ref(Key)` for a column of the outer query inside
a subquery.

## Aggregates

`values` takes `(Fn, Key)` or `(Fn, Key, Alias)` with `Fn` one of `count`,
`count_distinct`, `sum`, `avg`, `min`, `max` (`(count, all)` is `COUNT(*)`).
The other keys are grouped by, and aggregate aliases can be used in `order_by`:

```
models.post.objects() ->
  orm.query.values([author__name, (count, id, posts)]) ->
  orm.query.order_by(["-posts"])
```

There's no `HAVING`, to filter on an aggregate put the query in a CTE and
filter the CTE.

## Subqueries

A query used as a lookup value becomes a subquery. It returns its primary key
unless it selects `values`:

```
Over40 = orm.query.filter(models.user.objects(), {age__gt: 40})
orm.query.filter(models.post.objects(), {author_id__in: Over40})

Commenters = orm.query.values(models.comment.objects(), [author_id])
orm.query.filter(models.user.objects(), {id__in: Commenters})

AvgAge = orm.query.values(models.user.objects(), [(avg, age)])
orm.query.filter(models.user.objects(), {age__gt: AvgAge})
```

`orm.q.exists(Q)` is `EXISTS (...)`, inside it `orm.q.ref(Key)` refers to the
row of the outer query (a correlated subquery):

```
Published = orm.query.filter(models.post.objects(),
                             {author_id: orm.q.ref(id), published: true})
orm.query.filter(models.user.objects(), orm.q.exists(Published))
orm.query.exclude(models.user.objects(), orm.q.exists(Published))
```

## Filtered joins

Conditions in the `ON` clause of a join, with a left join the rows without
matching related rows are kept, so counts include zeros:

```
models.user.objects() ->
  orm.query.left_join(posts, {published: true}) ->
  orm.query.values([name, (count, posts__id, published_posts)])
```

Filters and values on `posts__...` use that join. To join the same relation
more than once with different conditions give each join a name:

```
models.user.objects() ->
  orm.query.join_as(published, posts, {published: true}) ->
  orm.query.join_as(drafts, posts, {published: false}) ->
  orm.query.values([name, published__title, drafts__title])
```

The keys in a join condition are fields of the joined model, they can't go
through more relations (`orm_join_in_join_condition`).

## CTEs

`orm.query.cte(Name, Q)` names a query, the `WITH` clause is added to any
statement that uses it:

```
Stats = orm.query.cte(author_stats,
          (models.post.objects() ->
            orm.query.values([author_id,
                              (count_distinct, id, post_count),
                              (count_distinct, comments__id, comment_count)])))
```

Query it like a table:

```
orm.query.from(Stats) -> orm.query.filter({comment_count__gte: 1})
```

Join it, then filter or select its columns with its name as prefix:

```
models.user.objects() ->
  orm.query.join_cte(Stats, {id: author_id}) ->
  orm.query.filter({author_stats__post_count__gte: 2}) ->
  orm.query.values([name, author_stats__post_count])
```

Use it in a subquery:

```
Prolific = orm.query.values(orm.query.filter(orm.query.from(Stats), {post_count__gte: 2}),
                            [author_id])
orm.query.filter(models.user.objects(), {id__in: Prolific})
```

Its columns are the keys of its `values` (or the model fields), they are
checked like model fields. Recursive CTEs are not supported.

## Dynamic queries

Queries are plain values, so a dynamic query is ordinary code that decides
which steps to apply. `src/demo.fn` (`dynamic/1`) has runnable versions of
these patterns.

Optional filters from request params, one function clause per param:

```
fn user_param
  case ("name", Name), Q: orm.query.filter(Q, {name__icontains: Name})
  case ("min_age", Age), Q: orm.query.filter(Q, {age__gte: list_to_integer(Age)})
  case ("order", Field), Q: orm.query.order_by(Q, [Field])
  case _Unknown, Q: Q
end

Q = lists.foldl(fn user_param:2, models.user.objects(), Params)
```

Field and operator chosen at runtime (a filter builder), `orm.q.lookup` builds
the condition from strings or binaries:

```
Conds = for (Field, Op, Value) in Rules: orm.q.lookup(Field, Op, Value) end
Q = orm.query.filter(models.user.objects(), orm.q.any(Conds))
```

Named scopes picked at runtime:

```
fn scope
  case "active", Q: orm.query.filter(Q, {active: true})
  case "authors", Q: orm.query.distinct(orm.query.join(Q, posts))
end

Q = lists.foldl(fn scope:2, models.user.objects(), ["active", "authors"])
```

Keys from user input are safe: they are matched against the model schema and
never turned into atoms (atoms are not garbage collected, creating them from
input can crash the node). Anything that isn't a field, relation or lookup of
the model raises when the query is compiled:

| input | error |
|---|---|
| `lookup("password", "exact", X)` | `(orm_unknown_field, 'models.user', <<"password">>)` |
| `lookup("age", "sounds_like", X)` | `(orm_unknown_lookup, 'models.user', age, <<"sounds_like">>)` |
| `lookup("friends__name", "exact", X)` | `(orm_unknown_relation, 'models.user', <<"friends">>)` |
| `order_by(Q, ["-secret"])` | `(orm_unknown_field, 'models.user', <<"secret">>)` |

`values` keys become the keys of the returned maps, as atoms, so only pass
keys that were validated (they are, by the time the rows come back).

## Running queries (`orm.repo`)

| function | returns |
|---|---|
| `connect(Opts)` | `(ok, Conn)`, Opts are postgrex options as a map |
| `all(Conn, Q)` | list of maps |
| `first(Conn, Q)` | first row (by primary key if not ordered) or `nil` |
| `get(Conn, Q)`, `get(Conn, Q, Cond)` | `(ok, Row)`, `(error, not_found)`, `(error, multiple_found)` |
| `count(Conn, Q)`, `exists(Conn, Q)` | integer, boolean |
| `update(Conn, Q, Changes)` | number of updated rows |
| `delete(Conn, Q)` | number of deleted rows |
| `insert(Conn, Model, Values)` | the inserted row |
| `raw(Conn, Sql, Params)`, `execute(Conn, Sql)` | rows, number of affected rows |
| `transaction(Conn, Fun)`, `rollback(Conn, Reason)` | `(ok, Result)` or `(error, Reason)` |

`update` and `delete` use `WHERE pk IN (SELECT ...)` so they work with joins,
ordering and limits. Values come back as the driver returns them: text is a
binary, NULL is `nil`. Efene strings (lists) passed as values are converted to
binaries.

## Differences with Django

- `exclude` across a `has_many` relation works on the joined rows (a left
  join): `exclude(Users, {posts__title__contains: 'x'})` keeps users without
  posts but also users that have a matching post and another one that doesn't
  (once per post, add `distinct`). Django uses a subquery and returns only the
  users with no matching post.
- Rows are plain maps, there are no model instances or `save()`.
- Unknown fields, relations and lookups raise when the query is compiled
  (`to_sql` or any `orm.repo` call), not when `filter` is called, see the
  table in Dynamic queries.
