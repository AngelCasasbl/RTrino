#' Create a table
#'
#' Trino has no temporary tables, so `temporary = TRUE` is an error rather
#' than being silently ignored.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, in any form [dbExistsTable()] accepts.
#' @param fields Either a named character vector of Trino types, one per
#'   column, or a data frame whose columns' R types are mapped to Trino
#'   types with [dbDataType()].
#' @param ... Unused, for compatibility with the generic.
#' @param row.names Unused: RTrino never writes row names as a column.
#' @param temporary Must be `FALSE`.
#' @return `TRUE`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbCreateTable(con, "sales", c(id = "bigint", label = "varchar"))
#' DBI::dbCreateTable(con, "sales", data.frame(id = 1L, label = "a"))
#' }
setMethod(
  "dbCreateTable", "TrinoConnection",
  function(conn, name, fields, ..., row.names = NULL, temporary = FALSE) {
    if (!identical(temporary, FALSE)) {
      stop("Temporary tables not supported by RTrino.", call. = FALSE)
    }
    if (is.data.frame(fields)) {
      fields <- trino_data_type(fields)
    }
    if (
      !is.character(fields) || is.null(names(fields)) ||
        !all(nzchar(names(fields))) || anyDuplicated(names(fields))
    ) {
      stop(
        "`fields` must be a named character vector or a data frame.",
        call. = FALSE
      )
    }

    columns <- paste(
      dbQuoteIdentifier(conn, names(fields)), unname(fields)
    )
    dbExecute(conn, paste0(
      "CREATE TABLE ", trino_qualify(conn, name),
      " (", paste(columns, collapse = ", "), ")"
    ))
    invisible(TRUE)
  }
)
