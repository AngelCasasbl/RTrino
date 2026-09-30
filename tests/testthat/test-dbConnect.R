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
  # The scheme is compared as a string, to refuse credentials over HTTP.
  expect_identical(
    trino_normalize_host("HTTP://Trino.example.com"),
    "http://Trino.example.com"
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

test_that("arguments are validated before the server is contacted", {
  drv <- RTrino::Trino()
  connect <- function(...) {
    DBI::dbConnect(drv, host = "http://127.0.0.1", port = 1L, ...)
  }

  expect_error(
    connect(catalog = c("a", "b"), schema = "s"),
    "`catalog` must be a single string"
  )
  expect_error(
    connect(catalog = "c", schema = NA_character_),
    "`schema` must be a single string"
  )
  expect_error(
    connect(catalog = "c", schema = "s", extra.headers = list("x")),
    "All extra headers must be named"
  )
  expect_error(
    connect(catalog = "c", schema = "s", extra.headers = list(A = 1:2)),
    "Extra header `A` must be a single string"
  )
  expect_error(
    connect(catalog = "c", schema = "s", timeout = 0),
    "`timeout` must be a positive number"
  )
  expect_error(
    connect(catalog = "c", schema = "s", query_max_run_time = "soon"),
    "`query_max_run_time` must be a duration"
  )
  expect_error(
    connect(catalog = "c", schema = "s", extra.headers = "X-A: 1"),
    "must be a named list"
  )
  expect_error(
    connect(catalog = "c", schema = "s", allow_http_auth = NA),
    "`allow_http_auth` must be `TRUE` or `FALSE`"
  )
})

test_that("the driver answers DBI's questions about itself", {
  drv <- RTrino::Trino()
  expect_true(DBI::dbIsValid(drv))
  expect_identical(DBI::dbGetInfo(drv)$driver.version, the$version)
  expect_invisible(unloaded <- DBI::dbUnloadDriver(drv))
  expect_true(unloaded)
})

test_that("a closed connection says so when printed", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)
  DBI::dbDisconnect(con)
  expect_output(print(con), "DISCONNECTED")
})

test_that("ports are whole numbers in range", {
  expect_identical(trino_check_port(8080), 8080L)
  expect_identical(trino_check_port("8443"), 8443L)
  for (bad in list(18080.9, 0, 70000, NA, "x", c(1, 2), TRUE)) {
    expect_error(trino_check_port(bad), "whole number between 1 and 65535")
  }
})

test_that("a port written into the host is used, not doubled", {
  expect_identical(
    trino_host_port("http://localhost:18080"),
    list(host = "http://localhost", port = 18080L)
  )
  expect_identical(
    trino_host_port("https://[::1]:8443"),
    list(host = "https://[::1]", port = 8443L)
  )
  expect_identical(
    trino_host_port("https://trino.example.com"),
    list(host = "https://trino.example.com", port = NA_integer_)
  )

  proc <- local_trino_app()
  url <- httr2::url_parse(proc$url())
  con <- DBI::dbConnect(
    RTrino::Trino(),
    host = paste0(url$hostname, ":", url$port),
    catalog = "memory", schema = "default"
  )
  withr::defer(DBI::dbDisconnect(con))
  expect_identical(con@port, as.integer(url$port))
  expect_identical(con@host, paste0("http://", url$hostname))

  expect_error(
    DBI::dbConnect(
      RTrino::Trino(),
      host = "http://localhost:1234", port = 5678,
      catalog = "memory", schema = "default"
    ),
    "`host` includes port 1234, but `port` is 5678"
  )
})

test_that("credentials are not sent over plain HTTP unless allowed", {
  proc <- local_trino_app()
  expect_error(
    local_trino_con(proc, auth = trino_auth_jwt("token")),
    "would send credentials unencrypted"
  )
  for (host in c("localhost", "HTTP://localhost")) {
    expect_error(
      DBI::dbConnect(
        RTrino::Trino(), host = host,
        catalog = "memory", schema = "default",
        auth = trino_auth_basic("u", "p")
      ),
      "set `allow_http_auth = TRUE`",
      info = host
    )
  }
  # Nothing was sent: the refusal comes before the probe.
  headers <- jsonlite::fromJSON(proc$url("/test/last-request"))$headers
  expect_null(headers[["authorization"]])

  con <- local_trino_con(
    proc,
    auth = trino_auth_jwt("token"),
    allow_http_auth = TRUE
  )
  expect_true(DBI::dbIsValid(con))

  # Over HTTPS the check does not apply; this fails on connecting instead.
  expect_error(
    DBI::dbConnect(
      RTrino::Trino(), host = "https://127.0.0.1", port = 1L,
      catalog = "memory", schema = "default",
      auth = trino_auth_jwt("token")
    ),
    "Cannot connect to Trino"
  )
})

test_that("each request is bounded by the timeout", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, timeout = 1)
  expect_identical(con@timeout, 1)

  # The fake coordinator takes three seconds to answer this one.
  started <- Sys.time()
  expect_error(DBI::dbGetQuery(con, "SELECT hang"), "Timeout")
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 2.9)

  req <- trino_timeouts(httr2::request("http://x"), 30)
  expect_identical(req$options$timeout_ms, 30000)
  expect_identical(req$options$connecttimeout_ms, 10000)
  req <- trino_timeouts(httr2::request("http://x"), Inf)
  expect_null(req$options$timeout_ms)
})

test_that("query_max_run_time is sent as a session property", {
  proc <- local_trino_app()
  session_header <- function() {
    headers <- jsonlite::fromJSON(proc$url("/test/last-request"))$headers
    names(headers) <- tolower(names(headers))
    headers[["x-trino-session"]]
  }

  con <- local_trino_con(proc, query_max_run_time = "5m")
  DBI::dbGetQuery(con, "SELECT 1")
  expect_identical(session_header(), "query_max_run_time=5m")

  con <- local_trino_con(proc, query_max_run_time = 90)
  DBI::dbGetQuery(con, "SELECT 1")
  expect_identical(session_header(), "query_max_run_time=90s")

  # Joined to the properties the caller already sets in the same header.
  con <- local_trino_con(
    proc,
    query_max_run_time = "1h",
    extra.headers = list("X-Trino-Session" = "join_distribution_type=BROADCAST")
  )
  DBI::dbGetQuery(con, "SELECT 1")
  expect_identical(
    session_header(),
    "join_distribution_type=BROADCAST,query_max_run_time=1h"
  )

  expect_error(
    local_trino_con(
      proc,
      query_max_run_time = "1h",
      extra.headers = list("x-trino-session" = "query_max_run_time=2h")
    ),
    "set it only once"
  )
})

test_that("a failure that is not an HTTP one is not reported as one", {
  proc <- local_trino_app()
  broken <- function(req) stop("the auth closure broke")
  expect_error(
    local_trino_con(proc, auth = broken, allow_http_auth = TRUE),
    "the auth closure broke"
  )
})
