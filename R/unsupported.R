#' What RTrino does not do
#'
#' RTrino does not manage transactions: every statement runs and is
#' committed on its own, so `dbBegin()`, `dbCommit()` and `dbRollback()` fail
#' with a message that says so, rather than with an error from deep inside
#' DBI.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param ... Unused.
#' @return Never returns.
#' @name RTrino-unsupported
#' @keywords internal
NULL

#' @noRd
trino_abort_transaction <- function(what) {
  stop(
    what, " is not supported: RTrino does not manage transactions, and ",
    "every statement is committed when it finishes.",
    call. = FALSE
  )
}

#' @rdname RTrino-unsupported
#' @export
setMethod("dbBegin", "TrinoConnection", function(conn, ...) {
  trino_abort_transaction("dbBegin()")
})

#' @rdname RTrino-unsupported
#' @export
setMethod("dbCommit", "TrinoConnection", function(conn, ...) {
  trino_abort_transaction("dbCommit()")
})

#' @rdname RTrino-unsupported
#' @export
setMethod("dbRollback", "TrinoConnection", function(conn, ...) {
  trino_abort_transaction("dbRollback()")
})
