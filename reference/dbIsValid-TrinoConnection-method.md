# Is this connection or result still usable?

A connection is valid until
[`dbDisconnect()`](https://dbi.r-dbi.org/reference/dbDisconnect.html) is
called. A result is valid until it is cleared by
[`dbClearResult()`](https://dbi.r-dbi.org/reference/dbClearResult.html) -
a result whose rows have all been fetched is still valid, so that
[`dbColumnInfo()`](https://dbi.r-dbi.org/reference/dbColumnInfo.html)
and friends keep working.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbIsValid(dbObj, ...)

# S4 method for class 'TrinoResult'
dbIsValid(dbObj, ...)
```

## Arguments

- dbObj:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  or
  [TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

A logical scalar.
