test_that("dbFetch() with n = -1 drains every page", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT * FROM big")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  out <- DBI::dbFetch(res)
  expect_s3_class(out, "tbl_df")
  expect_identical(out$n, 1:8)
  expect_true(DBI::dbHasCompleted(res))
  expect_identical(DBI::dbGetRowCount(res), 8L)
})

test_that("dbFetch() with n > 0 returns chunks and buffers the rest", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT * FROM big")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  first <- DBI::dbFetch(res, n = 3)
  expect_identical(first$n, 1:3)
  expect_false(DBI::dbHasCompleted(res))

  chunks <- list(first)
  while (!DBI::dbHasCompleted(res)) {
    chunks <- c(chunks, list(DBI::dbFetch(res, n = 3)))
  }
  expect_identical(unlist(lapply(chunks, function(x) x$n)), 1:8)
  expect_identical(DBI::dbGetRowCount(res), 8L)
})

test_that("a result with no rows keeps its schema", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- DBI::dbGetQuery(con, "SELECT n, label FROM t LIMIT 0")
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), c("n", "label"))
  expect_type(out$n, "integer")
  expect_type(out$label, "character")
})

test_that("fetching past the end warns and returns an empty frame", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  DBI::dbFetch(res)
  expect_warning(out <- DBI::dbFetch(res), "already exhausted")
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), c("n", "label"))
})

test_that("dbColumnInfo() reports the Trino types", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))
  DBI::dbFetch(res)

  info <- DBI::dbColumnInfo(res)
  expect_identical(info$name, c("n", "label"))
  expect_identical(info$type, c("integer", "varchar(20)"))
})

test_that("dbGetQuery() clears the result it created", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- DBI::dbGetQuery(con, "SELECT 1")
  expect_identical(out$n, 1:2)
  expect_identical(out$label, c("one", "two"))
})

test_that("n is validated", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  expect_error(DBI::dbFetch(res, n = -5), "non-negative whole number or -1")
  expect_error(DBI::dbFetch(res, n = NA), "non-negative whole number or -1")
})

test_that("duplicate column names are disambiguated", {
  columns <- list(
    list(name = "a", type = "integer"),
    list(name = "a", type = "integer")
  )
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- trino_rows_to_tibble(list(list(1L, 2L)), columns, con)
  expect_identical(names(out), c("a", "a_1"))
})
