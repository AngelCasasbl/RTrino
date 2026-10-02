# Insert rows into an existing table

Builds one `INSERT INTO ... VALUES (...)` statement per batch of rows,
with values quoted as literals by
[`DBI::sqlAppendTable()`](https://dbi.r-dbi.org/reference/sqlAppendTable.html)
(which calls
[`dbQuoteIdentifier()`](https://dbi.r-dbi.org/reference/dbQuoteIdentifier.html)
and
[`dbQuoteLiteral()`](https://dbi.r-dbi.org/reference/dbQuoteLiteral.html)
for Trino) — there is no parameter binding to fall back on.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbAppendTable(conn, name, value, ..., row.names = NULL)
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

  A data frame with the rows to insert.

- ...:

  Takes `chunk_size`: how many rows go into a single `INSERT` statement,
  1000 by default. Every row is written into the statement as a literal,
  so a data frame much larger than this is split into several statements
  rather than one that may exceed the coordinator's query length limit.

- row.names:

  Unused: RTrino never writes row names as a column.

## Value

The number of rows inserted.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "memory", schema = "default")
DBI::dbCreateTable(con, "sales", c(id = "integer", label = "varchar"))
DBI::dbAppendTable(con, "sales", data.frame(id = 1:3, label = letters[1:3]))
DBI::dbGetQuery(con, "SELECT * FROM sales ORDER BY id")
DBI::dbRemoveTable(con, "sales")
DBI::dbDisconnect(con)
}
```
