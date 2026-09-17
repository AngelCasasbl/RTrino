# What matters is the header that reaches the server, so the closures are
# checked against the fake coordinator rather than by inspecting the request
# object, whose credentials httr2 deliberately keeps opaque.
sent_authorization <- function(proc) {
  headers <- jsonlite::fromJSON(proc$url("/test/last-request"))$headers
  names(headers) <- tolower(names(headers))
  headers[["authorization"]]
}

test_that("trino_auth_basic() sends basic credentials", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, auth = trino_auth_basic("angel", "secret"))

  DBI::dbGetQuery(con, "SELECT 1")
  expect_identical(
    sent_authorization(proc),
    paste0("Basic ", jsonlite::base64_enc(charToRaw("angel:secret")))
  )
})

test_that("trino_auth_jwt() sends a bearer token", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, auth = trino_auth_jwt("abc.def.ghi"))

  DBI::dbGetQuery(con, "SELECT 1")
  expect_identical(sent_authorization(proc), "Bearer abc.def.ghi")
})

test_that("no auth means no Authorization header", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbGetQuery(con, "SELECT 1")
  expect_null(sent_authorization(proc))
})

test_that("authentication closures validate their arguments", {
  expect_error(trino_auth_basic(NULL, "x"), "`user` must be a single string")
  expect_error(trino_auth_jwt(""), "`token` must not be empty")
  expect_error(
    trino_auth_oauth2(client_id = "a", client_secret = "b", token_url = 1),
    "`token_url` must be a single string"
  )
})

test_that("trino_auth_oauth2() builds a closure without contacting the provider", {
  auth <- trino_auth_oauth2(
    client_id = "id",
    client_secret = "secret",
    token_url = "https://auth.example.com/token",
    scope = "trino"
  )
  expect_true(is.function(auth))
  req <- auth(httr2::request("http://example.com"))
  expect_s3_class(req, "httr2_request")
})

test_that("credentials stay inside the closure", {
  auth <- trino_auth_basic("angel", "secret")
  # They are reachable only through the closure's own environment, never from
  # the caller's.
  expect_false(exists("password", envir = globalenv(), inherits = FALSE))
  expect_identical(get("password", envir = environment(auth)), "secret")
})

test_that("an authenticating server accepts the connection", {
  token <- "Bearer test-token"
  proc <- local_trino_app(require_auth = token)

  con <- local_trino_con(proc, auth = trino_auth_jwt("test-token"))
  expect_true(DBI::dbIsValid(con))
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT 1")), 2L)
})

test_that("a missing credential is reported as a failed connection", {
  proc <- local_trino_app(require_auth = "Bearer test-token")
  expect_error(
    local_trino_con(proc),
    "Cannot connect to Trino"
  )
})

test_that("basic authentication reaches the server", {
  # "angel:secret" base64-encoded, as httr2 will send it.
  header <- paste0("Basic ", jsonlite::base64_enc(charToRaw("angel:secret")))
  proc <- local_trino_app(require_auth = header)

  con <- local_trino_con(proc, auth = trino_auth_basic("angel", "secret"))
  expect_true(DBI::dbIsValid(con))
})
