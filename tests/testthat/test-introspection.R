test_that("dbListTables() runs SHOW TABLES against catalog.schema", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_identical(DBI::dbListTables(con), c("sales", "regions"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(last$body, 'SHOW TABLES FROM "memory"."default"')
})

test_that("dbExistsTable() asks information_schema for a count", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_true(DBI::dbExistsTable(con, "sales"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_identical(
    last$body,
    paste0(
      'SELECT count(*) AS n FROM "memory".information_schema.tables',
      " WHERE table_schema = 'default' AND table_name = 'sales'"
    )
  )

  expect_false(DBI::dbExistsTable(con, "sale"))
  expect_false(DBI::dbExistsTable(con, "SALES"))
})

test_that("dbExistsTable() resolves qualified names", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_true(DBI::dbExistsTable(con, "analytics.sales"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_match(last$body, "table_schema = 'analytics'")
  expect_match(last$body, '"memory"\\.information_schema\\.tables')

  expect_true(DBI::dbExistsTable(con, "other.analytics.sales"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_match(last$body, '"other"\\.information_schema\\.tables')

  expect_error(
    DBI::dbExistsTable(con, "a.b.c.d"),
    "at most three parts"
  )
})

test_that("dbExistsTable() reports FALSE for a catalog that does not exist", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # DBI asks for a logical here, so a missing catalog is FALSE, not an error.
  expect_false(DBI::dbExistsTable(con, "nowhere.default.sales"))
})

test_that("a name needing quoting is escaped, not interpolated", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbExistsTable(con, "O'Brien")
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_match(last$body, "table_name = 'O''Brien'", fixed = TRUE)
})

test_that("Trino errors carry a class and the server's error name", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  cnd <- tryCatch(DBI::dbGetQuery(con, "SELECT fail"), error = identity)
  expect_s3_class(cnd, "trino_query_error")
  expect_identical(cnd$error_name, "COLUMN_NOT_FOUND")
  expect_identical(cnd$error_type, "USER_ERROR")

  cnd <- tryCatch(DBI::dbGetQuery(con, "SELECT cancel"), error = identity)
  expect_s3_class(cnd, "trino_canceled")
  expect_s3_class(cnd, "trino_query_error")
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
