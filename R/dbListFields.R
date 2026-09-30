#' List a table's columns
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, required, in any form
#'   [dbExistsTable()][dbExistsTable,TrinoConnection,character-method] accepts:
#'   a string with one to three dot-separated parts, a [DBI::Id()] or a quoted
#'   identifier from [DBI::SQL()]. An unqualified name is resolved against the
#'   connection's catalog and schema.
#' @param ... Unused, for compatibility with the generic.
#' @return A character vector of column names.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbListFields(con, "sales")
#' DBI::dbListFields(con, DBI::Id(schema = "analytics", table = "sales"))
#' }
setMethod(
  "dbListFields", c("TrinoConnection", "character"),
  function(conn, name, ...) {
    trino_check_valid(conn)
    out <- dbGetQuery(
      conn,
      paste0("DESCRIBE ", trino_qualify(conn, name))
    )
    if (nrow(out) == 0L) {
      return(character())
    }
    # DESCRIBE returns Column/Type/Extra/Comment; take the first column by
    # position so a server that renames the header still works.
    column <- if ("Column" %in% names(out)) out[["Column"]] else out[[1L]]
    as.character(column)
  }
)

#' @rdname dbListFields-TrinoConnection-character-method
#' @export
setMethod(
  "dbListFields", c("TrinoConnection", "Id"),
  function(conn, name, ...) {
    dbListFields(conn, DBI::SQL(trino_qualify(conn, name)), ...)
  }
)

#' @rdname dbListFields-TrinoConnection-character-method
#' @export
setMethod(
  "dbListFields", c("TrinoConnection", "ANY"),
  function(conn, name, ...) trino_bad_table_name(name, "the table to describe")
)
