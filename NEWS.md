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
