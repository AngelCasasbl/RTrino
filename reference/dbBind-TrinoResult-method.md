# Parameters are not supported

Trino's client protocol has no parameter binding of its own, so rather
than ignoring the values,
[`dbBind()`](https://dbi.r-dbi.org/reference/dbBind.html) fails.

## Usage

``` r
# S4 method for class 'TrinoResult'
dbBind(res, params, ...)
```

## Arguments

- res:

  A
  [TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  object.

- params:

  Unused.

- ...:

  Unused.

## Value

Never returns.
