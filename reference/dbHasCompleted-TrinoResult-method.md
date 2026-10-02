# Have all rows of a result been consumed?

`TRUE` once Trino has stopped handing out pages *and* the rows already
pulled have been handed to the caller. A result that has finished on the
server but still holds buffered rows is not complete, so a
`while (!dbHasCompleted(res))` loop over
[`dbFetch()`](https://dbi.r-dbi.org/reference/dbFetch.html) sees every
row.

## Usage

``` r
# S4 method for class 'TrinoResult'
dbHasCompleted(res, ...)
```

## Arguments

- res:

  A
  [TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

A logical scalar.
