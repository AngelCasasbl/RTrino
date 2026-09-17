#' Quote identifiers and strings for Trino
#'
#' Trino follows the SQL standard: identifiers are wrapped in double quotes
#' with embedded double quotes doubled, and string literals are wrapped in
#' single quotes with embedded single quotes doubled.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param x A character vector, or an identifier for `dbQuoteIdentifier()`.
#' @param ... Unused, for compatibility with the generic.
#' @return A [DBI::SQL] object.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbQuoteIdentifier(con, "my column")
#' DBI::dbQuoteString(con, "O'Brien")
#' }
setMethod(
  "dbQuoteIdentifier", c("TrinoConnection", "character"),
  function(conn, x, ...) {
    if (any(is.na(x))) {
      stop("Cannot quote NA as an identifier.", call. = FALSE)
    }
    DBI::SQL(paste0('"', gsub('"', '""', x, fixed = TRUE), '"'), names = names(x))
  }
)

#' @rdname dbQuoteIdentifier-TrinoConnection-character-method
#' @export
setMethod(
  "dbQuoteString", c("TrinoConnection", "character"),
  function(conn, x, ...) {
    out <- paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
    out[is.na(x)] <- "NULL"
    DBI::SQL(out)
  }
)
