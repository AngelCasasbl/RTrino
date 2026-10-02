# Map a Trino type to the name of an R type

Reports the R type a column of the given Trino type is converted to.
Mostly useful for documentation and testing;
[`dbFetch()`](https://dbi.r-dbi.org/reference/dbFetch.html) converts
columns through `trino_cast_column()`.

## Usage

``` r
trino_type_to_r(type, bigint = c("integer64", "numeric", "character"))
```

## Arguments

- type:

  A Trino type name, with or without parameters, as a single string.

- bigint:

  How `BIGINT` is handled; see
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Value

A string naming an R class.

## Examples

``` r
trino_type_to_r("varchar(10)")
#> [1] "character"
trino_type_to_r("bigint")
#> [1] "integer64"
trino_type_to_r("bigint", bigint = "numeric")
#> [1] "numeric"
trino_type_to_r("timestamp(3) with time zone")
#> [1] "POSIXct"
```
