# Does a table exist?

Asks `information_schema` for a count, so the answer costs the same
whatever the schema holds. Trino folds every identifier to lower case,
so the name is matched the same way: `"SALES"` exists if `sales` does,
as `SELECT * FROM SALES` would find it.

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbExistsTable(conn, name, ...)

# S4 method for class 'TrinoConnection,Id'
dbExistsTable(conn, name, ...)

# S4 method for class 'TrinoConnection,ANY'
dbExistsTable(conn, name, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- name:

  Table name, required. A string: `"table"` resolves against the
  connection's catalog and schema, `"schema.table"` keeps its catalog,
  and `"catalog.schema.table"` is used as given. Also a
  [`DBI::Id()`](https://dbi.r-dbi.org/reference/Id.html), with
  components named `catalog`, `schema` and `table`, or a quoted
  identifier from
  [`DBI::SQL()`](https://dbi.r-dbi.org/reference/SQL.html) or
  [`DBI::dbQuoteIdentifier()`](https://dbi.r-dbi.org/reference/dbQuoteIdentifier.html).

- ...:

  Unused, for compatibility with the generic.

## Value

A logical scalar. A name in a catalog or schema that does not exist is
simply `FALSE`, not an error.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbExistsTable(con, "nation")
DBI::dbExistsTable(con, "tpch.sf1.nation")
DBI::dbExistsTable(con, DBI::Id(catalog = "tpch", schema = "sf1",
                                table = "nation"))
DBI::dbExistsTable(con, "no_such_table")
DBI::dbDisconnect(con)
}
```
