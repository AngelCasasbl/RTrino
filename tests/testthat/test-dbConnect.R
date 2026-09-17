test_that("dbConnect() returns a usable connection and probes /v1/info", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_s4_class(con, "TrinoConnection")
  expect_true(DBI::dbIsValid(con))
  expect_identical(con@catalog, "memory")
  expect_identical(con@bigint, "integer64")
})

test_that("catalog and schema are required", {
  drv <- RTrino::Trino()
  expect_error(
    DBI::dbConnect(drv, host = "http://localhost", schema = "default"),
    "catalog and schema are required"
  )
  expect_error(
    DBI::dbConnect(drv, host = "http://localhost", catalog = "hive"),
    "catalog and schema are required"
  )
  expect_error(
    DBI::dbConnect(drv, catalog = "", schema = "default"),
    "catalog and schema are required"
  )
})

test_that("auth must be a function or NULL", {
  expect_error(
    DBI::dbConnect(
      RTrino::Trino(),
      catalog = "hive", schema = "default", auth = "token"
    ),
    "auth must be a function or NULL"
  )
})

test_that("an unreachable coordinator is reported with its address", {
  # Port 1 is reserved and never listening.
  expect_error(
    DBI::dbConnect(
      RTrino::Trino(),
      host = "http://127.0.0.1", port = 1L,
      catalog = "hive", schema = "default"
    ),
    "Cannot connect to Trino at http://127\\.0\\.0\\.1:1"
  )
})

test_that("the host is normalised", {
  expect_identical(trino_normalize_host("localhost"), "http://localhost")
  expect_identical(
    trino_normalize_host("https://trino.example.com/"),
    "https://trino.example.com"
  )
  expect_identical(
    trino_normalize_host("http://trino.example.com///"),
    "http://trino.example.com"
  )
  expect_error(trino_normalize_host(""), "non-empty string")
})

test_that("dbDisconnect() invalidates the connection", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_true(DBI::dbDisconnect(con))
  expect_false(DBI::dbIsValid(con))
  expect_error(DBI::dbGetQuery(con, "SELECT 1"), "Invalid TrinoConnection")
  expect_warning(DBI::dbDisconnect(con), "already closed")
})

test_that("dbGetInfo() reports the server version and the settings", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  info <- DBI::dbGetInfo(con)
  expect_identical(info$db.version, "451")
  expect_identical(info$catalog, "memory")
  expect_identical(info$schema, "default")
  expect_identical(info$user, "tester")
})

test_that("bigint is validated against the allowed values", {
  proc <- local_trino_app()
  expect_error(
    local_trino_con(proc, bigint = "int32"),
    "should be one of"
  )
})
