# RTrino 0.1.0

First release: a DBI backend for Trino over the cluster's HTTP REST API.

## Connections

* `Trino()`, `dbConnect()`, `dbDisconnect()` and `dbIsValid()` manage a
  connection's life cycle. `dbConnect()` probes `/v1/info`, so a wrong address
  or a rejected credential fails at connection time. Its arguments are
  validated before the coordinator is contacted, with plain messages.
* `trino_auth_basic()`, `trino_auth_jwt()` and `trino_auth_oauth2()` supply
  credentials, and `trino_ssl()` sets the TLS options, including `ca_bundle`
  to trust an internal certificate authority without turning verification off.
  `dbConnect()` refuses to send credentials to an `http://` host unless
  `allow_http_auth = TRUE`.
* `timeout` bounds each HTTP request (60 seconds by default) and
  `query_max_run_time` bounds a query on the cluster.
* 429, 502, 503 and 504 responses are retried after a short pause, as Trino's
  protocol asks.

## Queries and results

* `dbSendQuery()`, `dbFetch()`, `dbGetQuery()`, `dbExecute()`,
  `dbSendStatement()`, `dbHasCompleted()` and `dbClearResult()` run queries,
  with automatic `nextUri` pagination, chunked fetching through
  `dbFetch(n = )`, and server-side cancellation when a running result is
  cleared.
* `dbExecute()` returns the number of rows Trino says a statement changed, and
  `0` for DDL. `dbSendStatement()` runs the statement to completion, so that
  `dbGetRowsAffected()` answers straight away.
* `dbColumnInfo()` and `dbFetch(n = 0)` describe the columns before the first
  row is fetched.
* `dbIsValid()` on a result reports whether it has been *cleared*, not whether
  the query has finished, as DBI requires: `dbColumnInfo()` and
  `dbGetRowCount()` keep working until `dbClearResult()`. `dbHasCompleted()`
  reports that every row has been consumed.
* Query failures are raised as classed conditions, `trino_query_error` and
  `trino_canceled`, carrying the server's `error_name`, `error_code`,
  `error_type` and `query_id`, so a caller can react to a specific Trino error
  without matching on the message text.
* Queries do not pause between the empty pages Trino returns while it queues
  and plans. A capped pause still guards against a server that returns empty
  pages instantly and forever.
* Passing `params` is an error, and `dbBind()` says that parameters are not
  supported. Put values into a statement with `DBI::sqlInterpolate()` or
  `glue::glue_sql()`: `dbQuoteLiteral()` writes typed Trino literals
  (`DATE '...'`, `TIMESTAMP '...'`, `TRUE`, doubles that read back exactly).

## Types

* `BIGINT` is returned as exact `bit64::integer64` by default
  (`bigint = "numeric"` or `"character"` for the alternatives), and `DOUBLE`
  bit for bit. Trino sends both as JSON numbers, which are converted without
  going through text. The lowest `BIGINT`, which bit64 keeps for `NA`, is `NA`
  with a warning.
* Timestamps keep their microseconds, and `TIMESTAMP WITH TIME ZONE` is
  resolved per value whether the server sends a zone name or an offset.
* A column of a type RTrino does not know warns once per result; `INTERVAL`
  columns are read as text, and a bare `NULL` as a logical.
* `dbDataType()` and `trino_type_to_r()` map between R and Trino types.

## Tables, writes and transactions

* `dbListTables()`, `dbExistsTable()`, `dbListFields()` and `dbGetInfo()` read
  the catalog. Table names are strings of one to three parts, `DBI::Id()` or
  quoted identifiers, and are matched ignoring case, as Trino does.
  `dbExistsTable()` counts a row in `information_schema.tables`, so its cost
  does not grow with the size of the schema, and reports `FALSE` rather than an
  error for a name in a catalog that does not exist.
* `dbWriteTable()`, `dbAppendTable()` and `dbCreateTable()` write data frames.
  Rows go in as `INSERT INTO ... VALUES` statements of `chunk_size` rows each
  (1000 by default), every value a literal, since Trino's protocol has no
  parameter binding. `dbWriteTable(overwrite = TRUE)` renames the existing
  table rather than dropping it, and restores it if the write fails.
  `dbRemoveTable()` and `dbRenameTable()` drop and rename tables, and
  `temporary = TRUE` is an error, because Trino has no temporary tables.
* `dbBegin()`, `dbCommit()`, `dbRollback()` and `dbWithTransaction()` run
  statements inside a Trino transaction. Whether a `ROLLBACK` undoes a write
  depends on the connector behind the catalog; `dbBegin()` warns for the
  catalogs that hold no real storage (`memory`, `system`, `tpch`, `tpcds`,
  `jmx` and `blackhole`).

## dplyr

* `dplyr` pipelines are translated to Trino SQL through a dbplyr dialect,
  which requires dbplyr >= 2.6.0. The methods are registered when dbplyr is
  loaded rather than through `NAMESPACE`, because a `NAMESPACE` directive for
  `sql_dialect()`, which older versions lack, would make such a dbplyr fail to
  load.
* Translations are written so that an expression computes in Trino what it
  computes in R: `/` divides as a double, `%%` takes the sign of the divisor,
  `as.integer()` and `as.integer64()` truncate, `grepl()`, `sub()` and
  `gsub()` honour `fixed` and `ignore.case` and accept R's `\\1`
  back-references, and `paste()`, `paste0()` and `str_c()` accept columns of
  any type. `days()`, `weeks()`, `months()`, `years()`, `hours()`, `minutes()`
  and `seconds()` build intervals, for `date + days(1)`. A `Date` or `POSIXct`
  from R becomes a typed literal in a pipeline.
* `filter_out()`, from dplyr 1.2.0, uses Trino's native `IS DISTINCT FROM`
  rather than the `CASE WHEN` comparison dbplyr falls back to. dplyr 1.2.0's
  `when_any()`/`when_all()` and `recode_values()`/`replace_values()`/
  `replace_when()` are not translated, because dbplyr 2.6.0 has no translation
  for them on any backend.
* `copy_to()` and `compute()` write through `dbWriteTable()`, and need
  `temporary = FALSE` and a table name. `compute()` does not run `ANALYZE`,
  which not every connector supports.
* Column discovery uses dbplyr's default (`WHERE 0 = 1`) rather than
  `LIMIT 0`. Both plan without reading data on Trino, and the default avoids
  depending on dbplyr internals.
* `simulate_trino()` returns a connection that carries the dialect without a
  session, for inspecting translated SQL with no cluster to hand.
* The vignette lists the few places where a translation still differs from R:
  `round()` on halves, the approximate `median()` and `quantile()`, `DECIMAL`
  beyond 15 digits, and `paste()` of a `DOUBLE`.

## Testing

* The test suite runs offline against a fake coordinator that replays
  responses recorded from a real Trino (`dev/record-fixtures.R`), so everything
  about how values are encoded is tested against payloads a cluster really
  sends.
* `tests/testthat/test-live.R` runs against a real Trino when
  `RTRINO_TEST_URL` is set, and CI runs it against `trinodb/trino`.
