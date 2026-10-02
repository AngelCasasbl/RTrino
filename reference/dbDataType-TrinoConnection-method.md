# Map an R type to a Trino type

The inverse of
[`trino_type_to_r()`](https://angelcasasbl.github.io/RTrino/reference/trino_type_to_r.md):
used by
[`dbCreateTable()`](https://dbi.r-dbi.org/reference/dbCreateTable.html)
to pick a column type when the caller does not give one explicitly.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbDataType(dbObj, obj, ...)
```

## Arguments

- dbObj:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- obj:

  An R vector, or a data frame (one call per column).

- ...:

  Unused, for compatibility with the generic.

## Value

A string naming a Trino type.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbDataType(con, 1L)
DBI::dbDataType(con, Sys.Date())
DBI::dbDataType(con, data.frame(id = 1L, label = "a"))
DBI::dbDisconnect(con)
}
```
