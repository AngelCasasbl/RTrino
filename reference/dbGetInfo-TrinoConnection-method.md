# Metadata about a Trino connection

Reports the connection's settings plus the coordinator's version, read
from `/v1/info`. If that endpoint cannot be reached, `db.version` is
`NA` rather than an error, so the rest of the metadata stays available.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbGetInfo(dbObj, ...)
```

## Arguments

- dbObj:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

A list with `db.version`, `host`, `port`, `user`, `catalog` and
`schema`.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbGetInfo(con)
DBI::dbDisconnect(con)
}
```
