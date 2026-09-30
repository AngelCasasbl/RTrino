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
      " WHERE table_schema = lower('default')",
      " AND table_name = lower('sales')"
    )
  )

  expect_false(DBI::dbExistsTable(con, "sale"))
})

test_that("dbExistsTable() ignores case, as Trino's identifiers do", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # SELECT * FROM SALES finds `sales`, so the table exists under either name.
  expect_true(DBI::dbExistsTable(con, "SALES"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_match(last$body, "table_name = lower('SALES')", fixed = TRUE)
})

sent_body <- function(proc) {
  jsonlite::fromJSON(proc$url("/test/last-request"))$body
}

test_that("tables can be named with DBI::Id()", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # No note about an ambiguous method: Id has its own methods.
  expect_silent(
    exists <- DBI::dbExistsTable(
      con,
      DBI::Id(catalog = "other", schema = "analytics", table = "sales")
    )
  )
  expect_true(exists)
  expect_match(sent_body(proc), '"other"\\.information_schema\\.tables')
  expect_match(
    sent_body(proc),
    "table_schema = lower('analytics')",
    fixed = TRUE
  )

  expect_silent(fields <- DBI::dbListFields(con, DBI::Id(table = "sales")))
  expect_identical(fields, c("id", "region"))
  expect_identical(sent_body(proc), 'DESCRIBE "memory"."default"."sales"')

  DBI::dbListFields(con, DBI::Id(schema = "sch", table = "tbl"))
  expect_identical(sent_body(proc), 'DESCRIBE "memory"."sch"."tbl"')
  DBI::dbListFields(con, DBI::Id("cat", "sch", "tbl"))
  expect_identical(sent_body(proc), 'DESCRIBE "cat"."sch"."tbl"')

  expect_error(
    DBI::dbListFields(con, DBI::Id(catalog = "cat", table = "tbl")),
    "must also have a schema"
  )
  expect_error(
    DBI::dbListFields(con, DBI::Id(database = "x", table = "tbl")),
    "must name its components"
  )
})

test_that("tables can be named with an identifier already quoted", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_true(DBI::dbExistsTable(con, DBI::SQL('"memory"."default"."sales"')))
  expect_match(sent_body(proc), "table_name = lower('sales')", fixed = TRUE)

  # A dot inside quotes belongs to the name; a doubled quote is one quote.
  DBI::dbListFields(con, DBI::SQL('"we.ird"'))
  expect_identical(sent_body(proc), 'DESCRIBE "memory"."default"."we.ird"')
  DBI::dbListFields(con, DBI::SQL('sch."a""b"'))
  expect_identical(sent_body(proc), 'DESCRIBE "memory"."sch"."a""b"')

  # What dbQuoteIdentifier() returns can be passed straight back.
  quoted <- DBI::dbQuoteIdentifier(con, DBI::Id(schema = "sch", table = "t"))
  DBI::dbListFields(con, quoted)
  expect_identical(sent_body(proc), 'DESCRIBE "memory"."sch"."t"')

  expect_error(
    DBI::dbListFields(con, DBI::SQL('"open')),
    "unterminated quote"
  )
  expect_error(DBI::dbListFields(con, "a..b"), "has an empty part")
})

test_that("dbExistsTable() resolves qualified names", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_true(DBI::dbExistsTable(con, "analytics.sales"))
  last <- jsonlite::fromJSON(proc$url("/test/last-request"))
  expect_match(last$body, "table_schema = lower('analytics')", fixed = TRUE)
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
  expect_match(last$body, "table_name = lower('O''Brien')", fixed = TRUE)
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

test_that("a missing or malformed table name gets a readable error", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(DBI::dbListFields(con), "`name` is required")
  expect_error(DBI::dbExistsTable(con), "`name` is required")

  for (bad in list(NULL, 1, NA_character_, c("a", "b"))) {
    expect_error(DBI::dbListFields(con, bad), "must be a single string")
    expect_error(DBI::dbExistsTable(con, bad), "must be a single string")
  }

  expect_error(DBI::dbListFields(con, ""), "must not be empty")
  expect_error(DBI::dbExistsTable(con, ""), "must not be empty")
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
  expect_identical(
    as.character(DBI::dbQuoteString(con, "O'Brien")),
    "'O''Brien'"
  )
  expect_identical(as.character(DBI::dbQuoteString(con, NA_character_)), "NULL")
  expect_error(DBI::dbQuoteIdentifier(con, NA_character_), "Cannot quote NA")
  expect_identical(
    as.character(DBI::dbQuoteIdentifier(con, DBI::Id("a", "b", "c"))),
    '"a"."b"."c"'
  )
})

test_that("SQL that is already quoted is not quoted again", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  id <- DBI::SQL('"x"')
  expect_identical(DBI::dbQuoteIdentifier(con, id), id)
  literal <- DBI::SQL("'a'")
  expect_identical(DBI::dbQuoteString(con, literal), literal)
  expect_identical(DBI::dbQuoteLiteral(con, literal), literal)
})

test_that("R values are quoted as Trino literals of their type", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)
  quote <- function(x) as.character(DBI::dbQuoteLiteral(con, x))

  expect_identical(
    quote(as.Date(c("2026-01-15", NA))),
    c("DATE '2026-01-15'", "NULL")
  )
  expect_identical(
    quote(as.POSIXct("2026-01-15 10:30:00.123456", tz = "UTC")),
    "TIMESTAMP '2026-01-15 10:30:00.123456'"
  )
  expect_identical(
    quote(as.POSIXct("2026-01-15 10:30:00", tz = "UTC")),
    "TIMESTAMP '2026-01-15 10:30:00'"
  )
  expect_identical(quote(c(TRUE, FALSE, NA)), c("TRUE", "FALSE", "NULL"))
  expect_identical(quote(c(1L, NA)), c("1", "NULL"))
  expect_identical(
    quote(bit64::as.integer64("9007199254740993")),
    "9007199254740993"
  )
  expect_identical(
    quote(c(0.1 + 0.2, 1, 1e300, -2.5e-8, NA)),
    c("0.30000000000000004E0", "1E0", "1E+300", "-2.5E-08", "NULL")
  )
  expect_identical(
    quote(c(NaN, Inf, -Inf)),
    c("nan()", "infinity()", "-infinity()")
  )
  expect_identical(quote(c("O'Brien", NA)), c("'O''Brien'", "NULL"))
  expect_identical(quote(factor("a")), "'a'")
  expect_identical(quote(list(as.raw(c(1, 255)), NULL)), c("X'01ff'", "NULL"))
})

test_that("a POSIXct is written in the connection's time zone", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, session.timezone = "Europe/Madrid")

  # 09:30 UTC is 10:30 in Madrid in January, which is how Trino will read the
  # literal back in that session.
  x <- as.POSIXct("2026-01-15 09:30:00", tz = "UTC")
  expect_identical(
    as.character(DBI::dbQuoteLiteral(con, x)),
    "TIMESTAMP '2026-01-15 10:30:00'"
  )
})

test_that("sqlInterpolate() puts typed literals into a statement", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  sql <- DBI::sqlInterpolate(
    con,
    "SELECT * FROM t WHERE d >= ?d AND flag = ?flag AND name = ?name",
    d = as.Date("2026-01-01"), flag = TRUE, name = "x'; DROP TABLE t; --"
  )
  expect_identical(
    as.character(sql),
    paste0(
      "SELECT * FROM t WHERE d >= DATE '2026-01-01' AND flag = TRUE",
      " AND name = 'x''; DROP TABLE t; --'"
    )
  )
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
