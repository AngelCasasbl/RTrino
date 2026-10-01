#' Write a table
#'
#' Creates the table with [dbCreateTable()] and fills it with
#' [dbAppendTable()]. `CREATE TABLE` cannot be undone by [dbRollback()] on
#' most connectors, so `overwrite = TRUE` plays it safe on its own: it
#' renames the existing table rather than dropping it, and restores it if
#' anything fails before the new table is fully written.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, in any form [dbExistsTable()] accepts.
#' @param value A data frame to write.
#' @param ... Unused, for compatibility with the generic.
#' @param overwrite Drop and recreate the table if it already exists.
#' @param append Add to the table if it already exists, instead of creating
#'   it.
#' @param field.types A named character vector of Trino types, overriding
#'   the types [dbDataType()] would otherwise infer. Not allowed together
#'   with `append`.
#' @param temporary Must be `FALSE`: Trino has no temporary tables.
#' @param row.names Unused: RTrino never writes row names as a column.
#' @param chunk_size Passed to [dbAppendTable()].
#' @return `TRUE`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbWriteTable(con, "sales", data.frame(id = 1:3, label = letters[1:3]))
#' DBI::dbWriteTable(con, "sales", more_sales, append = TRUE)
#' DBI::dbWriteTable(con, "sales", new_sales, overwrite = TRUE)
#' }
setMethod(
  "dbWriteTable", c("TrinoConnection", "ANY"),
  function(conn, name, value, ..., overwrite = FALSE, append = FALSE,
           field.types = NULL, temporary = FALSE, row.names = NULL,
           chunk_size = 1000L) {
    trino_write_table(
      conn, name, value,
      overwrite = overwrite, append = append, field.types = field.types,
      temporary = temporary, row.names = row.names, chunk_size = chunk_size
    )
  }
)

#' @rdname dbWriteTable-TrinoConnection-ANY-method
#' @export
setMethod(
  "dbWriteTable", c("TrinoConnection", "Id"),
  function(conn, name, value, ...) {
    dbWriteTable(conn, DBI::SQL(trino_qualify(conn, name)), value, ...)
  }
)

#' @noRd
trino_write_table <- function(conn, name, value, ..., overwrite, append,
                               field.types, temporary, row.names,
                               chunk_size) {
  stopifnot(is.data.frame(value))
  if (!identical(temporary, FALSE)) {
    stop("Temporary tables not supported by RTrino.", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("overwrite must be a logical scalar.", call. = FALSE)
  }
  if (!is.logical(append) || length(append) != 1L || is.na(append)) {
    stop("append must be a logical scalar.", call. = FALSE)
  }
  if (overwrite && append) {
    stop("overwrite and append cannot both be TRUE.", call. = FALSE)
  }
  if (append && !is.null(field.types)) {
    stop("Cannot specify field.types with append = TRUE.", call. = FALSE)
  }

  found <- dbExistsTable(conn, name)
  if (found && !overwrite && !append) {
    stop(
      "Table ", trino_qualify(conn, name),
      " exists in database, and both overwrite and append are FALSE.",
      call. = FALSE
    )
  }

  rn <- paste0(
    "rtrino_rename_", paste(sample(letters, 10L, replace = TRUE), collapse = "")
  )
  renamed <- FALSE
  if (found && overwrite) {
    dbRenameTable(conn, name, rn)
    renamed <- TRUE
  }

  created <- FALSE
  tryCatch(
    {
      if (!found || overwrite) {
        fields <- if (is.null(field.types)) value else field.types
        dbCreateTable(conn, name, fields)
        created <- TRUE
      }
      if (nrow(value) > 0L) {
        dbAppendTable(conn, name, value,
          row.names = row.names, chunk_size = chunk_size
        )
      }
    },
    error = function(e) {
      if (created) {
        try(dbRemoveTable(conn, name), silent = TRUE)
      }
      if (renamed) {
        try(dbRenameTable(conn, rn, name), silent = TRUE)
      }
      stop(
        "Writing table ", trino_qualify(conn, name),
        ' failed with error: "', conditionMessage(e), '".',
        call. = FALSE
      )
    }
  )

  if (renamed) {
    dbRemoveTable(conn, rn)
    message("The table ", trino_qualify(conn, name), " is overwritten.")
  }
  invisible(TRUE)
}
