# Submit a statement to Trino

Posts the statement to `/v1/statement` and returns immediately with a
[TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
cursor; the rows are pulled by
[`dbFetch()`](https://dbi.r-dbi.org/reference/dbFetch.html). A statement
that fails during planning raises an error here, because Trino reports
it in the response to the initial `POST`.

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbSendQuery(conn, statement, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- statement:

  A single SQL statement, without a trailing semicolon.

- ...:

  Unused, for compatibility with the generic.

## Value

A
[TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
object.

## Details

Query parameters are not supported: passing `params` is an error rather
than being silently ignored. Put values into the statement with
[`DBI::sqlInterpolate()`](https://dbi.r-dbi.org/reference/sqlInterpolate.html)
or
[`glue::glue_sql()`](https://glue.tidyverse.org/reference/glue_sql.html),
which quote them with
[`DBI::dbQuoteLiteral()`](https://dbi.r-dbi.org/reference/dbQuoteLiteral.html)
as Trino literals.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
res <- DBI::dbSendQuery(con, "SELECT 1 AS n")
DBI::dbFetch(res)
DBI::dbClearResult(res)

# Values go into the SQL as literals, quoted for Trino
sql <- DBI::sqlInterpolate(
  con, "SELECT count(*) AS n FROM orders WHERE orderdate >= ?since",
  since = as.Date("1998-01-01")
)
DBI::dbGetQuery(con, sql)

DBI::dbDisconnect(con)
}
```
