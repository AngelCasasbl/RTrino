test_that("dbCreateTable() builds a CREATE TABLE from named types", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbCreateTable(con, "sales", c(id = "bigint", label = "varchar"))
  expect_identical(
    sent_body(proc),
    'CREATE TABLE "memory"."default"."sales" ("id" bigint, "label" varchar)'
  )
})

test_that("dbCreateTable() infers types from a data frame", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  fields <- data.frame(
    id = bit64::as.integer64(1), label = "a", flag = TRUE,
    stringsAsFactors = FALSE
  )
  DBI::dbCreateTable(con, "sales", fields)
  expect_identical(
    sent_body(proc),
    paste0(
      'CREATE TABLE "memory"."default"."sales" (',
      '"id" bigint, "label" varchar, "flag" boolean)'
    )
  )
})

test_that("dbCreateTable() rejects temporary tables", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    DBI::dbCreateTable(con, "sales", c(id = "bigint"), temporary = TRUE),
    "Temporary tables not supported by RTrino"
  )
})

test_that("dbCreateTable() rejects malformed fields", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    DBI::dbCreateTable(con, "sales", c("bigint", "varchar")),
    "must be a named character vector or a data frame"
  )
})
