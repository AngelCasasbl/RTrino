# Trino connection class

An S4 class representing a connection to a Trino cluster. Trino's REST
API is stateless, so the object only holds the information needed to
build requests; no socket is kept open.

## Usage

``` r
# S4 method for class 'TrinoConnection'
show(object)
```

## Arguments

- object:

  A TrinoConnection object.

## Slots

- `host`:

  Base URL of the coordinator, including the scheme.

- `port`:

  Coordinator port.

- `user`:

  Trino user name.

- `catalog`:

  Trino catalog.

- `schema`:

  Trino schema.

- `session.timezone`:

  Session time zone used for timestamp columns.

- `bigint`:

  How `BIGINT` columns are returned; see
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

- `extra.headers`:

  Named list of additional HTTP headers.

- `source`:

  Value of the `X-Trino-Source` header.

- `auth`:

  Authentication closure, or `NULL` for no authentication.

- `ssl_options`:

  SSL options as returned by
  [`trino_ssl()`](https://angelcasasbl.github.io/RTrino/reference/trino_ssl.md).

- `timeout`:

  Seconds allowed for each HTTP request, or `Inf`.

- `valid`:

  Environment holding the connection's validity flag.

- `transaction`:

  Environment holding the active transaction id, or `NULL` when there is
  none.
