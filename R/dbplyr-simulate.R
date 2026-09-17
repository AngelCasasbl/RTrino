#' A Trino connection that never talks to a server
#'
#' Returns an object that carries the `TrinoConnection` class without holding a
#' session, so [sql_dialect.TrinoConnection()] and, through it,
#' [sql_translation.sql_dialect_trino()] dispatch as they would on a live
#' connection. Useful for inspecting the SQL a `dplyr` pipeline produces, and
#' used by this package's own translation tests, which then need no coordinator
#' at all. Anything that reaches the database, such as `collect()`, still fails.
#'
#' @return A simulated `dbplyr` connection of class `TrinoConnection`.
#' @keywords internal
#' @export
#' @examples
#' if (requireNamespace("dbplyr", quietly = TRUE)) {
#'   con <- simulate_trino()
#'   dbplyr::translate_sql(as.numeric(x), con = con)
#' }
simulate_trino <- function() {
  # dbplyr is a soft dependency, so the check has to happen at call time.
  rlang::check_installed("dbplyr", version = "2.6.0")
  dbplyr::simulate_dbi("TrinoConnection")
}
