# RTrino 0.1.0

First release: a DBI backend for Trino over the cluster's HTTP REST API.

* `Trino()`, `dbConnect()`, `dbDisconnect()` and `dbIsValid()` for the
  connection's life cycle. `dbConnect()` probes `/v1/info` so a wrong address or a
  rejected credential fails at connection time.
* `dbSendQuery()`, `dbFetch()`, `dbGetQuery()`, `dbExecute()`,
  `dbHasCompleted()` and `dbClearResult()` for queries, with automatic
  `nextUri` pagination, chunked fetching through `dbFetch(n = )`, and
  server-side cancellation when a running result is cleared.
* `dbListTables()`, `dbExistsTable()`, `dbListFields()`, `dbGetInfo()`,
  `dbColumnInfo()`, `dbQuoteIdentifier()` and `dbQuoteString()` for
  introspection and quoting.
* Trino to R type conversion, with `BIGINT` returned as exact
  `bit64::integer64` by default (`bigint = "numeric"` or `"character"` for the
  alternatives), `DOUBLE` bit for bit, timestamps to the microsecond, and
  `TIMESTAMP WITH TIME ZONE` resolved per value whether the server sends a zone
  name or an offset.
* Authentication through `trino_auth_basic()`, `trino_auth_jwt()` and
  `trino_auth_oauth2()`; TLS settings through `trino_ssl()`, including
  `ca_bundle` for an internal certificate authority.
* `dplyr` support via a dbplyr SQL dialect, requiring dbplyr >= 2.6.0.
  `filter_out()`, from dplyr 1.2.0, uses Trino's native `IS DISTINCT FROM`
  rather than the `CASE WHEN` comparison dbplyr falls back to. dplyr 1.2.0's
  `when_any()`/`when_all()` and `recode_values()`/`replace_values()`/
  `replace_when()` are not translated, because dbplyr 2.6.0 has no translation
  for them on any backend.
* `simulate_trino()` returns a connection that carries the dialect without a
  session, for inspecting translated SQL with no cluster to hand.

## Notes on the specification

Two details differ from the design document this release was built from:

* The driver class is `TrinoDriver` throughout (the document spelled it
  `TrinoDiver` in places).
* `dbIsValid()` on a result reports whether the result has been *cleared*,
  not whether the query has finished. Reporting `FALSE` for a finished result
  would break DBI's contract, under which `dbColumnInfo()` and
  `dbGetRowCount()` keep working until `dbClearResult()`. `dbHasCompleted()` is
  what reports that all rows have been consumed.
* Column discovery for `dplyr` uses dbplyr's default (`WHERE 0 = 1`) rather
  than `LIMIT 0`. Both plan without reading data on Trino, and the default
  avoids depending on dbplyr internals.

## Performance and behaviour changes after benchmarking

* Queries no longer pause between the empty pages Trino returns while it
  queues and plans. Measured against Trino 483, that backoff added about
  150 ms to *every* query, roughly six times the cost of the HTTP calls
  themselves; `SELECT 1` went from 220 ms to 30 ms. A capped pause still
  guards against a server that returns empty pages instantly and forever.
* `dbExistsTable()` counts a row in `information_schema.tables` instead of
  listing the schema and matching in R. The old form cost +0.005 ms per table
  in the schema (36.5 ms at 1200 tables) where this stays flat at ~28 ms. It
  also now accepts `"schema.table"` and `"catalog.schema.table"`, consistently
  with `dbListFields()`, and reports `FALSE` rather than an error for a name in
  a catalog that does not exist.
* Query failures are raised as classed conditions (`trino_query_error`, and
  `trino_canceled` for a cancelled query) carrying the server's `error_name`,
  `error_code`, `error_type` and `query_id`, so callers can react to a specific
  Trino error without matching on the message text.

## Fixes after the September 2026 audit

Verified against Trino 483; the audit's identifiers are given in brackets.

### Values

* `BIGINT` and `DOUBLE` values were read through text, because Trino sends
  them as JSON numbers: `3000000000` came back as `NA`, digits were lost past
  2^53 and doubles were rounded to 15 digits. They are now converted without
  going through text, and 15 000 values of each agree with Trino's own
  rendering bit for bit (C1). The lowest `BIGINT`, which bit64 keeps for `NA`,
  is `NA` with a warning.
* Converting a result is done a column at a time rather than a cell at a time
  (m4).
* RTrino now declares the `PARAMETRIC_DATETIME` client capability, without
  which Trino rounded every timestamp to milliseconds (m1).
* A column of a type RTrino does not know warns once per result, not once per
  fetched chunk; `INTERVAL` columns are read as text, and a bare `NULL` as a
  logical (m3).

### DBI

* `dbExecute()` returns the number of rows Trino says a statement changed, and
  `0` for DDL, instead of `NA` every time; `dbSendStatement()` runs the
  statement to completion so that `dbGetRowsAffected()` answers straight away
  (M4).
* `dbExistsTable()` and `dbListFields()` accept `DBI::Id()` and quoted
  identifiers, and `dbExistsTable()` ignores case as Trino does.
  `dbQuoteIdentifier()` and `dbQuoteString()` return `SQL()` unchanged.
  `dbColumnInfo()` and `dbFetch(n = 0)` describe the columns before the first
  row is fetched (M3). `Id` has methods of its own, which removes S4's note
  about an ambiguous method (m6).
* Passing `params` is an error rather than being ignored, and `dbBind()` says
  that parameters are not supported. `dbQuoteLiteral()` writes typed Trino
  literals (`DATE '...'`, `TIMESTAMP '...'`, `TRUE`, doubles that read back
  exactly), so `sqlInterpolate()` and `glue::glue_sql()` work with dates and
  logicals (M5).
* `dbWriteTable()`, `dbAppendTable()`, `dbCreateTable()`, `dbBegin()`,
  `dbCommit()` and `dbRollback()` fail with a message saying that RTrino does
  not upload data or manage transactions (m3).

### Connections

* `dbConnect()` gains `timeout`, which bounds each HTTP request (60 seconds by
  default), and `query_max_run_time`, which bounds a query on the cluster
  (M6).
* `dbConnect()` refuses to send credentials to an `http://` host unless
  `allow_http_auth = TRUE` (M7).
* Arguments are validated before the coordinator is contacted, with plain
  messages: a `catalog` of length two, a fractional `port`, a port written in
  both `host` and `port` (a port in `host` alone is now used), unnamed or
  non-scalar `extra.headers`, and a non-numeric `n` in `dbFetch()` (m3).
* 429, 502, 503 and 504 responses are retried after a short pause, as Trino's
  protocol asks; before, only 429 and 503 were (m5).

### dplyr

* `/` divides as a double, `%%` takes the sign of the divisor, and
  `as.integer()` and `as.integer64()` truncate, as in R (M1, m2).
* `grepl()`, `sub()` and `gsub()` honour `fixed` and `ignore.case` and accept
  R's `\\1` back-references; `sub()` replaces only the first match, instead of
  generating a call Trino does not have (M1, M2).
* `paste()`, `paste0()` and `str_c()` accept columns of any type (M2).
* `days()`, `weeks()`, `months()`, `years()`, `hours()`, `minutes()` and
  `seconds()` build intervals, for `date + days(1)` (M2).
* A `Date` or `POSIXct` from R becomes a typed literal in a pipeline.
* `compute()` explains that Trino needs `temporary = FALSE`, and no longer
  runs `ANALYZE`, which not every connector supports; `copy_to()` says that
  RTrino does not upload data (m3).
* The dbplyr methods are no longer exported as functions. They are still
  registered when dbplyr is loaded rather than through `NAMESPACE`, now only
  with dbplyr 2.6.0 or later: a `NAMESPACE` directive for `sql_dialect()`,
  which older versions lack, made such a dbplyr fail to load (m7).

### Tests and documentation

* The fake coordinator used by the tests replays responses recorded from a
  real Trino (`dev/record-fixtures.R`) for everything about how values are
  encoded, instead of payloads made up for the tests, which had hidden C1 and
  M4 (M8).
* `tests/testthat/test-live.R` runs against a real Trino when
  `RTRINO_TEST_URL` is set, and CI runs it against `trinodb/trino` (M8, m7).
* The vignette documents where a `dplyr` translation still differs from R
  (`round()` on halves, the approximate `median()` and `quantile()`, `DECIMAL`
  beyond 15 digits, `paste()` of a `DOUBLE`) and no longer claims that
  `verify = FALSE` warns on every request (m2, m5).
