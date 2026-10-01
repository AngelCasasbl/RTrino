test_that("dbBegin() starts a transaction and threads its id on requests", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, catalog = "hive", schema = "default")

  DBI::dbBegin(con)
  DBI::dbExecute(con, "SELECT 1")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(
    last$headers[["X-Trino-Transaction-Id"]], "fake-transaction-id"
  )

  DBI::dbCommit(con)
  DBI::dbExecute(con, "SELECT 1")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$headers[["X-Trino-Transaction-Id"]], "NONE")
})

test_that("dbRollback() also clears the transaction id", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, catalog = "hive", schema = "default")

  DBI::dbBegin(con)
  DBI::dbRollback(con)
  DBI::dbExecute(con, "SELECT 1")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$headers[["X-Trino-Transaction-Id"]], "NONE")
})

test_that("the transaction id header is always present, even as NONE", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbExecute(con, "SELECT 1")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$headers[["X-Trino-Transaction-Id"]], "NONE")
})

test_that("dbCommit() and dbRollback() error without a transaction", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(DBI::dbCommit(con), "No transaction is in progress")
  expect_error(DBI::dbRollback(con), "No transaction is in progress")
})

test_that("dbBegin() errors on a transaction already in progress", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, catalog = "hive", schema = "default")

  DBI::dbBegin(con)
  expect_error(DBI::dbBegin(con), "already in progress")
  DBI::dbCommit(con)
})

test_that("dbBegin() warns for a catalog with no real transactional storage", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, catalog = "memory", schema = "default")

  expect_warning(DBI::dbBegin(con), "has no real transactional storage")
  DBI::dbCommit(con)
})

test_that("dbBegin() does not warn for a catalog that supports transactions", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, catalog = "hive", schema = "default")

  expect_no_warning(DBI::dbBegin(con))
  DBI::dbCommit(con)
})

test_that("dbWithTransaction() commits on success and rolls back on error", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, catalog = "hive", schema = "default")

  out <- DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "SELECT 1")
    42
  })
  expect_identical(out, 42)
  expect_error(DBI::dbCommit(con), "No transaction is in progress")

  expect_error(
    DBI::dbWithTransaction(con, stop("boom")),
    "boom"
  )
  expect_error(DBI::dbCommit(con), "No transaction is in progress")
})
