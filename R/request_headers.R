#' Trino protocol headers
#'
#' Builds the `X-Trino-*` headers required by the REST API. Headers from
#' `conn@extra.headers` and from `extra` are merged last, in that order, so a
#' caller can deliberately override a protocol header.
#'
#' `X-Trino-Client-Capabilities: PARAMETRIC_DATETIME` tells Trino the client
#' reads date-time types of any precision. Without it Trino treats the client
#' as a legacy one and rounds every `TIMESTAMP` and `TIME` to milliseconds.
#'
#' `X-Trino-Transaction-Id` is always present, `"NONE"` outside a
#' transaction: Trino takes the header's mere presence, on every request
#' since the connection's first, as the client's declaration that it
#' understands the transaction protocol and will carry the id it is given
#' back on later requests. A client that only adds the header once it
#' starts a transaction has never made that declaration, and
#' [dbBegin()][dbBegin,TrinoConnection-method] gets `INCOMPATIBLE_CLIENT`
#' instead of a transaction id.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param extra Named list of additional headers.
#' @return A named list of headers.
#' @noRd
trino_headers <- function(conn, extra = list()) {
  headers <- list(
    "X-Trino-User" = conn@user,
    "X-Trino-Catalog" = conn@catalog,
    "X-Trino-Schema" = conn@schema,
    "X-Trino-Source" = conn@source,
    "X-Trino-Time-Zone" = conn@session.timezone,
    "X-Trino-Language" = "en-US",
    "X-Trino-Client-Capabilities" = "PARAMETRIC_DATETIME",
    "X-Trino-Transaction-Id" = conn@transaction$id %||% "NONE",
    "Accept" = "application/json"
  )

  for (set in list(conn@extra.headers, extra)) {
    if (length(set) == 0L) {
      next
    }
    if (is.null(names(set)) || !all(nzchar(names(set)))) {
      stop("All extra headers must be named.", call. = FALSE)
    }
    headers[names(set)] <- set
  }

  headers
}
