# Release a Trino result

Frees the buffered rows and marks the cursor cleared. If the query is
still running on the server, a `DELETE` is sent to its `nextUri` so the
coordinator stops working on it instead of letting it run to completion
for nobody.

## Usage

``` r
# S4 method for class 'TrinoResult'
dbClearResult(res, ...)
```

## Arguments

- res:

  A
  [TrinoResult](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

`TRUE`, invisibly.
