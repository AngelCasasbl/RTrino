# Quote identifiers and strings for Trino

Trino follows the SQL standard: identifiers are wrapped in double quotes
with embedded double quotes doubled, and string literals are wrapped in
single quotes with embedded single quotes doubled. A value that is
already [`DBI::SQL()`](https://dbi.r-dbi.org/reference/SQL.html) is
returned unchanged rather than quoted a second time.

## Usage

``` r
# S4 method for class 'TrinoConnection,character'
dbQuoteIdentifier(conn, x, ...)

# S4 method for class 'TrinoConnection,SQL'
dbQuoteIdentifier(conn, x, ...)

# S4 method for class 'TrinoConnection,character'
dbQuoteString(conn, x, ...)

# S4 method for class 'TrinoConnection,SQL'
dbQuoteString(conn, x, ...)
```

## Arguments

- conn:

  A
  [TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  object.

- x:

  A character vector, or an identifier for
  [`dbQuoteIdentifier()`](https://dbi.r-dbi.org/reference/dbQuoteIdentifier.html).

- ...:

  Unused, for compatibility with the generic.

## Value

A [DBI::SQL](https://dbi.r-dbi.org/reference/SQL.html) object.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
                      catalog = "tpch", schema = "tiny")
DBI::dbQuoteIdentifier(con, "my column")
DBI::dbQuoteString(con, "O'Brien")
DBI::dbDisconnect(con)
}
```
