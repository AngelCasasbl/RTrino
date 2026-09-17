# RTrino 0.1.0

First release: a DBI backend for Trino over the cluster's HTTP REST API.

* `Trino()`, `dbConnect()`, `dbDisconnect()` and `dbIsValid()` for the
  connection lifecycle. `dbConnect()` probes `/v1/info` so a wrong address or a
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
  alternatives), and `TIMESTAMP WITH TIME ZONE` resolved per value whether the
  server sends a zone name or an offset.
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
