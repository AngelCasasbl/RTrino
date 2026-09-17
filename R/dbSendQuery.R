#' Submit a statement to Trino
#'
#' Posts the statement to `/v1/statement` and returns immediately with a
#' [TrinoResult-class] cursor; the rows are pulled by [dbFetch()]. A statement
#' that fails during planning raises an error here, because Trino reports it in
#' the response to the initial `POST`.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param statement A single SQL statement, without a trailing semicolon.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A [TrinoResult-class] object.
#' @export
#' @examples
#' \dontrun{
#' res <- DBI::dbSendQuery(con, "SELECT 1 AS n")
#' DBI::dbFetch(res)
#' DBI::dbClearResult(res)
#' }
setMethod(
  "dbSendQuery", c("TrinoConnection", "character"),
  function(conn, statement, ...) {
    trino_check_valid(conn)
    statement <- trino_check_string(statement, "statement")

    resp <- trino_perform(
      conn,
      trino_url(conn, "/v1/statement"),
      "POST",
      body = statement
    )

    res <- new(
      "TrinoResult",
      connection = conn,
      statement = statement,
      state = trino_result_state()
    )
    trino_absorb_payload(res@state, trino_parse_response(resp))
    res
  }
)

#' Execute a statement that returns no rows
#'
#' Runs the statement to completion and reports how many rows Trino says it
#' touched. Trino does not report an affected-row count for every statement, so
#' the answer can be `NA`.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param statement A single SQL statement.
#' @param ... Unused, for compatibility with the generic.
#' @return The number of affected rows, invisibly, or `NA`.
#' @export
setMethod(
  "dbExecute", c("TrinoConnection", "character"),
  function(conn, statement, ...) {
    res <- dbSendQuery(conn, statement, ...)
    on.exit(dbClearResult(res), add = TRUE)
    trino_drain(res, -1L)
    invisible(dbGetRowsAffected(res))
  }
)
