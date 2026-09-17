#' Have all rows of a result been consumed?
#'
#' `TRUE` once Trino has stopped handing out pages *and* the rows already
#' pulled have been handed to the caller. A result that has finished on the
#' server but still holds buffered rows is not complete, so a
#' `while (!dbHasCompleted(res))` loop over [dbFetch()] sees every row.
#'
#' @param res A [TrinoResult-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @return A logical scalar.
#' @export
setMethod("dbHasCompleted", "TrinoResult", function(res, ...) {
  isTRUE(res@state$completed) && length(res@state$data) == 0L
})
