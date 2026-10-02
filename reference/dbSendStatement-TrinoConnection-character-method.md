# Submit a statement that changes something

Unlike
[dbSendQuery()](https://angelcasasbl.github.io/RTrino/reference/dbSendQuery-TrinoConnection-character-method.md),
runs the statement to completion before returning, so that
[`dbGetRowsAffected()`](https://dbi.r-dbi.org/reference/dbGetRowsAffected.html)
answers straight away, as DBI requires: Trino only reports the count
once the statement has finished.

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbSendStatement(conn, statement, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- statement:

  A single SQL statement, without a trailing semicolon.

- ...:

  Unused, for compatibility with the generic.

## Value

A
[TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
object whose statement has finished.
