# Explain a Trino query

Trino's `EXPLAIN` takes the statement directly, without the
parenthesised options some engines require.

## Usage

``` r
sql_query_explain.sql_dialect_trino(con, sql, ...)
```

## Arguments

- con:

  A Trino SQL dialect object.

- sql:

  A query.

- ...:

  Unused, for compatibility with the generic.

## Value

The `EXPLAIN` statement, as SQL.

## Details

Column discovery (`sql_query_fields()`) is deliberately left to dbplyr's
default, which wraps the query in `WHERE 0 = 1`. On Trino that plans
without reading any data, exactly like the `LIMIT 0` the specification
suggests, and the default is built from dbplyr internals that a backend
should not reach into.
