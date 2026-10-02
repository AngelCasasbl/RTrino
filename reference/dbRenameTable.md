# Rename a table

Not a DBI generic: DBI has no `dbRenameTable()`, so RTrino defines its
own, the way RPresto does for Presto.

## Usage

``` r
dbRenameTable(conn, name, new_name, ...)

# S4 method for class 'TrinoConnection'
dbRenameTable(conn, name, new_name, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- name:

  Current table name, in any form
  [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html)
  accepts.

- new_name:

  New table name, in the same forms.

- ...:

  Unused, for compatibility with the generic.

## Value

`TRUE`, invisibly.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "memory", schema = "default")
DBI::dbWriteTable(con, "sales", data.frame(id = 1:3))
dbRenameTable(con, "sales", "sales_old")
DBI::dbExistsTable(con, "sales_old")
DBI::dbRemoveTable(con, "sales_old")
DBI::dbDisconnect(con)
}
```
