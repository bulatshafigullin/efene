# efene shop API example

A REST API written in efene on top of the [ORM example](../orm): the backend
defines products (with a foreign key to categories) and the filters clients can
use on them, each request's query params are matched against those filters,
validated and turned into an ORM query.

```
GET /products?category=laptops,phones&min_price=30&in_stock=true&ordering=-price&page=1
GET /categories
```

## Running it

Needs Elixir (to build postgrex and cowboy) and PostgreSQL, it uses a database
called `efene_shop_example` (`make run DB=other` to change it) and port 8088
(`SHOP_PORT`).

```
make -C ../.. escript   # build the efene compiler
make deps               # fetch and compile postgrex and cowboy with mix
make run                # start the server, make example requests, print the responses
make serve              # keep it running and try it with curl
```

`make build` compiles `src/shop_api.fn` with `--root ../orm/src`: the shop's
modules are found in `src`, the ORM's (`orm.query`, `orm.filterset`...) in the
ORM example, nothing is copied.

## Declaring the filters

`src/catalog/product_filters.fn` is the whole contract with the client:

```
fn filterset
  case:
    {filters: {q: (fn search:2, text),
               name: (name__icontains, text),
               category: (category__slug__in, (list, text)),
               min_price: (price_cents__gte, money),
               max_price: (price_cents__lte, money),
               in_stock: (fn in_stock:2, bool)},
     ordering: {name: name, price: price_cents, stock: stock, category: category__name},
     default_ordering: [name],
     default_page_size: 5,
     max_page_size: 50}
end

fn search
  case Query, Text: filter(Query, #q ({name__icontains: Text} | {description__icontains: Text}))
end
```

Each filter is `(Target, Type)`. The target is an ORM lookup the parsed value is
used with (it can go through relations, `category__slug__in` joins categories)
or a function `(Query, Value) -> Query` for anything else. The type parses and
validates the value:

| type | accepts | value |
|---|---|---|
| `text` | non empty text | binary |
| `int` | `42` | integer |
| `money` | `10`, `10.5`, `10.50` | cents, `1050` |
| `bool` | `true/false`, `1/0`, `yes/no` | boolean |
| `(choice, [a, b])` | one of the names | the atom |
| `(list, Type)` | repeated (`?c=a&c=b`) or comma separated (`?c=a,b`) | list |

`ordering` maps the names clients can order by to fields (`?ordering=category,-price`),
the primary key is always added last so pages are stable. `page` and `page_size`
paginate.

## Handling a request

`src/api/products.fn`:

```
Base = models.product.objects() ->
  filter({active: true}) ->
  select_related([category])
match orm.filterset.apply(Base, catalog.product_filters.filterset(), cowboy_req.parse_qs(Req)):
  case (ok, Query, Pagination):
    Rows = orm.repo.all(Db, orm.filterset.paginate(Query, Pagination))
    ... 200 with count, page, page_size and results
  case (error, Errors):
    api.http.json(400, {errors: maps.from_list(Errors)}, Req)
end
```

The base query holds what the client can't change (only active products), the
client's filters are added on top. Every problem is reported at once:

```
GET /products?min_price=ten&colour=red&in_stock=maybe&ordering=weight&page=0
400
{
  "errors": {
    "colour": "unknown filter, use one of: category, in_stock, max_price, min_price, name, q",
    "in_stock": "must be true or false",
    "min_price": "must be an amount like 10 or 10.50",
    "ordering": "unknown ordering, use one of: category, name, price, stock",
    "page": "must be at least 1"
  }
}
```

Param names are matched against the declared names as binaries, so a client
can't create atoms, and values only reach SQL as query parameters.

## Layout

| module | file | |
|---|---|---|
| `shop_api` | src/shop_api.fn | starts the server, `demo/0` makes example requests |
| `shop.db` | src/shop/db.fn | connection pool, tables and sample data |
| `models.product`, `models.category` | src/models/*.fn | the models |
| `catalog.product_filters` | src/catalog/product_filters.fn | the filters clients can use |
| `api.products`, `api.categories` | src/api/*.fn | cowboy handlers |
| `api.http` | src/api/http.fn | JSON replies |
| `orm.filterset` | ../orm/src/orm/filterset.fn | matches params to filters (generic) |

## Note on dependencies

`mix deps.get` reports two advisories in cowlib 2.20.0 (the latest release when
this was written): EEF-CVE-2026-43966 (response splitting in structured header
string escaping) and EEF-CVE-2026-43969 (cookie encoding). This example uses
neither structured header escaping nor cookies, update cowlib when a fixed
release is out.
