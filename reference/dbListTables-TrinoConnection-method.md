# List the tables in the connection's schema

List the tables in the connection's schema

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbListTables(conn, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

A character vector of table names.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbListTables(con)
DBI::dbDisconnect(con)
}
```
