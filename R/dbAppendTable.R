#' Insert rows into an existing table
#'
#' Builds one `INSERT INTO ... VALUES (...)` statement per batch of rows,
#' with values quoted as literals by [DBI::sqlAppendTable()] (which calls
#' [dbQuoteIdentifier()] and [dbQuoteLiteral()] for Trino) — there is no
#' parameter binding to fall back on.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, in any form [dbExistsTable()] accepts.
#' @param value A data frame with the rows to insert.
#' @param ... Takes `chunk_size`: how many rows go into a single `INSERT`
#'   statement, 1000 by default. Every row is written into the statement as
#'   a literal, so a data frame much larger than this is split into several
#'   statements rather than one that may exceed the coordinator's query
#'   length limit.
#' @param row.names Unused: RTrino never writes row names as a column.
#' @return The number of rows inserted.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "memory", schema = "default")
#' DBI::dbCreateTable(con, "sales", c(id = "integer", label = "varchar"))
#' DBI::dbAppendTable(con, "sales", data.frame(id = 1:3, label = letters[1:3]))
#' DBI::dbGetQuery(con, "SELECT * FROM sales ORDER BY id")
#' DBI::dbRemoveTable(con, "sales")
#' DBI::dbDisconnect(con)
setMethod(
  "dbAppendTable", "TrinoConnection",
  function(conn, name, value, ..., row.names = NULL) {
    chunk_size <- list(...)$chunk_size
    if (is.null(chunk_size)) chunk_size <- 1000L
    stopifnot(is.data.frame(value))
    name <- DBI::SQL(trino_qualify(conn, name))
    is_factor <- vapply(value, is.factor, logical(1L))
    if (any(is_factor)) {
      value[is_factor] <- lapply(value[is_factor], as.character)
    }

    total_rows <- 0L
    n <- nrow(value)
    if (n == 0L) {
      return(total_rows)
    }
    starts <- seq.int(1L, n, by = chunk_size)
    for (start in starts) {
      rows <- start:min(start + chunk_size - 1L, n)
      sql <- DBI::sqlAppendTable(conn, name, value[rows, , drop = FALSE],
        row.names = row.names
      )
      total_rows <- total_rows + dbExecute(conn, sql)
    }
    total_rows
  }
)
