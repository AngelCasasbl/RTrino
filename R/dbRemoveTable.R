#' Drop a table
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, in any form [dbExistsTable()] accepts.
#' @param ... Unused, for compatibility with the generic.
#' @return `TRUE`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbRemoveTable(con, "sales")
#' }
setMethod(
  "dbRemoveTable", c("TrinoConnection", "character"),
  function(conn, name, ...) {
    dbExecute(conn, paste("DROP TABLE", trino_qualify(conn, name)))
    invisible(TRUE)
  }
)

#' @rdname dbRemoveTable-TrinoConnection-character-method
#' @export
setMethod(
  "dbRemoveTable", c("TrinoConnection", "Id"),
  function(conn, name, ...) {
    dbRemoveTable(conn, DBI::SQL(trino_qualify(conn, name)), ...)
  }
)

#' @rdname dbRemoveTable-TrinoConnection-character-method
#' @export
setMethod(
  "dbRemoveTable", c("TrinoConnection", "ANY"),
  function(conn, name, ...) trino_bad_table_name(name, "the table to drop")
)
