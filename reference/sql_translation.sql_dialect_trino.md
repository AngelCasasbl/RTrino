# Function translations for Trino

Extends dbplyr's base translation so that an R expression computes in
Trino what it computes in R, or fails, rather than quietly computing
something else:

## Usage

``` r
sql_translation.sql_dialect_trino(con)
```

## Arguments

- con:

  A Trino SQL dialect object.

## Value

A `dbplyr` SQL variant.

## Details

- `/` divides as a double, where Trino would truncate the quotient of
  two integers; `%%` takes the sign of the divisor, as in R.

- [`as.integer()`](https://rdrr.io/r/base/integer.html) and
  `as.integer64()` truncate towards zero, where a cast would round.

- [`paste()`](https://rdrr.io/r/base/paste.html),
  [`paste0()`](https://rdrr.io/r/base/paste.html) and `str_c()` cast
  every argument to `VARCHAR`, which Trino's `CONCAT_WS` requires.

- [`grepl()`](https://rdrr.io/r/base/grep.html),
  [`sub()`](https://rdrr.io/r/base/grep.html) and
  [`gsub()`](https://rdrr.io/r/base/grep.html) honour `fixed` and
  `ignore.case`, and rewrite R's `\\1` back-references into Trino's
  `$1`; [`sub()`](https://rdrr.io/r/base/grep.html) replaces the first
  match only.

- `days()`, `weeks()`,
  [`months()`](https://rdrr.io/r/base/weekday.POSIXt.html), `years()`,
  `hours()`, `minutes()` and `seconds()` build intervals, so
  `date + days(1)` works where `date + 1` does not.

- Casts name Trino types, and
  [`median()`](https://rdrr.io/r/stats/median.html) and
  [`quantile()`](https://rdrr.io/r/stats/quantile.html) use
  `approx_percentile`, which is the percentile Trino offers over an
  arbitrary number of rows. Null-safe comparison uses Trino's native
  `IS DISTINCT FROM` rather than dbplyr's portable `CASE WHEN` spelling.
