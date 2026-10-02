# Quote R values as Trino literals

Turns R values into SQL literals Trino accepts where a value of the
matching type is expected. Used by
[`DBI::sqlInterpolate()`](https://dbi.r-dbi.org/reference/sqlInterpolate.html)
and
[`glue::glue_sql()`](https://glue.tidyverse.org/reference/glue_sql.html),
and so the way to put values into a statement, since RTrino has no
parameter binding. Missing values become `NULL`.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbQuoteLiteral(conn, x, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- x:

  A vector to quote.

- ...:

  Unused, for compatibility with the generic.

## Value

A [DBI::SQL](https://dbi.r-dbi.org/reference/SQL.html) object.

## Details

- character and factor: `'text'`, with embedded quotes doubled;

- logical: `TRUE` or `FALSE`;

- integer and `integer64`: the integer's digits;

- double: a `DOUBLE` literal that reads back as the same double, such as
  `0.30000000000000004E0`, or `nan()`, `infinity()` or `-infinity()`;

- `Date`: `DATE '2026-01-15'`;

- `POSIXct`: `TIMESTAMP '2026-01-15 10:30:00.123456'`, the instant as a
  wall-clock time in the connection's `session.timezone`, which is how
  Trino reads it back;

- a list of raw vectors: `X'0102FF'`.

Other classes are quoted by DBI's default method.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbQuoteLiteral(con, as.Date("2026-01-15"))
DBI::sqlInterpolate(
  con, "SELECT * FROM orders WHERE orderdate >= ?since AND urgent = ?flag",
  since = as.Date("2026-01-01"), flag = TRUE
)
DBI::dbDisconnect(con)
}
```
