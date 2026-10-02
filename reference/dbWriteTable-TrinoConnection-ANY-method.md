# Write a table

Creates the table with
[`dbCreateTable()`](https://dbi.r-dbi.org/reference/dbCreateTable.html)
and fills it with
[`dbAppendTable()`](https://dbi.r-dbi.org/reference/dbAppendTable.html).
`CREATE TABLE` cannot be undone by
[`dbRollback()`](https://dbi.r-dbi.org/reference/transactions.html) on
most connectors, so `overwrite = TRUE` plays it safe on its own: it
renames the existing table rather than dropping it, and restores it if
anything fails before the new table is fully written.

## Usage

``` r
# S4 method for class 'TrinoConnection,ANY'
dbWriteTable(
  conn,
  name,
  value,
  ...,
  overwrite = FALSE,
  append = FALSE,
  field.types = NULL,
  temporary = FALSE,
  row.names = NULL,
  chunk_size = 1000L
)

# S4 method for class 'TrinoConnection,Id'
dbWriteTable(conn, name, value, ...)
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

- value:

  A data frame to write.

- ...:

  Unused, for compatibility with the generic.

- overwrite:

  Drop and recreate the table if it already exists.

- append:

  Add to the table if it already exists, instead of creating it.

- field.types:

  A named character vector of Trino types, overriding the types
  [`dbDataType()`](https://dbi.r-dbi.org/reference/dbDataType.html)
  would otherwise infer. Not allowed together with `append`.

- temporary:

  Must be `FALSE`: Trino has no temporary tables.

- row.names:

  Unused: RTrino never writes row names as a column.

- chunk_size:

  Passed to
  [`dbAppendTable()`](https://dbi.r-dbi.org/reference/dbAppendTable.html).

## Value

`TRUE`, invisibly.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "memory", schema = "default")
DBI::dbWriteTable(con, "sales", data.frame(id = 1:3, label = letters[1:3]))
DBI::dbWriteTable(con, "sales", data.frame(id = 4L, label = "d"),
                  append = TRUE)
DBI::dbGetQuery(con, "SELECT * FROM sales ORDER BY id")

# Replace the table and its contents
DBI::dbWriteTable(con, "sales", data.frame(id = 9L, label = "z"),
                  overwrite = TRUE)
DBI::dbGetQuery(con, "SELECT * FROM sales")

DBI::dbRemoveTable(con, "sales")
DBI::dbDisconnect(con)
}
```
