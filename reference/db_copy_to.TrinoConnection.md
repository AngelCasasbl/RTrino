# `copy_to()` for Trino

Overrides dbplyr's default, which wraps the write in a transaction
([dbBegin()](https://angelcasasbl.github.io/RTrino/reference/dbBegin-TrinoConnection-method.md)).
Whether that transaction could actually be rolled back depends on the
catalog's connector, and `CREATE TABLE` itself is not something most
connectors undo, so the write goes straight to
[`dbWriteTable()`](https://dbi.r-dbi.org/reference/dbWriteTable.html)
instead, which already has its own way of playing it safe on
`overwrite = TRUE`. `temporary` defaults to `TRUE`, as in the generic,
which means the call fails unless the caller passes `temporary = FALSE`:
Trino has no temporary tables.

## Usage

``` r
db_copy_to.TrinoConnection(
  con,
  table,
  values,
  ...,
  overwrite = FALSE,
  types = NULL,
  temporary = TRUE,
  unique_indexes = NULL,
  indexes = NULL,
  analyze = TRUE,
  in_transaction = TRUE
)
```

## Arguments

- con:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- table, values, overwrite, types, temporary:

  Passed to
  [`dbWriteTable()`](https://dbi.r-dbi.org/reference/dbWriteTable.html).

- unique_indexes, indexes, analyze, in_transaction, ...:

  Unused, for compatibility with the generic.

## Value

`table`.
