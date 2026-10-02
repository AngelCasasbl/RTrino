# Trino result class

An S4 class representing the result of a statement submitted to Trino.

## Usage

``` r
# S4 method for class 'TrinoResult'
show(object)

# S4 method for class 'TrinoResult'
dbGetStatement(res, ...)

# S4 method for class 'TrinoResult'
dbGetRowCount(res, ...)

# S4 method for class 'TrinoResult'
dbGetRowsAffected(res, ...)

# S4 method for class 'TrinoResult'
dbColumnInfo(res, ...)
```

## Arguments

- object:

  A TrinoResult object.

- res:

  A TrinoResult object.

- ...:

  Unused, for compatibility with the generic.

## Details

Trino returns results page by page; each payload carries a `nextUri` to
follow until the query reaches a terminal state. Because that progress
is mutated as rows are fetched, and S4 slots are copy-on-modify, the
mutable part of the result lives in the `state` environment rather than
in slots. This makes `res` behave like a cursor, as DBI expects.

## Slots

- `connection`:

  The
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  the statement was sent on.

- `statement`:

  The SQL statement, as a string.

- `state`:

  Environment holding the mutable cursor state: `next_uri`, `columns`,
  `data`, `completed`, `rows_fetched`, `query_id`, and the `update_type`
  and `update_count` of a statement that changes something.
