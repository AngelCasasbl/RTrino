#' Rename a table
#'
#' Not a DBI generic: DBI has no `dbRenameTable()`, so RTrino defines its
#' own, the way RPresto does for Presto.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Current table name, in any form [dbExistsTable()] accepts.
#' @param new_name New table name, in the same forms.
#' @param ... Unused, for compatibility with the generic.
#' @return `TRUE`, invisibly.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "memory", schema = "default")
#' DBI::dbWriteTable(con, "sales", data.frame(id = 1:3))
#' dbRenameTable(con, "sales", "sales_old")
#' DBI::dbExistsTable(con, "sales_old")
#' DBI::dbRemoveTable(con, "sales_old")
#' DBI::dbDisconnect(con)
setGeneric(
  "dbRenameTable",
  function(conn, name, new_name, ...) standardGeneric("dbRenameTable")
)

#' @rdname dbRenameTable
#' @export
setMethod(
  "dbRenameTable", c("TrinoConnection", "ANY", "ANY"),
  function(conn, name, new_name, ...) {
    dbExecute(conn, paste(
      "ALTER TABLE", trino_qualify(conn, name),
      "RENAME TO", trino_qualify(conn, new_name)
    ))
    invisible(TRUE)
  }
)
