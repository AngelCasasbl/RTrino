test_that("transactions fail with a message that says why", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(DBI::dbBegin(con), "does not manage transactions")
  expect_error(DBI::dbCommit(con), "does not manage transactions")
  expect_error(DBI::dbRollback(con), "does not manage transactions")
  expect_error(
    DBI::dbWithTransaction(con, DBI::dbGetQuery(con, "SELECT 1")),
    "does not manage transactions"
  )
})
