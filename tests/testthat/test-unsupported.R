test_that("uploading data frames fails with a message that says why", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)
  df <- data.frame(x = 1:2)

  expect_error(
    DBI::dbWriteTable(con, "t", df),
    "dbWriteTable\\(\\) is not supported: RTrino does not upload data"
  )
  expect_error(
    DBI::dbWriteTable(con, DBI::Id(schema = "s", table = "t"), df),
    "dbWriteTable\\(\\) is not supported"
  )
  expect_error(DBI::dbAppendTable(con, "t", df), "dbAppendTable\\(\\) is not")
  expect_error(DBI::dbCreateTable(con, "t", df), "dbCreateTable\\(\\) is not")
})

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
