#' Is this connection or result still usable?
#'
#' A connection is valid until [dbDisconnect()] is called. A result is valid
#' until it is cleared by [dbClearResult()] - a result whose rows have all been
#' fetched is still valid, so that [dbColumnInfo()] and friends keep working.
#'
#' @param dbObj A [TrinoConnection-class] or [TrinoResult-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @return A logical scalar.
#' @export
setMethod("dbIsValid", "TrinoConnection", function(dbObj, ...) {
  isTRUE(dbObj@valid$open)
})

#' @rdname dbIsValid-TrinoConnection-method
#' @export
setMethod("dbIsValid", "TrinoResult", function(dbObj, ...) {
  !isTRUE(dbObj@state$cleared)
})
