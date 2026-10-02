# SQL dialect for Trino

Describes Trino to `dbplyr` so that `dplyr` verbs on a
[TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
are translated to SQL Trino accepts. Registered, when dbplyr 2.6.0 or
later is loaded, as an S3 method for
[`dbplyr::sql_dialect()`](https://dbplyr.tidyverse.org/reference/sql_dialect.html),
the extension point that version introduced, which separates the SQL
dialect from the connection mechanism.

## Usage

``` r
sql_dialect.TrinoConnection(con)
```

## Arguments

- con:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

## Value

A `dbplyr` SQL dialect object.

## Details

Trino quotes identifiers with double quotes (the SQL standard), supports
the `WINDOW` clause, accepts `AS` before a table alias, and does not
allow `table.*` prefixes on a star selection.
