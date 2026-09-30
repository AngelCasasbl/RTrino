#' Explain a Trino query
#'
#' Trino's `EXPLAIN` takes the statement directly, without the parenthesised
#' options some engines require.
#'
#' Column discovery (`sql_query_fields()`) is deliberately left to dbplyr's
#' default, which wraps the query in `WHERE 0 = 1`. On Trino that plans without
#' reading any data, exactly like the `LIMIT 0` the specification suggests, and
#' the default is built from dbplyr internals that a backend should not reach
#' into.
#'
#' @param con A Trino SQL dialect object.
#' @param sql A query.
#' @param ... Unused, for compatibility with the generic.
#' @return The `EXPLAIN` statement, as SQL.
#' @keywords internal
#' @exportS3Method NULL
sql_query_explain.sql_dialect_trino <- function(con, sql, ...) {
  dbplyr::sql_glue2(con, "EXPLAIN {.sql sql}")
}

#' `copy_to()` is not supported
#'
#' RTrino does not upload data from R; see [RTrino-unsupported].
#'
#' @param con A [TrinoConnection-class] object.
#' @param table,values,overwrite,types,temporary Unused.
#' @param unique_indexes,indexes,analyze,in_transaction,... Unused.
#' @return Never returns.
#' @keywords internal
#' @exportS3Method NULL
db_copy_to.TrinoConnection <- function(con, table, values, ...,
                                       overwrite = FALSE, types = NULL,
                                       temporary = TRUE,
                                       unique_indexes = NULL, indexes = NULL,
                                       analyze = TRUE, in_transaction = TRUE) {
  trino_abort_upload("copy_to()")
}
