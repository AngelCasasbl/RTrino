#' Disconnect from Trino
#'
#' Marks the connection as closed. Trino's REST API is stateless, so nothing is
#' sent to the server; any later use of `conn` raises an error.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @return `TRUE`, invisibly.
#' @export
setMethod("dbDisconnect", "TrinoConnection", function(conn, ...) {
  if (!dbIsValid(conn)) {
    warning("Connection already closed.", call. = FALSE)
    return(invisible(TRUE))
  }
  conn@valid$open <- FALSE
  invisible(TRUE)
})
