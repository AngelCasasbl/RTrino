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

#' Normalise a Trino host
#'
#' Adds a default scheme when missing, writes the scheme in lower case, and
#' drops any trailing slash so that URLs can be built by simple
#' concatenation and the scheme compared as a plain string.
#'
#' @param host Host as supplied by the user.
#' @return A single string.
#' @noRd
trino_normalize_host <- function(host) {
  if (!is.character(host) || length(host) != 1L || is.na(host) ||
        !nzchar(host)) {
    stop("`host` must be a non-empty string.", call. = FALSE)
  }
  if (grepl("^https?://", host, ignore.case = TRUE)) {
    host <- sub("^(https?)://", "\\L\\1://", host, ignore.case = TRUE,
                perl = TRUE)
  } else {
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
#' the Trino protocol headers, the connection's authentication closure, its
#' SSL options and its timeout, so that they behave identically for the
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
  req <- httr2::req_user_agent(req, the$user_agent)
  if (!is.null(body)) {
    req <- httr2::req_body_raw(req, body, type = "text/plain")
  }
  if (!is.null(conn@auth)) {
    req <- conn@auth(req)
  }
  req <- trino_ssl_options(req, conn@ssl_options)
  req <- trino_timeouts(req, conn@timeout)
  # Trino's client protocol asks for a retry after 50-100 ms on a 502, 503 or
  # 504, which a load balancer sends while the coordinator is busy or
  # restarting, and after its Retry-After on a 429. A 4xx from a bad query is
  # final. httr2's own default would retry only 429 and 503.
  req <- httr2::req_retry(
    req,
    max_tries = 3L,
    is_transient = function(resp) {
      httr2::resp_status(resp) %in% c(429L, 502L, 503L, 504L)
    },
    backoff = function(attempt) 0.1
  )

  httr2::req_perform(req)
}

#' Apply the connection's timeout to a request
#'
#' `timeout` bounds the whole request, connecting included. Connecting on its
#' own keeps curl's usual limit of 10 seconds, or `timeout` if shorter, so an
#' unreachable host still fails fast.
#'
#' @param req An `httr2` request.
#' @param timeout Seconds, or `Inf` for curl's defaults.
#' @return The modified request.
#' @noRd
trino_timeouts <- function(req, timeout) {
  if (!is.finite(timeout)) {
    return(req)
  }
  httr2::req_options(
    req,
    timeout_ms = ceiling(timeout * 1000),
    connecttimeout_ms = ceiling(min(timeout, 10) * 1000)
  )
}

#' Parse a Trino JSON payload
#'
#' Keeps the payload as nested lists: Trino sends every value as JSON, and
#' `simplifyVector = TRUE` would coerce column types before
#' `trino_cast_column()` has had a chance to apply the declared Trino type.
#'
#' Trino sends `BIGINT` and `DOUBLE` values as JSON numbers, not strings. A
#' double holds every integer exactly only up to 2^53, so `bigint_as_char` has
#' jsonlite keep the digits of any integer beyond that as a string. Smaller
#' integers arrive as an R integer (within 32 bits) or as an exact double, and
#' `DOUBLE` values as the double the text denotes; `trino_cast_column()` then
#' converts them without going through text.
#'
#' @param resp An `httr2_response`.
#' @return A list.
#' @noRd
trino_parse_response <- function(resp) {
  httr2::resp_body_json(resp, simplifyVector = FALSE, bigint_as_char = TRUE)
}
