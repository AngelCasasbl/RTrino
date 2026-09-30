#' What RTrino does not do
#'
#' RTrino reads from Trino; it does not upload data frames, and it does not
#' manage transactions. These methods exist so that the attempt fails with a
#' message that says so, rather than with an error from deep inside DBI.
#'
#' * `dbWriteTable()`, `dbAppendTable()` and `dbCreateTable()`: create and fill
#'   tables with SQL run through
#'   [dbExecute()][dbExecute,TrinoConnection,character-method], such as
#'   `CREATE TABLE ... AS SELECT ...` or `INSERT INTO ... SELECT ...`. Values
#'   from R can be put into such a statement with [DBI::sqlInterpolate()].
#' * `dbBegin()`, `dbCommit()` and `dbRollback()`: every statement runs in a
#'   transaction of its own, committed when it finishes.
#'
#' For the same reason `dplyr::copy_to()` is not supported, and
#' `dplyr::compute()` needs `temporary = FALSE`, as Trino has no temporary
#' tables.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name,value,fields,temporary,row.names Unused.
#' @param ... Unused.
#' @return Never returns.
#' @name RTrino-unsupported
#' @keywords internal
NULL

#' @noRd
trino_abort_upload <- function(what) {
  stop(
    what, " is not supported: RTrino does not upload data from R. Create ",
    "and fill tables with SQL through dbExecute(), such as ",
    "CREATE TABLE ... AS SELECT ... or INSERT INTO ... SELECT ....",
    call. = FALSE
  )
}

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
setMethod(
  "dbWriteTable", c("TrinoConnection", "ANY"),
  function(conn, name, value, ...) trino_abort_upload("dbWriteTable()")
)

#' @rdname RTrino-unsupported
#' @export
setMethod(
  "dbWriteTable", c("TrinoConnection", "Id"),
  function(conn, name, value, ...) trino_abort_upload("dbWriteTable()")
)

#' @rdname RTrino-unsupported
#' @export
setMethod(
  "dbAppendTable", "TrinoConnection",
  function(conn, name, value, ..., row.names = NULL) {
    trino_abort_upload("dbAppendTable()")
  }
)

#' @rdname RTrino-unsupported
#' @export
setMethod(
  "dbCreateTable", "TrinoConnection",
  function(conn, name, fields, ..., row.names = NULL, temporary = FALSE) {
    trino_abort_upload("dbCreateTable()")
  }
)

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
