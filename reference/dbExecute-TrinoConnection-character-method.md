# Execute a statement that returns no rows

Runs the statement to completion and reports how many rows Trino says it
changed: the count of an `INSERT`, an `UPDATE`, a `DELETE`, a `MERGE` or
a `CREATE TABLE ... AS SELECT`, and `0` for a statement that changes no
rows, such as `CREATE TABLE` or `DROP TABLE`.

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbExecute(conn, statement, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- statement:

  A single SQL statement.

- ...:

  Unused, for compatibility with the generic.

## Value

The number of affected rows, invisibly: a double, or `NA` for a data
change whose count Trino did not report.
