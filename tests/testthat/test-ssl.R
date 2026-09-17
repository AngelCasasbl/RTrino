test_that("trino_ssl() verifies certificates by default", {
  opts <- trino_ssl()
  expect_true(opts$verify)
  expect_null(opts$ca_bundle)
  expect_s3_class(opts, "trino_ssl_options")
})

test_that("disabling verification warns every time it is applied", {
  req <- httr2::request("https://example.com")
  expect_warning(
    trino_ssl_options(req, trino_ssl(verify = FALSE)),
    "SSL verification disabled"
  )
})

test_that("a CA bundle is passed to curl and must exist", {
  bundle <- withr::local_tempfile(lines = "-----BEGIN CERTIFICATE-----")
  opts <- trino_ssl(ca_bundle = bundle)
  expect_identical(opts$ca_bundle, bundle)

  req <- trino_ssl_options(httr2::request("https://example.com"), opts)
  expect_identical(req$options$cainfo, bundle)

  expect_error(
    trino_ssl(ca_bundle = file.path(tempdir(), "no-such-ca.pem")),
    "CA bundle not found"
  )
})

test_that("trino_ssl() validates verify", {
  expect_error(trino_ssl(verify = NA), "must be `TRUE` or `FALSE`")
  expect_error(trino_ssl(verify = "yes"), "must be `TRUE` or `FALSE`")
})

test_that("verified connections leave curl's defaults alone", {
  req <- trino_ssl_options(httr2::request("https://example.com"), trino_ssl())
  expect_null(req$options$ssl_verifypeer)
  expect_null(req$options$cainfo)
})

test_that("dbConnect() rejects ssl_options that are not from trino_ssl()", {
  expect_error(
    DBI::dbConnect(
      Rtrino::Trino(),
      catalog = "hive", schema = "default",
      ssl_options = list(verify = TRUE)
    ),
    "must be the result of `trino_ssl\\(\\)`"
  )
})

test_that("the warning fires on each request, not only on connect", {
  proc <- local_trino_app()
  url <- httr2::url_parse(proc$url())
  expect_warning(
    con <- DBI::dbConnect(
      Rtrino::Trino(),
      host = paste0(url$scheme, "://", url$hostname),
      port = as.integer(url$port),
      catalog = "memory", schema = "default",
      ssl_options = trino_ssl(verify = FALSE)
    ),
    "SSL verification disabled"
  )
  withr::defer(try(DBI::dbDisconnect(con), silent = TRUE))
  # One warning per HTTP call, and a query makes several.
  warnings <- testthat::capture_warnings(DBI::dbGetQuery(con, "SELECT 1"))
  expect_true(all(grepl("SSL verification disabled", warnings)))
  expect_gte(length(warnings), 2L)
})
