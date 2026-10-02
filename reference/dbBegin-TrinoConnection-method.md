# Start, commit and roll back a transaction

Every statement runs inside Trino's engine-level transaction mechanism:
[`dbBegin()`](https://dbi.r-dbi.org/reference/transactions.html) sends
`START TRANSACTION` and keeps the transaction id Trino answers with,
which is then carried on every later request until
[`dbCommit()`](https://dbi.r-dbi.org/reference/transactions.html) or
[`dbRollback()`](https://dbi.r-dbi.org/reference/transactions.html)
sends `COMMIT` or `ROLLBACK` and clears it.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbBegin(conn, ...)

# S4 method for class 'TrinoConnection'
dbCommit(conn, ...)

# S4 method for class 'TrinoConnection'
dbRollback(conn, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

`TRUE`, invisibly.

## Details

Whether a `ROLLBACK` actually undoes a write depends on the connector
behind the active catalog, not on RTrino: Iceberg and Delta Lake tables
support it, most others (including Hive, strictly) only partially, and
Trino's own synthetic catalogs (`memory`, `tpch`, ...) not at all.
[`dbBegin()`](https://dbi.r-dbi.org/reference/transactions.html) warns
when the active catalog is one of the latter.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")

# tpch holds no real storage, so dbBegin() warns that a ROLLBACK would
# undo nothing. On an Iceberg or Delta Lake catalog it would not.
DBI::dbBegin(con)
DBI::dbGetQuery(con, "SELECT count(*) AS n FROM nation")
DBI::dbCommit(con)

DBI::dbDisconnect(con)
}
```
