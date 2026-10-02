# dbplyr edition used by Trino connections

dbplyr refuses to work with a backend that has not declared the second
edition of its interface, so the declaration is explicit even though
every method here is written against the current API.

## Usage

``` r
dbplyr_edition.TrinoConnection(con)
```

## Arguments

- con:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

## Value

`2L`.
