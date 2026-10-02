# Create a table

Trino has no temporary tables, so `temporary = TRUE` is an error rather
than being silently ignored.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbCreateTable(conn, name, fields, ..., row.names = NULL, temporary = FALSE)
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

- fields:

  Either a named character vector of Trino types, one per column, or a
  data frame whose columns' R types are mapped to Trino types with
  [`dbDataType()`](https://dbi.r-dbi.org/reference/dbDataType.html).

- ...:

  Unused, for compatibility with the generic.

- row.names:

  Unused: RTrino never writes row names as a column.

- temporary:

  Must be `FALSE`.

## Value

`TRUE`, invisibly.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "memory", schema = "default")
DBI::dbCreateTable(con, "sales", c(id = "bigint", label = "varchar"))
DBI::dbListFields(con, "sales")
DBI::dbRemoveTable(con, "sales")

# The column types can also follow a data frame's
DBI::dbCreateTable(con, "sales", data.frame(id = 1L, label = "a"))
DBI::dbRemoveTable(con, "sales")

DBI::dbDisconnect(con)
}
```
