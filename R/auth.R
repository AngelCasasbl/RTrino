#' Authentication methods for Trino
#'
#' Each helper returns a *closure* that takes an `httr2` request and returns it
#' with the appropriate credentials attached. The credentials live only in that
#' closure's environment, so they are never written to the global environment
#' and never stored on the connection object in plain sight. Pass the result as
#' the `auth` argument of [dbConnect()].
#'
#' * `trino_auth_basic()` — HTTP basic authentication, used by Trino's LDAP and
#'   password-file authenticators.
#' * `trino_auth_jwt()` — a bearer JWT, for service accounts and unattended
#'   pipelines, or for a cluster fronted by an SSO proxy that mints its own
#'   tokens.
#' * `trino_auth_oauth2()` — OAuth2 client credentials, for corporate identity
#'   providers such as Okta or Entra ID. `httr2` caches the token and renews it
#'   when it expires.
#'
#' Trino rejects basic and bearer credentials over plain HTTP, so use an
#' `https://` host with all three.
#'
#' @param user User name.
#' @param password Password. Read it from the environment
#'   (`Sys.getenv("TRINO_PASSWORD")`) rather than writing it in a script.
#' @param token A JWT, as a string.
#' @param client_id OAuth2 client id.
#' @param client_secret OAuth2 client secret.
#' @param token_url Token endpoint of the OAuth2 provider.
#' @param scope Optional OAuth2 scope.
#' @param ... Further arguments passed on to
#'   [httr2::req_oauth_client_credentials()].
#'
#' @return A function of one argument (an `httr2` request) returning a modified
#'   request.
#'
#' @name trino_auth
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(
#'   Rtrino::Trino(),
#'   host    = "https://trino.example.com",
#'   port    = 443,
#'   user    = "analyst",
#'   catalog = "hive",
#'   schema  = "default",
#'   auth    = trino_auth_basic("analyst", Sys.getenv("TRINO_PASSWORD"))
#' )
#' }
NULL

#' @rdname trino_auth
#' @export
trino_auth_basic <- function(user, password) {
  user <- trino_check_string(user, "user")
  password <- trino_check_string(password, "password", allow_empty = TRUE)
  function(req) httr2::req_auth_basic(req, user, password)
}

#' @rdname trino_auth
#' @export
trino_auth_jwt <- function(token) {
  token <- trino_check_string(token, "token")
  function(req) httr2::req_auth_bearer_token(req, token)
}

#' @rdname trino_auth
#' @export
trino_auth_oauth2 <- function(client_id,
                              client_secret,
                              token_url,
                              scope = NULL,
                              ...) {
  client_id <- trino_check_string(client_id, "client_id")
  client_secret <- trino_check_string(client_secret, "client_secret")
  token_url <- trino_check_string(token_url, "token_url")
  if (!is.null(scope)) {
    scope <- trino_check_string(scope, "scope")
  }

  client <- httr2::oauth_client(
    id = client_id,
    secret = client_secret,
    token_url = token_url
  )
  dots <- list(...)

  function(req) {
    rlang::inject(httr2::req_oauth_client_credentials(
      req,
      client = client,
      scope = scope,
      !!!dots
    ))
  }
}

#' Validate a scalar string argument
#'
#' @param x Value to check.
#' @param arg Argument name, used in the error message.
#' @param allow_empty Whether `""` is acceptable.
#' @return `x`, unchanged.
#' @noRd
trino_check_string <- function(x, arg, allow_empty = FALSE) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    stop(sprintf("`%s` must be a single string.", arg), call. = FALSE)
  }
  if (!allow_empty && !nzchar(x)) {
    stop(sprintf("`%s` must not be empty.", arg), call. = FALSE)
  }
  x
}
