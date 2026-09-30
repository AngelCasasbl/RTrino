#' Resolve a table name into catalog, schema and table
#'
#' Shared by every method that has to address a table, so they all accept the
#' same names and resolve them the same way:
#'
#' * a string: `"table"` resolves against the connection's catalog and schema,
#'   `"schema.table"` keeps the connection's catalog, and
#'   `"catalog.schema.table"` is used as given;
#' * [DBI::SQL()], an identifier already quoted, such as
#'   `SQL('"hive"."sales"')`, split on the dots between its parts;
#' * [DBI::Id()], with components named `catalog`, `schema` and `table`, or
#'   unnamed and read from the right, the last being the table.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name The table name.
#' @return A character vector of length three.
#' @noRd
trino_table_parts <- function(conn, name) {
  if (methods::is(name, "Id")) {
    parts <- trino_id_parts(name@name)
    shown <- paste(name@name, collapse = ".")
  } else if (methods::is(name, "SQL")) {
    shown <- trino_check_string(as.character(name), "name")
    parts <- trino_split_identifier(shown)
  } else {
    shown <- trino_check_string(name, "name")
    parts <- strsplit(shown, ".", fixed = TRUE)[[1L]]
  }

  if (anyNA(parts) || !all(nzchar(parts))) {
    stop(sprintf("`name` has an empty part: %s", shown), call. = FALSE)
  }
  switch(
    as.character(length(parts)),
    "1" = c(conn@catalog, conn@schema, parts),
    "2" = c(conn@catalog, parts),
    "3" = parts,
    stop(
      sprintf(
        "`name` must have at most three parts, got %d: %s",
        length(parts), shown
      ),
      call. = FALSE
    )
  )
}

#' The parts of a `DBI::Id()`, catalog first
#'
#' @param x The `name` slot of an `Id`.
#' @return A character vector of one to three parts, `NA` for the catalog or
#'   schema when only the later parts were named.
#' @noRd
trino_id_parts <- function(x) {
  keys <- names(x)
  if (is.null(keys) || !any(nzchar(keys))) {
    return(unname(x))
  }
  known <- c("catalog", "schema", "table")
  if (!all(keys %in% known) || anyDuplicated(keys) || !"table" %in% keys) {
    stop(
      "An `Id()` must name its components `catalog`, `schema` and `table`, ",
      "with at least `table`.",
      call. = FALSE
    )
  }
  # Drop the leading parts that were not given, so that Id(table = "t")
  # resolves like "t" and Id(schema = "s", table = "t") like "s.t".
  parts <- unname(x[known])
  parts <- parts[match(TRUE, !is.na(parts)):3L]
  if (anyNA(parts)) {
    stop("An `Id()` with a catalog must also have a schema.", call. = FALSE)
  }
  parts
}

#' Split a quoted SQL identifier on the dots between its parts
#'
#' Follows the SQL standard Trino uses: a part is either bare or wrapped in
#' double quotes, and a double quote inside a quoted part is doubled. A dot
#' inside quotes belongs to the part.
#'
#' @param x A string, such as `'"hive"."sales"'` or `'hive.sales'`.
#' @return A character vector of the unquoted parts.
#' @noRd
trino_split_identifier <- function(x) {
  chars <- strsplit(x, "", fixed = TRUE)[[1L]]
  parts <- character()
  current <- character()
  quoted <- FALSE
  i <- 1L
  while (i <= length(chars)) {
    ch <- chars[[i]]
    if (quoted) {
      if (ch != "\"") {
        current <- c(current, ch)
      } else if (i < length(chars) && chars[[i + 1L]] == "\"") {
        current <- c(current, "\"")
        i <- i + 1L
      } else {
        quoted <- FALSE
      }
    } else if (ch == "\"") {
      quoted <- TRUE
    } else if (ch == ".") {
      parts <- c(parts, paste(current, collapse = ""))
      current <- character()
    } else if (!grepl("[[:space:]]", ch)) {
      current <- c(current, ch)
    }
    i <- i + 1L
  }
  if (quoted) {
    stop(sprintf("`name` has an unterminated quote: %s", x), call. = FALSE)
  }
  c(parts, paste(current, collapse = ""))
}

#' Qualify a table name with the connection's catalog and schema
#'
#' @param conn A [TrinoConnection-class] object.
#' @param name Table name, in any form `trino_table_parts()` accepts.
#' @return A quoted, fully qualified identifier as a string.
#' @noRd
trino_qualify <- function(conn, name) {
  paste(
    dbQuoteIdentifier(conn, trino_table_parts(conn, name)),
    collapse = "."
  )
}

#' Fail with a readable error for a table name that is not a string
#'
#' The table methods are registered for `"character"` (which `SQL()` extends)
#' and for `"Id"`, so without a fallback a missing or `NULL` name ends in S4's
#' "unable to find an inherited method". Registered for `"ANY"`, the fallback
#' only sees what those methods did not take.
#'
#' @param name The `name` argument, possibly missing.
#' @param what What the name is for, for the error message.
#' @return Never returns.
#' @noRd
trino_bad_table_name <- function(name, what) {
  if (missing(name)) {
    stop(sprintf("`name` is required: %s.", what), call. = FALSE)
  }
  trino_check_string(name, "name")
  stop("`name` must be a single string.", call. = FALSE)
}
