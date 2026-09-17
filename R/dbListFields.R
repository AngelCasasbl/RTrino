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

#' Split a table name into catalog, schema and table
#'
#' An unqualified name resolves against the connection's catalog and schema; a
#' `schema.table` name keeps the connection's catalog; a `catalog.schema.table`
#' name is used as given. Shared by every method that has to address a table,
#' so they all resolve a name the same way.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, with one, two or three dot-separated parts.
#' @return A character vector of length three.
#' @noRd
trino_name_parts <- function(conn, name) {
  parts <- strsplit(name, ".", fixed = TRUE)[[1L]]
  switch(
    as.character(length(parts)),
    "1" = c(conn@catalog, conn@schema, parts),
    "2" = c(conn@catalog, parts),
    "3" = parts,
    stop(
      sprintf(
        "`name` must have at most three parts, got %d: %s",
        length(parts), name
      ),
      call. = FALSE
    )
  )
}

#' Qualify a table name with the connection's catalog and schema
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name.
#' @return A quoted, fully qualified identifier as a string.
#' @noRd
trino_qualify <- function(conn, name) {
  paste(
    vapply(trino_name_parts(conn, name), function(p) {
      as.character(dbQuoteIdentifier(conn, p))
    }, character(1L)),
    collapse = "."
  )
}
