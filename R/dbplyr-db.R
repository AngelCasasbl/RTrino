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

#' `copy_to()` for Trino
#'
#' Overrides dbplyr's default, which wraps the write in a transaction;
#' RTrino has none ([dbBegin()][RTrino-unsupported]), so the write goes
#' straight to [dbWriteTable()]. `temporary` defaults to `TRUE`, as in the
#' generic, which means the call fails unless the caller passes
#' `temporary = FALSE`: Trino has no temporary tables.
#'
#' @param con A [TrinoConnection-class] object.
#' @param table,values,overwrite,types,temporary Passed to [dbWriteTable()].
#' @param unique_indexes,indexes,analyze,in_transaction,... Unused, for
#'   compatibility with the generic.
#' @return `table`.
#' @keywords internal
#' @exportS3Method NULL
db_copy_to.TrinoConnection <- function(con, table, values, ...,
                                       overwrite = FALSE, types = NULL,
                                       temporary = TRUE,
                                       unique_indexes = NULL, indexes = NULL,
                                       analyze = TRUE, in_transaction = TRUE) {
  # dbplyr hands `table` over as a dbplyr_table_path, already rendered into
  # a quoted identifier string; wrapping it as SQL tells trino_table_parts()
  # not to quote it a second time.
  dbWriteTable(
    con, DBI::SQL(as.character(table)), values,
    field.types = types, temporary = temporary, overwrite = overwrite
  )
  table
}
