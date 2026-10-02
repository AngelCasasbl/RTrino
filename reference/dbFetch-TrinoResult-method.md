# Fetch rows from a Trino result

Pulls rows from the cursor, following Trino's `nextUri` chain as needed,
and converts each column to its R type according to the column's
declared Trino type and the connection's `bigint` setting.

## Usage

``` r
# S4 method for class 'TrinoResult'
dbFetch(res, n = -1, ...)
```

## Arguments

- res:

  A
  [TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  object.

- n:

  Number of rows to fetch. `-1` or `Inf` (the default is `-1`) fetches
  every remaining row, paginating until the query finishes. A positive
  `n` returns at most that many rows, pulling as many pages as needed
  and keeping the remainder buffered on the cursor for the next call.
  `0` returns no rows but the result's columns, with their types.

- ...:

  Unused, for compatibility with the generic.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html). Once the
result is exhausted, a zero-row tibble with the right columns and types.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
res <- DBI::dbSendQuery(con, "SELECT * FROM orders")
while (!DBI::dbHasCompleted(res)) {
  chunk <- DBI::dbFetch(res, n = 4000)
  # process chunk; here, just count its rows
  cat(nrow(chunk), "rows\n")
}
DBI::dbClearResult(res)
DBI::dbDisconnect(con)
}
```
