#' Run a query and return all of its rows
#'
#' Submits the statement, fetches every row and clears the result, even if
#' fetching fails.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param statement A single SQL statement.
#' @param n Number of rows to return; `-1` (the default) returns all of them.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A [tibble][tibble::tibble].
#' @export
#' @examples
#' \dontrun{
#' DBI::dbGetQuery(con, "SELECT * FROM sales LIMIT 100")
#' }
setMethod(
  "dbGetQuery", c("TrinoConnection", "character"),
  function(conn, statement, n = -1, ...) {
    res <- dbSendQuery(conn, statement, ...)
    on.exit(dbClearResult(res), add = TRUE)
    dbFetch(res, n = n)
  }
)
