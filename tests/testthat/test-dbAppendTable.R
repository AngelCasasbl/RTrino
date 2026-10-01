test_that("dbAppendTable() inserts all rows in one statement under chunk_size", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  value <- data.frame(id = 1:2, label = c("one", "two"))
  DBI::dbAppendTable(con, "sales", value)
  expect_identical(
    sent_body(proc),
    paste0(
      'INSERT INTO "memory"."default"."sales"\n  ("id", "label")\nVALUES\n',
      "  (1, 'one'),\n  (2, 'two')"
    )
  )
})

test_that("dbAppendTable() splits rows into chunk_size-sized statements", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  value <- data.frame(id = 1:5)
  DBI::dbAppendTable(con, "sales", value, chunk_size = 2L)
  # The last statement sent carries only the final chunk of rows.
  expect_identical(
    sent_body(proc),
    'INSERT INTO "memory"."default"."sales"\n  ("id")\nVALUES\n  (5)'
  )
})

test_that("dbAppendTable() converts factors to character before inserting", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  value <- data.frame(label = factor("a"))
  DBI::dbAppendTable(con, "sales", value)
  expect_identical(
    sent_body(proc),
    "INSERT INTO \"memory\".\"default\".\"sales\"\n  (\"label\")\nVALUES\n  ('a')"
  )
})

test_that("dbAppendTable() does nothing for zero rows", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_identical(
    DBI::dbAppendTable(con, "sales", data.frame(id = integer())),
    0L
  )
})
