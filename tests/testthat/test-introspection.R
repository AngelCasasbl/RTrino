test_that("dbListTables() runs SHOW TABLES against catalog.schema", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_identical(DBI::dbListTables(con), c("sales", "regions"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$body, 'SHOW TABLES FROM "memory"."default"')
})

test_that("dbExistsTable() matches exactly", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_true(DBI::dbExistsTable(con, "sales"))
  expect_false(DBI::dbExistsTable(con, "sale"))
  expect_false(DBI::dbExistsTable(con, "SALES"))
})

test_that("dbListFields() describes a qualified table", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_identical(DBI::dbListFields(con, "sales"), c("id", "region"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$body, 'DESCRIBE "memory"."default"."sales"')
})

test_that("an already qualified name is not qualified twice", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbListFields(con, "other.sch.tbl")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$body, 'DESCRIBE "other"."sch"."tbl"')
})

test_that("identifiers and strings are quoted the SQL standard way", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_identical(
    as.character(DBI::dbQuoteIdentifier(con, "my column")),
    '"my column"'
  )
  expect_identical(
    as.character(DBI::dbQuoteIdentifier(con, 'we"ird')),
    '"we""ird"'
  )
  expect_identical(as.character(DBI::dbQuoteString(con, "O'Brien")), "'O''Brien'")
  expect_identical(as.character(DBI::dbQuoteString(con, NA_character_)), "NULL")
  expect_error(DBI::dbQuoteIdentifier(con, NA_character_), "Cannot quote NA")
})

test_that("introspection needs a live connection", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)
  DBI::dbDisconnect(con)

  expect_error(DBI::dbListTables(con), "Invalid TrinoConnection")
  expect_error(DBI::dbListFields(con, "sales"), "Invalid TrinoConnection")
  expect_error(DBI::dbGetInfo(con), "Invalid TrinoConnection")
})

test_that("the objects print informatively", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_output(print(RTrino::Trino()), "<TrinoDriver>")
  expect_output(print(con), "<TrinoConnection>")
  expect_output(print(con), "catalog: memory")

  res <- DBI::dbSendQuery(con, "SELECT 1")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))
  expect_output(print(res), "<TrinoResult>")
})
