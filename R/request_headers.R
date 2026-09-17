#' Trino protocol headers
#'
#' Builds the `X-Trino-*` headers required by the REST API. Headers from
#' `conn@extra.headers` and from `extra` are merged last, in that order, so a
#' caller can deliberately override a protocol header.
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
