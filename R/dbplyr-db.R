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
#' @export
sql_query_explain.sql_dialect_trino <- function(con, sql, ...) {
  dbplyr::sql_glue2(con, "EXPLAIN {.sql sql}")
}
