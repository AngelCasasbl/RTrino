#' List the tables in the connection's schema
#'
#' @param conn A [TrinoConnection-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @return A character vector of table names.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#' DBI::dbListTables(con)
#' DBI::dbDisconnect(con)
setMethod("dbListTables", "TrinoConnection", function(conn, ...) {
  trino_check_valid(conn)
  sql <- paste0(
    "SHOW TABLES FROM ",
    dbQuoteIdentifier(conn, conn@catalog), ".",
    dbQuoteIdentifier(conn, conn@schema)
  )
  out <- dbGetQuery(conn, sql)
  if (nrow(out) == 0L) character() else as.character(out[[1L]])
})
