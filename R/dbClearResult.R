#' Release a Trino result
#'
#' Frees the buffered rows and marks the cursor cleared. If the query is still
#' running on the server, a `DELETE` is sent to its `nextUri` so the
#' coordinator stops working on it instead of letting it run to completion for
#' nobody.
#'
#' @param res A [TrinoResult-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @return `TRUE`, invisibly.
#' @export
setMethod("dbClearResult", "TrinoResult", function(res, ...) {
  state <- res@state
  if (isTRUE(state$cleared)) {
    warning("Result already cleared.", call. = FALSE)
    return(invisible(TRUE))
  }

  if (!is.null(state$next_uri) && dbIsValid(res@connection)) {
    # Best effort: the query may have finished between the last page and now,
    # in which case the coordinator has already forgotten the URI.
    try(
      trino_perform(res@connection, state$next_uri, "DELETE"),
      silent = TRUE
    )
  }

  state$next_uri <- NULL
  state$data <- list()
  state$completed <- TRUE
  state$cleared <- TRUE
  invisible(TRUE)
})
