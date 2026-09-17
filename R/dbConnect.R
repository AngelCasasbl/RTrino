#' Connect to a Trino cluster
#'
#' Creates a [TrinoConnection-class]. Trino's REST API is stateless, so no
#' session is opened on the server; the connection object holds the coordinator
#' address and the per-request settings. To fail early on a wrong address or
#' bad credentials, `dbConnect()` probes `GET /v1/info` before returning.
#'
#' @param drv A [TrinoDriver-class] object, from [Trino()].
#' @param host Coordinator URL. A missing scheme defaults to `http://`; a
#'   trailing slash is dropped.
#' @param port Coordinator port.
#' @param user Trino user name, sent as `X-Trino-User`.
#' @param catalog Trino catalog. Required.
#' @param schema Trino schema. Required.
#' @param source Value of the `X-Trino-Source` header; shows up in the
#'   coordinator's query history.
#' @param session.timezone Session time zone, used when reading `TIMESTAMP`
#'   columns.
#' @param bigint How to return `BIGINT` columns: `"integer64"` (the default,
#'   via `bit64`, exact), `"numeric"` (a double, exact only up to 2^53) or
#'   `"character"`.
#' @param auth An authentication closure from [trino_auth_basic()],
#'   [trino_auth_jwt()] or [trino_auth_oauth2()], or `NULL` for a cluster with
#'   no authentication.
#' @param ssl_options TLS options from [trino_ssl()].
#' @param extra.headers Named list of extra HTTP headers added to every
#'   request. Useful for Trino session properties set through
#'   `X-Trino-Session`.
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
#' # LDAP over TLS
#' con <- DBI::dbConnect(
#'   RTrino::Trino(),
#'   host    = "https://trino.example.com",
#'   port    = 443,
#'   user    = Sys.getenv("TRINO_USER"),
#'   catalog = "hive",
#'   schema  = "analytics",
#'   auth    = trino_auth_basic(Sys.getenv("TRINO_USER"),
#'                              Sys.getenv("TRINO_PASSWORD"))
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
                                               ...) {
  host <- trino_normalize_host(host)

  if (is.null(catalog) || is.null(schema) ||
        !nzchar(catalog %||% "") || !nzchar(schema %||% "")) {
    stop("catalog and schema are required", call. = FALSE)
  }
  catalog <- trino_check_string(catalog, "catalog")
  schema <- trino_check_string(schema, "schema")
  user <- trino_check_string(user, "user")
  source <- trino_check_string(source, "source")
  session.timezone <- trino_check_string(session.timezone, "session.timezone")

  if (!is.null(auth) && !is.function(auth)) {
    stop("auth must be a function or NULL", call. = FALSE)
  }
  if (!is.list(ssl_options) ||
        !all(c("verify", "ca_bundle") %in% names(ssl_options))) {
    stop("`ssl_options` must be the result of `trino_ssl()`.", call. = FALSE)
  }
  if (!is.list(extra.headers)) {
    stop("`extra.headers` must be a named list.", call. = FALSE)
  }

  port <- suppressWarnings(as.integer(port))
  if (length(port) != 1L || is.na(port) || port <= 0L) {
    stop("`port` must be a positive integer.", call. = FALSE)
  }

  bigint <- match.arg(bigint)

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
    valid = valid
  )

  # Fail here rather than on the user's first query.
  tryCatch(
    trino_perform(conn, trino_url(conn, "/v1/info"), "GET"),
    error = function(e) {
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
