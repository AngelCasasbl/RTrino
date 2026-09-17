#' Does a table exist?
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, as a string or an identifier.
#' @param ... Unused, for compatibility with the generic.
#' @return A logical scalar.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbExistsTable(con, "sales")
#' }
setMethod(
  "dbExistsTable", c("TrinoConnection", "character"),
  function(conn, name, ...) {
    trino_check_valid(conn)
    name <- trino_check_string(name, "name")
    # SHOW TABLES LIKE would need Trino's pattern escaping; an exact match
    # against the schema listing is both simpler and correct.
    name %in% dbListTables(conn)
  }
)
