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

  for (bad in list(-5, NA, "3", 1.5, c(1, 2), numeric(), -Inf, TRUE)) {
    expect_error(
      DBI::dbFetch(res, n = bad),
      "non-negative whole number or -1",
      info = deparse(bad)
    )
  }
  expect_identical(DBI::dbGetRowCount(res), 0L)
  expect_identical(nrow(DBI::dbFetch(res, n = Inf)), 2L)
})

test_that("the columns are known before the first row is fetched", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # Recorded from Trino 483, whose first response describes no columns: they
  # come a few pages later, before the rows.
  res <- DBI::dbSendQuery(con, trino_fixture_sql("nation"))
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  info <- DBI::dbColumnInfo(res)
  expect_identical(info$name, c("nationkey", "name", "regionkey"))
  expect_identical(info$type, c("bigint", "varchar(25)", "bigint"))

  empty <- DBI::dbFetch(res, n = 0)
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), c("nationkey", "name", "regionkey"))
  expect_s3_class(empty$nationkey, "integer64")
  expect_type(empty$name, "character")

  # Looking at the columns consumed no rows.
  expect_identical(nrow(DBI::dbFetch(res)), 25L)
})

test_that("asking for the columns keeps rows that came with them", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # In the "simple" scenario the columns arrive on the same page as the rows,
  # as they do on a real cluster when the query is quick.
  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  expect_identical(DBI::dbColumnInfo(res)$name, c("n", "label"))
  expect_identical(nrow(DBI::dbFetch(res, n = 0)), 0L)
  expect_identical(DBI::dbFetch(res)$n, 1:2)
})

test_that("a query that returns no rows still describes its columns", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- DBI::dbGetQuery(con, trino_fixture_sql("empty"))
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), c("orderkey", "orderstatus", "totalprice"))
  expect_s3_class(out$orderkey, "integer64")
  expect_type(out$totalprice, "double")
})

test_that("dbColumnInfo() on a cleared result is an error", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT 1")
  DBI::dbClearResult(res)
  expect_error(DBI::dbColumnInfo(res), "has been cleared")
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

test_that("rows are transposed into columns with NULLs anywhere", {
  columns <- list(
    list(name = "n", type = "integer"),
    list(name = "s", type = "varchar"),
    list(name = "a", type = "array(integer)")
  )
  rows <- list(
    list(1L, NULL, list(1L)),
    list(NULL, "b", NULL),
    list(3L, "c", list())
  )
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- trino_rows_to_tibble(rows, columns, con)
  expect_identical(out$n, c(1L, NA, 3L))
  expect_identical(out$s, c(NA, "b", "c"))
  expect_identical(out$a, list(list(1L), NULL, list()))

  one <- trino_rows_to_tibble(list(list(7L, "x", NULL)), columns, con)
  expect_identical(one$n, 7L)
  expect_identical(one$a, list(NULL))
})
