#' Normalise a Trino host
#'
#' Adds a default scheme when missing and drops any trailing slash so that
#' URLs can be built by simple concatenation.
#'
#' @param host Host as supplied by the user.
#' @return A single string.
#' @noRd
trino_normalize_host <- function(host) {
  if (!is.character(host) || length(host) != 1L || is.na(host) || !nzchar(host)) {
    stop("`host` must be a non-empty string.", call. = FALSE)
  }
  if (!grepl("^https?://", host, ignore.case = TRUE)) {
    host <- paste0("http://", host)
  }
  sub("/+$", "", host)
}

#' Base URL of a connection
#'
#' @param conn A [TrinoConnection-class] object.
#' @return A string of the form `scheme://host:port`.
#' @noRd
trino_base_url <- function(conn) {
  paste0(conn@host, ":", conn@port)
}

#' Build an absolute URL from a connection and a path
#'
#' @param conn A [TrinoConnection-class] object.
#' @param path Path beginning with a slash, e.g. `"/v1/statement"`.
#' @return A string.
#' @noRd
trino_url <- function(conn, path) {
  paste0(trino_base_url(conn), path)
}

#' Truncate a string for display
#'
#' @param x A string.
#' @param width Maximum number of characters.
#' @return A string, with an ellipsis when truncated.
#' @noRd
trino_truncate <- function(x, width = 60L) {
  x <- gsub("[[:space:]]+", " ", trimws(x))
  if (nchar(x) <= width) {
    return(x)
  }
  paste0(substr(x, 1L, width - 3L), "...")
}

#' Fail unless a connection is usable
#'
#' @param conn A [TrinoConnection-class] object.
#' @return `conn`, invisibly.
#' @noRd
trino_check_valid <- function(conn) {
  if (!dbIsValid(conn)) {
    stop("Invalid TrinoConnection", call. = FALSE)
  }
  invisible(conn)
}

#' Build and perform a request against a Trino endpoint
#'
#' The single HTTP entry point of the package. Every call composes, in order,
#' the Trino protocol headers, the connection's authentication closure and its
#' SSL options, so that authentication and TLS behave identically for the
#' initial `POST /v1/statement`, every pagination `GET` and the cancelling
#' `DELETE`.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param url Absolute URL to call.
#' @param method HTTP method.
#' @param body Optional request body, sent as `text/plain` (Trino's statement
#'   endpoint takes raw SQL, not JSON).
#' @param extra_headers Extra headers for this request only.
#' @return An `httr2_response`.
#' @noRd
trino_perform <- function(conn,
                          url,
                          method = c("GET", "POST", "DELETE"),
                          body = NULL,
                          extra_headers = list()) {
  method <- match.arg(method)

  req <- httr2::request(url)
  req <- httr2::req_method(req, method)
  req <- httr2::req_headers(req, !!!trino_headers(conn, extra_headers))
  req <- httr2::req_user_agent(
    req,
    paste0("RTrino/", as.character(packageVersion("RTrino")))
  )
  if (!is.null(body)) {
    req <- httr2::req_body_raw(req, body, type = "text/plain")
  }
  if (!is.null(conn@auth)) {
    req <- conn@auth(req)
  }
  req <- trino_ssl_options(req, conn@ssl_options)
  # Trino answers 502/503/504 while the coordinator is busy; those are worth
  # retrying, unlike the 4xx a bad query produces.
  req <- httr2::req_retry(req, max_tries = 3L)

  httr2::req_perform(req)
}

#' Parse a Trino JSON payload
#'
#' Keeps the payload as nested lists: Trino sends every value as JSON, and
#' `simplifyVector = TRUE` would coerce column types before `trino_cast_column()`
#' has had a chance to apply the declared Trino type.
#'
#' @param resp An `httr2_response`.
#' @return A list.
#' @noRd
trino_parse_response <- function(resp) {
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}
