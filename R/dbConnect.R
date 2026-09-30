#' Connect to a Trino cluster
#'
#' Creates a [TrinoConnection-class]. Trino's REST API is stateless, so no
#' session is opened on the server; the connection object holds the coordinator
#' address and the per-request settings. To fail early on a wrong address or
#' bad credentials, `dbConnect()` probes `GET /v1/info` before returning.
#'
#' @section Timeouts:
#' A query is a series of HTTP requests, so two limits apply. `timeout` bounds
#' each request: a coordinator or network that stops answering fails with an
#' error instead of blocking the R session. `query_max_run_time` bounds the
#' query as a whole on the server: past it, Trino stops the query and RTrino
#' raises a `trino_query_error` whose `error_name` is `"EXCEEDED_TIME_LIMIT"`.
#' In a Shiny app, where a blocked session blocks its user, set both.
#'
#' @param drv A [TrinoDriver-class] object, from [Trino()].
#' @param host Coordinator URL. A missing scheme defaults to `http://`; a
#'   trailing slash is dropped. It may include the port
#'   (`"https://trino.example.com:8443"`), in which case `port` need not be
#'   given.
#' @param port Coordinator port, a whole number between 1 and 65535.
#' @param user Trino user name, sent as `X-Trino-User`.
#' @param catalog Trino catalog. Required.
#' @param schema Trino schema. Required.
#' @param source Value of the `X-Trino-Source` header; shows up in the
#'   coordinator's query history.
#' @param session.timezone Session time zone, used when reading `TIMESTAMP`
#'   columns.
#' @param bigint How to return `BIGINT` columns: `"integer64"` (the default,
#'   via `bit64`, exact except for the lowest value, -9223372036854775808,
#'   which bit64 reserves for `NA`), `"numeric"` (a double, exact only up to
#'   2^53) or `"character"` (the exact digits).
#' @param auth An authentication closure from [trino_auth_basic()],
#'   [trino_auth_jwt()] or [trino_auth_oauth2()], or `NULL` for a cluster with
#'   no authentication.
#' @param ssl_options TLS options from [trino_ssl()].
#' @param extra.headers Named list of extra HTTP headers added to every
#'   request, each a single string. Useful for Trino session properties set
#'   through `X-Trino-Session`.
#' @param timeout Seconds allowed for each HTTP request to the coordinator,
#'   not for the whole query; `Inf` for no limit. Connecting gives up after
#'   10 seconds, or `timeout` if shorter.
#' @param query_max_run_time Longest a query may run on the cluster before
#'   Trino stops it, as a Trino duration such as `"30m"` or `"2h"`, or a
#'   number of seconds. `NULL`, the default, leaves the cluster's own limit.
#'   Sent as the `query_max_run_time` session property.
#' @param allow_http_auth Set to `TRUE` to send `auth` credentials to an
#'   `http://` host, which carries them unencrypted. Only for a connection
#'   that is encrypted by other means, such as an SSH tunnel.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A [TrinoConnection-class] object.
#'
#' @export
#' @examples
#' \dontrun{
#' # Internal cluster, no authentication
#' con <- DBI::dbConnect(
#'   RTrino::Trino(),
#'   host = "http://localhost", port = 8080,
#'   catalog = "hive", schema = "default"
#' )
#'
#' # LDAP over TLS, with limits for use in a Shiny app
#' con <- DBI::dbConnect(
#'   RTrino::Trino(),
#'   host    = "https://trino.example.com",
#'   port    = 443,
#'   user    = Sys.getenv("TRINO_USER"),
#'   catalog = "hive",
#'   schema  = "analytics",
#'   auth    = trino_auth_basic(Sys.getenv("TRINO_USER"),
#'                              Sys.getenv("TRINO_PASSWORD")),
#'   timeout = 30,
#'   query_max_run_time = "5m"
#' )
#'
#' DBI::dbDisconnect(con)
#' }
setMethod("dbConnect", "TrinoDriver", function(drv,
                                               host = "http://localhost",
                                               port = 8080L,
                                               user = trino_default_user(),
                                               catalog = NULL,
                                               schema = NULL,
                                               source = "RTrino",
                                               session.timezone = "UTC",
                                               bigint = c(
                                                 "integer64",
                                                 "numeric",
                                                 "character"
                                               ),
                                               auth = NULL,
                                               ssl_options = trino_ssl(),
                                               extra.headers = list(),
                                               timeout = 60,
                                               query_max_run_time = NULL,
                                               allow_http_auth = FALSE,
                                               ...) {
  host <- trino_normalize_host(host)
  embedded <- trino_host_port(host)
  if (!is.na(embedded$port)) {
    if (!missing(port) && !identical(trino_check_port(port), embedded$port)) {
      stop(
        sprintf(
          "`host` includes port %d, but `port` is %s.",
          embedded$port, format(port)
        ),
        call. = FALSE
      )
    }
    host <- embedded$host
    port <- embedded$port
  }
  port <- trino_check_port(port)

  if (is.null(catalog) || is.null(schema) ||
        identical(catalog, "") || identical(schema, "")) {
    stop("catalog and schema are required", call. = FALSE)
  }
  catalog <- trino_check_string(catalog, "catalog")
  schema <- trino_check_string(schema, "schema")
  user <- trino_check_string(user, "user")
  source <- trino_check_string(source, "source")
  session.timezone <- trino_check_string(session.timezone, "session.timezone")
  bigint <- match.arg(bigint)

  if (!is.null(auth) && !is.function(auth)) {
    stop("auth must be a function or NULL", call. = FALSE)
  }
  if (!is.logical(allow_http_auth) || length(allow_http_auth) != 1L ||
        is.na(allow_http_auth)) {
    stop("`allow_http_auth` must be `TRUE` or `FALSE`.", call. = FALSE)
  }
  if (!is.null(auth) && startsWith(host, "http://") && !allow_http_auth) {
    stop(
      "`auth` would send credentials unencrypted to ", host, ". Use an ",
      "https:// host, or set `allow_http_auth = TRUE` if the connection is ",
      "encrypted by other means, such as an SSH tunnel.",
      call. = FALSE
    )
  }
  if (!is.list(ssl_options) ||
        !all(c("verify", "ca_bundle") %in% names(ssl_options))) {
    stop("`ssl_options` must be the result of `trino_ssl()`.", call. = FALSE)
  }

  extra.headers <- trino_check_headers(extra.headers)
  timeout <- trino_check_timeout(timeout)
  if (!is.null(query_max_run_time)) {
    extra.headers <- trino_add_session_property(
      extra.headers,
      "query_max_run_time",
      trino_check_duration(query_max_run_time, "query_max_run_time")
    )
  }

  # Once per connection: a single query makes several HTTP calls, and a
  # warning on each of them buries everything else.
  if (isFALSE(ssl_options$verify)) {
    warning(
      "SSL verification disabled - not recommended for production",
      call. = FALSE
    )
  }

  valid <- new.env(parent = emptyenv())
  valid$open <- TRUE

  conn <- new(
    "TrinoConnection",
    host = host,
    port = port,
    user = user,
    catalog = catalog,
    schema = schema,
    session.timezone = session.timezone,
    bigint = bigint,
    extra.headers = extra.headers,
    source = source,
    auth = auth,
    ssl_options = unclass(ssl_options),
    timeout = timeout,
    valid = valid
  )

  # Fail here rather than on the user's first query. Only a failed request is
  # reported as a failed connection; anything else is a bug worth seeing as
  # it is.
  tryCatch(
    trino_perform(conn, trino_url(conn, "/v1/info"), "GET"),
    httr2_error = function(e) {
      status <- if (inherits(e, "httr2_http")) {
        httr2::resp_status(e$resp)
      } else {
        conditionMessage(e)
      }
      stop(
        sprintf(
          "Cannot connect to Trino at %s - %s",
          trino_base_url(conn), status
        ),
        call. = FALSE
      )
    }
  )

  conn
})

#' Default Trino user name
#'
#' @return A string; the first non-empty of `USER`, `USERNAME` and
#'   `Sys.info()[["user"]]`.
#' @noRd
trino_default_user <- function() {
  candidates <- c(
    Sys.getenv("USER"),
    Sys.getenv("USERNAME"),
    tryCatch(Sys.info()[["user"]], error = function(e) "")
  )
  candidates <- candidates[nzchar(candidates)]
  if (length(candidates) == 0L) "unknown" else candidates[[1L]]
}

#' Validate a port
#'
#' @param port A number, or a string of digits.
#' @return The port as an integer.
#' @noRd
trino_check_port <- function(port) {
  value <- if (is.numeric(port) || is.character(port)) {
    suppressWarnings(as.numeric(port))
  }
  if (length(value) != 1L || is.na(value) || value != trunc(value) ||
        value < 1 || value > 65535) {
    stop("`port` must be a whole number between 1 and 65535.", call. = FALSE)
  }
  as.integer(value)
}

#' Split the port off a normalised host
#'
#' @param host A host from `trino_normalize_host()`.
#' @return A list with the `host` without its port, and the `port` it had, or
#'   `NA`.
#' @noRd
trino_host_port <- function(host) {
  # scheme, then a bracketed IPv6 address or a name, then an optional port.
  pattern <- "^(https?://)(\\[[^]]*\\]|[^:/]+)(:([0-9]+))?(/.*)?$"
  if (!grepl(pattern, host, perl = TRUE)) {
    return(list(host = host, port = NA_integer_))
  }
  digits <- sub(pattern, "\\4", host, perl = TRUE)
  if (!nzchar(digits)) {
    return(list(host = host, port = NA_integer_))
  }
  list(
    host = sub(pattern, "\\1\\2\\5", host, perl = TRUE),
    port = trino_check_port(digits)
  )
}

#' Validate the extra headers
#'
#' @param headers The `extra.headers` argument.
#' @return `headers`, with every value a string.
#' @noRd
trino_check_headers <- function(headers) {
  if (!is.list(headers)) {
    stop("`extra.headers` must be a named list.", call. = FALSE)
  }
  if (length(headers) == 0L) {
    return(headers)
  }
  if (is.null(names(headers)) || !all(nzchar(names(headers)))) {
    stop("All extra headers must be named.", call. = FALSE)
  }
  for (name in names(headers)) {
    value <- headers[[name]]
    if (!is.atomic(value) || length(value) != 1L || is.na(value)) {
      stop(
        sprintf("Extra header `%s` must be a single string.", name),
        call. = FALSE
      )
    }
    headers[[name]] <- as.character(value)
  }
  headers
}

#' Validate the request timeout
#'
#' @param timeout Seconds, or `Inf`.
#' @return `timeout` as a double.
#' @noRd
trino_check_timeout <- function(timeout) {
  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) ||
        timeout <= 0) {
    stop("`timeout` must be a positive number of seconds, or `Inf`.",
         call. = FALSE)
  }
  as.numeric(timeout)
}

#' Validate a Trino duration
#'
#' @param x A string such as `"30m"`, or a number of seconds.
#' @param arg Argument name, for the error message.
#' @return The duration as Trino writes it.
#' @noRd
trino_check_duration <- function(x, arg) {
  if (is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
        x > 0) {
    return(paste0(format(x, scientific = FALSE, trim = TRUE), "s"))
  }
  if (is.character(x) && length(x) == 1L && !is.na(x) &&
        grepl("^[0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h|d)$", x)) {
    return(x)
  }
  stop(
    sprintf(
      paste(
        "`%s` must be a duration such as \"30m\" or \"2h\",",
        "or a positive number of seconds."
      ),
      arg
    ),
    call. = FALSE
  )
}

#' Add a session property to the extra headers
#'
#' Trino reads every session property from one `X-Trino-Session` header, as a
#' comma-separated list, so a property set here joins any the caller already
#' set there.
#'
#' @param headers Validated extra headers.
#' @param name,value The property.
#' @return `headers`, with the property added.
#' @noRd
trino_add_session_property <- function(headers, name, value) {
  property <- paste0(name, "=", value)
  at <- match("x-trino-session", tolower(names(headers)))
  if (is.na(at)) {
    headers[["X-Trino-Session"]] <- property
    return(headers)
  }
  if (grepl(paste0("(^|,)\\s*", name, "\\s*="), headers[[at]])) {
    stop(
      sprintf(
        "`%s` is also set in the X-Trino-Session header; set it only once.",
        name
      ),
      call. = FALSE
    )
  }
  headers[[at]] <- paste(headers[[at]], property, sep = ",")
  headers
}
