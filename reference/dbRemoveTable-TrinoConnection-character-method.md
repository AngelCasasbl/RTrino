# Drop a table

Drop a table

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbRemoveTable(conn, name, ...)

# S4 method for class 'TrinoConnection,Id'
dbRemoveTable(conn, name, ...)

# S4 method for class 'TrinoConnection,ANY'
dbRemoveTable(conn, name, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- name:

  Table name, in any form
  [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html)
  accepts.

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
DBI::dbRemoveTable(con, "sales")
DBI::dbExistsTable(con, "sales")
DBI::dbDisconnect(con)
}
```
