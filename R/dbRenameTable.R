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
#' @examples
#' \dontrun{
#' dbRenameTable(con, "sales", "sales_old")
#' }
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
