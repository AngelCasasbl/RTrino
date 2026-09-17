#' List a table's columns
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name. An unqualified name is resolved against the
#'   connection's catalog and schema.
#' @param ... Unused, for compatibility with the generic.
#' @return A character vector of column names.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbListFields(con, "sales")
#' }
setMethod(
  "dbListFields", c("TrinoConnection", "character"),
  function(conn, name, ...) {
    trino_check_valid(conn)
    name <- trino_check_string(name, "name")
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

#' Qualify a table name with the connection's catalog and schema
#'
#' A name that already contains dots is assumed to be qualified and is quoted
#' part by part.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name.
#' @return A quoted, fully qualified identifier as a string.
#' @noRd
trino_qualify <- function(conn, name) {
  parts <- strsplit(name, ".", fixed = TRUE)[[1L]]
  if (length(parts) == 1L) {
    parts <- c(conn@catalog, conn@schema, parts)
  }
  paste(
    vapply(parts, function(p) {
      as.character(dbQuoteIdentifier(conn, p))
    }, character(1L)),
    collapse = "."
  )
}
