#' Trino connection class
#'
#' An S4 class representing a connection to a Trino cluster. Trino's REST API
#' is stateless, so the object only holds the information needed to build
#' requests; no socket is kept open.
#'
#' @slot host Base URL of the coordinator, including the scheme.
#' @slot port Coordinator port.
#' @slot user Trino user name.
#' @slot catalog Trino catalog.
#' @slot schema Trino schema.
#' @slot session.timezone Session time zone used for timestamp columns.
#' @slot bigint How `BIGINT` columns are returned; see [dbConnect()].
#' @slot extra.headers Named list of additional HTTP headers.
#' @slot source Value of the `X-Trino-Source` header.
#' @slot auth Authentication closure, or `NULL` for no authentication.
#' @slot ssl_options SSL options as returned by [trino_ssl()].
#' @slot valid Environment holding the connection's validity flag.
#'
#' @keywords internal
#' @export
setClass(
  "TrinoConnection",
  contains = "DBIConnection",
  slots = c(
    host = "character",
    port = "integer",
    user = "character",
    catalog = "character",
    schema = "character",
    session.timezone = "character",
    bigint = "character",
    extra.headers = "list",
    source = "character",
    auth = "ANY",
    ssl_options = "list",
    valid = "environment"
  )
)

#' @rdname TrinoConnection-class
#' @param object A [TrinoConnection-class] object.
#' @export
setMethod("show", "TrinoConnection", function(object) {
  cat("<TrinoConnection>\n")
  cat("  ", trino_base_url(object), "\n", sep = "")
  cat("  catalog: ", object@catalog, "  schema: ", object@schema, "\n", sep = "")
  cat("  user: ", object@user, "\n", sep = "")
  if (!dbIsValid(object)) {
    cat("  DISCONNECTED\n")
  }
  invisible(NULL)
})
