# Instantiate the Trino driver

Creates the driver object passed as the first argument to
[`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).
The call has no side effects and always succeeds.

## Usage

``` r
Trino()
```

## Value

A
[TrinoDriver](https://angelcasasbl.github.io/RTrino/reference/TrinoDriver-class.md)
object.

## Examples

``` r
drv <- Trino()
drv
#> <TrinoDriver>
```
