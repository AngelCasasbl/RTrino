# Changelog

## RTrino 0.1.0

First release: a DBI backend for Trino over the cluster’s HTTP REST API.

### Connections

- [`Trino()`](https://angelcasasbl.github.io/RTrino/reference/Trino.md),
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html),
  [`dbDisconnect()`](https://dbi.r-dbi.org/reference/dbDisconnect.html)
  and [`dbIsValid()`](https://dbi.r-dbi.org/reference/dbIsValid.html)
  manage a connection’s life cycle.
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html) probes
  `/v1/info`, so a wrong address or a rejected credential fails at
  connection time. Its arguments are validated before the coordinator is
  contacted, with plain messages.
- [`trino_auth_basic()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md),
  [`trino_auth_jwt()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  and
  [`trino_auth_oauth2()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  supply credentials, and
  [`trino_ssl()`](https://angelcasasbl.github.io/RTrino/reference/trino_ssl.md)
  sets the TLS options, including `ca_bundle` to trust an internal
  certificate authority without turning verification off.
  [`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  refuses to send credentials to an `http://` host unless
  `allow_http_auth = TRUE`.
- `timeout` bounds each HTTP request (60 seconds by default) and
  `query_max_run_time` bounds a query on the cluster.
- 429, 502, 503 and 504 responses are retried after a short pause, as
  Trino’s protocol asks.

### Queries and results

- [`dbSendQuery()`](https://dbi.r-dbi.org/reference/dbSendQuery.html),
  [`dbFetch()`](https://dbi.r-dbi.org/reference/dbFetch.html),
  [`dbGetQuery()`](https://dbi.r-dbi.org/reference/dbGetQuery.html),
  [`dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html),
  [`dbSendStatement()`](https://dbi.r-dbi.org/reference/dbSendStatement.html),
  [`dbHasCompleted()`](https://dbi.r-dbi.org/reference/dbHasCompleted.html)
  and
  [`dbClearResult()`](https://dbi.r-dbi.org/reference/dbClearResult.html)
  run queries, with automatic `nextUri` pagination, chunked fetching
  through `dbFetch(n = )`, and server-side cancellation when a running
  result is cleared.
- [`dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html)
  returns the number of rows Trino says a statement changed, and `0` for
  DDL.
  [`dbSendStatement()`](https://dbi.r-dbi.org/reference/dbSendStatement.html)
  runs the statement to completion, so that
  [`dbGetRowsAffected()`](https://dbi.r-dbi.org/reference/dbGetRowsAffected.html)
  answers straight away.
- [`dbColumnInfo()`](https://dbi.r-dbi.org/reference/dbColumnInfo.html)
  and `dbFetch(n = 0)` describe the columns before the first row is
  fetched.
- [`dbIsValid()`](https://dbi.r-dbi.org/reference/dbIsValid.html) on a
  result reports whether it has been *cleared*, not whether the query
  has finished, as DBI requires:
  [`dbColumnInfo()`](https://dbi.r-dbi.org/reference/dbColumnInfo.html)
  and
  [`dbGetRowCount()`](https://dbi.r-dbi.org/reference/dbGetRowCount.html)
  keep working until
  [`dbClearResult()`](https://dbi.r-dbi.org/reference/dbClearResult.html).
  [`dbHasCompleted()`](https://dbi.r-dbi.org/reference/dbHasCompleted.html)
  reports that every row has been consumed.
- Query failures are raised as classed conditions, `trino_query_error`
  and `trino_canceled`, carrying the server’s `error_name`,
  `error_code`, `error_type` and `query_id`, so a caller can react to a
  specific Trino error without matching on the message text.
- Queries do not pause between the empty pages Trino returns while it
  queues and plans. A capped pause still guards against a server that
  returns empty pages instantly and forever.
- Passing `params` is an error, and
  [`dbBind()`](https://dbi.r-dbi.org/reference/dbBind.html) says that
  parameters are not supported. Put values into a statement with
  [`DBI::sqlInterpolate()`](https://dbi.r-dbi.org/reference/sqlInterpolate.html)
  or
  [`glue::glue_sql()`](https://glue.tidyverse.org/reference/glue_sql.html):
  [`dbQuoteLiteral()`](https://dbi.r-dbi.org/reference/dbQuoteLiteral.html)
  writes typed Trino literals (`DATE '...'`, `TIMESTAMP '...'`, `TRUE`,
  doubles that read back exactly).

### Types

- `BIGINT` is returned as exact
  [`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html)
  by default (`bigint = "numeric"` or `"character"` for the
  alternatives), and `DOUBLE` bit for bit. Trino sends both as JSON
  numbers, which are converted without going through text. The lowest
  `BIGINT`, which bit64 keeps for `NA`, is `NA` with a warning.
- Timestamps keep their microseconds, and `TIMESTAMP WITH TIME ZONE` is
  resolved per value whether the server sends a zone name or an offset.
- A column of a type RTrino does not know warns once per result;
  `INTERVAL` columns are read as text, and a bare `NULL` as a logical.
- [`dbDataType()`](https://dbi.r-dbi.org/reference/dbDataType.html) and
  [`trino_type_to_r()`](https://angelcasasbl.github.io/RTrino/reference/trino_type_to_r.md)
  map between R and Trino types.

### Tables, writes and transactions

- [`dbListTables()`](https://dbi.r-dbi.org/reference/dbListTables.html),
  [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html),
  [`dbListFields()`](https://dbi.r-dbi.org/reference/dbListFields.html)
  and [`dbGetInfo()`](https://dbi.r-dbi.org/reference/dbGetInfo.html)
  read the catalog. Table names are strings of one to three parts,
  [`DBI::Id()`](https://dbi.r-dbi.org/reference/Id.html) or quoted
  identifiers, and are matched ignoring case, as Trino does.
  [`dbExistsTable()`](https://dbi.r-dbi.org/reference/dbExistsTable.html)
  counts a row in `information_schema.tables`, so its cost does not grow
  with the size of the schema, and reports `FALSE` rather than an error
  for a name in a catalog that does not exist.
- [`dbWriteTable()`](https://dbi.r-dbi.org/reference/dbWriteTable.html),
  [`dbAppendTable()`](https://dbi.r-dbi.org/reference/dbAppendTable.html)
  and
  [`dbCreateTable()`](https://dbi.r-dbi.org/reference/dbCreateTable.html)
  write data frames. Rows go in as `INSERT INTO ... VALUES` statements
  of `chunk_size` rows each (1000 by default), every value a literal,
  since Trino’s protocol has no parameter binding.
  `dbWriteTable(overwrite = TRUE)` renames the existing table rather
  than dropping it, and restores it if the write fails.
  [`dbRemoveTable()`](https://dbi.r-dbi.org/reference/dbRemoveTable.html)
  and
  [`dbRenameTable()`](https://angelcasasbl.github.io/RTrino/reference/dbRenameTable.md)
  drop and rename tables, and `temporary = TRUE` is an error, because
  Trino has no temporary tables.
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

### dplyr

- `dplyr` pipelines are translated to Trino SQL through a dbplyr
  dialect, which requires dbplyr \>= 2.6.0. The methods are registered
  when dbplyr is loaded rather than through `NAMESPACE`, because a
  `NAMESPACE` directive for `sql_dialect()`, which older versions lack,
  would make such a dbplyr fail to load.
- Translations are written so that an expression computes in Trino what
  it computes in R: `/` divides as a double, `%%` takes the sign of the
  divisor, [`as.integer()`](https://rdrr.io/r/base/integer.html) and
  `as.integer64()` truncate,
  [`grepl()`](https://rdrr.io/r/base/grep.html),
  [`sub()`](https://rdrr.io/r/base/grep.html) and
  [`gsub()`](https://rdrr.io/r/base/grep.html) honour `fixed` and
  `ignore.case` and accept R’s `\\1` back-references, and
  [`paste()`](https://rdrr.io/r/base/paste.html),
  [`paste0()`](https://rdrr.io/r/base/paste.html) and `str_c()` accept
  columns of any type. `days()`, `weeks()`,
  [`months()`](https://rdrr.io/r/base/weekday.POSIXt.html), `years()`,
  `hours()`, `minutes()` and `seconds()` build intervals, for
  `date + days(1)`. A `Date` or `POSIXct` from R becomes a typed literal
  in a pipeline.
- [`filter_out()`](https://dplyr.tidyverse.org/reference/filter.html),
  from dplyr 1.2.0, uses Trino’s native `IS DISTINCT FROM` rather than
  the `CASE WHEN` comparison dbplyr falls back to. dplyr 1.2.0’s
  [`when_any()`](https://dplyr.tidyverse.org/reference/when-any-all.html)/[`when_all()`](https://dplyr.tidyverse.org/reference/when-any-all.html)
  and
  [`recode_values()`](https://dplyr.tidyverse.org/reference/recode-and-replace-values.html)/[`replace_values()`](https://dplyr.tidyverse.org/reference/recode-and-replace-values.html)/
  [`replace_when()`](https://dplyr.tidyverse.org/reference/case-and-replace-when.html)
  are not translated, because dbplyr 2.6.0 has no translation for them
  on any backend.
- [`copy_to()`](https://dplyr.tidyverse.org/reference/copy_to.html) and
  [`compute()`](https://dplyr.tidyverse.org/reference/compute.html)
  write through
  [`dbWriteTable()`](https://dbi.r-dbi.org/reference/dbWriteTable.html),
  and need `temporary = FALSE` and a table name.
  [`compute()`](https://dplyr.tidyverse.org/reference/compute.html) does
  not run `ANALYZE`, which not every connector supports.
- Column discovery uses dbplyr’s default (`WHERE 0 = 1`) rather than
  `LIMIT 0`. Both plan without reading data on Trino, and the default
  avoids depending on dbplyr internals.
- [`simulate_trino()`](https://angelcasasbl.github.io/RTrino/reference/simulate_trino.md)
  returns a connection that carries the dialect without a session, for
  inspecting translated SQL with no cluster to hand.
- The vignette lists the few places where a translation still differs
  from R: [`round()`](https://rdrr.io/r/base/Round.html) on halves, the
  approximate [`median()`](https://rdrr.io/r/stats/median.html) and
  [`quantile()`](https://rdrr.io/r/stats/quantile.html), `DECIMAL`
  beyond 15 digits, and [`paste()`](https://rdrr.io/r/base/paste.html)
  of a `DOUBLE`.

### Testing

- The test suite runs offline against a fake coordinator that replays
  responses recorded from a real Trino (`dev/record-fixtures.R`), so
  everything about how values are encoded is tested against payloads a
  cluster really sends.
- `tests/testthat/test-live.R` runs against a real Trino when
  `RTRINO_TEST_URL` is set, and CI runs it against `trinodb/trino`.
