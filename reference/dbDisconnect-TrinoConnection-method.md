# Disconnect from Trino

Marks the connection as closed. Trino's REST API is stateless, so
nothing is sent to the server; any later use of `conn` raises an error.

## Usage

``` r
# S4 method for class 'TrinoConnection'
dbDisconnect(conn, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- ...:

  Unused, for compatibility with the generic.

## Value

`TRUE`, invisibly.
