# Literal dates and date-times in dplyr pipelines

A `Date` or `POSIXct` from R, in a pipeline such as
`filter(orderdate >= !!as.Date("2026-01-01"))`, becomes a typed Trino
literal. dbplyr's default renders it as a plain string, which Trino
refuses to compare with a date.

## Usage

``` r
sql_escape_date.sql_dialect_trino(con, x)

sql_escape_datetime.sql_dialect_trino(con, x)
```

## Arguments

- con:

  The connection or dialect being translated for.

- x:

  A `Date` or date-time vector.

## Value

SQL.
