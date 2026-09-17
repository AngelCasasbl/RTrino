test_that("dbSendQuery() returns a cursor without draining the query", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  expect_s4_class(res, "TrinoResult")
  expect_identical(DBI::dbGetStatement(res), "SELECT 1")
  expect_identical(DBI::dbGetRowCount(res), 0L)
  expect_false(DBI::dbHasCompleted(res))
})

test_that("the statement is sent as the request body", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbGetQuery(con, "SELECT 1 AS n")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$body, "SELECT 1 AS n")
})

test_that("the Trino protocol headers are sent on every request", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, extra.headers = list("X-Trino-Language" = "es-ES"))

  DBI::dbGetQuery(con, "SELECT 1")
  headers <- jsonlite::fromJSON(proc$url("/test/last-request"))$headers
  names(headers) <- tolower(names(headers))

  expect_identical(headers[["x-trino-user"]], "tester")
  expect_identical(headers[["x-trino-catalog"]], "memory")
  expect_identical(headers[["x-trino-schema"]], "default")
  expect_identical(headers[["x-trino-source"]], "RTrino")
  expect_identical(headers[["x-trino-time-zone"]], "UTC")
  # extra.headers wins over the protocol default.
  expect_identical(headers[["x-trino-language"]], "es-ES")
})

test_that("the User-Agent names this package and its installed version", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbGetQuery(con, "SELECT 1")
  headers <- jsonlite::fromJSON(proc$url("/test/last-request"))$headers
  names(headers) <- tolower(names(headers))

  # Derived from the package name R itself reports, so a rename cannot leave a
  # stale string behind.
  expect_identical(headers[["user-agent"]], the$user_agent)
  expect_match(headers[["user-agent"]], "^RTrino/")
})

test_that("trino_headers() merges and validates extra headers", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  headers <- trino_headers(con, list("X-Custom" = "1"))
  expect_identical(headers[["X-Custom"]], "1")
  expect_identical(headers[["Accept"]], "application/json")
  expect_error(trino_headers(con, list("nameless")), "must be named")
})

test_that("a FAILED query raises the server's message", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    DBI::dbGetQuery(con, "SELECT fail FROM t"),
    "Trino error \\[COLUMN_NOT_FOUND\\]: line 1:8: Column 'nope' cannot be resolved"
  )
})

test_that("a CANCELED query raises a cancellation error", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(DBI::dbGetQuery(con, "SELECT cancel"), "Query was canceled")
})

test_that("queued and planning pages are followed without rows", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # The "slow" scenario answers three pages with no data before finishing.
  out <- DBI::dbGetQuery(con, "SELECT slow")
  expect_identical(nrow(out), 1L)
  expect_identical(out$n, 42L)
})

test_that("dbClearResult() cancels a query that is still running", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT * FROM big")
  expect_true(DBI::dbClearResult(res))
  expect_true(DBI::dbHasCompleted(res))
  expect_false(DBI::dbIsValid(res))

  deleted <- jsonlite::fromJSON(proc$url("/test/last-request"))$deleted
  expect_true("paged" %in% deleted)

  expect_warning(DBI::dbClearResult(res), "already cleared")
  expect_error(DBI::dbFetch(res), "has been cleared")
})

test_that("statements are validated", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(DBI::dbSendQuery(con, character()), "single string")
})
