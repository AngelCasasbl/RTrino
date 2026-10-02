# A Trino connection that never talks to a server

Returns an object that carries the `TrinoConnection` class without
holding a session, so
[`sql_dialect.TrinoConnection()`](https://angelcasasbl.github.io/RTrino/reference/sql_dialect.TrinoConnection.md)
and, through it,
[`sql_translation.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_translation.sql_dialect_trino.md)
dispatch as they would on a live connection. Useful for inspecting the
SQL a `dplyr` pipeline produces, and used by this package's own
translation tests, which then need no coordinator at all. Anything that
reaches the database, such as
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html), still
fails.

## Usage

``` r
simulate_trino()
```

## Value

A simulated `dbplyr` connection of class `TrinoConnection`.

## Examples

``` r
if (requireNamespace("dbplyr", quietly = TRUE) &&
      utils::packageVersion("dbplyr") >= "2.6.0") {
  con <- simulate_trino()
  dbplyr::translate_sql(as.numeric(x), con = con)
}
#> <SQL> CAST("x" AS DOUBLE)
```
