#' Submit a statement to Trino
#'
#' Posts the statement to `/v1/statement` and returns immediately with a
#' [TrinoResult-class] cursor; the rows are pulled by [dbFetch()]. A statement
#' that fails during planning raises an error here, because Trino reports it in
#' the response to the initial `POST`.
#'
#' Query parameters are not supported: passing `params` is an error rather
#' than being silently ignored. Put values into the statement with
#' [DBI::sqlInterpolate()] or `glue::glue_sql()`, which quote them with
#' [DBI::dbQuoteLiteral()] as Trino literals.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param statement A single SQL statement, without a trailing semicolon.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A [TrinoResult-class] object.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#' res <- DBI::dbSendQuery(con, "SELECT 1 AS n")
#' DBI::dbFetch(res)
#' DBI::dbClearResult(res)
#'
#' # Values go into the SQL as literals, quoted for Trino
#' sql <- DBI::sqlInterpolate(
#'   con, "SELECT count(*) AS n FROM orders WHERE orderdate >= ?since",
#'   since = as.Date("1998-01-01")
#' )
#' DBI::dbGetQuery(con, sql)
#'
#' DBI::dbDisconnect(con)
setMethod(
  "dbSendQuery", c("TrinoConnection", "character"),
  function(conn, statement, ...) {
    trino_check_valid(conn)
    statement <- trino_check_string(statement, "statement")
    trino_check_no_params(...)

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

#' Submit a statement that changes something
#'
#' Unlike [dbSendQuery()][dbSendQuery,TrinoConnection,character-method], runs
#' the statement to completion before returning, so that
#' [dbGetRowsAffected()] answers straight away, as DBI requires: Trino only
#' reports the count once the statement has finished.
#'
#' @inheritParams dbSendQuery,TrinoConnection,character-method
#' @return A [TrinoResult-class] object whose statement has finished.
#' @export
setMethod(
  "dbSendStatement", c("TrinoConnection", "character"),
  function(conn, statement, ...) {
    res <- dbSendQuery(conn, statement, ...)
    # An interrupt or a failure while waiting must not leave the statement
    # running on the cluster with nobody holding its result.
    finished <- FALSE
    on.exit(if (!finished) try(dbClearResult(res), silent = TRUE), add = TRUE)
    trino_drain(res, -1L)
    finished <- TRUE
    res
  }
)

#' Execute a statement that returns no rows
#'
#' Runs the statement to completion and reports how many rows Trino says it
#' changed: the count of an `INSERT`, an `UPDATE`, a `DELETE`, a `MERGE` or a
#' `CREATE TABLE ... AS SELECT`, and `0` for a statement that changes no rows,
#' such as `CREATE TABLE` or `DROP TABLE`.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param statement A single SQL statement.
#' @param ... Unused, for compatibility with the generic.
#' @return The number of affected rows, invisibly: a double, or `NA` for a data
#'   change whose count Trino did not report.
#' @export
setMethod(
  "dbExecute", c("TrinoConnection", "character"),
  function(conn, statement, ...) {
    res <- dbSendStatement(conn, statement, ...)
    on.exit(dbClearResult(res), add = TRUE)
    invisible(dbGetRowsAffected(res))
  }
)

#' Parameters are not supported
#'
#' Trino's client protocol has no parameter binding of its own, so rather than
#' ignoring the values, `dbBind()` fails.
#'
#' @param res A [TrinoResult-class] object.
#' @param params Unused.
#' @param ... Unused.
#' @return Never returns.
#' @export
setMethod("dbBind", "TrinoResult", function(res, params, ...) {
  trino_abort_params()
})

#' Fail if a caller passed query parameters
#'
#' @param ... The dots of a query method.
#' @return `NULL`, invisibly.
#' @noRd
trino_check_no_params <- function(...) {
  if (!is.null(list(...)$params)) {
    trino_abort_params()
  }
  invisible()
}

#' @noRd
trino_abort_params <- function() {
  stop(
    "RTrino does not support parameterised queries, so `params` cannot be ",
    "used. Put the values into the statement with DBI::sqlInterpolate() or ",
    "glue::glue_sql(), which quote them as Trino literals.",
    call. = FALSE
  )
}
