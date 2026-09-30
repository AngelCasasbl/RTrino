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
  con <- local_trino_con(
    proc,
    extra.headers = list("X-Trino-Language" = "es-ES")
  )

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
  # Without it Trino rounds every timestamp to milliseconds.
  expect_identical(
    headers[["x-trino-client-capabilities"]],
    "PARAMETRIC_DATETIME"
  )
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
    paste0(
      "Trino error \\[COLUMN_NOT_FOUND\\]: ",
      "line 1:8: Column 'nope' cannot be resolved"
    )
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

test_that("query parameters are refused, not ignored", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    DBI::dbGetQuery(con, "SELECT 1", params = list(99)),
    "does not support parameterised queries"
  )
  expect_error(
    DBI::dbExecute(con, "SELECT 1", params = list(99)),
    "does not support parameterised queries"
  )
  # Nothing reached the server.
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$body, "")

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))
  expect_error(DBI::dbBind(res, list(1)), "does not support parameterised")

  # An explicit NULL is no parameters at all.
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT 1", params = NULL)), 2L)
})

test_that("dbExecute() reports the rows Trino says a statement changed", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # Recorded from Trino 483: updateCount arrives on the last pages only.
  expect_identical(DBI::dbExecute(con, trino_fixture_sql("insert")), 2)
  expect_identical(DBI::dbExecute(con, trino_fixture_sql("ctas")), 2)
  # DDL changes no rows, and Trino sends no count for it.
  expect_identical(DBI::dbExecute(con, trino_fixture_sql("create_table")), 0)
  expect_identical(DBI::dbExecute(con, trino_fixture_sql("drop_table")), 0)
  expect_invisible(DBI::dbExecute(con, trino_fixture_sql("insert")))
})

test_that("dbSendStatement() has the count as soon as it returns", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendStatement(con, trino_fixture_sql("insert"))
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))
  expect_identical(DBI::dbGetRowsAffected(res), 2)
  # The row Trino reports the count in is still there to fetch.
  expect_identical(as.character(DBI::dbFetch(res)$rows), "2")
})

test_that("a query changes no rows", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))
  expect_identical(DBI::dbGetRowsAffected(res), 0)
  DBI::dbFetch(res)
  expect_identical(DBI::dbGetRowsAffected(res), 0)
})

test_that("a data change without a count is unknown, not zero", {
  state <- trino_result_state()
  trino_absorb_payload(state, list(
    id = "q", stats = list(state = "FINISHED"), updateType = "DELETE"
  ))
  res <- methods::new(
    "TrinoResult",
    connection = methods::new("TrinoConnection"),
    statement = "DELETE FROM t",
    state = state
  )
  expect_identical(DBI::dbGetRowsAffected(res), NA_real_)
})

test_that("a recorded failure raises the server's error", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  cnd <- tryCatch(
    DBI::dbGetQuery(con, trino_fixture_sql("failed")),
    error = identity
  )
  expect_s3_class(cnd, "trino_query_error")
  expect_identical(cnd$error_name, "COLUMN_NOT_FOUND")
  expect_identical(cnd$error_code, 47L)
  expect_match(conditionMessage(cnd), "Column 'no_such_column' cannot be")
})

test_that("recorded tpch rows arrive whole and typed", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- DBI::dbGetQuery(con, trino_fixture_sql("nation"))
  expect_identical(nrow(out), 25L)
  expect_identical(as.character(out$nationkey), as.character(0:24))
  expect_identical(out$name[1:3], c("ALGERIA", "ARGENTINA", "BRAZIL"))
  expect_s3_class(out$regionkey, "integer64")
})

test_that("a 502 from a load balancer is retried", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_message(
    out <- DBI::dbGetQuery(con, "SELECT flaky"),
    "retry backoff"
  )
  expect_identical(nrow(out), 2L)
})

test_that("the empty pages of a normal query are followed without pausing", {
  # A backoff on those pages used to add ~150 ms to every single query, while
  # the pages themselves come back in under 30 ms.
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  slept <- 0
  testthat::local_mocked_bindings(
    Sys.sleep = function(time) slept <<- slept + time,
    .package = "base"
  )

  # The "slow" scenario answers three pages with no rows before finishing.
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT slow")), 1L)
  expect_identical(slept, 0)
})

test_that("a server stuck on empty pages is eventually polled slowly", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  slept <- numeric()
  testthat::local_mocked_bindings(
    Sys.sleep = function(time) slept <<- c(slept, time),
    .package = "base"
  )

  # The "stalled" scenario answers the POST plus fourteen GETs with no rows
  # before the fifteenth GET carries the single row.
  empty_pages <- 14L
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT stalled")), 1L)

  # The first pages are followed at full speed; only the ones past the
  # threshold pause, and each pause is capped.
  expect_length(slept, empty_pages - trino_poll_free_pages)
  expect_identical(slept, pmin(0.025 * seq_along(slept), 0.1))
  expect_lte(max(slept), 0.1)
})
