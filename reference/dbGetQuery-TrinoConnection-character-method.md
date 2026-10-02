# Run a query and return all of its rows

Submits the statement, fetches every row and clears the result, even if
fetching fails.

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbGetQuery(conn, statement, n = -1, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- statement:

  A single SQL statement.

- n:

  Number of rows to return; `-1` (the default) returns all of them.

- ...:

  Unused, for compatibility with the generic.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbGetQuery(con, "SELECT * FROM nation LIMIT 5")
DBI::dbGetQuery(con, "SELECT * FROM nation", n = 3)
DBI::dbDisconnect(con)
}
```
