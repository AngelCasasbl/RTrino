# List a table's columns

List a table's columns

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbListFields(conn, name, ...)

# S4 method for class 'TrinoConnection,Id'
dbListFields(conn, name, ...)

# S4 method for class 'TrinoConnection,ANY'
dbListFields(conn, name, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- name:

  Table name, required, in any form
  [dbExistsTable()](https://angelcasasbl.github.io/RTrino/reference/dbExistsTable-TrinoConnection-character-method.md)
  accepts: a string with one to three dot-separated parts, a
  [`DBI::Id()`](https://dbi.r-dbi.org/reference/Id.html) or a quoted
  identifier from
  [`DBI::SQL()`](https://dbi.r-dbi.org/reference/SQL.html). An
  unqualified name is resolved against the connection's catalog and
  schema.

- ...:

  Unused, for compatibility with the generic.

## Value

A character vector of column names.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbListFields(con, "nation")
DBI::dbListFields(con, DBI::Id(schema = "sf1", table = "region"))
DBI::dbDisconnect(con)
}
```
