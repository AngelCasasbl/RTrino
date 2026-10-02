# Saving a query as a table

Trino has no temporary tables, so
[`compute()`](https://dplyr.tidyverse.org/reference/compute.html) needs
`temporary = FALSE` and a name, and then runs `CREATE TABLE ... AS`.
`ANALYZE` is not run afterwards: not every connector supports it, and
where it does it scans the whole new table.

## Usage

``` r
sql_query_save.sql_dialect_trino(con, sql, name, temporary = TRUE, ...)

sql_table_analyze.sql_dialect_trino(con, table, ...)
```

## Arguments

- con:

  The connection or dialect.

- sql:

  The query to save.

- name:

  The table to create.

- temporary:

  Whether a temporary table was asked for.

- ...:

  Unused.

- table:

  The table that would be analysed.

## Value

SQL, or `NULL` for no `ANALYZE`.
