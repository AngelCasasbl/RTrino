# Changelog

## RTrino 0.1.0

First release: a DBI backend for Trino over the cluster’s HTTP REST API.

- [`Trino()`](https://angelcasasbl.github.io/RTrino/reference/Trino.md),
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html),
  [`dbDisconnect()`](https://dbi.r-dbi.org/reference/dbDisconnect.html)
  and [`dbIsValid()`](https://dbi.r-dbi.org/reference/dbIsValid.html)
  for the connection’s life cycle.
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html) probes
  `/v1/info` so a wrong address or a rejected credential fails at
  connection time.
- [`dbSendQuery()`](https://dbi.r-dbi.org/reference/dbSendQuery.html),
  [`dbFetch()`](https://dbi.r-dbi.org/reference/dbFetch.html),
  [`dbGetQuery()`](https://dbi.r-dbi.org/reference/dbGetQuery.html),
  [`dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html),
  [`dbHasCompleted()`](https://dbi.r-dbi.org/reference/dbHasCompleted.html)
  and
  [`dbClearResult()`](https://dbi.r-dbi.org/reference/dbClearResult.html)
  for queries, with automatic `nextUri` pagination, chunked fetching
  through `dbFetch(n = )`, and server-side cancellation when a running
  result is cleared.
- [`dbListTables()`](https://dbi.r-dbi.org/reference/dbListTables.html),
  [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html),
  [`dbListFields()`](https://dbi.r-dbi.org/reference/dbListFields.html),
  [`dbGetInfo()`](https://dbi.r-dbi.org/reference/dbGetInfo.html),
  [`dbColumnInfo()`](https://dbi.r-dbi.org/reference/dbColumnInfo.html),
  [`dbQuoteIdentifier()`](https://dbi.r-dbi.org/reference/dbQuoteIdentifier.html)
  and
  [`dbQuoteString()`](https://dbi.r-dbi.org/reference/dbQuoteString.html)
  for introspection and quoting.
- Trino to R type conversion, with `BIGINT` returned as exact
  [`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html)
  by default (`bigint = "numeric"` or `"character"` for the
  alternatives), `DOUBLE` bit for bit, timestamps to the microsecond,
  and `TIMESTAMP WITH TIME ZONE` resolved per value whether the server
  sends a zone name or an offset.
- Authentication through
  [`trino_auth_basic()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md),
  [`trino_auth_jwt()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  and
  [`trino_auth_oauth2()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md);
  TLS settings through
  [`trino_ssl()`](https://angelcasasbl.github.io/RTrino/reference/trino_ssl.md),
  including `ca_bundle` for an internal certificate authority.
- `dplyr` support via a dbplyr SQL dialect, requiring dbplyr \>= 2.6.0.
  [`filter_out()`](https://dplyr.tidyverse.org/reference/filter.html),
  from dplyr 1.2.0, uses Trino’s native `IS DISTINCT FROM` rather than
  the `CASE WHEN` comparison dbplyr falls back to. dplyr 1.2.0’s
  [`when_any()`](https://dplyr.tidyverse.org/reference/when-any-all.html)/[`when_all()`](https://dplyr.tidyverse.org/reference/when-any-all.html)
  and
  [`recode_values()`](https://dplyr.tidyverse.org/reference/recode-and-replace-values.html)/[`replace_values()`](https://dplyr.tidyverse.org/reference/recode-and-replace-values.html)/
  [`replace_when()`](https://dplyr.tidyverse.org/reference/case-and-replace-when.html)
  are not translated, because dbplyr 2.6.0 has no translation for them
  on any backend.
- [`simulate_trino()`](https://angelcasasbl.github.io/RTrino/reference/simulate_trino.md)
  returns a connection that carries the dialect without a session, for
  inspecting translated SQL with no cluster to hand.

### Notes on the specification

Two details differ from the design document this release was built from:

- The driver class is `TrinoDriver` throughout (the document spelled it
  `TrinoDiver` in places).
- [`dbIsValid()`](https://dbi.r-dbi.org/reference/dbIsValid.html) on a
  result reports whether the result has been *cleared*, not whether the
  query has finished. Reporting `FALSE` for a finished result would
  break DBI’s contract, under which
  [`dbColumnInfo()`](https://dbi.r-dbi.org/reference/dbColumnInfo.html)
  and
  [`dbGetRowCount()`](https://dbi.r-dbi.org/reference/dbGetRowCount.html)
  keep working until
  [`dbClearResult()`](https://dbi.r-dbi.org/reference/dbClearResult.html).
  [`dbHasCompleted()`](https://dbi.r-dbi.org/reference/dbHasCompleted.html)
  is what reports that all rows have been consumed.
- Column discovery for `dplyr` uses dbplyr’s default (`WHERE 0 = 1`)
  rather than `LIMIT 0`. Both plan without reading data on Trino, and
  the default avoids depending on dbplyr internals.

### Performance and behaviour changes after benchmarking

- Queries no longer pause between the empty pages Trino returns while it
  queues and plans. Measured against Trino 483, that backoff added about
  150 ms to *every* query, roughly six times the cost of the HTTP calls
  themselves; `SELECT 1` went from 220 ms to 30 ms. A capped pause still
  guards against a server that returns empty pages instantly and
  forever.
- [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html)
  counts a row in `information_schema.tables` instead of listing the
  schema and matching in R. The old form cost +0.005 ms per table in the
  schema (36.5 ms at 1200 tables) where this stays flat at ~28 ms. It
  also now accepts `"schema.table"` and `"catalog.schema.table"`,
  consistently with
  [`dbListFields()`](https://dbi.r-dbi.org/reference/dbListFields.html),
  and reports `FALSE` rather than an error for a name in a catalog that
  does not exist.
- Query failures are raised as classed conditions (`trino_query_error`,
  and `trino_canceled` for a cancelled query) carrying the server’s
  `error_name`, `error_code`, `error_type` and `query_id`, so callers
  can react to a specific Trino error without matching on the message
  text.

### Fixes after the September 2026 audit

Verified against Trino 483; the audit’s identifiers are given in
brackets.

#### Values

- `BIGINT` and `DOUBLE` values were read through text, because Trino
  sends them as JSON numbers: `3000000000` came back as `NA`, digits
  were lost past 2^53 and doubles were rounded to 15 digits. They are
  now converted without going through text, and 15 000 values of each
  agree with Trino’s own rendering bit for bit (C1). The lowest
  `BIGINT`, which bit64 keeps for `NA`, is `NA` with a warning.
- Converting a result is done a column at a time rather than a cell at a
  time (m4).
- RTrino now declares the `PARAMETRIC_DATETIME` client capability,
  without which Trino rounded every timestamp to milliseconds (m1).
- A column of a type RTrino does not know warns once per result, not
  once per fetched chunk; `INTERVAL` columns are read as text, and a
  bare `NULL` as a logical (m3).

#### DBI

- [`dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html)
  returns the number of rows Trino says a statement changed, and `0` for
  DDL, instead of `NA` every time;
  [`dbSendStatement()`](https://dbi.r-dbi.org/reference/dbSendStatement.html)
  runs the statement to completion so that
  [`dbGetRowsAffected()`](https://dbi.r-dbi.org/reference/dbGetRowsAffected.html)
  answers straight away (M4).
- [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html)
  and
  [`dbListFields()`](https://dbi.r-dbi.org/reference/dbListFields.html)
  accept [`DBI::Id()`](https://dbi.r-dbi.org/reference/Id.html) and
  quoted identifiers, and
  [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html)
  ignores case as Trino does.
  [`dbQuoteIdentifier()`](https://dbi.r-dbi.org/reference/dbQuoteIdentifier.html)
  and
  [`dbQuoteString()`](https://dbi.r-dbi.org/reference/dbQuoteString.html)
  return [`SQL()`](https://dbi.r-dbi.org/reference/SQL.html) unchanged.
  [`dbColumnInfo()`](https://dbi.r-dbi.org/reference/dbColumnInfo.html)
  and `dbFetch(n = 0)` describe the columns before the first row is
  fetched (M3). `Id` has methods of its own, which removes S4’s note
  about an ambiguous method (m6).
- Passing `params` is an error rather than being ignored, and
  [`dbBind()`](https://dbi.r-dbi.org/reference/dbBind.html) says that
  parameters are not supported.
  [`dbQuoteLiteral()`](https://dbi.r-dbi.org/reference/dbQuoteLiteral.html)
  writes typed Trino literals (`DATE '...'`, `TIMESTAMP '...'`, `TRUE`,
  doubles that read back exactly), so
  [`sqlInterpolate()`](https://dbi.r-dbi.org/reference/sqlInterpolate.html)
  and
  [`glue::glue_sql()`](https://glue.tidyverse.org/reference/glue_sql.html)
  work with dates and logicals (M5).
- [`dbWriteTable()`](https://dbi.r-dbi.org/reference/dbWriteTable.html),
  [`dbAppendTable()`](https://dbi.r-dbi.org/reference/dbAppendTable.html),
  [`dbCreateTable()`](https://dbi.r-dbi.org/reference/dbCreateTable.html)
  and [`dbDataType()`](https://dbi.r-dbi.org/reference/dbDataType.html)
  write data frames. Rows go in as `INSERT INTO ... VALUES` statements
  of `chunk_size` rows each (1000 by default), every value a literal,
  since Trino’s protocol has no parameter binding.
  `dbWriteTable(overwrite = TRUE)` renames the existing table rather
  than dropping it, and restores it if the write fails.
  [`dbRemoveTable()`](https://dbi.r-dbi.org/reference/dbRemoveTable.html)
  and
  [`dbRenameTable()`](https://angelcasasbl.github.io/RTrino/reference/dbRenameTable.md)
  drop and rename tables; `temporary = TRUE` is an error, because Trino
  has no temporary tables.
- [`dbBegin()`](https://dbi.r-dbi.org/reference/transactions.html),
  [`dbCommit()`](https://dbi.r-dbi.org/reference/transactions.html),
  [`dbRollback()`](https://dbi.r-dbi.org/reference/transactions.html)
  and
  [`dbWithTransaction()`](https://dbi.r-dbi.org/reference/dbWithTransaction.html)
  run statements inside a Trino transaction. Whether a `ROLLBACK` undoes
  a write depends on the connector behind the catalog;
  [`dbBegin()`](https://dbi.r-dbi.org/reference/transactions.html) warns
  for the catalogs that hold no real storage (`memory`, `system`,
  `tpch`, `tpcds`, `jmx` and `blackhole`).

#### Connections

- [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html) gains
  `timeout`, which bounds each HTTP request (60 seconds by default), and
  `query_max_run_time`, which bounds a query on the cluster (M6).
- [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  refuses to send credentials to an `http://` host unless
  `allow_http_auth = TRUE` (M7).
- Arguments are validated before the coordinator is contacted, with
  plain messages: a `catalog` of length two, a fractional `port`, a port
  written in both `host` and `port` (a port in `host` alone is now
  used), unnamed or non-scalar `extra.headers`, and a non-numeric `n` in
  [`dbFetch()`](https://dbi.r-dbi.org/reference/dbFetch.html) (m3).
- 429, 502, 503 and 504 responses are retried after a short pause, as
  Trino’s protocol asks; before, only 429 and 503 were (m5).

#### dplyr

- `/` divides as a double, `%%` takes the sign of the divisor, and
  [`as.integer()`](https://rdrr.io/r/base/integer.html) and
  `as.integer64()` truncate, as in R (M1, m2).
- [`grepl()`](https://rdrr.io/r/base/grep.html),
  [`sub()`](https://rdrr.io/r/base/grep.html) and
  [`gsub()`](https://rdrr.io/r/base/grep.html) honour `fixed` and
  `ignore.case` and accept R’s `\\1` back-references;
  [`sub()`](https://rdrr.io/r/base/grep.html) replaces only the first
  match, instead of generating a call Trino does not have (M1, M2).
- [`paste()`](https://rdrr.io/r/base/paste.html),
  [`paste0()`](https://rdrr.io/r/base/paste.html) and `str_c()` accept
  columns of any type (M2).
- `days()`, `weeks()`,
  [`months()`](https://rdrr.io/r/base/weekday.POSIXt.html), `years()`,
  `hours()`, `minutes()` and `seconds()` build intervals, for
  `date + days(1)` (M2).
- A `Date` or `POSIXct` from R becomes a typed literal in a pipeline.
- [`compute()`](https://dplyr.tidyverse.org/reference/compute.html)
  explains that Trino needs `temporary = FALSE`, and no longer runs
  `ANALYZE`, which not every connector supports.
  [`copy_to()`](https://dplyr.tidyverse.org/reference/copy_to.html) and
  [`compute()`](https://dplyr.tidyverse.org/reference/compute.html)
  write through
  [`dbWriteTable()`](https://dbi.r-dbi.org/reference/dbWriteTable.html),
  with the table name handed over as the quoted identifier dbplyr
  already built (m3).
- The dbplyr methods are no longer exported as functions. They are still
  registered when dbplyr is loaded rather than through `NAMESPACE`, now
  only with dbplyr 2.6.0 or later: a `NAMESPACE` directive for
  `sql_dialect()`, which older versions lack, made such a dbplyr fail to
  load (m7).

#### Tests and documentation

- The fake coordinator used by the tests replays responses recorded from
  a real Trino (`dev/record-fixtures.R`) for everything about how values
  are encoded, instead of payloads made up for the tests, which had
  hidden C1 and M4 (M8).
- `tests/testthat/test-live.R` runs against a real Trino when
  `RTRINO_TEST_URL` is set, and CI runs it against `trinodb/trino` (M8,
  m7).
- The vignette documents where a `dplyr` translation still differs from
  R ([`round()`](https://rdrr.io/r/base/Round.html) on halves, the
  approximate [`median()`](https://rdrr.io/r/stats/median.html) and
  [`quantile()`](https://rdrr.io/r/stats/quantile.html), `DECIMAL`
  beyond 15 digits, [`paste()`](https://rdrr.io/r/base/paste.html) of a
  `DOUBLE`) and no longer claims that `verify = FALSE` warns on every
  request (m2, m5).
